/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMAppController.h"
#import "MMVimController.h"
#import "MMWindowController.h"



// Default timeout intervals on all connections.
static NSTimeInterval MMRequestTimeout = 5;
static NSTimeInterval MMReplyTimeout = 5;

// Timeout used when the app should terminate.
static NSTimeInterval MMTerminateTimeout = 3;



@interface MMAppController (MMServices)
- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)userData
                error:(NSString **)error;
- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error;
@end


@interface MMAppController (Private)
- (MMVimController *)keyVimController;
- (MMVimController *)topmostVimController;
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
    NSString *firstMissingFile = nil;
    NSMutableArray *files = [NSMutableArray array];
    int i, count = [filenames count];
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
        return;
    }

    MMVimController *vc;
    BOOL openInTabs = [[NSUserDefaults standardUserDefaults]
        boolForKey:MMOpenFilesInTabsKey];

    if (openInTabs && (vc = [self topmostVimController])) {
        [vc dropFiles:files];
    } else {
        NSMutableArray *args = [NSMutableArray arrayWithObjects:
            @"-g", @"-p", nil];
        [args addObjectsFromArray:files];

        NSString *path = [[NSBundle mainBundle]
                pathForAuxiliaryExecutable:@"Vim"];
        if (!path) {
            NSLog(@"ERROR: Vim executable could not be found inside app "
                   "bundle!");
            [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
            return;
        }

        [NSTask launchedTaskWithLaunchPath:path arguments:args];
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
    int reply = NSTerminateNow;
    BOOL modifiedBuffers = NO;
    BOOL notResponding = NO;

    // Go through vim controllers, checking for modified buffers.  If a process
    // is not responding then note this as well.
    unsigned i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        id proxy = [controller backendProxy];
        NSConnection *connection = [proxy connectionForProxy];
        if (connection) {
            NSTimeInterval req = [connection requestTimeout];
            NSTimeInterval rep = [connection replyTimeout];
            [connection setRequestTimeout:MMTerminateTimeout];
            [connection setReplyTimeout:MMTerminateTimeout];

            @try {
                if ([proxy checkForModifiedBuffers])
                    modifiedBuffers = YES;
            }
            @catch (NSException *e) {
                NSLog(@"WARNING: Got exception while waiting for "
                        "checkForModifiedBuffers: \"%@\"", e);
                notResponding = YES;
            }
            @finally {
                [connection setRequestTimeout:req];
                [connection setReplyTimeout:rep];
                if (modifiedBuffers || notResponding)
                    break;
            }
        }
    }

    if (modifiedBuffers || notResponding) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Quit"];
        [alert addButtonWithTitle:@"Cancel"];
        if (modifiedBuffers) {
            [alert setMessageText:@"Quit without saving?"];
            [alert setInformativeText:@"There are modified buffers, "
                "if you quit now all changes will be lost.  Quit anyway?"];
        } else {
            [alert setMessageText:@"Force Quit?"];
            [alert setInformativeText:@"At least one Vim process is not "
                "responding, if you quit now any changes you have made "
                "will be lost. Quit anyway?"];
        }
        [alert setAlertStyle:NSWarningAlertStyle];

        if ([alert runModal] != NSAlertFirstButtonReturn) {
            reply = NSTerminateCancel;
        }

        [alert release];
    }

    return reply;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Send a SIGINT to all running Vim processes, so that they are sure to
    // receive the connectionDidDie: notification (a process has to checking
    // the run-loop for this to happen).
    unsigned i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        int pid = [controller pid];
        if (pid > 0)
            kill(pid, SIGINT);

        id proxy = [controller backendProxy];
        NSConnection *connection = [proxy connectionForProxy];
        if (connection) {
            [connection invalidate];
        }
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
        // but do not touch the MacVim menu.
        NSMenu *mainMenu = [NSApp mainMenu];
        int i, count = [mainMenu numberOfItems];
        for (i = 1; i < count; ++i) {
            NSMenu *submenu = [[mainMenu itemAtIndex:i] submenu];
            [submenu recurseSetAutoenablesItems:YES];
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
    NSMutableArray *args = [NSMutableArray arrayWithObject:@"-g"];
    NSString *path = [[NSBundle mainBundle]
            pathForAuxiliaryExecutable:@"Vim"];
    if (!path) {
        NSLog(@"ERROR: Vim executable could not be found inside app bundle!");
        return;
    }


    //NSLog(@"Launching a new VimTask...");
    [NSTask launchedTaskWithLaunchPath:path arguments:args];
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

    MMVimController *vc = nil;
    if (userData && [userData isEqual:@"Tab"])
        vc = [self topmostVimController];

    if (vc) {
        [vc dropFiles:[NSArray arrayWithObject:string]];
    } else {
        [self application:NSApp openFiles:[NSArray arrayWithObject:string]];
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

@end




@implementation NSMenu (MMExtras)

- (void)recurseSetAutoenablesItems:(BOOL)on
{
    [self setAutoenablesItems:on];

    int i, count = [self numberOfItems];
    for (i = 0; i < count; ++i) {
        NSMenu *submenu = [[self itemAtIndex:i] submenu];
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
