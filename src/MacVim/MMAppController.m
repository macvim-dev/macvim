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
 * coordinates all MMVimControllers.
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
 */

#import "MMAppController.h"
#import "MMVimController.h"
#import "MMWindowController.h"
#import "MMPreferenceController.h"
#import <unistd.h>


#define MM_HANDLE_XCODE_MOD_EVENT 0



// Default timeout intervals on all connections.
static NSTimeInterval MMRequestTimeout = 5;
static NSTimeInterval MMReplyTimeout = 5;

static NSString *MMWebsiteString = @"http://code.google.com/p/macvim/";


#pragma options align=mac68k
typedef struct
{
    short unused1;      // 0 (not used)
    short lineNum;      // line to select (< 0 to specify range)
    long  startRange;   // start of selection range (if line < 0)
    long  endRange;     // end of selection range (if line < 0)
    long  unused2;      // 0 (not used)
    long  theDate;      // modification date/time
} MMSelectionRange;
#pragma options align=reset


static int executeInLoginShell(NSString *path, NSArray *args);


@interface MMAppController (MMServices)
- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)userData
                error:(NSString **)error;
- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error;
@end


@interface MMAppController (Private)
- (MMVimController *)keyVimController;
- (MMVimController *)topmostVimController;
- (int)launchVimProcessWithArguments:(NSArray *)args;
- (NSArray *)filterFilesAndNotify:(NSArray *)files;
- (NSArray *)filterOpenFiles:(NSArray *)filenames
                   arguments:(NSDictionary *)args;
#if MM_HANDLE_XCODE_MOD_EVENT
- (void)handleXcodeModEvent:(NSAppleEventDescriptor *)event
                 replyEvent:(NSAppleEventDescriptor *)reply;
#endif
- (int)findLaunchingProcessWithoutArguments;
- (MMVimController *)findUntitledWindow;
- (NSMutableDictionary *)extractArgumentsFromOdocEvent:
    (NSAppleEventDescriptor *)desc;
- (void)passArguments:(NSDictionary *)args toVimController:(MMVimController*)vc;
@end


@interface NSNumber (MMExtras)
- (int)tag;
@end


@interface NSMenu (MMExtras)
- (int)indexOfItemWithAction:(SEL)action;
- (NSMenuItem *)itemWithAction:(SEL)action;
- (NSMenu *)findMenuContainingItemWithAction:(SEL)action;
- (NSMenu *)findWindowsMenu;
- (NSMenu *)findApplicationMenu;
- (NSMenu *)findServicesMenu;
- (NSMenu *)findFileMenu;
@end




@implementation MMAppController

+ (void)initialize
{
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:NO],   MMNoWindowKey,
        [NSNumber numberWithInt:64],    MMTabMinWidthKey,
        [NSNumber numberWithInt:6*64],  MMTabMaxWidthKey,
        [NSNumber numberWithInt:132],   MMTabOptimumWidthKey,
        [NSNumber numberWithInt:2],     MMTextInsetLeftKey,
        [NSNumber numberWithInt:1],     MMTextInsetRightKey,
        [NSNumber numberWithInt:1],     MMTextInsetTopKey,
        [NSNumber numberWithInt:1],     MMTextInsetBottomKey,
        [NSNumber numberWithBool:NO],   MMTerminateAfterLastWindowClosedKey,
        @"MMTypesetter",                MMTypesetterKey,
        [NSNumber numberWithFloat:1],   MMCellWidthMultiplierKey,
        [NSNumber numberWithFloat:-1],  MMBaselineOffsetKey,
        [NSNumber numberWithBool:YES],  MMTranslateCtrlClickKey,
        [NSNumber numberWithBool:NO],   MMOpenFilesInTabsKey,
        [NSNumber numberWithBool:NO],   MMNoFontSubstitutionKey,
        [NSNumber numberWithBool:NO],   MMLoginShellKey,
        [NSNumber numberWithBool:NO],   MMAtsuiRendererKey,
        [NSNumber numberWithInt:MMUntitledWindowAlways],
                                        MMUntitledWindowKey,
        [NSNumber numberWithBool:NO],   MMTexturedWindowKey,
        [NSNumber numberWithBool:NO],   MMZoomBothKey,
        @"",                            MMLoginShellCommandKey,
        @"",                            MMLoginShellArgumentKey,
        [NSNumber numberWithBool:YES],  MMDialogsTrackPwdKey,
        nil];

    [[NSUserDefaults standardUserDefaults] registerDefaults:dict];

    NSArray *types = [NSArray arrayWithObject:NSStringPboardType];
    [NSApp registerServicesMenuSendTypes:types returnTypes:types];
}

- (id)init
{
    if ((self = [super init])) {
        fontContainerRef = loadFonts();

        vimControllers = [NSMutableArray new];
        pidArguments = [NSMutableDictionary new];

        // NOTE: Do not use the default connection since the Logitech Control
        // Center (LCC) input manager steals and this would cause MacVim to
        // never open any windows.  (This is a bug in LCC but since they are
        // unlikely to fix it, we graciously give them the default connection.)
        connection = [[NSConnection alloc] initWithReceivePort:[NSPort port]
                                                      sendPort:nil];
        [connection setRootObject:self];
        [connection setRequestTimeout:MMRequestTimeout];
        [connection setReplyTimeout:MMReplyTimeout];

        // NOTE: When the user is resizing the window the AppKit puts the run
        // loop in event tracking mode.  Unless the connection listens to
        // request in this mode, live resizing won't work.
        [connection addRequestMode:NSEventTrackingRunLoopMode];

        // NOTE!  If the name of the connection changes here it must also be
        // updated in MMBackend.m.
        NSString *name = [NSString stringWithFormat:@"%@-connection",
                 [[NSBundle mainBundle] bundleIdentifier]];
        //NSLog(@"Registering connection with name '%@'", name);
        if (![connection registerName:name]) {
            NSLog(@"FATAL ERROR: Failed to register connection with name '%@'",
                    name);
            [connection release];  connection = nil;
        }
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"MMAppController dealloc");

    [connection release];  connection = nil;
    [pidArguments release];  pidArguments = nil;
    [vimControllers release];  vimControllers = nil;
    [openSelectionString release];  openSelectionString = nil;
    [recentFilesMenuItem release];  recentFilesMenuItem = nil;
    [defaultMainMenu release];  defaultMainMenu = nil;

    [super dealloc];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Remember the default menu so that it can be restored if the user closes
    // all editor windows.
    defaultMainMenu = [[NSApp mainMenu] retain];

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
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [NSApp setServicesProvider:self];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSAppleEventManager *aem = [NSAppleEventManager sharedAppleEventManager];
    NSAppleEventDescriptor *desc = [aem currentAppleEvent];

    // The user default MMUntitledWindow can be set to control whether an
    // untitled window should open on 'Open' and 'Reopen' events.
    int untitledWindowFlag = [ud integerForKey:MMUntitledWindowKey];
    if ([desc eventID] == kAEOpenApplication
            && (untitledWindowFlag & MMUntitledWindowOnOpen) == 0)
        return NO;
    else if ([desc eventID] == kAEReopenApplication
            && (untitledWindowFlag & MMUntitledWindowOnReopen) == 0)
        return NO;

    // When a process is started from the command line, the 'Open' event will
    // contain a parameter to surpress the opening of an untitled window.
    desc = [desc paramDescriptorForKeyword:keyAEPropData];
    desc = [desc paramDescriptorForKeyword:keyMMUntitledWindow];
    if (desc && ![desc booleanValue])
        return NO;

    // Never open an untitled window if there is at least one open window or if
    // there are processes that are currently launching.
    if ([vimControllers count] > 0 || [pidArguments count] > 0)
        return NO;

    // NOTE!  This way it possible to start the app with the command-line
    // argument '-nowindow yes' and no window will be opened by default.
    return ![ud boolForKey:MMNoWindowKey];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender
{
    [self newWindow:self];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    // Opening files works like this:
    //  a) extract ODB/Xcode/Spotlight parameters from the current Apple event
    //  b) filter out any already open files (see filterOpenFiles::)
    //  c) open any remaining files
    //
    // A file is opened in an untitled window if there is one (it may be
    // currently launching, or it may already be visible), otherwise a new
    // window is opened.
    //
    // Each launching Vim process has a dictionary of arguments that are passed
    // to the process when in checks in (via connectBackend:pid:).  The
    // arguments for each launching process can be looked up by its PID (in the
    // pidArguments dictionary).

    NSMutableDictionary *arguments = [self extractArgumentsFromOdocEvent:
            [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent]];

    // Filter out files that are already open
    filenames = [self filterOpenFiles:filenames arguments:arguments];

    // Open any files that remain
    if ([filenames count]) {
        MMVimController *vc;
        BOOL openInTabs = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMOpenFilesInTabsKey];

        [arguments setObject:filenames forKey:@"filenames"];
        [arguments setObject:[NSNumber numberWithBool:YES] forKey:@"openFiles"];

        // Add file names to "Recent Files" menu.
        int i, count = [filenames count];
        for (i = 0; i < count; ++i) {
            // Don't add files that are being edited remotely (using ODB).
            if ([arguments objectForKey:@"remoteID"]) continue;

            [[NSDocumentController sharedDocumentController]
                    noteNewRecentFilePath:[filenames objectAtIndex:i]];
        }

        if ((openInTabs && (vc = [self topmostVimController]))
               || (vc = [self findUntitledWindow])) {
            // Open files in an already open window.
            [[[vc windowController] window] makeKeyAndOrderFront:self];
            [self passArguments:arguments toVimController:vc];
        } else {
            // Open files in a launching Vim process or start a new process.
            int pid = [self findLaunchingProcessWithoutArguments];
            if (!pid) {
                // Pass the filenames to the process straight away.
                //
                // TODO: It would be nicer if all arguments were passed to the
                // Vim process in connectBackend::, but if we don't pass the
                // filename arguments here, the window 'flashes' once when it
                // opens.  This is due to the 'welcome' screen first being
                // displayed, then quickly thereafter the files are opened.
                NSArray *fileArgs = [NSArray arrayWithObject:@"-p"];
                fileArgs = [fileArgs arrayByAddingObjectsFromArray:filenames];

                pid = [self launchVimProcessWithArguments:fileArgs];

                if (-1 == pid) {
                    // TODO: Notify user of failure?
                    [NSApp replyToOpenOrPrint:
                        NSApplicationDelegateReplyFailure];
                    return;
                }

                // Make sure these files aren't opened again when
                // connectBackend:pid: is called.
                [arguments setObject:[NSNumber numberWithBool:NO]
                              forKey:@"openFiles"];
            }

            // TODO: If the Vim process fails to start, or if it changes PID,
            // then the memory allocated for these parameters will leak.
            // Ensure that this cannot happen or somehow detect it.

            if ([arguments count] > 0)
                [pidArguments setObject:arguments
                                 forKey:[NSNumber numberWithInt:pid]];
        }
    }

    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    // NSApplicationDelegateReplySuccess = 0,
    // NSApplicationDelegateReplyCancel = 1,
    // NSApplicationDelegateReplyFailure = 2
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return [[NSUserDefaults standardUserDefaults]
            boolForKey:MMTerminateAfterLastWindowClosedKey];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication *)sender
{
    // TODO: Follow Apple's guidelines for 'Graceful Application Termination'
    // (in particular, allow user to review changes and save).
    int reply = NSTerminateNow;
    BOOL modifiedBuffers = NO;

    // Go through windows, checking for modified buffers.  (Each Vim process
    // tells MacVim when any buffer has been modified and MacVim sets the
    // 'documentEdited' flag of the window correspondingly.)
    NSEnumerator *e = [[NSApp windows] objectEnumerator];
    id window;
    while ((window = [e nextObject])) {
        if ([window isDocumentEdited]) {
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
    } else {
        // No unmodified buffers, but give a warning if there are multiple
        // windows and/or tabs open.
        int numWindows = [vimControllers count];
        int numTabs = 0;

        // Count the number of open tabs
        e = [vimControllers objectEnumerator];
        id vc;
        while ((vc = [e nextObject])) {
            NSString *eval = [vc evaluateVimExpression:@"tabpagenr('$')"];
            if (eval) {
                int count = [eval intValue];
                if (count > 0 && count < INT_MAX)
                    numTabs += count;
            }
        }

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

            [alert release];
        }
    }


    // Tell all Vim processes to terminate now (otherwise they'll leave swap
    // files behind).
    if (NSTerminateNow == reply) {
        e = [vimControllers objectEnumerator];
        id vc;
        while ((vc = [e nextObject]))
            [vc sendMessage:TerminateNowMsgID data:nil];
    }

    return reply;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
#if MM_HANDLE_XCODE_MOD_EVENT
    [[NSAppleEventManager sharedAppleEventManager]
            removeEventHandlerForEventClass:'KAHL'
                                 andEventID:'MOD '];
#endif

    // This will invalidate all connections (since they were spawned from this
    // connection).
    [connection invalidate];

    // Send a SIGINT to all running Vim processes, so that they are sure to
    // receive the connectionDidDie: notification (a process has to be checking
    // the run-loop for this to happen).
    unsigned i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        int pid = [controller pid];
        if (pid > 0)
            kill(pid, SIGINT);
    }

    if (fontContainerRef) {
        ATSFontDeactivate(fontContainerRef, NULL, kATSOptionFlagsDefault);
        fontContainerRef = 0;
    }

    [NSApp setDelegate:nil];
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

- (void)removeVimController:(id)controller
{
    //NSLog(@"%s%@", _cmd, controller);

    [[controller windowController] close];

    [vimControllers removeObject:controller];

    if (![vimControllers count]) {
        // The last editor window just closed so restore the main menu back to
        // its default state (which is defined in MainMenu.nib).
        [self setMainMenu:defaultMainMenu];
    }
}

- (void)windowControllerWillOpen:(MMWindowController *)windowController
{
    NSPoint topLeft = NSZeroPoint;
    NSWindow *topWin = [[[self topmostVimController] windowController] window];
    NSWindow *win = [windowController window];

    if (!win) return;

    // If there is a window belonging to a Vim process, cascade from it,
    // otherwise use the autosaved window position (if any).
    if (topWin) {
        NSRect frame = [topWin frame];
        topLeft = NSMakePoint(frame.origin.x, NSMaxY(frame));
    } else {
        NSString *topLeftString = [[NSUserDefaults standardUserDefaults]
            stringForKey:MMTopLeftPointKey];
        if (topLeftString)
            topLeft = NSPointFromString(topLeftString);
    }

    if (!NSEqualPoints(topLeft, NSZeroPoint)) {
        if (topWin)
            topLeft = [win cascadeTopLeftFromPoint:topLeft];

        [win setFrameTopLeftPoint:topLeft];
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
}

- (void)setMainMenu:(NSMenu *)mainMenu
{
    if ([NSApp mainMenu] == mainMenu) return;

    // If the new menu has a "Recent Files" dummy item, then swap the real item
    // for the dummy.  We are forced to do this since Cocoa initializes the
    // "Recent Files" menu and there is no way to simply point Cocoa to a new
    // item each time the menus are swapped.
    NSMenu *fileMenu = [mainMenu findFileMenu];
    int dummyIdx =
            [fileMenu indexOfItemWithAction:@selector(recentFilesDummy:)];
    if (dummyIdx >= 0 && recentFilesMenuItem) {
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

        [NSApp setWindowsMenu:windowsMenu];
    }
}

- (IBAction)newWindow:(id)sender
{
    [self launchVimProcessWithArguments:nil];
}

- (IBAction)fileOpen:(id)sender
{
    NSString *dir = nil;
    BOOL trackPwd = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMDialogsTrackPwdKey];
    if (trackPwd) {
        MMVimController *vc = [self keyVimController];
        if (vc) dir = [[vc vimState] objectForKey:@"pwd"];
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:YES];
    int result = [panel runModalForDirectory:dir file:nil types:nil];
    if (NSOKButton == result)
        [self application:NSApp openFiles:[panel filenames]];
}

- (IBAction)selectNextWindow:(id)sender
{
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

- (IBAction)fontSizeUp:(id)sender
{
    [[NSFontManager sharedFontManager] modifyFont:
            [NSNumber numberWithInt:NSSizeUpFontAction]];
}

- (IBAction)fontSizeDown:(id)sender
{
    [[NSFontManager sharedFontManager] modifyFont:
            [NSNumber numberWithInt:NSSizeDownFontAction]];
}

- (IBAction)orderFrontPreferencePanel:(id)sender
{
    [[MMPreferenceController sharedPrefsWindowController] showWindow:self];
}

- (IBAction)openWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:
            [NSURL URLWithString:MMWebsiteString]];
}

- (IBAction)showHelp:(id)sender
{
    [self launchVimProcessWithArguments:[NSArray arrayWithObjects:
            @"-c", @":h gui_mac", nil]];
}

- (IBAction)zoomAll:(id)sender
{
    [NSApp makeWindowsPerform:@selector(performZoom:) inOrder:YES];
}

- (byref id <MMFrontendProtocol>)
    connectBackend:(byref in id <MMBackendProtocol>)backend
               pid:(int)pid
{
    //NSLog(@"Connect backend (pid=%d)", pid);
    NSNumber *pidKey = [NSNumber numberWithInt:pid];
    MMVimController *vc = nil;

    @try {
        [(NSDistantObject*)backend
                setProtocolForProxy:@protocol(MMBackendProtocol)];

        vc = [[[MMVimController alloc]
            initWithBackend:backend pid:pid]
            autorelease];

        if (![vimControllers count]) {
            // The first window autosaves its position.  (The autosaving
            // features of Cocoa are not used because we need more control over
            // what is autosaved and when it is restored.)
            [[vc windowController] setWindowAutosaveKey:MMTopLeftPointKey];
        }

        [vimControllers addObject:vc];

        id args = [pidArguments objectForKey:pidKey];
        if (args && [NSNull null] != args)
            [self passArguments:args toVimController:vc];

        // HACK!  MacVim does not get activated if it is launched from the
        // terminal, so we forcibly activate here unless it is an untitled
        // window opening.  Untitled windows are treated differently, else
        // MacVim would steal the focus if another app was activated while the
        // untitled window was loading.
        if (!args || args != [NSNull null])
            [NSApp activateIgnoringOtherApps:YES];

        if (args)
            [pidArguments removeObjectForKey:pidKey];

        return vc;
    }

    @catch (NSException *e) {
        NSLog(@"Exception caught in %s: \"%@\"", _cmd, e);

        if (vc)
            [vimControllers removeObject:vc];

        [pidArguments removeObjectForKey:pidKey];
    }

    return nil;
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
        NSLog(@"WARNING: Pasteboard contains no object of type "
                "NSStringPboardType");
        return;
    }

    MMVimController *vc = [self topmostVimController];
    if (vc) {
        // Open a new tab first, since dropString: does not do this.
        [vc sendMessage:AddNewTabMsgID data:nil];
        [vc dropString:[pboard stringForType:NSStringPboardType]];
    } else {
        // NOTE: There is no window to paste the selection into, so save the
        // text, open a new window, and paste the text when the next window
        // opens.  (If this is called several times in a row, then all but the
        // last call might be ignored.)
        if (openSelectionString) [openSelectionString release];
        openSelectionString = [[pboard stringForType:NSStringPboardType] copy];

        [self newWindow:self];
    }
}

- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error
{
    if (![[pboard types] containsObject:NSStringPboardType]) {
        NSLog(@"WARNING: Pasteboard contains no object of type "
                "NSStringPboardType");
        return;
    }

    // TODO: Parse multiple filenames and create array with names.
    NSString *string = [pboard stringForType:NSStringPboardType];
    string = [string stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    string = [string stringByStandardizingPath];

    NSArray *filenames = [self filterFilesAndNotify:
            [NSArray arrayWithObject:string]];
    if ([filenames count] > 0) {
        MMVimController *vc = nil;
        if (userData && [userData isEqual:@"Tab"])
            vc = [self topmostVimController];

        if (vc) {
            [vc dropFiles:filenames forceOpen:YES];
        } else {
            [self application:NSApp openFiles:filenames];
        }
    }
}

@end // MMAppController (MMServices)




@implementation MMAppController (Private)

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

- (MMVimController *)topmostVimController
{
    // Find the topmost visible window which has an associated vim controller.
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

    return nil;
}

- (int)launchVimProcessWithArguments:(NSArray *)args
{
    int pid = -1;
    NSString *path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"Vim"];

    if (!path) {
        NSLog(@"ERROR: Vim executable could not be found inside app bundle!");
        return -1;
    }

    NSArray *taskArgs = [NSArray arrayWithObjects:@"-g", @"-f", nil];
    if (args)
        taskArgs = [taskArgs arrayByAddingObjectsFromArray:args];

    BOOL useLoginShell = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMLoginShellKey];
    if (useLoginShell) {
        // Run process with a login shell, roughly:
        //   echo "exec Vim -g -f args" | ARGV0=-`basename $SHELL` $SHELL [-l]
        pid = executeInLoginShell(path, taskArgs);
    } else {
        // Run process directly:
        //   Vim -g -f args
        NSTask *task = [NSTask launchedTaskWithLaunchPath:path
                                                arguments:taskArgs];
        pid = task ? [task processIdentifier] : -1;
    }

    if (-1 != pid) {
        // NOTE: If the process has no arguments, then add a null argument to
        // the pidArguments dictionary.  This is later used to detect that a
        // process without arguments is being launched.
        if (!args)
            [pidArguments setObject:[NSNull null]
                             forKey:[NSNumber numberWithInt:pid]];
    } else {
        NSLog(@"WARNING: %s%@ failed (useLoginShell=%d)", _cmd, args,
                useLoginShell);
    }

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
                   arguments:(NSDictionary *)args
{
    // Check if any of the files in the 'filenames' array are open in any Vim
    // process.  Remove the files that are open from the 'filenames' array and
    // return it.  If all files were filtered out, then raise the first file in
    // the Vim process it is open.  Files that are filtered are sent an odb
    // open event in case theID is not zero.

    NSMutableDictionary *localArgs =
            [NSMutableDictionary dictionaryWithDictionary:args];
    MMVimController *raiseController = nil;
    NSString *raiseFile = nil;
    NSMutableArray *files = [filenames mutableCopy];
    NSString *expr = [NSString stringWithFormat:
            @"map([\"%@\"],\"bufloaded(v:val)\")",
            [files componentsJoinedByString:@"\",\""]];
    unsigned i, count = [vimControllers count];

    // Ensure that the files aren't opened when passing arguments.
    [localArgs setObject:[NSNumber numberWithBool:NO] forKey:@"openFiles"];

    for (i = 0; i < count && [files count]; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];

        // Query Vim for which files in the 'files' array are open.
        NSString *eval = [controller evaluateVimExpression:expr];
        if (!eval) continue;

        NSIndexSet *idxSet = [NSIndexSet indexSetWithVimList:eval];
        if ([idxSet count]) {
            if (!raiseFile) {
                // Remember the file and which Vim that has it open so that
                // we can raise it later on.
                raiseController = controller;
                raiseFile = [files objectAtIndex:[idxSet firstIndex]];
                [[raiseFile retain] autorelease];
            }

            // Pass (ODB/Xcode/Spotlight) arguments to this process.
            [localArgs setObject:[files objectsAtIndexes:idxSet]
                          forKey:@"filenames"];
            [self passArguments:localArgs toVimController:controller];

            // Remove all the files that were open in this Vim process and
            // create a new expression to evaluate.
            [files removeObjectsAtIndexes:idxSet];
            expr = [NSString stringWithFormat:
                    @"map([\"%@\"],\"bufloaded(v:val)\")",
                    [files componentsJoinedByString:@"\",\""]];
        }
    }

    if (![files count] && raiseFile) {
        // Raise the window containing the first file that was already open,
        // and make sure that the tab containing that file is selected.  Only
        // do this if there are no more files to open, otherwise sometimes the
        // window with 'raiseFile' will be raised, other times it might be the
        // window that will open with the files in the 'files' array.
        raiseFile = [raiseFile stringByEscapingSpecialFilenameCharacters];
        NSString *input = [NSString stringWithFormat:@"<C-\\><C-N>"
            ":let oldswb=&swb|let &swb=\"useopen,usetab\"|"
            "tab sb %@|let &swb=oldswb|unl oldswb|"
            "cal foreground()|redr|f<CR>", raiseFile];

        [raiseController addVimInput:input];
    }

    return files;
}

#if MM_HANDLE_XCODE_MOD_EVENT
- (void)handleXcodeModEvent:(NSAppleEventDescriptor *)event
                 replyEvent:(NSAppleEventDescriptor *)reply
{
#if 0
    // Xcode sends this event to query MacVim which open files have been
    // modified.
    NSLog(@"reply:%@", reply);
    NSLog(@"event:%@", event);

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

- (int)findLaunchingProcessWithoutArguments
{
    NSArray *keys = [pidArguments allKeysForObject:[NSNull null]];
    if ([keys count] > 0) {
        //NSLog(@"found launching process without arguments");
        return [[keys objectAtIndex:0] intValue];
    }

    return 0;
}

- (MMVimController *)findUntitledWindow
{
    NSEnumerator *e = [vimControllers objectEnumerator];
    id vc;
    while ((vc = [e nextObject])) {
        // TODO: This is a moronic test...should query the Vim process if there
        // are any open buffers or something like that instead.
        NSString *title = [[[vc windowController] window] title];

        // TODO: this will not work in a localized MacVim
        if ([title hasPrefix:@"[No Name] - VIM"]) {
            //NSLog(@"found untitled window");
            return vc;
        }
    }

    return nil;
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
        if (p)
            [dict setObject:p forKey:@"remotePath"];
    }

    // 2. Extract Xcode parameters (if any)
    NSAppleEventDescriptor *xcodedesc =
            [desc paramDescriptorForKeyword:keyAEPosition];
    if (xcodedesc) {
        NSRange range;
        MMSelectionRange *sr = (MMSelectionRange*)[[xcodedesc data] bytes];

        if (sr->lineNum < 0) {
            // Should select a range of lines.
            range.location = sr->startRange + 1;
            range.length = sr->endRange - sr->startRange + 1;
        } else {
            // Should only move cursor to a line.
            range.location = sr->lineNum + 1;
            range.length = 0;
        }

        [dict setObject:NSStringFromRange(range) forKey:@"selectionRange"];
    }

    // 3. Extract Spotlight search text (if any)
    NSAppleEventDescriptor *spotlightdesc = 
            [desc paramDescriptorForKeyword:keyAESearchText];
    if (spotlightdesc)
        [dict setObject:[spotlightdesc stringValue] forKey:@"searchText"];

    return dict;
}

- (void)passArguments:(NSDictionary *)args toVimController:(MMVimController*)vc
{
    if (!args) return;

    // Pass filenames to open if required (the 'openFiles' argument can be used
    // to disallow opening of the files).
    NSArray *filenames = [args objectForKey:@"filenames"];
    if (filenames && [[args objectForKey:@"openFiles"] boolValue]) {
        NSString *tabDrop = buildTabDropCommand(filenames);
        [vc addVimInput:tabDrop];
    }

    // Pass ODB data
    if (filenames && [args objectForKey:@"remoteID"]) {
        [vc odbEdit:filenames
             server:[[args objectForKey:@"remoteID"] unsignedIntValue]
               path:[args objectForKey:@"remotePath"]
              token:[args objectForKey:@"remoteToken"]];
    }

    // Pass range of lines to select
    if ([args objectForKey:@"selectionRange"]) {
        NSRange selectionRange = NSRangeFromString(
                [args objectForKey:@"selectionRange"]);
        [vc addVimInput:buildSelectRangeCommand(selectionRange)];
    }

    // Pass search text
    NSString *searchText = [args objectForKey:@"searchText"];
    if (searchText)
        [vc addVimInput:buildSearchTextCommand(searchText)];
}

@end // MMAppController (Private)




@implementation NSNumber (MMExtras)
- (int)tag
{
    return [self intValue];
}
@end // NSNumber (MMExtras)




@implementation NSMenu (MMExtras)

- (int)indexOfItemWithAction:(SEL)action
{
    int i, count = [self numberOfItems];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [self itemAtIndex:i];
        if ([item action] == action)
            return i;
    }

    return -1;
}

- (NSMenuItem *)itemWithAction:(SEL)action
{
    int idx = [self indexOfItemWithAction:action];
    return idx >= 0 ? [self itemAtIndex:idx] : nil;
}

- (NSMenu *)findMenuContainingItemWithAction:(SEL)action
{
    // NOTE: We only look for the action in the submenus of 'self'
    int i, count = [self numberOfItems];
    for (i = 0; i < count; ++i) {
        NSMenu *menu = [[self itemAtIndex:i] submenu];
        NSMenuItem *item = [menu itemWithAction:action];
        if (item) return menu;
    }

    return nil;
}

- (NSMenu *)findWindowsMenu
{
    return [self findMenuContainingItemWithAction:
        @selector(performMiniaturize:)];
}

- (NSMenu *)findApplicationMenu
{
    // TODO: Just return [self itemAtIndex:0]?
    return [self findMenuContainingItemWithAction:@selector(terminate:)];
}

- (NSMenu *)findServicesMenu
{
    // NOTE!  Our heuristic for finding the "Services" menu is to look for the
    // second item before the "Hide MacVim" menu item on the "MacVim" menu.
    // (The item before "Hide MacVim" should be a separator, but this is not
    // important as long as the item before that is the "Services" menu.)

    NSMenu *appMenu = [self findApplicationMenu];
    if (!appMenu) return nil;

    int idx = [appMenu indexOfItemWithAction: @selector(hide:)];
    if (idx-2 < 0) return nil;  // idx == -1, if selector not found

    return [[appMenu itemAtIndex:idx-2] submenu];
}

- (NSMenu *)findFileMenu
{
    return [self findMenuContainingItemWithAction:@selector(performClose:)];
}

@end // NSMenu (MMExtras)




    static int
executeInLoginShell(NSString *path, NSArray *args)
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

    //NSLog(@"shell = %@", shell);

    // Bash needs the '-l' flag to launch a login shell.  The user may add
    // flags by setting a user default.
    NSString *shellArgument = [ud stringForKey:MMLoginShellArgumentKey];
    if (!shellArgument || [shellArgument length] == 0) {
        if ([[shell lastPathComponent] isEqual:@"bash"])
            shellArgument = @"-l";
        else
            shellArgument = nil;
    }

    //NSLog(@"shellArgument = %@", shellArgument);

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
    }

    return pid;
}
