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


#define MM_HANDLE_XCODE_MOD_EVENT 0



// Default timeout intervals on all connections.
static NSTimeInterval MMRequestTimeout = 5;
static NSTimeInterval MMReplyTimeout = 5;


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

@interface NSMenu (MMExtras)
- (void)recurseSetAutoenablesItems:(BOOL)on;
@end

@interface NSNumber (MMExtras)
- (int)tag;
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

        // NOTE!  If the name of the connection changes here it must also be
        // updated in MMBackend.m.
        NSConnection *connection = [NSConnection defaultConnection];
        NSString *name = [NSString stringWithFormat:@"%@-connection",
                 [[NSBundle mainBundle] bundleIdentifier]];
        //NSLog(@"Registering connection with name '%@'", name);
        if ([connection registerName:name]) {
            [connection setRequestTimeout:MMRequestTimeout];
            [connection setReplyTimeout:MMReplyTimeout];
            [connection setRootObject:self];

            // NOTE: When the user is resizing the window the AppKit puts the
            // run loop in event tracking mode.  Unless the connection listens
            // to request in this mode, live resizing won't work.
            [connection addRequestMode:NSEventTrackingRunLoopMode];
        } else {
            NSLog(@"WARNING: Failed to register connection with name '%@'",
                    name);
        }
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"MMAppController dealloc");

    [pidArguments release];  pidArguments = nil;
    [vimControllers release];  vimControllers = nil;
    [openSelectionString release];  openSelectionString = nil;

    [super dealloc];
}

#if MM_HANDLE_XCODE_MOD_EVENT
- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler:self
                andSelector:@selector(handleXcodeModEvent:replyEvent:)
              forEventClass:'KAHL'
                 andEventID:'MOD '];
}
#endif

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
        [alert addButtonWithTitle:@"Quit"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert setMessageText:@"Quit without saving?"];
        [alert setInformativeText:@"There are modified buffers, "
            "if you quit now all changes will be lost.  Quit anyway?"];

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
            [alert addButtonWithTitle:@"Quit"];
            [alert addButtonWithTitle:@"Cancel"];
            [alert setMessageText:@"Are you sure you want to quit MacVim?"];

            NSString *info = nil;
            if (numWindows > 1) {
                if (numTabs > numWindows)
                    info = [NSString stringWithFormat:@"There are %d windows "
                        "open in MacVim, with a total of %d tabs. Do you want "
                        "to quit anyway?", numWindows, numTabs];
                else
                    info = [NSString stringWithFormat:@"There are %d windows "
                        "open in MacVim. Do you want to quit anyway?",
                        numWindows];

            } else {
                info = [NSString stringWithFormat:@"There are %d tabs open "
                    "in MacVim. Do you want to quit anyway?", numTabs];
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

    // This will invalidate all connections (since they were spawned from the
    // default connection).
    [[NSConnection defaultConnection] invalidate];

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

- (void)removeVimController:(id)controller
{
    //NSLog(@"%s%@", _cmd, controller);

    [[controller windowController] close];

    [vimControllers removeObject:controller];

    if (![vimControllers count]) {
        // Turn on autoenabling of menus (because no Vim is open to handle it),
        // but do not touch the MacVim menu.  Note that the menus must be
        // enabled first otherwise autoenabling does not work.
        NSMenu *mainMenu = [NSApp mainMenu];
        int i, count = [mainMenu numberOfItems];
        for (i = 1; i < count; ++i) {
            NSMenuItem *item = [mainMenu itemAtIndex:i];
            [item setEnabled:YES];
            [[item submenu] recurseSetAutoenablesItems:YES];
        }
    }
}

- (void)windowControllerWillOpen:(MMWindowController *)windowController
{
    NSPoint topLeft = NSZeroPoint;
    NSWindow *keyWin = [NSApp keyWindow];
    NSWindow *win = [windowController window];

    if (!win) return;

    // If there is a key window, cascade from it, otherwise use the autosaved
    // window position (if any).
    if (keyWin) {
        NSRect frame = [keyWin frame];
        topLeft = NSMakePoint(frame.origin.x, NSMaxY(frame));
    } else {
        NSString *topLeftString = [[NSUserDefaults standardUserDefaults]
            stringForKey:MMTopLeftPointKey];
        if (topLeftString)
            topLeft = NSPointFromString(topLeftString);
    }

    if (!NSEqualPoints(topLeft, NSZeroPoint)) {
        if (keyWin)
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

- (IBAction)newWindow:(id)sender
{
    [self launchVimProcessWithArguments:nil];
}

- (IBAction)fileOpen:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:YES];

    int result = [panel runModalForTypes:nil];
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
    [[MMPreferenceController sharedPreferenceController] showWindow:self];
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
                initWithBackend:backend pid:pid] autorelease];

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
    NSArray *windows = [NSApp orderedWindows];
    if ([windows count] > 0) {
        NSWindow *window = [windows objectAtIndex:0];
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
    NSString *taskPath = nil;
    NSArray *taskArgs = nil;
    NSString *path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"Vim"];

    if (!path) {
        NSLog(@"ERROR: Vim executable could not be found inside app bundle!");
        return 0;
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey:MMLoginShellKey]) {
        // Run process with a login shell
        //   $SHELL -l -c "exec Vim -g -f args"
        // (-g for GUI, -f for foreground, i.e. don't fork)

        NSMutableString *execArg = [NSMutableString
            stringWithFormat:@"exec \"%@\" -g -f", path];
        if (args) {
            // Append all arguments while making sure that arguments containing
            // spaces are enclosed in quotes.
            NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
            unsigned i, count = [args count];

            for (i = 0; i < count; ++i) {
                NSString *arg = [args objectAtIndex:i];
                if (NSNotFound != [arg rangeOfCharacterFromSet:space].location)
                    [execArg appendFormat:@" \"%@\"", arg];
                else
                    [execArg appendFormat:@" %@", arg];
            }
        }

        // Launch the process with a login shell so that users environment
        // settings get sourced.  This does not always happen when MacVim is
        // started.
        taskArgs = [NSArray arrayWithObjects:@"-l", @"-c", execArg, nil];
        taskPath = [[[NSProcessInfo processInfo] environment]
            objectForKey:@"SHELL"];
        if (!taskPath)
            taskPath = @"/bin/sh";
    } else {
        // Run process directly:
        //   Vim -g -f args
        // (-g for GUI, -f for foreground, i.e. don't fork)
        taskPath = path;
        taskArgs = [NSArray arrayWithObjects:@"-g", @"-f", nil];
        if (args)
            taskArgs = [taskArgs arrayByAddingObjectsFromArray:args];
    }

    NSTask *task =[NSTask launchedTaskWithLaunchPath:taskPath
                                           arguments:taskArgs];
    //NSLog(@"launch %@ with args=%@ (pid=%d)", taskPath, taskArgs,
    //        [task processIdentifier]);

    int pid = [task processIdentifier];

    // If the process has no arguments, then add a null argument to the
    // pidArguments dictionary.  This is later used to detect that a process
    // without arguments is being launched.
    if (!args)
        [pidArguments setObject:[NSNull null]
                         forKey:[NSNumber numberWithInt:pid]];

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
        [alert addButtonWithTitle:@"OK"];

        NSString *text;
        if ([files count] >= count-1) {
            [alert setMessageText:@"File not found"];
            text = [NSString stringWithFormat:@"Could not open file with "
                "name %@.", firstMissingFile];
        } else {
            [alert setMessageText:@"Multiple files not found"];
            text = [NSString stringWithFormat:@"Could not open file with "
                "name %@, and %d other files.", firstMissingFile,
                count-[files count]-1];
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




@implementation NSMenu (MMExtras)

- (void)recurseSetAutoenablesItems:(BOOL)on
{
    [self setAutoenablesItems:on];

    int i, count = [self numberOfItems];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [self itemAtIndex:i];
        [item setEnabled:YES];
        NSMenu *submenu = [item submenu];
        if (submenu) {
            [submenu recurseSetAutoenablesItems:on];
        }
    }
}

@end  // NSMenu (MMExtras)




@implementation NSNumber (MMExtras)
- (int)tag
{
    return [self intValue];
}
@end // NSNumber (MMExtras)
