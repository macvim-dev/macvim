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
#import "MacVim.h"



@implementation MMAppController

- (id)init
{
    if ((self = [super init])) {
        vimControllers = [NSMutableArray new];

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
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"MMAppController dealloc");

    [receivePort release];
    [vimControllers release];

    [super dealloc];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    // NOTE!  This way it possible to start the app with the command-line
    // argument '-nowindow yes' and no window will be opened by default.
    return ![[NSUserDefaults standardUserDefaults] boolForKey:@"nowindow"];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender
{
    //NSLog(@"%s NSapp=%@ theApp=%@", _cmd, NSApp, sender);

    [self newVimWindow:self];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-g", @"-p", nil];
    [args addObjectsFromArray:filenames];

    NSString *path = [[NSBundle mainBundle]
            pathForAuxiliaryExecutable:@"Vim"];

    [NSTask launchedTaskWithLaunchPath:path arguments:args];

    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    // NSApplicationDelegateReplySuccess = 0,
    // NSApplicationDelegateReplyCancel = 1,
    // NSApplicationDelegateReplyFailure = 2
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication *)sender
{
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
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // NOTE! Is this a correct way of releasing the MMAppController?
    [NSApp setDelegate:nil];
    [self autorelease];
}

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

- (void)removeVimController:(id)controller
{
    [vimControllers removeObject:controller];
}

- (IBAction)newVimWindow:(id)sender
{
    NSMutableArray *args = [NSMutableArray arrayWithObject:@"-g"];
    NSString *path = [[NSBundle mainBundle]
            pathForAuxiliaryExecutable:@"Vim"];

    //NSLog(@"Launching a new VimTask...");
    [NSTask launchedTaskWithLaunchPath:path arguments:args];
}

@end
