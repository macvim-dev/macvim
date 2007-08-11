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



@implementation MMAppController

+ (void)initialize
{
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:NO],   MMNoWindowKey,
        [NSNumber numberWithInt:64],    MMTabMinWidthKey,
        [NSNumber numberWithInt:6*64],  MMTabMaxWidthKey,
        [NSNumber numberWithInt:132],   MMTabOptimumWidthKey,
        [NSNumber numberWithBool:NO],   MMStatuslineOffKey,
        [NSNumber numberWithInt:2],     MMTextInsetLeftKey,
        [NSNumber numberWithInt:1],     MMTextInsetRightKey,
        [NSNumber numberWithInt:1],     MMTextInsetTopKey,
        [NSNumber numberWithInt:1],     MMTextInsetBottomKey,
        [NSNumber numberWithBool:NO],   MMTerminateAfterLastWindowClosedKey,
        @"MMTypesetter",                MMTypesetterKey,
        [NSNumber numberWithFloat:1],   MMCellWidthMultiplierKey,
        [NSNumber numberWithFloat:-1],  MMBaselineOffsetKey,
        [NSNumber numberWithBool:YES],  MMTranslateCtrlClickKey,
        nil];

    [[NSUserDefaults standardUserDefaults] registerDefaults:dict];

    NSArray *types = [NSArray arrayWithObject:NSStringPboardType];
    [NSApp registerServicesMenuSendTypes:types returnTypes:types];
}

- (id)init
{
    if ((self = [super init])) {
        vimControllers = [NSMutableArray new];

        // NOTE!  If the name of the connection changes here it must also be
        // updated in MMBackend.m.
        NSConnection *connection = [NSConnection defaultConnection];
        NSString *name = [NSString stringWithFormat:@"%@-connection",
                 [[NSBundle mainBundle] bundleIdentifier]];
        //NSLog(@"Registering connection with name '%@'", name);
        if ([connection registerName:name]) {
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
    return ![[NSUserDefaults standardUserDefaults] boolForKey:MMNoWindowKey];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender
{
    //NSLog(@"%s NSapp=%@ theApp=%@", _cmd, NSApp, sender);

    [self newVimWindow:self];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    NSString *firstMissingFile = nil;
    NSMutableArray *files = [NSMutableArray array];
    int i, count = [filenames count];
    for (i = 0; i < count; ++i) {
        NSString *name = [filenames objectAtIndex:i];
        if ([NSFileHandle fileHandleForReadingAtPath:name]) {
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

        return;
    }

    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-g", @"-p", nil];
    [args addObjectsFromArray:files];

    NSString *path = [[NSBundle mainBundle]
            pathForAuxiliaryExecutable:@"Vim"];

    [NSTask launchedTaskWithLaunchPath:path arguments:args];

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

    unsigned i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        id proxy = [controller backendProxy];
        if (proxy && [proxy checkForModifiedBuffers]) {
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
           " if you quit now all changes will be lost.  Quit anyway?"];
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
    // NOTE! Is this a correct way of releasing the MMAppController?
    [NSApp setDelegate:nil];
    [self autorelease];
}

- (void)removeVimController:(id)controller
{
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
}

- (IBAction)newVimWindow:(id)sender
{
    NSMutableArray *args = [NSMutableArray arrayWithObject:@"-g"];
    NSString *path = [[NSBundle mainBundle]
            pathForAuxiliaryExecutable:@"Vim"];

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

- (byref id <MMFrontendProtocol>)connectBackend:
    (byref in id <MMBackendProtocol>)backend;
{
    //NSLog(@"Frontend got connection request from backend...adding new "
    //        "MMVimController");

    [(NSDistantObject*)backend
            setProtocolForProxy:@protocol(MMBackendProtocol)];

    MMVimController *vc = [[[MMVimController alloc] initWithBackend:backend]
            autorelease];

    if (![vimControllers count]) {
        // The first window autosaves its position.  (The autosaving features
        // of Cocoa are not used because we need more control over what is
        // autosaved and when it is restored.)
        [[vc windowController] setWindowAutosaveKey:MMTopLeftPointKey];
    }

    [vimControllers addObject:vc];

    // HACK!  MacVim does not get activated if it is launched from the
    // terminal, so we forcibly activate here.
    [NSApp activateIgnoringOtherApps:YES];

    return vc;
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
        NSString *string = [pboard stringForType:NSStringPboardType];
        NSMutableData *data = [NSMutableData data];
        int len = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;

        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:[string UTF8String] length:len];

        [vc sendMessage:AddNewTabMsgID data:nil wait:NO];
        [vc sendMessage:DropStringMsgID data:data wait:NO];
    } else {
        // TODO: Open the selection in the new window.
        *error = @"ERROR: No window found to open selection in.";
        [self newVimWindow:self];
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
    int numberOfFiles = 1;
    NSString *string = [pboard stringForType:NSStringPboardType];
    string = [string stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    string = [string stringByStandardizingPath];

    MMVimController *vc = nil;
    if (userData && [userData isEqual:@"Tab"])
        vc = [self topmostVimController];

    if (vc) {
        NSMutableData *data = [NSMutableData data];
        int len = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        [data appendBytes:&numberOfFiles length:sizeof(int)];
        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:[string UTF8String] length:len];

        [vc sendMessage:DropFilesMsgID data:data wait:NO];
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
