/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * MMAppController
 *
 * MMAppController is the delegate of NSApp and as such handles file open
 * requests, application termination, etc.  It sets up a named NSConnection on
 * which it listens to incoming connections from Vim processes.  It also
 * coordinates all MMVimControllers and takes care of the main menu.
 *
 * A new Vim process is started by calling launchVimProcessWithArguments:.
 * When the Vim process is initialized it notifies the app controller by
 * sending a connectBackend:pid: message.  At this point a new MMVimController
 * is allocated.  Afterwards, the Vim process communicates directly with its
 * MMVimController.
 *
 * A Vim process started from the command line connects directly by sending the
 * connectBackend:pid: message (launchVimProcessWithArguments: is never called
 * in this case).
 *
 * The main menu is handled as follows.  Each Vim controller keeps its own main
 * menu.  All menus except the "MacVim" menu are controlled by the Vim process.
 * The app controller also keeps a reference to the "default main menu" which
 * is set up in MainMenu.nib.  When no editor window is open the default main
 * menu is used.  When a new editor window becomes main its main menu becomes
 * the new main menu, this is done in -[MMAppController setMainMenu:].
 *   NOTE: Certain heuristics are used to find the "MacVim", "Windows", "File",
 * and "Services" menu.  If MainMenu.nib changes these heuristics may have to
 * change as well.  For specifics see the find... methods defined in the NSMenu
 * category "MMExtras".
 */

#import "MMAppController.h"
#import "MMPreferenceController.h"
#import "MMVimController.h"
#import "MMWindowController.h"
#import "MMTextView.h"
#import "Miscellaneous.h"
#import <unistd.h>
#import <CoreServices/CoreServices.h>
// Need Carbon for TIS...() functions
#import <Carbon/Carbon.h>


#define MM_HANDLE_XCODE_MOD_EVENT 0



// Default timeout intervals on all connections.
static NSTimeInterval MMRequestTimeout = 5;
static NSTimeInterval MMReplyTimeout = 5;

static NSString *MMWebsiteString = @"https://macvim-dev.github.io/macvim/";

// Latency (in s) between FS event occuring and being reported to MacVim.
// Should be small so that MacVim is notified of changes to the ~/.vim
// directory more or less immediately.
static CFTimeInterval MMEventStreamLatency = 0.1;

static float MMCascadeHorizontalOffset = 21;
static float MMCascadeVerticalOffset = 23;


#pragma pack(push,1)
// The alignment and sizes of these fields are based on trial-and-error.  It
// may be necessary to adjust them to fit if Xcode ever changes this struct.
typedef struct
{
    int16_t unused1;      // 0 (not used)
    int16_t lineNum;      // line to select (< 0 to specify range)
    int32_t startRange;   // start of selection range (if line < 0)
    int32_t endRange;     // end of selection range (if line < 0)
    int32_t unused2;      // 0 (not used)
    int32_t theDate;      // modification date/time
} MMXcodeSelectionRange;
#pragma pack(pop)


// This is a private AppKit API gleaned from class-dump.
@interface NSKeyBindingManager : NSObject
+ (id)sharedKeyBindingManager;
- (id)dictionary;
- (void)setDictionary:(id)arg1;
@end


@interface MMAppController (MMServices)
- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)userData
                error:(NSString **)error;
- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error;
- (void)newFileHere:(NSPasteboard *)pboard userData:(NSString *)userData
              error:(NSString **)error;
@end


@interface MMAppController (Private)
- (MMVimController *)topmostVimController;
- (int)launchVimProcessWithArguments:(NSArray *)args
                    workingDirectory:(NSString *)cwd;
- (NSArray *)filterFilesAndNotify:(NSArray *)files;
- (NSArray *)filterOpenFiles:(NSArray *)filenames
               openFilesDict:(NSDictionary **)openFiles;
#if MM_HANDLE_XCODE_MOD_EVENT
- (void)handleXcodeModEvent:(NSAppleEventDescriptor *)event
                 replyEvent:(NSAppleEventDescriptor *)reply;
#endif
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event
               replyEvent:(NSAppleEventDescriptor *)reply;
- (NSMutableDictionary *)extractArgumentsFromOdocEvent:
    (NSAppleEventDescriptor *)desc;
- (void)scheduleVimControllerPreloadAfterDelay:(NSTimeInterval)delay;
- (void)cancelVimControllerPreloadRequests;
- (void)preloadVimController:(id)sender;
- (int)maxPreloadCacheSize;
- (MMVimController *)takeVimControllerFromCache;
- (void)clearPreloadCacheWithCount:(int)count;
- (void)rebuildPreloadCache;
- (NSDate *)rcFilesModificationDate;
- (BOOL)openVimControllerWithArguments:(NSDictionary *)arguments;
- (void)activateWhenNextWindowOpens;
- (void)startWatchingVimDir;
- (void)stopWatchingVimDir;
- (void)handleFSEvent;
- (int)executeInLoginShell:(NSString *)path arguments:(NSArray *)args;
- (void)reapChildProcesses:(id)sender;
- (void)processInputQueues:(id)sender;
- (void)addVimController:(MMVimController *)vc;
- (NSDictionary *)convertVimControllerArguments:(NSDictionary *)args
                                  toCommandLine:(NSArray **)cmdline;
- (NSString *)workingDirectoryForArguments:(NSDictionary *)args;
- (NSScreen *)screenContainingTopLeftPoint:(NSPoint)pt;
- (void)addInputSourceChangedObserver;
- (void)removeInputSourceChangedObserver;
- (void)inputSourceChanged:(NSNotification *)notification;
@end



    static void
fsEventCallback(ConstFSEventStreamRef streamRef,
                void *clientCallBackInfo,
                size_t numEvents,
                void *eventPaths,
                const FSEventStreamEventFlags eventFlags[],
                const FSEventStreamEventId eventIds[])
{
    [[MMAppController sharedInstance] handleFSEvent];
}

@implementation MMAppController

+ (void)initialize
{
    static BOOL initDone = NO;
    if (initDone) return;
    initDone = YES;

    ASLInit();

    // HACK! The following user default must be reset, else Ctrl-q (or
    // whichever key is specified by the default) will be blocked by the input
    // manager (interpretKeyEvents: swallows that key).  (We can't use
    // NSUserDefaults since it only allows us to write to the registration
    // domain and this preference has "higher precedence" than that so such a
    // change would have no effect.)
    CFPreferencesSetAppValue(CFSTR("NSQuotedKeystrokeBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);

    // Also disable NSRepeatCountBinding -- it is not enabled by default, but
    // it does not make much sense to support it since Vim has its own way of
    // dealing with repeat counts.
    CFPreferencesSetAppValue(CFSTR("NSRepeatCountBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);
    
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:NO],     MMNoWindowKey,
        [NSNumber numberWithInt:64],      MMTabMinWidthKey,
        [NSNumber numberWithInt:6*64],    MMTabMaxWidthKey,
        [NSNumber numberWithInt:132],     MMTabOptimumWidthKey,
        [NSNumber numberWithBool:YES],    MMShowAddTabButtonKey,
        [NSNumber numberWithInt:2],       MMTextInsetLeftKey,
        [NSNumber numberWithInt:1],       MMTextInsetRightKey,
        [NSNumber numberWithInt:1],       MMTextInsetTopKey,
        [NSNumber numberWithInt:1],       MMTextInsetBottomKey,
        @"MMTypesetter",                  MMTypesetterKey,
        [NSNumber numberWithFloat:1],     MMCellWidthMultiplierKey,
        [NSNumber numberWithFloat:-1],    MMBaselineOffsetKey,
        [NSNumber numberWithBool:YES],    MMTranslateCtrlClickKey,
        [NSNumber numberWithInt:0],       MMOpenInCurrentWindowKey,
        [NSNumber numberWithBool:NO],     MMNoFontSubstitutionKey,
        [NSNumber numberWithBool:YES],    MMLoginShellKey,
        [NSNumber numberWithInt:MMRendererCoreText],
                                          MMRendererKey,
        [NSNumber numberWithInt:MMUntitledWindowAlways],
                                          MMUntitledWindowKey,
        [NSNumber numberWithBool:NO],     MMZoomBothKey,
        @"",                              MMLoginShellCommandKey,
        @"",                              MMLoginShellArgumentKey,
        [NSNumber numberWithBool:YES],    MMDialogsTrackPwdKey,
        [NSNumber numberWithInt:3],       MMOpenLayoutKey,
        [NSNumber numberWithBool:NO],     MMVerticalSplitKey,
        [NSNumber numberWithInt:0],       MMPreloadCacheSizeKey,
        [NSNumber numberWithInt:0],       MMLastWindowClosedBehaviorKey,
#ifdef INCLUDE_OLD_IM_CODE
        [NSNumber numberWithBool:YES],    MMUseInlineImKey,
#endif // INCLUDE_OLD_IM_CODE
        [NSNumber numberWithBool:NO],     MMSuppressTerminationAlertKey,
        [NSNumber numberWithBool:YES],    MMNativeFullScreenKey,
        [NSNumber numberWithDouble:0.25], MMFullScreenFadeTimeKey,
        nil];

    [[NSUserDefaults standardUserDefaults] registerDefaults:dict];

    NSArray *types = [NSArray arrayWithObject:NSStringPboardType];
    [NSApp registerServicesMenuSendTypes:types returnTypes:types];

    // NOTE: Set the current directory to user's home directory, otherwise it
    // will default to the root directory.  (This matters since new Vim
    // processes inherit MacVim's environment variables.)
    [[NSFileManager defaultManager] changeCurrentDirectoryPath:
            NSHomeDirectory()];
}

- (id)init
{
    if (!(self = [super init])) return nil;

#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)
    // Disable automatic relaunching
    if ([NSApp respondsToSelector:@selector(disableRelaunchOnLogin)])
        [NSApp disableRelaunchOnLogin];
#endif

    vimControllers = [NSMutableArray new];
    cachedVimControllers = [NSMutableArray new];
    preloadPid = -1;
    pidArguments = [NSMutableDictionary new];
    inputQueues = [NSMutableDictionary new];

    // NOTE: Do not use the default connection since the Logitech Control
    // Center (LCC) input manager steals and this would cause MacVim to
    // never open any windows.  (This is a bug in LCC but since they are
    // unlikely to fix it, we graciously give them the default connection.)
    connection = [[NSConnection alloc] initWithReceivePort:[NSPort port]
                                                  sendPort:nil];
    [connection setRootObject:self];
    [connection setRequestTimeout:MMRequestTimeout];
    [connection setReplyTimeout:MMReplyTimeout];

    // NOTE!  If the name of the connection changes here it must also be
    // updated in MMBackend.m.
    NSString *name = [NSString stringWithFormat:@"%@-connection",
             [[NSBundle mainBundle] bundlePath]];
    if (![connection registerName:name]) {
        ASLogCrit(@"Failed to register connection with name '%@'", name);
        [connection release];  connection = nil;
    }

    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [connection release];  connection = nil;
    [inputQueues release];  inputQueues = nil;
    [pidArguments release];  pidArguments = nil;
    [vimControllers release];  vimControllers = nil;
    [cachedVimControllers release];  cachedVimControllers = nil;
    [openSelectionString release];  openSelectionString = nil;
    [recentFilesMenuItem release];  recentFilesMenuItem = nil;
    [defaultMainMenu release];  defaultMainMenu = nil;
    [appMenuItemTemplate release];  appMenuItemTemplate = nil;

    [super dealloc];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Remember the default menu so that it can be restored if the user closes
    // all editor windows.
    defaultMainMenu = [[NSApp mainMenu] retain];

    // Store a copy of the default app menu so we can use this as a template
    // for all other menus.  We make a copy here because the "Services" menu
    // will not yet have been populated at this time.  If we don't we get
    // problems trying to set key equivalents later on because they might clash
    // with items on the "Services" menu.
    appMenuItemTemplate = [defaultMainMenu itemAtIndex:0];
    appMenuItemTemplate = [appMenuItemTemplate copy];

    // Set up the "Open Recent" menu. See
    //   http://lapcatsoftware.com/blog/2007/07/10/
    //     working-without-a-nib-part-5-open-recent-menu/
    // and
    //   http://www.cocoabuilder.com/archive/message/cocoa/2007/8/15/187793
    // for more information.
    //
    // The menu itself is created in MainMenu.nib but we still seem to have to
    // hack around a bit to get it to work.  (This has to be done in
    // applicationWillFinishLaunching at the latest, otherwise it doesn't
    // work.)
    NSMenu *fileMenu = [defaultMainMenu findFileMenu];
    if (fileMenu) {
        int idx = [fileMenu indexOfItemWithAction:@selector(fileOpen:)];
        if (idx >= 0 && idx+1 < [fileMenu numberOfItems])

        recentFilesMenuItem = [fileMenu itemWithTitle:@"Open Recent"];
        [[recentFilesMenuItem submenu] performSelector:@selector(_setMenuName:)
                                        withObject:@"NSRecentDocumentsMenu"];

        // Note: The "Recent Files" menu must be moved around since there is no
        // -[NSApp setRecentFilesMenu:] method.  We keep a reference to it to
        // facilitate this move (see setMainMenu: below).
        [recentFilesMenuItem retain];
    }

#if MM_HANDLE_XCODE_MOD_EVENT
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler:self
                andSelector:@selector(handleXcodeModEvent:replyEvent:)
              forEventClass:'KAHL'
                 andEventID:'MOD '];
#endif

    // Register 'mvim://' URL handler
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler:self
                andSelector:@selector(handleGetURLEvent:replyEvent:)
              forEventClass:kInternetEventClass
                 andEventID:kAEGetURL];

    // Disable the default Cocoa "Key Bindings" since they interfere with the
    // way Vim handles keyboard input.  Cocoa reads bindings from
    //     /System/Library/Frameworks/AppKit.framework/Resources/
    //                                                  StandardKeyBinding.dict
    // and
    //     ~/Library/KeyBindings/DefaultKeyBinding.dict
    // To avoid having the user accidentally break keyboard handling (by
    // modifying the latter in some unexpected way) in MacVim we load our own
    // key binding dictionary from Resource/KeyBinding.plist.  We can't disable
    // the bindings completely since it would break keyboard handling in
    // dialogs so the our custom dictionary contains all the entries from the
    // former location.
    //
    // It is possible to disable key bindings completely by not calling
    // interpretKeyEvents: in keyDown: but this also disables key bindings used
    // by certain input methods.  E.g.  Ctrl-Shift-; would no longer work in
    // the Kotoeri input manager.
    //
    // To solve this problem we access a private API and set the key binding
    // dictionary to our own custom dictionary here.  At this time Cocoa will
    // have already read the above mentioned dictionaries so it (hopefully)
    // won't try to change the key binding dictionary again after this point.
    NSKeyBindingManager *mgr = [NSKeyBindingManager sharedKeyBindingManager];
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *path = [mainBundle pathForResource:@"KeyBinding"
                                          ofType:@"plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (mgr && dict) {
        [mgr setDictionary:dict];
    } else {
        ASLogNotice(@"Failed to override the Cocoa key bindings.  Keyboard "
                "input may behave strangely as a result (path=%@).", path);
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [NSApp setServicesProvider:self];

    if ([self maxPreloadCacheSize] > 0) {
        [self scheduleVimControllerPreloadAfterDelay:2];
        [self startWatchingVimDir];
    }

    [self addInputSourceChangedObserver];

    ASLogInfo(@"MacVim finished launching");
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSAppleEventManager *aem = [NSAppleEventManager sharedAppleEventManager];
    NSAppleEventDescriptor *desc = [aem currentAppleEvent];

    // The user default MMUntitledWindow can be set to control whether an
    // untitled window should open on 'Open' and 'Reopen' events.
    int untitledWindowFlag = [ud integerForKey:MMUntitledWindowKey];

    BOOL isAppOpenEvent = [desc eventID] == kAEOpenApplication;
    if (isAppOpenEvent && (untitledWindowFlag & MMUntitledWindowOnOpen) == 0)
        return NO;

    BOOL isAppReopenEvent = [desc eventID] == kAEReopenApplication;
    if (isAppReopenEvent
            && (untitledWindowFlag & MMUntitledWindowOnReopen) == 0)
        return NO;

    // When a process is started from the command line, the 'Open' event may
    // contain a parameter to surpress the opening of an untitled window.
    desc = [desc paramDescriptorForKeyword:keyAEPropData];
    desc = [desc paramDescriptorForKeyword:keyMMUntitledWindow];
    if (desc && ![desc booleanValue])
        return NO;

    // Never open an untitled window if there is at least one open window.
    if ([vimControllers count] > 0)
        return NO;

    // Don't open an untitled window if there are processes about to launch...
    NSUInteger numLaunching = [pidArguments count];
    if (numLaunching > 0) {
        // ...unless the launching process is being preloaded
        NSNumber *key = [NSNumber numberWithInt:preloadPid];
        if (numLaunching != 1 || [pidArguments objectForKey:key] == nil)
            return NO;
    }

    // NOTE!  This way it possible to start the app with the command-line
    // argument '-nowindow yes' and no window will be opened by default but
    // this argument will only be heeded when the application is opening.
    if (isAppOpenEvent && [ud boolForKey:MMNoWindowKey] == YES)
        return NO;

    return YES;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender
{
    ASLogDebug(@"Opening untitled window...");
    [self newWindow:self];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    ASLogInfo(@"Opening files %@", filenames);

    // Extract ODB/Xcode/Spotlight parameters from the current Apple event,
    // sort the filenames, and then let openFiles:withArguments: do the heavy
    // lifting.

    if (!(filenames && [filenames count] > 0))
        return;

    // Sort filenames since the Finder doesn't take care in preserving the
    // order in which files are selected anyway (and "sorted" is more
    // predictable than "random").
    if ([filenames count] > 1)
        filenames = [filenames sortedArrayUsingSelector:
                @selector(localizedCompare:)];

    // Extract ODB/Xcode/Spotlight parameters from the current Apple event
    NSMutableDictionary *arguments = [self extractArgumentsFromOdocEvent:
            [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent]];

    if ([self openFiles:filenames withArguments:arguments]) {
        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    } else {
        // TODO: Notify user of failure?
        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return (MMTerminateWhenLastWindowClosed ==
            [[NSUserDefaults standardUserDefaults]
                integerForKey:MMLastWindowClosedBehaviorKey]);
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication *)sender
{
    // TODO: Follow Apple's guidelines for 'Graceful Application Termination'
    // (in particular, allow user to review changes and save).
    int reply = NSTerminateNow;
    BOOL modifiedBuffers = NO;

    // Go through Vim controllers, checking for modified buffers.
    NSEnumerator *e = [vimControllers objectEnumerator];
    id vc;
    while ((vc = [e nextObject])) {
        if ([vc hasModifiedBuffer]) {
            modifiedBuffers = YES;
            break;
        }
    }

    if (modifiedBuffers) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert addButtonWithTitle:NSLocalizedString(@"Quit",
                @"Dialog button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel",
                @"Dialog button")];
        [alert setMessageText:NSLocalizedString(@"Quit without saving?",
                @"Quit dialog with changed buffers, title")];
        [alert setInformativeText:NSLocalizedString(
                @"There are modified buffers, "
                "if you quit now all changes will be lost.  Quit anyway?",
                @"Quit dialog with changed buffers, text")];

        if ([alert runModal] != NSAlertFirstButtonReturn)
            reply = NSTerminateCancel;

        [alert release];
    } else if (![[NSUserDefaults standardUserDefaults]
                                boolForKey:MMSuppressTerminationAlertKey]) {
        // No unmodified buffers, but give a warning if there are multiple
        // windows and/or tabs open.
        int numWindows = [vimControllers count];
        int numTabs = 0;

        // Count the number of open tabs
        e = [vimControllers objectEnumerator];
        while ((vc = [e nextObject]))
            numTabs += [[vc objectForVimStateKey:@"numTabs"] intValue];

        if (numWindows > 1 || numTabs > 1) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert addButtonWithTitle:NSLocalizedString(@"Quit",
                    @"Dialog button")];
            [alert addButtonWithTitle:NSLocalizedString(@"Cancel",
                    @"Dialog button")];
            [alert setMessageText:NSLocalizedString(
                    @"Are you sure you want to quit MacVim?",
                    @"Quit dialog with no changed buffers, title")];
            [alert setShowsSuppressionButton:YES];

            NSString *info = nil;
            if (numWindows > 1) {
                if (numTabs > numWindows)
                    info = [NSString stringWithFormat:NSLocalizedString(
                            @"There are %d windows open in MacVim, with a "
                            "total of %d tabs. Do you want to quit anyway?",
                            @"Quit dialog with no changed buffers, text"),
                         numWindows, numTabs];
                else
                    info = [NSString stringWithFormat:NSLocalizedString(
                            @"There are %d windows open in MacVim. "
                            "Do you want to quit anyway?",
                            @"Quit dialog with no changed buffers, text"),
                        numWindows];

            } else {
                info = [NSString stringWithFormat:NSLocalizedString(
                        @"There are %d tabs open in MacVim. "
                        "Do you want to quit anyway?",
                        @"Quit dialog with no changed buffers, text"), 
                     numTabs];
            }

            [alert setInformativeText:info];

            if ([alert runModal] != NSAlertFirstButtonReturn)
                reply = NSTerminateCancel;

            if ([[alert suppressionButton] state] == NSOnState) {
                [[NSUserDefaults standardUserDefaults]
                            setBool:YES forKey:MMSuppressTerminationAlertKey];
            }

            [alert release];
        }
    }


    // Tell all Vim processes to terminate now (otherwise they'll leave swap
    // files behind).
    if (NSTerminateNow == reply) {
        e = [vimControllers objectEnumerator];
        id vc;
        while ((vc = [e nextObject])) {
            ASLogDebug(@"Terminate pid=%d", [vc pid]);
            [vc sendMessage:TerminateNowMsgID data:nil];
        }

        e = [cachedVimControllers objectEnumerator];
        while ((vc = [e nextObject])) {
            ASLogDebug(@"Terminate pid=%d (cached)", [vc pid]);
            [vc sendMessage:TerminateNowMsgID data:nil];
        }

        // If a Vim process is being preloaded as we quit we have to forcibly
        // kill it since we have not established a connection yet.
        if (preloadPid > 0) {
            ASLogDebug(@"Kill incomplete preloaded process pid=%d", preloadPid);
            kill(preloadPid, SIGKILL);
        }

        // If a Vim process was loading as we quit we also have to kill it.
        e = [[pidArguments allKeys] objectEnumerator];
        NSNumber *pidKey;
        while ((pidKey = [e nextObject])) {
            ASLogDebug(@"Kill incomplete process pid=%d", [pidKey intValue]);
            kill([pidKey intValue], SIGKILL);
        }

        // Sleep a little to allow all the Vim processes to exit.
        usleep(10000);
    }

    return reply;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    ASLogInfo(@"Terminating MacVim...");

    [self removeInputSourceChangedObserver];

    [self stopWatchingVimDir];

#if MM_HANDLE_XCODE_MOD_EVENT
    [[NSAppleEventManager sharedAppleEventManager]
            removeEventHandlerForEventClass:'KAHL'
                                 andEventID:'MOD '];
#endif

    // This will invalidate all connections (since they were spawned from this
    // connection).
    [connection invalidate];

    [NSApp setDelegate:nil];

    // Try to wait for all child processes to avoid leaving zombies behind (but
    // don't wait around for too long).
    NSDate *timeOutDate = [NSDate dateWithTimeIntervalSinceNow:2];
    while ([timeOutDate timeIntervalSinceNow] > 0) {
        [self reapChildProcesses:nil];
        if (numChildProcesses <= 0)
            break;

        ASLogDebug(@"%d processes still left, hold on...", numChildProcesses);

        // Run in NSConnectionReplyMode while waiting instead of calling e.g.
        // usleep().  Otherwise incoming messages may clog up the DO queues and
        // the outgoing TerminateNowMsgID sent earlier never reaches the Vim
        // process.
        // This has at least one side-effect, namely we may receive the
        // annoying "dropping incoming DO message".  (E.g. this may happen if
        // you quickly hit Cmd-n several times in a row and then immediately
        // press Cmd-q, Enter.)
        while (CFRunLoopRunInMode((CFStringRef)NSConnectionReplyMode,
                0.05, true) == kCFRunLoopRunHandledSource)
            ;   // do nothing
    }

    if (numChildProcesses > 0) {
        ASLogNotice(@"%d zombies left behind", numChildProcesses);
    }
}

+ (MMAppController *)sharedInstance
{
    // Note: The app controller is a singleton which is instantiated in
    // MainMenu.nib where it is also connected as the delegate of NSApp.
    id delegate = [NSApp delegate];
    return [delegate isKindOfClass:self] ? (MMAppController*)delegate : nil;
}

- (NSMenu *)defaultMainMenu
{
    return defaultMainMenu;
}

- (NSMenuItem *)appMenuItemTemplate
{
    return appMenuItemTemplate;
}

- (void)removeVimController:(id)controller
{
    ASLogDebug(@"Remove Vim controller pid=%d id=%d (processingFlag=%d)",
               [controller pid], [controller vimControllerId], processingFlag);

    NSUInteger idx = [vimControllers indexOfObject:controller];
    if (NSNotFound == idx) {
        ASLogDebug(@"Controller not found, probably due to duplicate removal");
        return;
    }

    [controller retain];
    [vimControllers removeObjectAtIndex:idx];
    [controller cleanup];
    [controller release];

    if (![vimControllers count]) {
        // The last editor window just closed so restore the main menu back to
        // its default state (which is defined in MainMenu.nib).
        [self setMainMenu:defaultMainMenu];

        BOOL hide = (MMHideWhenLastWindowClosed ==
                    [[NSUserDefaults standardUserDefaults]
                        integerForKey:MMLastWindowClosedBehaviorKey]);
        if (hide)
            [NSApp hide:self];
    }

    // There is a small delay before the Vim process actually exits so wait a
    // little before trying to reap the child process.  If the process still
    // hasn't exited after this wait it won't be reaped until the next time
    // reapChildProcesses: is called (but this should be harmless).
    [self performSelector:@selector(reapChildProcesses:)
               withObject:nil
               afterDelay:0.1];
}

- (void)windowControllerWillOpen:(MMWindowController *)windowController
{
    NSPoint topLeft = NSZeroPoint;
    NSWindow *cascadeFrom = [[[self topmostVimController] windowController]
                                                                    window];
    NSWindow *win = [windowController window];

    if (!win) return;

    // Heuristic to determine where to position the window:
    //   1. Use the default top left position (set using :winpos in .[g]vimrc)
    //   2. Cascade from an existing window
    //   3. Use autosaved position
    // If all of the above fail, then the window position is not changed.
    if ([windowController getDefaultTopLeft:&topLeft]) {
        // Make sure the window is not cascaded (note that topLeft was set in
        // the above call).
        cascadeFrom = nil;
    } else if (cascadeFrom) {
        NSRect frame = [cascadeFrom frame];
        topLeft = NSMakePoint(frame.origin.x, NSMaxY(frame));
    } else {
        NSString *topLeftString = [[NSUserDefaults standardUserDefaults]
            stringForKey:MMTopLeftPointKey];
        if (topLeftString)
            topLeft = NSPointFromString(topLeftString);
    }

    if (!NSEqualPoints(topLeft, NSZeroPoint)) {
        // Try to tile from the correct screen in case the user has multiple
        // monitors ([win screen] always seems to return the "main" screen).
        //
        // TODO: Check for screen _closest_ to top left?
        NSScreen *screen = [self screenContainingTopLeftPoint:topLeft];
        if (!screen)
            screen = [win screen];

        BOOL willSwitchScreens = screen != [win screen];
        if (cascadeFrom) {
            // Do manual cascading instead of using
            // -[MMWindow cascadeTopLeftFromPoint:] since it is rather
            // unpredictable.
            topLeft.x += MMCascadeHorizontalOffset;
            topLeft.y -= MMCascadeVerticalOffset;
        }

        if (screen) {
            // Constrain the window so that it is entirely visible on the
            // screen.  If it sticks out on the right, move it all the way
            // left.  If it sticks out on the bottom, move it all the way up.
            // (Assumption: the cascading offsets are positive.)
            NSRect screenFrame = [screen frame];
            NSSize winSize = [win frame].size;
            NSRect winFrame =
                { { topLeft.x, topLeft.y - winSize.height }, winSize };

            if (NSMaxX(winFrame) > NSMaxX(screenFrame))
                topLeft.x = NSMinX(screenFrame);
            if (NSMinY(winFrame) < NSMinY(screenFrame))
                topLeft.y = NSMaxY(screenFrame);
        } else {
            ASLogNotice(@"Window not on screen, don't constrain position");
        }

        // setFrameTopLeftPoint will trigger a resize event if the window is
        // moved across monitors; at this point such a resize would incorrectly
        // constrain the window to the default vim dimensions, so a specialized
        // method is used that will avoid that behavior.
        if (willSwitchScreens)
            [windowController moveWindowAcrossScreens:topLeft];
        else
            [win setFrameTopLeftPoint:topLeft];
    }

    if (1 == [vimControllers count]) {
        // The first window autosaves its position.  (The autosaving
        // features of Cocoa are not used because we need more control over
        // what is autosaved and when it is restored.)
        [windowController setWindowAutosaveKey:MMTopLeftPointKey];
    }

    if (openSelectionString) {
        // TODO: Pass this as a parameter instead!  Get rid of
        // 'openSelectionString' etc.
        //
        // There is some text to paste into this window as a result of the
        // services menu "Open selection ..." being used.
        [[windowController vimController] dropString:openSelectionString];
        [openSelectionString release];
        openSelectionString = nil;
    }

    if (shouldActivateWhenNextWindowOpens) {
        [NSApp activateIgnoringOtherApps:YES];
        shouldActivateWhenNextWindowOpens = NO;
    }
}

- (void)setMainMenu:(NSMenu *)mainMenu
{
    if ([NSApp mainMenu] == mainMenu) return;

    // If the new menu has a "Recent Files" dummy item, then swap the real item
    // for the dummy.  We are forced to do this since Cocoa initializes the
    // "Recent Files" menu and there is no way to simply point Cocoa to a new
    // item each time the menus are swapped.
    NSMenu *fileMenu = [mainMenu findFileMenu];
    if (recentFilesMenuItem && fileMenu) {
        int dummyIdx =
                [fileMenu indexOfItemWithAction:@selector(recentFilesDummy:)];
        if (dummyIdx >= 0) {
            NSMenuItem *dummyItem = [[fileMenu itemAtIndex:dummyIdx] retain];
            [fileMenu removeItemAtIndex:dummyIdx];

            NSMenu *recentFilesParentMenu = [recentFilesMenuItem menu];
            int idx = [recentFilesParentMenu indexOfItem:recentFilesMenuItem];
            if (idx >= 0) {
                [[recentFilesMenuItem retain] autorelease];
                [recentFilesParentMenu removeItemAtIndex:idx];
                [recentFilesParentMenu insertItem:dummyItem atIndex:idx];
            }

            [fileMenu insertItem:recentFilesMenuItem atIndex:dummyIdx];
            [dummyItem release];
        }
    }

    // Now set the new menu.  Notice that we keep one menu for each editor
    // window since each editor can have its own set of menus.  When swapping
    // menus we have to tell Cocoa where the new "MacVim", "Windows", and
    // "Services" menu are.
    [NSApp setMainMenu:mainMenu];

    // Setting the "MacVim" (or "Application") menu ensures that it is typeset
    // in boldface.  (The setAppleMenu: method used to be public but is now
    // private so this will have to be considered a bit of a hack!)
    NSMenu *appMenu = [mainMenu findApplicationMenu];
    [NSApp performSelector:@selector(setAppleMenu:) withObject:appMenu];

    NSMenu *servicesMenu = [mainMenu findServicesMenu];
    [NSApp setServicesMenu:servicesMenu];

    NSMenu *windowsMenu = [mainMenu findWindowsMenu];
    if (windowsMenu) {
        // Cocoa isn't clever enough to get rid of items it has added to the
        // "Windows" menu so we have to do it ourselves otherwise there will be
        // multiple menu items for each window in the "Windows" menu.
        //   This code assumes that the only items Cocoa add are ones which
        // send off the action makeKeyAndOrderFront:.  (Cocoa will not add
        // another separator item if the last item on the "Windows" menu
        // already is a separator, so we needen't worry about separators.)
        int i, count = [windowsMenu numberOfItems];
        for (i = count-1; i >= 0; --i) {
            NSMenuItem *item = [windowsMenu itemAtIndex:i];
            if ([item action] == @selector(makeKeyAndOrderFront:))
                [windowsMenu removeItem:item];
        }
    }
    [NSApp setWindowsMenu:windowsMenu];
}

- (NSArray *)filterOpenFiles:(NSArray *)filenames
{
    return [self filterOpenFiles:filenames openFilesDict:nil];
}

- (BOOL)openFiles:(NSArray *)filenames withArguments:(NSDictionary *)args
{
    // Opening files works like this:
    //  a) filter out any already open files
    //  b) open any remaining files
    //
    // Each launching Vim process has a dictionary of arguments that are passed
    // to the process when in checks in (via connectBackend:pid:).  The
    // arguments for each launching process can be looked up by its PID (in the
    // pidArguments dictionary).

    NSMutableDictionary *arguments = (args ? [[args mutableCopy] autorelease]
                                           : [NSMutableDictionary dictionary]);

    filenames = normalizeFilenames(filenames);

    //
    // a) Filter out any already open files
    //
    NSString *firstFile = [filenames objectAtIndex:0];
    NSDictionary *openFilesDict = nil;
    filenames = [self filterOpenFiles:filenames openFilesDict:&openFilesDict];

    // The meaning of "layout" is defined by the WIN_* defines in main.c.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int layout = [ud integerForKey:MMOpenLayoutKey];
    BOOL splitVert = [ud boolForKey:MMVerticalSplitKey];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];

    if (splitVert && MMLayoutHorizontalSplit == layout)
        layout = MMLayoutVerticalSplit;
    if (layout < 0 || (layout > MMLayoutTabs && openInCurrentWindow))
        layout = MMLayoutTabs;

    // Pass arguments to vim controllers that had files open.
    id key;
    NSEnumerator *e = [openFilesDict keyEnumerator];

    // (Indicate that we do not wish to open any files at the moment.)
    [arguments setObject:[NSNumber numberWithBool:YES] forKey:@"dontOpen"];

    while ((key = [e nextObject])) {
        MMVimController *vc = [key pointerValue];
        NSArray *files = [openFilesDict objectForKey:key];
        [arguments setObject:files forKey:@"filenames"];

        if ([filenames count] == 0 && [files containsObject:firstFile]) {
            // Raise the window containing the first file that was already
            // open, and make sure that the tab containing that file is
            // selected.  Only do this when there are no more files to open,
            // otherwise sometimes the window with 'firstFile' will be raised,
            // other times it might be the window that will open with the files
            // in the 'filenames' array.
            //
            // NOTE: Raise window before passing arguments, otherwise the
            // selection will be lost when selectionRange is set.
            firstFile = [firstFile stringByEscapingSpecialFilenameCharacters];

            NSString *bufCmd = @"tab sb";
            switch (layout) {
                case MMLayoutHorizontalSplit: bufCmd = @"sb"; break;
                case MMLayoutVerticalSplit:   bufCmd = @"vert sb"; break;
                case MMLayoutArglist:         bufCmd = @"b"; break;
            }

            NSString *input = [NSString stringWithFormat:@"<C-\\><C-N>"
                    ":let oldswb=&swb|let &swb=\"useopen,usetab\"|"
                    "%@ %@|let &swb=oldswb|unl oldswb|"
                    "cal foreground()<CR>", bufCmd, firstFile];

            [vc addVimInput:input];
        }

        [vc passArguments:arguments];
    }

    // Add filenames to "Recent Files" menu, unless they are being edited
    // remotely (using ODB).
    if ([arguments objectForKey:@"remoteID"] == nil) {
        [[NSDocumentController sharedDocumentController]
                noteNewRecentFilePaths:filenames];
    }

    if ([filenames count] == 0)
        return YES; // No files left to open (all were already open)

    //
    // b) Open any remaining files
    //

    [arguments setObject:[NSNumber numberWithInt:layout] forKey:@"layout"];
    [arguments setObject:filenames forKey:@"filenames"];
    // (Indicate that files should be opened from now on.)
    [arguments setObject:[NSNumber numberWithBool:NO] forKey:@"dontOpen"];

    MMVimController *vc;
    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        // Open files in an already open window.
        [[[vc windowController] window] makeKeyAndOrderFront:self];
        [vc passArguments:arguments];
        return YES;
    }

    BOOL openOk = YES;
    int numFiles = [filenames count];
    if (MMLayoutWindows == layout && numFiles > 1) {
        // Open one file at a time in a new window, but don't open too many at
        // once (at most cap+1 windows will open).  If the user has increased
        // the preload cache size we'll take that as a hint that more windows
        // should be able to open at once.
        int cap = [self maxPreloadCacheSize] - 1;
        if (cap < 4) cap = 4;
        if (cap > numFiles) cap = numFiles;

        int i;
        for (i = 0; i < cap; ++i) {
            NSArray *a = [NSArray arrayWithObject:[filenames objectAtIndex:i]];
            [arguments setObject:a forKey:@"filenames"];

            // NOTE: We have to copy the args since we'll mutate them in the
            // next loop and the below call may retain the arguments while
            // waiting for a process to start.
            NSDictionary *args = [[arguments copy] autorelease];

            openOk = [self openVimControllerWithArguments:args];
            if (!openOk) break;
        }

        // Open remaining files in tabs in a new window.
        if (openOk && numFiles > cap) {
            NSRange range = { i, numFiles-cap };
            NSArray *a = [filenames subarrayWithRange:range];
            [arguments setObject:a forKey:@"filenames"];
            [arguments setObject:[NSNumber numberWithInt:MMLayoutTabs]
                          forKey:@"layout"];

            openOk = [self openVimControllerWithArguments:arguments];
        }
    } else {
        // Open all files at once.
        openOk = [self openVimControllerWithArguments:arguments];
    }

    return openOk;
}

- (IBAction)newWindow:(id)sender
{
    ASLogDebug(@"Open new window");

    // A cached controller requires no loading times and results in the new
    // window popping up instantaneously.  If the cache is empty it may take
    // 1-2 seconds to start a new Vim process.
    MMVimController *vc = [self takeVimControllerFromCache];
    if (vc) {
        [[vc backendProxy] acknowledgeConnection];
    } else {
        [self launchVimProcessWithArguments:nil workingDirectory:nil];
    }
}

- (IBAction)newWindowAndActivate:(id)sender
{
    [self activateWhenNextWindowOpens];
    [self newWindow:sender];
}

- (IBAction)fileOpen:(id)sender
{
    ASLogDebug(@"Show file open panel");

    NSString *dir = nil;
    BOOL trackPwd = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMDialogsTrackPwdKey];
    if (trackPwd) {
        MMVimController *vc = [self keyVimController];
        if (vc) dir = [vc objectForVimStateKey:@"pwd"];
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:YES];
    [panel setCanChooseDirectories:YES];
    [panel setAccessoryView:showHiddenFilesView()];
    dir = [dir stringByExpandingTildeInPath];
    if (dir) {
        NSURL *dirURL = [NSURL fileURLWithPath:dir isDirectory:YES];
        if (dirURL)
            [panel setDirectoryURL:dirURL];
    }

    NSInteger result = [panel runModal];

#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10)
    if (NSModalResponseOK == result) {
#else
    if (NSOKButton == result) {
#endif
        // NOTE: -[NSOpenPanel filenames] is deprecated on 10.7 so use
        // -[NSOpenPanel URLs] instead.  The downside is that we have to check
        // that each URL is really a path first.
        NSMutableArray *filenames = [NSMutableArray array];
        NSArray *urls = [panel URLs];
        NSUInteger i, count = [urls count];
        for (i = 0; i < count; ++i) {
            NSURL *url = [urls objectAtIndex:i];
            if ([url isFileURL]) {
                NSString *path = [url path];
                if (path)
                    [filenames addObject:path];
            }
        }

        if ([filenames count] > 0)
            [self application:NSApp openFiles:filenames];
    }
}

- (IBAction)selectNextWindow:(id)sender
{
    ASLogDebug(@"Select next window");

    unsigned i, count = [vimControllers count];
    if (!count) return;

    NSWindow *keyWindow = [NSApp keyWindow];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        if ([[[vc windowController] window] isEqual:keyWindow])
            break;
    }

    if (i < count) {
        if (++i >= count)
            i = 0;
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [[vc windowController] showWindow:self];
    }
}

- (IBAction)selectPreviousWindow:(id)sender
{
    ASLogDebug(@"Select previous window");

    unsigned i, count = [vimControllers count];
    if (!count) return;

    NSWindow *keyWindow = [NSApp keyWindow];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        if ([[[vc windowController] window] isEqual:keyWindow])
            break;
    }

    if (i < count) {
        if (i > 0) {
            --i;
        } else {
            i = count - 1;
        }
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [[vc windowController] showWindow:self];
    }
}

- (IBAction)orderFrontPreferencePanel:(id)sender
{
    ASLogDebug(@"Show preferences panel");
    [[MMPreferenceController sharedPrefsWindowController] showWindow:self];
}

- (IBAction)openWebsite:(id)sender
{
    ASLogDebug(@"Open MacVim website");
    [[NSWorkspace sharedWorkspace] openURL:
            [NSURL URLWithString:MMWebsiteString]];
}

- (IBAction)showVimHelp:(id)sender
{
    ASLogDebug(@"Open window with Vim help");
    // Open a new window with the help window maximized.
    [self launchVimProcessWithArguments:[NSArray arrayWithObjects:
                                    @"-c", @":h gui_mac", @"-c", @":res", nil]
                       workingDirectory:nil];
}

- (IBAction)zoomAll:(id)sender
{
    ASLogDebug(@"Zoom all windows");
    [NSApp makeWindowsPerform:@selector(performZoom:) inOrder:YES];
}

- (IBAction)coreTextButtonClicked:(id)sender
{
    ASLogDebug(@"Toggle CoreText renderer");
    NSInteger renderer = MMRendererDefault;
    BOOL enable = ([sender state] == NSOnState);

    if (enable) {
        renderer = MMRendererCoreText;
    }

    // Update the user default MMRenderer and synchronize the change so that
    // any new Vim process will pick up on the changed setting.
    CFPreferencesSetAppValue(
            (CFStringRef)MMRendererKey,
            (CFPropertyListRef)[NSNumber numberWithInt:renderer],
            kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);

    ASLogInfo(@"Use renderer=%ld", renderer);

    // This action is called when the user clicks the "use CoreText renderer"
    // button in the advanced preferences pane.
    [self rebuildPreloadCache];
}

- (IBAction)loginShellButtonClicked:(id)sender
{
    ASLogDebug(@"Toggle login shell option");
    // This action is called when the user clicks the "use login shell" button
    // in the advanced preferences pane.
    [self rebuildPreloadCache];
}

- (IBAction)quickstartButtonClicked:(id)sender
{
    ASLogDebug(@"Toggle Quickstart option");
    if ([self maxPreloadCacheSize] > 0) {
        [self scheduleVimControllerPreloadAfterDelay:1.0];
        [self startWatchingVimDir];
    } else {
        [self cancelVimControllerPreloadRequests];
        [self clearPreloadCacheWithCount:-1];
        [self stopWatchingVimDir];
    }
}

- (MMVimController *)keyVimController
{
    NSWindow *keyWindow = [NSApp keyWindow];
    if (keyWindow) {
        unsigned i, count = [vimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [vimControllers objectAtIndex:i];
            if ([[[vc windowController] window] isEqual:keyWindow])
                return vc;
        }
    }

    return nil;
}

- (unsigned)connectBackend:(byref in id <MMBackendProtocol>)proxy pid:(int)pid
{
    ASLogDebug(@"pid=%d", pid);

    [(NSDistantObject*)proxy setProtocolForProxy:@protocol(MMBackendProtocol)];

    // NOTE: Allocate the vim controller now but don't add it to the list of
    // controllers since this is a distributed object call and as such can
    // arrive at unpredictable times (e.g. while iterating the list of vim
    // controllers).
    // (What if input arrives before the vim controller is added to the list of
    // controllers?  This should not be a problem since the input isn't
    // processed immediately (see processInput:forIdentifier:).)
    // Also, since the app may be multithreaded (e.g. as a result of showing
    // the open panel) we have to ensure this call happens on the main thread,
    // else there is a race condition that may lead to a crash.
    MMVimController *vc = [[MMVimController alloc] initWithBackend:proxy
                                                               pid:pid];
    [self performSelectorOnMainThread:@selector(addVimController:)
                           withObject:vc
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObject:
                                       NSDefaultRunLoopMode]];

    [vc release];

    return [vc vimControllerId];
}

- (oneway void)processInput:(in bycopy NSArray *)queue
              forIdentifier:(unsigned)identifier
{
    // NOTE: Input is not handled immediately since this is a distributed
    // object call and as such can arrive at unpredictable times.  Instead,
    // queue the input and process it when the run loop is updated.

    if (!(queue && identifier)) {
        ASLogWarn(@"Bad input for identifier=%d", identifier);
        return;
    }

    ASLogDebug(@"QUEUE for identifier=%d: <<< %@>>>", identifier,
               debugStringForMessageQueue(queue));

    NSNumber *key = [NSNumber numberWithUnsignedInt:identifier];
    NSArray *q = [inputQueues objectForKey:key];
    if (q) {
        q = [q arrayByAddingObjectsFromArray:queue];
        [inputQueues setObject:q forKey:key];
    } else {
        [inputQueues setObject:queue forKey:key];
    }

    // NOTE: We must use "event tracking mode" as well as "default mode",
    // otherwise the input queue will not be processed e.g. during live
    // resizing.
    // Also, since the app may be multithreaded (e.g. as a result of showing
    // the open panel) we have to ensure this call happens on the main thread,
    // else there is a race condition that may lead to a crash.
    [self performSelectorOnMainThread:@selector(processInputQueues:)
                           withObject:nil
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObjects:
                                       NSDefaultRunLoopMode,
                                       NSEventTrackingRunLoopMode, nil]];
}

- (NSArray *)serverList
{
    NSMutableArray *array = [NSMutableArray array];

    unsigned i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        if ([controller serverName])
            [array addObject:[controller serverName]];
    }

    return array;
}

@end // MMAppController




@implementation MMAppController (MMServices)

- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)userData
                error:(NSString **)error
{
    if (![[pboard types] containsObject:NSStringPboardType]) {
        ASLogNotice(@"Pasteboard contains no NSStringPboardType");
        return;
    }

    ASLogInfo(@"Open new window containing current selection");

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];
    MMVimController *vc;

    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        [vc sendMessage:AddNewTabMsgID data:nil];
        [vc dropString:[pboard stringForType:NSStringPboardType]];
    } else {
        // Save the text, open a new window, and paste the text when the next
        // window opens.  (If this is called several times in a row, then all
        // but the last call may be ignored.)
        if (openSelectionString) [openSelectionString release];
        openSelectionString = [[pboard stringForType:NSStringPboardType] copy];

        [self newWindow:self];
    }
}

- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error
{
    if (![[pboard types] containsObject:NSStringPboardType]) {
        ASLogNotice(@"Pasteboard contains no NSStringPboardType");
        return;
    }

    // TODO: Parse multiple filenames and create array with names.
    NSString *string = [pboard stringForType:NSStringPboardType];
    string = [string stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    string = [string stringByStandardizingPath];

    ASLogInfo(@"Open new window with selected file: %@", string);

    NSArray *filenames = [self filterFilesAndNotify:
            [NSArray arrayWithObject:string]];
    if ([filenames count] == 0)
        return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];
    MMVimController *vc;

    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        [vc dropFiles:filenames forceOpen:YES];
    } else {
        [self openFiles:filenames withArguments:nil];
    }
}

- (void)newFileHere:(NSPasteboard *)pboard userData:(NSString *)userData
              error:(NSString **)error
{
    if (![[pboard types] containsObject:NSFilenamesPboardType]) {
        ASLogNotice(@"Pasteboard contains no NSFilenamesPboardType");
        return;
    }

    NSArray *filenames = [pboard propertyListForType:NSFilenamesPboardType];
    NSString *path = [filenames lastObject];

    BOOL dirIndicator;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path
                                              isDirectory:&dirIndicator]) {
        ASLogNotice(@"Invalid path. Cannot open new document at: %@", path);
        return;
    }

    ASLogInfo(@"Open new file at path=%@", path);

    if (!dirIndicator)
        path = [path stringByDeletingLastPathComponent];

    path = [path stringByEscapingSpecialFilenameCharacters];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];
    MMVimController *vc;

    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        NSString *input = [NSString stringWithFormat:@"<C-\\><C-N>"
                ":tabe|cd %@<CR>", path];
        [vc addVimInput:input];
    } else {
        [self launchVimProcessWithArguments:nil workingDirectory:path];
    }
}

@end // MMAppController (MMServices)




@implementation MMAppController (Private)

- (MMVimController *)topmostVimController
{
    // Find the topmost visible window which has an associated vim controller
    // as follows:
    //
    // 1. Search through ordered windows as determined by NSApp.  Unfortunately
    //    this method can fail, e.g. if a full-screen window is on another
    //    "Space" (in this case NSApp returns no windows at all), so we have to
    //    fall back on ...
    // 2. Search through all Vim controllers and return the first visible
    //    window.

    NSEnumerator *e = [[NSApp orderedWindows] objectEnumerator];
    id window;
    while ((window = [e nextObject]) && [window isVisible]) {
        unsigned i, count = [vimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [vimControllers objectAtIndex:i];
            if ([[[vc windowController] window] isEqual:window])
                return vc;
        }
    }

    unsigned i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        if ([[[vc windowController] window] isVisible]) {
            return vc;
        }
    }

    return nil;
}

- (int)launchVimProcessWithArguments:(NSArray *)args
                    workingDirectory:(NSString *)cwd
{
    int pid = -1;
    NSString *path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"Vim"];

    if (!path) {
        ASLogCrit(@"Vim executable could not be found inside app bundle!");
        return -1;
    }

    // Change current working directory so that the child process picks it up.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *restoreCwd = nil;
    if (cwd) {
        restoreCwd = [fm currentDirectoryPath];
        [fm changeCurrentDirectoryPath:cwd];
    }

    NSArray *taskArgs = [NSArray arrayWithObjects:@"-g", @"-f", nil];
    if (args)
        taskArgs = [taskArgs arrayByAddingObjectsFromArray:args];

    BOOL useLoginShell = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMLoginShellKey];
    if (useLoginShell) {
        // Run process with a login shell, roughly:
        //   echo "exec Vim -g -f args" | ARGV0=-`basename $SHELL` $SHELL [-l]
        pid = [self executeInLoginShell:path arguments:taskArgs];
    } else {
        // Run process directly:
        //   Vim -g -f args
        NSTask *task = [NSTask launchedTaskWithLaunchPath:path
                                                arguments:taskArgs];
        pid = task ? [task processIdentifier] : -1;
    }

    if (-1 != pid) {
        // The 'pidArguments' dictionary keeps arguments to be passed to the
        // process when it connects (this is in contrast to arguments which are
        // passed on the command line, like '-f' and '-g').
        // NOTE: If there are no arguments to pass we still add a null object
        // so that we can use this dictionary to check if there are any
        // processes loading.
        NSNumber *pidKey = [NSNumber numberWithInt:pid];
        if (![pidArguments objectForKey:pidKey])
            [pidArguments setObject:[NSNull null] forKey:pidKey];
    } else {
        ASLogWarn(@"Failed to launch Vim process: args=%@, useLoginShell=%d",
                  args, useLoginShell);
    }

    // Now that child has launched, restore the current working directory.
    if (restoreCwd)
        [fm changeCurrentDirectoryPath:restoreCwd];

    return pid;
}

- (NSArray *)filterFilesAndNotify:(NSArray *)filenames
{
    // Go trough 'filenames' array and make sure each file exists.  Present
    // warning dialog if some file was missing.

    NSString *firstMissingFile = nil;
    NSMutableArray *files = [NSMutableArray array];
    unsigned i, count = [filenames count];

    for (i = 0; i < count; ++i) {
        NSString *name = [filenames objectAtIndex:i];
        if ([[NSFileManager defaultManager] fileExistsAtPath:name]) {
            [files addObject:name];
        } else if (!firstMissingFile) {
            firstMissingFile = name;
        }
    }

    if (firstMissingFile) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:NSLocalizedString(@"OK",
                @"Dialog button")];

        NSString *text;
        if ([files count] >= count-1) {
            [alert setMessageText:NSLocalizedString(@"File not found",
                    @"File not found dialog, title")];
            text = [NSString stringWithFormat:NSLocalizedString(
                    @"Could not open file with name %@.",
                    @"File not found dialog, text"), firstMissingFile];
        } else {
            [alert setMessageText:NSLocalizedString(@"Multiple files not found",
                    @"File not found dialog, title")];
            text = [NSString stringWithFormat:NSLocalizedString(
                    @"Could not open file with name %@, and %d other files.",
                    @"File not found dialog, text"),
                firstMissingFile, count-[files count]-1];
        }

        [alert setInformativeText:text];
        [alert setAlertStyle:NSWarningAlertStyle];

        [alert runModal];
        [alert release];

        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
    }

    return files;
}

- (NSArray *)filterOpenFiles:(NSArray *)filenames
               openFilesDict:(NSDictionary **)openFiles
{
    // Filter out any files in the 'filenames' array that are open and return
    // all files that are not already open.  On return, the 'openFiles'
    // parameter (if non-nil) will point to a dictionary of open files, indexed
    // by Vim controller.

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSMutableArray *files = [filenames mutableCopy];

    // TODO: Escape special characters in 'files'?
    NSString *expr = [NSString stringWithFormat:
            @"map([\"%@\"],\"bufloaded(v:val)\")",
            [files componentsJoinedByString:@"\",\""]];

    unsigned i, count = [vimControllers count];
    for (i = 0; i < count && [files count] > 0; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];

        // Query Vim for which files in the 'files' array are open.
        NSString *eval = [vc evaluateVimExpression:expr];
        if (!eval) continue;

        NSIndexSet *idxSet = [NSIndexSet indexSetWithVimList:eval];
        if ([idxSet count] > 0) {
            [dict setObject:[files objectsAtIndexes:idxSet]
                     forKey:[NSValue valueWithPointer:vc]];

            // Remove all the files that were open in this Vim process and
            // create a new expression to evaluate.
            [files removeObjectsAtIndexes:idxSet];
            expr = [NSString stringWithFormat:
                    @"map([\"%@\"],\"bufloaded(v:val)\")",
                    [files componentsJoinedByString:@"\",\""]];
        }
    }

    if (openFiles != nil)
        *openFiles = dict;

    return [files autorelease];
}

#if MM_HANDLE_XCODE_MOD_EVENT
- (void)handleXcodeModEvent:(NSAppleEventDescriptor *)event
                 replyEvent:(NSAppleEventDescriptor *)reply
{
#if 0
    // Xcode sends this event to query MacVim which open files have been
    // modified.
    ASLogDebug(@"reply:%@", reply);
    ASLogDebug(@"event:%@", event);

    NSEnumerator *e = [vimControllers objectEnumerator];
    id vc;
    while ((vc = [e nextObject])) {
        DescType type = [reply descriptorType];
        unsigned len = [[type data] length];
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&type length:sizeof(DescType)];
        [data appendBytes:&len length:sizeof(unsigned)];
        [data appendBytes:[reply data] length:len];

        [vc sendMessage:XcodeModMsgID data:data];
    }
#endif
}
#endif

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event
               replyEvent:(NSAppleEventDescriptor *)reply
{
    NSURL *url = [NSURL URLWithString:[[event
                                        paramDescriptorForKeyword:keyDirectObject]
                                        stringValue]];

    // We try to be compatible with TextMate's URL scheme here, as documented
    // at http://blog.macromates.com/2007/the-textmate-url-scheme/ . Currently,
    // this means that:
    //
    // The format is: mvim://open?<arguments> where arguments can be:
    //
    // * url — the actual file to open (i.e. a file://… URL), if you leave
    //         out this argument, the frontmost document is implied.
    // * line — line number to go to (one based).
    // * column — column number to go to (one based).
    //
    // Example: mvim://open?url=file:///etc/profile&line=20

    if ([[url host] isEqualToString:@"open"]) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];

        // Parse query ("url=file://...&line=14") into a dictionary
        NSArray *queries = [[url query] componentsSeparatedByString:@"&"];
        NSEnumerator *enumerator = [queries objectEnumerator];
        NSString *param;
        while ((param = [enumerator nextObject])) {
            NSArray *arr = [param componentsSeparatedByString:@"="];
            if ([arr count] == 2) {
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_11
                [dict setValue:[[arr lastObject] stringByRemovingPercentEncoding]
                        forKey:[[arr objectAtIndex:0] stringByRemovingPercentEncoding]];
#else
                [dict setValue:[[arr lastObject]
                            stringByReplacingPercentEscapesUsingEncoding:
                                NSUTF8StringEncoding]
                        forKey:[[arr objectAtIndex:0]
                            stringByReplacingPercentEscapesUsingEncoding:
                                NSUTF8StringEncoding]];
#endif
            }
        }

        // Actually open the file.
        NSString *file = [dict objectForKey:@"url"];
        if (file != nil) {
            NSURL *fileUrl= [NSURL URLWithString:file];
            // TextMate only opens files that already exist.
            if ([fileUrl isFileURL]
                    && [[NSFileManager defaultManager] fileExistsAtPath:
                           [fileUrl path]]) {
                // Strip 'file://' path, else application:openFiles: might think
                // the file is not yet open.
                NSArray *filenames = [NSArray arrayWithObject:[fileUrl path]];

                // Look for the line and column options.
                NSDictionary *args = nil;
                NSString *line = [dict objectForKey:@"line"];
                if (line) {
                    NSString *column = [dict objectForKey:@"column"];
                    if (column)
                        args = [NSDictionary dictionaryWithObjectsAndKeys:
                                line, @"cursorLine",
                                column, @"cursorColumn",
                                nil];
                    else
                        args = [NSDictionary dictionaryWithObject:line
                                forKey:@"cursorLine"];
                }

                [self openFiles:filenames withArguments:args];
            }
        }
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:NSLocalizedString(@"OK",
            @"Dialog button")];

        [alert setMessageText:NSLocalizedString(@"Unknown URL Scheme",
            @"Unknown URL Scheme dialog, title")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(
            @"This version of MacVim does not support \"%@\""
            @" in its URL scheme.",
            @"Unknown URL Scheme dialog, text"),
            [url host]]];

        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
    }
}

- (NSMutableDictionary *)extractArgumentsFromOdocEvent:
    (NSAppleEventDescriptor *)desc
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // 1. Extract ODB parameters (if any)
    NSAppleEventDescriptor *odbdesc = desc;
    if (![odbdesc paramDescriptorForKeyword:keyFileSender]) {
        // The ODB paramaters may hide inside the 'keyAEPropData' descriptor.
        odbdesc = [odbdesc paramDescriptorForKeyword:keyAEPropData];
        if (![odbdesc paramDescriptorForKeyword:keyFileSender])
            odbdesc = nil;
    }

    if (odbdesc) {
        NSAppleEventDescriptor *p =
                [odbdesc paramDescriptorForKeyword:keyFileSender];
        if (p)
            [dict setObject:[NSNumber numberWithUnsignedInt:[p typeCodeValue]]
                     forKey:@"remoteID"];

        p = [odbdesc paramDescriptorForKeyword:keyFileCustomPath];
        if (p)
            [dict setObject:[p stringValue] forKey:@"remotePath"];

        p = [odbdesc paramDescriptorForKeyword:keyFileSenderToken];
        if (p) {
            [dict setObject:[NSNumber numberWithUnsignedLong:[p descriptorType]]
                     forKey:@"remoteTokenDescType"];
            [dict setObject:[p data] forKey:@"remoteTokenData"];
        }
    }

    // 2. Extract Xcode parameters (if any)
    NSAppleEventDescriptor *xcodedesc =
            [desc paramDescriptorForKeyword:keyAEPosition];
    if (xcodedesc) {
        NSRange range;
        NSData *data = [xcodedesc data];
        NSUInteger length = [data length];

        if (length == sizeof(MMXcodeSelectionRange)) {
            MMXcodeSelectionRange *sr = (MMXcodeSelectionRange*)[data bytes];
            ASLogDebug(@"Xcode selection range (%d,%d,%d,%d,%d,%d)",
                    sr->unused1, sr->lineNum, sr->startRange, sr->endRange,
                    sr->unused2, sr->theDate);

            if (sr->lineNum < 0) {
                // Should select a range of characters.
                range.location = sr->startRange + 1;
                range.length = sr->endRange > sr->startRange
                             ? sr->endRange - sr->startRange : 1;
            } else {
                // Should only move cursor to a line.
                range.location = sr->lineNum + 1;
                range.length = 0;
            }

            [dict setObject:NSStringFromRange(range) forKey:@"selectionRange"];
        } else {
            ASLogErr(@"Xcode selection range size mismatch! got=%ld "
                     "expected=%ld", length, sizeof(MMXcodeSelectionRange));
        }
    }

    // 3. Extract Spotlight search text (if any)
    NSAppleEventDescriptor *spotlightdesc = 
            [desc paramDescriptorForKeyword:keyAESearchText];
    if (spotlightdesc) {
        NSString *s = [[spotlightdesc stringValue]
                                            stringBySanitizingSpotlightSearch];
        if (s && [s length] > 0)
            [dict setObject:s forKey:@"searchText"];
    }

    return dict;
}

- (void)scheduleVimControllerPreloadAfterDelay:(NSTimeInterval)delay
{
    [self performSelector:@selector(preloadVimController:)
               withObject:nil
               afterDelay:delay];
}

- (void)cancelVimControllerPreloadRequests
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
            selector:@selector(preloadVimController:)
              object:nil];
}

- (void)preloadVimController:(id)sender
{
    // We only allow preloading of one Vim process at a time (to avoid hogging
    // CPU), so schedule another preload in a little while if necessary.
    if (-1 != preloadPid) {
        [self scheduleVimControllerPreloadAfterDelay:2];
        return;
    }

    if ([cachedVimControllers count] >= [self maxPreloadCacheSize])
        return;

    preloadPid = [self launchVimProcessWithArguments:
                                    [NSArray arrayWithObject:@"--mmwaitforack"]
                                    workingDirectory:nil];

    // This method is kicked off via FSEvents, so if MacVim is in the
    // background, the runloop won't bother flushing the autorelease pool.
    // Triggering an NSEvent works around this.
    // http://www.mikeash.com/pyblog/more-fun-with-autorelease.html
    NSEvent* event = [NSEvent otherEventWithType:NSApplicationDefined
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:0
                                           data1:0
                                           data2:0];
    [NSApp postEvent:event atStart:NO];
}

- (int)maxPreloadCacheSize
{
    // The maximum number of Vim processes to keep in the cache can be
    // controlled via the user default "MMPreloadCacheSize".
    int maxCacheSize = [[NSUserDefaults standardUserDefaults]
            integerForKey:MMPreloadCacheSizeKey];
    if (maxCacheSize < 0) maxCacheSize = 0;
    else if (maxCacheSize > 10) maxCacheSize = 10;

    return maxCacheSize;
}

- (MMVimController *)takeVimControllerFromCache
{
    // NOTE: After calling this message the backend corresponding to the
    // returned vim controller must be sent an acknowledgeConnection message,
    // else the vim process will be stuck.
    //
    // This method may return nil even though the cache might be non-empty; the
    // caller should handle this by starting a new Vim process.

    int i, count = [cachedVimControllers count];
    if (0 == count) return nil;

    // Locate the first Vim controller with up-to-date rc-files sourced.
    NSDate *rcDate = [self rcFilesModificationDate];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [cachedVimControllers objectAtIndex:i];
        NSDate *date = [vc creationDate];
        if ([date compare:rcDate] != NSOrderedAscending)
            break;
    }

    if (i > 0) {
        // Clear out cache entries whose vimrc/gvimrc files were sourced before
        // the latest modification date for those files.  This ensures that the
        // latest rc-files are always sourced for new windows.
        [self clearPreloadCacheWithCount:i];
    }

    if ([cachedVimControllers count] == 0) {
        [self scheduleVimControllerPreloadAfterDelay:2.0];
        return nil;
    }

    MMVimController *vc = [cachedVimControllers objectAtIndex:0];
    [vimControllers addObject:vc];
    [cachedVimControllers removeObjectAtIndex:0];
    [vc setIsPreloading:NO];

    // If the Vim process has finished loading then the window will displayed
    // now, otherwise it will be displayed when the OpenWindowMsgID message is
    // received.
    [[vc windowController] presentWindow:nil];

    // Since we've taken one controller from the cache we take the opportunity
    // to preload another.
    [self scheduleVimControllerPreloadAfterDelay:1];

    return vc;
}

- (void)clearPreloadCacheWithCount:(int)count
{
    // Remove the 'count' first entries in the preload cache.  It is assumed
    // that objects are added/removed from the cache in a FIFO manner so that
    // this effectively clears the 'count' oldest entries.
    // If 'count' is negative, then the entire cache is cleared.

    if ([cachedVimControllers count] == 0 || count == 0)
        return;

    if (count < 0)
        count = [cachedVimControllers count];

    // Make sure the preloaded Vim processes get killed or they'll just hang
    // around being useless until MacVim is terminated.
    NSEnumerator *e = [cachedVimControllers objectEnumerator];
    MMVimController *vc;
    int n = count;
    while ((vc = [e nextObject]) && n-- > 0) {
        [[NSNotificationCenter defaultCenter] removeObserver:vc];
        [vc sendMessage:TerminateNowMsgID data:nil];

        // Since the preloaded processes were killed "prematurely" we have to
        // manually tell them to cleanup (it is not enough to simply release
        // them since deallocation and cleanup are separated).
        [vc cleanup];
    }

    n = count;
    while (n-- > 0 && [cachedVimControllers count] > 0)
        [cachedVimControllers removeObjectAtIndex:0];

    // There is a small delay before the Vim process actually exits so wait a
    // little before trying to reap the child process.  If the process still
    // hasn't exited after this wait it won't be reaped until the next time
    // reapChildProcesses: is called (but this should be harmless).
    [self performSelector:@selector(reapChildProcesses:)
               withObject:nil
               afterDelay:0.1];
}

- (void)rebuildPreloadCache
{
    if ([self maxPreloadCacheSize] > 0) {
        [self clearPreloadCacheWithCount:-1];
        [self cancelVimControllerPreloadRequests];
        [self scheduleVimControllerPreloadAfterDelay:1.0];
    }
}

- (NSDate *)rcFilesModificationDate
{
    // Check modification dates for ~/.vimrc and ~/.gvimrc and return the
    // latest modification date.  If ~/.vimrc does not exist, check ~/_vimrc
    // and similarly for gvimrc.
    // Returns distantPath if no rc files were found.

    NSDate *date = [NSDate distantPast];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *path = [@"~/.vimrc" stringByExpandingTildeInPath];
    NSDictionary *attr = [fm attributesOfItemAtPath:path error:NULL];
    if (!attr) {
        path = [@"~/_vimrc" stringByExpandingTildeInPath];
        attr = [fm attributesOfItemAtPath:path error:NULL];
    }
    NSDate *modDate = [attr objectForKey:NSFileModificationDate];
    if (modDate)
        date = modDate;

    path = [@"~/.gvimrc" stringByExpandingTildeInPath];
    attr = [fm attributesOfItemAtPath:path error:NULL];
    if (!attr) {
        path = [@"~/_gvimrc" stringByExpandingTildeInPath];
        attr = [fm attributesOfItemAtPath:path error:NULL];
    }
    modDate = [attr objectForKey:NSFileModificationDate];
    if (modDate)
        date = [date laterDate:modDate];

    return date;
}

- (BOOL)openVimControllerWithArguments:(NSDictionary *)arguments
{
    MMVimController *vc = [self takeVimControllerFromCache];
    if (vc) {
        // Open files in a new window using a cached vim controller.  This
        // requires virtually no loading time so the new window will pop up
        // instantaneously.
        [vc passArguments:arguments];
        [[vc backendProxy] acknowledgeConnection];
    } else {
        NSArray *cmdline = nil;
        NSString *cwd = [self workingDirectoryForArguments:arguments];
        arguments = [self convertVimControllerArguments:arguments
                                          toCommandLine:&cmdline];
        int pid = [self launchVimProcessWithArguments:cmdline
                                     workingDirectory:cwd];
        if (-1 == pid)
            return NO;

        // TODO: If the Vim process fails to start, or if it changes PID,
        // then the memory allocated for these parameters will leak.
        // Ensure that this cannot happen or somehow detect it.

        if ([arguments count] > 0)
            [pidArguments setObject:arguments
                             forKey:[NSNumber numberWithInt:pid]];
    }

    return YES;
}

- (void)activateWhenNextWindowOpens
{
    ASLogDebug(@"Activate MacVim when next window opens");
    shouldActivateWhenNextWindowOpens = YES;
}

- (void)startWatchingVimDir
{
    if (fsEventStream)
        return;

    NSString *path = [@"~/.vim" stringByExpandingTildeInPath];
    NSArray *pathsToWatch = [NSArray arrayWithObject:path];
 
    fsEventStream = FSEventStreamCreate(NULL, &fsEventCallback, NULL,
            (CFArrayRef)pathsToWatch, kFSEventStreamEventIdSinceNow,
            MMEventStreamLatency, kFSEventStreamCreateFlagNone);

    FSEventStreamScheduleWithRunLoop(fsEventStream,
            [[NSRunLoop currentRunLoop] getCFRunLoop],
            kCFRunLoopDefaultMode);

    FSEventStreamStart(fsEventStream);
    ASLogDebug(@"Started FS event stream");
}

- (void)stopWatchingVimDir
{
    if (fsEventStream) {
        FSEventStreamStop(fsEventStream);
        FSEventStreamInvalidate(fsEventStream);
        FSEventStreamRelease(fsEventStream);
        fsEventStream = NULL;
        ASLogDebug(@"Stopped FS event stream");
    }
}

- (void)handleFSEvent
{
    [self clearPreloadCacheWithCount:-1];

    // Several FS events may arrive in quick succession so make sure to cancel
    // any previous preload requests before making a new one.
    [self cancelVimControllerPreloadRequests];
    [self scheduleVimControllerPreloadAfterDelay:0.5];
}

- (int)executeInLoginShell:(NSString *)path arguments:(NSArray *)args
{
    // Start a login shell and execute the command 'path' with arguments 'args'
    // in the shell.  This ensures that user environment variables are set even
    // when MacVim was started from the Finder.

    int pid = -1;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // Determine which shell to use to execute the command.  The user
    // may decide which shell to use by setting a user default or the
    // $SHELL environment variable.
    NSString *shell = [ud stringForKey:MMLoginShellCommandKey];
    if (!shell || [shell length] == 0)
        shell = [[[NSProcessInfo processInfo] environment]
            objectForKey:@"SHELL"];
    if (!shell)
        shell = @"/bin/bash";

    // Bash needs the '-l' flag to launch a login shell.  The user may add
    // flags by setting a user default.
    NSString *shellArgument = [ud stringForKey:MMLoginShellArgumentKey];
    if (!shellArgument || [shellArgument length] == 0) {
        if ([[shell lastPathComponent] isEqual:@"bash"])
            shellArgument = @"-l";
        else
            shellArgument = nil;
    }

    // Build input string to pipe to the login shell.
    NSMutableString *input = [NSMutableString stringWithFormat:
            @"exec \"%@\"", path];
    if (args) {
        // Append all arguments, making sure they are properly quoted, even
        // when they contain single quotes.
        NSEnumerator *e = [args objectEnumerator];
        id obj;

        while ((obj = [e nextObject])) {
            NSMutableString *arg = [NSMutableString stringWithString:obj];
            [arg replaceOccurrencesOfString:@"'" withString:@"'\"'\"'"
                                    options:NSLiteralSearch
                                      range:NSMakeRange(0, [arg length])];
            [input appendFormat:@" '%@'", arg];
        }
    }

    // Build the argument vector used to start the login shell.
    NSString *shellArg0 = [NSString stringWithFormat:@"-%@",
             [shell lastPathComponent]];
    char *shellArgv[3] = { (char *)[shellArg0 UTF8String], NULL, NULL };
    if (shellArgument)
        shellArgv[1] = (char *)[shellArgument UTF8String];

    // Get the C string representation of the shell path before the fork since
    // we must not call Foundation functions after a fork.
    const char *shellPath = [shell fileSystemRepresentation];

    // Fork and execute the process.
    int ds[2];
    if (pipe(ds)) return -1;

    pid = fork();
    if (pid == -1) {
        return -1;
    } else if (pid == 0) {
        // Child process

        if (close(ds[1]) == -1) exit(255);
        if (dup2(ds[0], 0) == -1) exit(255);

        // Without the following call warning messages like this appear on the
        // console:
        //     com.apple.launchd[69] : Stray process with PGID equal to this
        //                             dead job: PID 1589 PPID 1 Vim
        setsid();

        execv(shellPath, shellArgv);

        // Never reached unless execv fails
        exit(255);
    } else {
        // Parent process
        if (close(ds[0]) == -1) return -1;

        // Send input to execute to the child process
        [input appendString:@"\n"];
        int bytes = [input lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (write(ds[1], [input UTF8String], bytes) != bytes) return -1;
        if (close(ds[1]) == -1) return -1;

        ++numChildProcesses;
        ASLogDebug(@"new process pid=%d (count=%d)", pid, numChildProcesses);
    }

    return pid;
}

- (void)reapChildProcesses:(id)sender
{
    // NOTE: numChildProcesses (currently) only counts the number of Vim
    // processes that have been started with executeInLoginShell::.  If other
    // processes are spawned this code may need to be adjusted (or
    // numChildProcesses needs to be incremented when such a process is
    // started).
    while (numChildProcesses > 0) {
        int status = 0;
        int pid = waitpid(-1, &status, WNOHANG);
        if (pid <= 0)
            break;

        ASLogDebug(@"Wait for pid=%d complete", pid);
        --numChildProcesses;
    }
}

- (void)processInputQueues:(id)sender
{
    // NOTE: Because we use distributed objects it is quite possible for this
    // function to be re-entered.  This can cause all sorts of unexpected
    // problems so we guard against it here so that the rest of the code does
    // not need to worry about it.

    // The processing flag is > 0 if this function is already on the call
    // stack; < 0 if this function was also re-entered.
    if (processingFlag != 0) {
        ASLogDebug(@"BUSY!");
        processingFlag = -1;
        return;
    }

    // NOTE: Be _very_ careful that no exceptions can be raised between here
    // and the point at which 'processingFlag' is reset.  Otherwise the above
    // test could end up always failing and no input queues would ever be
    // processed!
    processingFlag = 1;

    // NOTE: New input may arrive while we're busy processing; we deal with
    // this by putting the current queue aside and creating a new input queue
    // for future input.
    NSDictionary *queues = inputQueues;
    inputQueues = [NSMutableDictionary new];

    // Pass each input queue on to the vim controller with matching
    // identifier (and note that it could be cached).
    NSEnumerator *e = [queues keyEnumerator];
    NSNumber *key;
    while ((key = [e nextObject])) {
        unsigned ukey = [key unsignedIntValue];
        int i = 0, count = [vimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [vimControllers objectAtIndex:i];
            if (ukey == [vc vimControllerId]) {
                [vc processInputQueue:[queues objectForKey:key]]; // !exceptions
                break;
            }
        }

        if (i < count) continue;

        count = [cachedVimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [cachedVimControllers objectAtIndex:i];
            if (ukey == [vc vimControllerId]) {
                [vc processInputQueue:[queues objectForKey:key]]; // !exceptions
                break;
            }
        }

        if (i == count) {
            ASLogWarn(@"No Vim controller for identifier=%d", ukey);
        }
    }

    [queues release];

    // If new input arrived while we were processing it would have been
    // blocked so we have to schedule it to be processed again.
    if (processingFlag < 0)
        [self performSelectorOnMainThread:@selector(processInputQueues:)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:[NSArray arrayWithObjects:
                                           NSDefaultRunLoopMode,
                                           NSEventTrackingRunLoopMode, nil]];

    processingFlag = 0;
}

- (void)addVimController:(MMVimController *)vc
{
    ASLogDebug(@"Add Vim controller pid=%d id=%d",
            [vc pid], [vc vimControllerId]);

    int pid = [vc pid];
    NSNumber *pidKey = [NSNumber numberWithInt:pid];
    id args = [pidArguments objectForKey:pidKey];

    if (preloadPid == pid) {
        // This controller was preloaded, so add it to the cache and
        // schedule another vim process to be preloaded.
        preloadPid = -1;
        [vc setIsPreloading:YES];
        [cachedVimControllers addObject:vc];
        [self scheduleVimControllerPreloadAfterDelay:1];
    } else {
        [vimControllers addObject:vc];

        if (args && [NSNull null] != args)
            [vc passArguments:args];

        // HACK!  MacVim does not get activated if it is launched from the
        // terminal, so we forcibly activate here.  Note that each process
        // launched from MacVim has an entry in the pidArguments dictionary,
        // which is how we detect if the process was launched from the
        // terminal.
        if (!args) [self activateWhenNextWindowOpens];
    }

    if (args)
        [pidArguments removeObjectForKey:pidKey];
}

- (NSDictionary *)convertVimControllerArguments:(NSDictionary *)args
                                  toCommandLine:(NSArray **)cmdline
{
    // Take all arguments out of 'args' and put them on an array suitable to
    // pass as arguments to launchVimProcessWithArguments:.  The untouched
    // dictionary items are returned in a new autoreleased dictionary.

    if (cmdline)
        *cmdline = nil;

    NSArray *filenames = [args objectForKey:@"filenames"];
    int numFiles = filenames ? [filenames count] : 0;
    BOOL openFiles = ![[args objectForKey:@"dontOpen"] boolValue];

    if (numFiles <= 0 || !openFiles)
        return args;

    NSMutableArray *a = [NSMutableArray array];
    NSMutableDictionary *d = [[args mutableCopy] autorelease];

    // Search for text and highlight it (this Vim script avoids warnings in
    // case there is no match for the search text).
    NSString *searchText = [args objectForKey:@"searchText"];
    if (searchText && [searchText length] > 0) {
        [a addObject:@"-c"];
        NSString *s = [NSString stringWithFormat:@"if search('\\V\\c%@','cW')"
                "|let @/='\\V\\c%@'|set hls|endif", searchText, searchText];
        [a addObject:s];

        [d removeObjectForKey:@"searchText"];
    }

    // Position cursor using "+line" or "-c :cal cursor(line,column)".
    NSString *lineString = [args objectForKey:@"cursorLine"];
    if (lineString && [lineString intValue] > 0) {
        NSString *columnString = [args objectForKey:@"cursorColumn"];
        if (columnString && [columnString intValue] > 0) {
            [a addObject:@"-c"];
            [a addObject:[NSString stringWithFormat:@":cal cursor(%@,%@)",
                          lineString, columnString]];

            [d removeObjectForKey:@"cursorColumn"];
        } else {
            [a addObject:[NSString stringWithFormat:@"+%@", lineString]];
        }

        [d removeObjectForKey:@"cursorLine"];
    }

    // Set selection using normal mode commands.
    NSString *rangeString = [args objectForKey:@"selectionRange"];
    if (rangeString) {
        NSRange r = NSRangeFromString(rangeString);
        [a addObject:@"-c"];
        if (r.length > 0) {
            // Select given range of characters.
            // TODO: This only works for encodings where 1 byte == 1 character
            [a addObject:[NSString stringWithFormat:@"norm %ldgov%ldgo",
                                                r.location, NSMaxRange(r)-1]];
        } else {
            // Position cursor on line at start of range.
            [a addObject:[NSString stringWithFormat:@"norm %ldGz.0",
                                                                r.location]];
        }

        [d removeObjectForKey:@"selectionRange"];
    }

    // Choose file layout using "-[o|O|p]".
    int layout = [[args objectForKey:@"layout"] intValue];
    switch (layout) {
        case MMLayoutHorizontalSplit: [a addObject:@"-o"]; break;
        case MMLayoutVerticalSplit:   [a addObject:@"-O"]; break;
        case MMLayoutTabs:            [a addObject:@"-p"]; break;
    }
    [d removeObjectForKey:@"layout"];


    // Last of all add the names of all files to open (DO NOT add more args
    // after this point).
    [a addObjectsFromArray:filenames];

    if ([args objectForKey:@"remoteID"]) {
        // These files should be edited remotely so keep the filenames on the
        // argument list -- they will need to be passed back to Vim when it
        // checks in.  Also set the 'dontOpen' flag or the files will be
        // opened twice.
        [d setObject:[NSNumber numberWithBool:YES] forKey:@"dontOpen"];
    } else {
        [d removeObjectForKey:@"dontOpen"];
        [d removeObjectForKey:@"filenames"];
    }

    if (cmdline)
        *cmdline = a;

    return d;
}

- (NSString *)workingDirectoryForArguments:(NSDictionary *)args
{
    // Find the "filenames" argument and pick the first path that actually
    // exists and return it.
    // TODO: Return common parent directory in the case of multiple files?
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *filenames = [args objectForKey:@"filenames"];
    NSUInteger i, count = [filenames count];
    for (i = 0; i < count; ++i) {
        BOOL isdir;
        NSString *file = [filenames objectAtIndex:i];
        if ([fm fileExistsAtPath:file isDirectory:&isdir])
            return isdir ? file : [file stringByDeletingLastPathComponent];
    }

    return nil;
}

- (NSScreen *)screenContainingTopLeftPoint:(NSPoint)pt
{
    // NOTE: The top left point has y-coordinate which lies one pixel above the
    // window which must be taken into consideration (this method used to be
    // called screenContainingPoint: but that method is "off by one" in
    // y-coordinate).

    NSArray *screens = [NSScreen screens];
    NSUInteger i, count = [screens count];
    for (i = 0; i < count; ++i) {
        NSScreen *screen = [screens objectAtIndex:i];
        NSRect frame = [screen frame];
        if (pt.x >= frame.origin.x && pt.x < NSMaxX(frame)
                // NOTE: inequalities below are correct due to this being a top
                // left test (see comment above)
                && pt.y > frame.origin.y && pt.y <= NSMaxY(frame))
            return screen;
    }

    return nil;
}

- (void)addInputSourceChangedObserver
{
    id nc = [NSDistributedNotificationCenter defaultCenter];
    NSString *notifyInputSourceChanged =
        (NSString *)kTISNotifySelectedKeyboardInputSourceChanged;
    [nc addObserver:self
           selector:@selector(inputSourceChanged:)
               name:notifyInputSourceChanged
             object:nil];
}

- (void)removeInputSourceChangedObserver
{
    id nc = [NSDistributedNotificationCenter defaultCenter];
    [nc removeObserver:self];
}

- (void)inputSourceChanged:(NSNotification *)notification
{
    unsigned i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        MMWindowController *wc = [controller windowController];
        MMTextView *tv = (MMTextView *)[[wc vimView] textView];
        [tv checkImState];
    }
}

@end // MMAppController (Private)
