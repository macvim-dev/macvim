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



// NSUserDefaults keys
NSString *MMNoWindowKey                     = @"nowindow";
NSString *MMTabMinWidthKey                  = @"tabminwidth";
NSString *MMTabMaxWidthKey                  = @"tabmaxwidth";
NSString *MMTabOptimumWidthKey              = @"taboptimumwidth";
NSString *MMStatuslineOffKey                = @"statuslineoff";
NSString *MMTextInsetLeft                   = @"insetleft";
NSString *MMTextInsetRight                  = @"insetright";
NSString *MMTextInsetTop                    = @"insettop";
NSString *MMTextInsetBottom                 = @"insetbottom";
NSString *MMTerminateAfterLastWindowClosed  = @"terminateafterlastwindowclosed";



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
        [NSNumber numberWithInt:2],     MMTextInsetLeft,
        [NSNumber numberWithInt:1],     MMTextInsetRight,
        [NSNumber numberWithInt:1],     MMTextInsetTop,
        [NSNumber numberWithInt:1],     MMTextInsetBottom,
        [NSNumber numberWithBool:NO],   MMTerminateAfterLastWindowClosed,
        nil];

    [[NSUserDefaults standardUserDefaults] registerDefaults:dict];

    NSArray *types = [NSArray arrayWithObject:NSStringPboardType];
    [NSApp registerServicesMenuSendTypes:types returnTypes:types];
}

- (id)init
{
    if ((self = [super init])) {
        vimControllers = [NSMutableArray new];

#if MM_USE_DO
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
#else
        // Init named port for VimTasks to connect to
        receivePort = [NSMachPort new];
        [receivePort setDelegate:self];

        [[NSRunLoop currentRunLoop] addPort:receivePort
                                    forMode:NSDefaultRunLoopMode];

        // NOTE!  If the name of the port changes here it must also be updated
        // in MMBackend.m.
        NSString *portName = [NSString stringWithFormat:@"%@-taskport",
                 [[NSBundle mainBundle] bundleIdentifier]];
        //NSLog(@"Starting mach bootstrap server: %@", portName);
        if (![[NSMachBootstrapServer sharedInstance] registerPort:receivePort
                                                             name:portName]) {
            NSLog(@"WARNING: Failed to start mach bootstrap server");
        }
#endif
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"MMAppController dealloc");

#if !MM_USE_DO
    [receivePort release];
#endif
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
            boolForKey:MMTerminateAfterLastWindowClosed];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication *)sender
{
#if MM_USE_DO
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
#else
    int reply = NSTerminateNow;

    // HACK!  Send message to all vim tasks asking if they have modified
    // buffers, then hang around for a while waiting for responses to come
    // back.  If any task has at least one modified buffer an alert dialog is
    // displayed telling the user that there are modified buffers.  The user
    // can then choose whether to quit anyway, or cancel the termination.
    // (NSTerminateLater is not supported.)
    terminateNowCount = 0;
    abortTermination = NO;

    unsigned i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        [NSPortMessage sendMessage:TaskShouldTerminateMsgID
                      withSendPort:[controller sendPort]
                       receivePort:receivePort
                              wait:NO];
    }

    NSDate *timeOutDate = [NSDate dateWithTimeIntervalSinceNow:15];
    while (terminateNowCount < count && !abortTermination &&
            NSOrderedDescending == [timeOutDate compare:[NSDate date]]) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:timeOutDate];
    }

    //NSLog(@"%s terminateNowCount=%d abortTermination=%s", _cmd,
    //        terminateNowCount, abortTermination ? "YES" : "NO");

    if (abortTermination) {
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
    } else if (terminateNowCount < count) {
        NSLog(@"WARNING: Not all tasks replied to TaskShouldTerminateMsgID,"
                " quitting anyway.");
    }

    return reply;
#endif
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // NOTE! Is this a correct way of releasing the MMAppController?
    [NSApp setDelegate:nil];
    [self autorelease];
}

#if !MM_USE_DO
- (void)handlePortMessage:(NSPortMessage *)portMessage
{
    unsigned msgid = [portMessage msgid];

    if (msgid == CheckinMsgID) {
        //NSLog(@"Received checkin message from VimTask.");
        MMVimController *wc = [[MMVimController alloc]
                initWithPort:[portMessage sendPort]];
        [vimControllers addObject:wc];
        [wc release];
    } else if (msgid == TerminateReplyYesMsgID) {
        ++terminateNowCount;
    } else if (msgid == TerminateReplyNoMsgID) {
        abortTermination = YES;
    } else {
        NSLog(@"WARNING: Unknown message received (msgid=%d)", msgid);
    }
}
#endif

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
#if 0
    NSArray *windows = [NSApp orderedWindows];
    unsigned idx = [windows indexOfObject:[NSApp keyWindow]];
    if (NSNotFound != idx) {
        if (++idx >= [windows count])
            idx = 0;
        [[windows objectAtIndex:idx] makeKeyAndOrderFront:self];
    }
#else
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
#endif
}

- (IBAction)selectPreviousWindow:(id)sender
{
#if 0
    NSArray *windows = [NSApp orderedWindows];
    unsigned idx = [windows indexOfObject:[NSApp keyWindow]];
    if (NSNotFound != idx) {
        if (idx > 0) {
            --idx;
        } else {
            idx = [windows count] - 1;
        }
        [[windows objectAtIndex:idx] makeKeyAndOrderFront:self];
    }
#else
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
#endif
}


#if MM_USE_DO
- (byref id <MMFrontendProtocol>)connectBackend:
    (byref in id <MMBackendProtocol>)backend;
{
    //NSLog(@"Frontend got connection request from backend...adding new "
    //        "MMVimController");

    [(NSDistantObject*)backend
            setProtocolForProxy:@protocol(MMBackendProtocol)];

    MMVimController *wc = [[[MMVimController alloc] initWithBackend:backend]
            autorelease];
    [vimControllers addObject:wc];

    // HACK!  MacVim does not get activated if it is launched from the
    // terminal, so we forcibly activate here.
    [NSApp activateIgnoringOtherApps:YES];

    return wc;
}
#endif

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
