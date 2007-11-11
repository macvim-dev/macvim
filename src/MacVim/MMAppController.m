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



// Default timeout intervals on all connections.
static NSTimeInterval MMRequestTimeout = 5;
static NSTimeInterval MMReplyTimeout = 5;



@interface MMAppController (MMServices)
- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)userData
                error:(NSString **)error;
- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error;
@end


@interface MMAppController (Private)
- (MMVimController *)keyVimController;
- (MMVimController *)topmostVimController;
- (void)launchVimProcessWithArguments:(NSArray *)args;
- (NSArray *)filterFilesAndNotify:(NSArray *)files;
- (NSArray *)filterOpenFilesAndRaiseFirst:(NSArray *)filenames;
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

    [vimControllers release];
    [openSelectionString release];

    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [NSApp setServicesProvider:self];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    // NOTE!  This way it possible to start the app with the command-line
    // argument '-nowindow yes' and no window will be opened by default.
    untitledWindowOpening =
        ![[NSUserDefaults standardUserDefaults] boolForKey:MMNoWindowKey];
    return untitledWindowOpening;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender
{
    //NSLog(@"%s NSapp=%@ theApp=%@", _cmd, NSApp, sender);

    [self newWindow:self];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    filenames = [self filterOpenFilesAndRaiseFirst:filenames];
    if ([filenames count]) {
        MMVimController *vc;
        BOOL openInTabs = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMOpenFilesInTabsKey];

        if (openInTabs && (vc = [self topmostVimController])) {
            [vc dropFiles:filenames];
        } else {
            NSMutableArray *args = [NSMutableArray arrayWithObject:@"-p"];
            [args addObjectsFromArray:filenames];
            [self launchVimProcessWithArguments:args];
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
    while (window = [e nextObject]) {
        if ([window isDocumentEdited]) {
            modifiedBuffers = YES;
            break;
        }
    }

    if (modifiedBuffers) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Quit"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert setMessageText:@"Quit without saving?"];
        [alert setInformativeText:@"There are modified buffers, "
            "if you quit now all changes will be lost.  Quit anyway?"];
        [alert setAlertStyle:NSWarningAlertStyle];

        if ([alert runModal] != NSAlertFirstButtonReturn)
            reply = NSTerminateCancel;

        [alert release];
    }

    return reply;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
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

    // TODO: Is this a correct way of releasing the MMAppController?
    // (It doesn't seem like dealloc is ever called.)
    [NSApp setDelegate:nil];
    [self autorelease];
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

- (byref id <MMFrontendProtocol>)
    connectBackend:(byref in id <MMBackendProtocol>)backend
               pid:(int)pid
{
    //NSLog(@"Frontend got connection request from backend...adding new "
    //        "MMVimController");

    [(NSDistantObject*)backend
            setProtocolForProxy:@protocol(MMBackendProtocol)];

    MMVimController *vc = [[[MMVimController alloc]
            initWithBackend:backend pid:pid] autorelease];

    if (![vimControllers count]) {
        // The first window autosaves its position.  (The autosaving features
        // of Cocoa are not used because we need more control over what is
        // autosaved and when it is restored.)
        [[vc windowController] setWindowAutosaveKey:MMTopLeftPointKey];
    }

    [vimControllers addObject:vc];

    // HACK!  MacVim does not get activated if it is launched from the
    // terminal, so we forcibly activate here unless it is an untitled window
    // opening (i.e. MacVim was opened from the Finder).  Untitled windows are
    // treated differently, else MacVim would steal the focus if another app
    // was activated while the untitled window was loading.
    if (!untitledWindowOpening)
        [NSApp activateIgnoringOtherApps:YES];

    untitledWindowOpening = NO;

    return vc;
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
            [vc dropFiles:filenames];
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

- (void)launchVimProcessWithArguments:(NSArray *)args
{
    NSString *path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"Vim"];
    if (!path) {
        NSLog(@"ERROR: Vim executable could not be found inside app bundle!");
        return;
    }

    NSMutableString *execArg = [NSMutableString
        stringWithFormat:@"exec \"%@\" -g", path];
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

    // Launch the process with a login shell so that users environment settings
    // get sourced.  This does not always happen when MacVim is started.
    NSArray *shellArgs = [NSArray arrayWithObjects:@"-l", @"-c", execArg, nil];
    NSString *shell = [[[NSProcessInfo processInfo] environment]
        objectForKey:@"SHELL"];
    if (!shell)
        shell = @"/bin/sh";

    //NSLog(@"Launching: %@  args: %@", shell, shellArgs);
    [NSTask launchedTaskWithLaunchPath:shell arguments:shellArgs];
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

- (NSArray *)filterOpenFilesAndRaiseFirst:(NSArray *)filenames
{
    // Check if any of the files in the 'filenames' array are open in any Vim
    // process.  Remove the files that are open from the 'filenames' array and
    // return it.  If all files were filtered out, then raise the first file in
    // the Vim process it is open.

    MMVimController *raiseController = nil;
    NSString *raiseFile = nil;
    NSMutableArray *files = [filenames mutableCopy];
    NSString *expr = [NSString stringWithFormat:
            @"map([\"%@\"],\"bufloaded(v:val)\")",
            [files componentsJoinedByString:@"\",\""]];
    unsigned i, count = [vimControllers count];

    for (i = 0; i < count && [files count]; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        id proxy = [controller backendProxy];

        @try {
            NSString *eval = [proxy evaluateExpression:expr];
            NSIndexSet *idxSet = [NSIndexSet indexSetWithVimList:eval];
            if ([idxSet count]) {
                if (!raiseFile) {
                    // Remember the file and which Vim that has it open so that
                    // we can raise it later on.
                    raiseController = controller;
                    raiseFile = [files objectAtIndex:[idxSet firstIndex]];
                    [[raiseFile retain] autorelease];
                }

                // Remove all the files that were open in this Vim process and
                // create a new expression to evaluate.
                [files removeObjectsAtIndexes:idxSet];
                expr = [NSString stringWithFormat:
                        @"map([\"%@\"],\"bufloaded(v:val)\")",
                        [files componentsJoinedByString:@"\",\""]];
            }
        }
        @catch (NSException *e) {
            // Do nothing ...
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
