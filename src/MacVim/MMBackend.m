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
 * MMBackend
 *
 * MMBackend communicates with the frontend (MacVim).  It maintains a queue of
 * output which is flushed to the frontend under controlled circumstances (so
 * as to maintain a steady framerate).  Input from the frontend is also handled
 * here.
 *
 * The frontend communicates with the backend via the MMBackendProtocol.  In
 * particular, input is sent to the backend via processInput:data: and Vim
 * state can be queried from the frontend with evaluateExpression:.
 *
 * It is very important to realize that all state is held by the backend, the
 * frontend must either ask for state [MMBackend evaluateExpression:] or wait
 * for the backend to update [MMVimController processCommandQueue:].
 *
 * The client/server functionality of Vim is handled by the backend.  It sets
 * up a named NSConnection to which other Vim processes can connect.
 */

#import "MMBackend.h"



// NOTE: Colors in MMBackend are stored as unsigned ints on the form 0xaarrggbb
// whereas colors in Vim are int without the alpha component.  Also note that
// 'transp' is assumed to be a value between 0 and 100.
#define MM_COLOR(col) ((unsigned)( ((col)&0xffffff) | 0xff000000 ))
#define MM_COLOR_WITH_TRANSP(col,transp) \
    ((unsigned)( ((col)&0xffffff) \
        | ((((unsigned)((((100-(transp))*255)/100)+.5f))&0xff)<<24) ))

// Values for window layout (must match values in main.c).
#define WIN_HOR     1       // "-o" horizontally split windows
#define WIN_VER     2       // "-O" vertically split windows
#define WIN_TABS    3       // "-p" windows on tab pages

static unsigned MMServerMax = 1000;

// TODO: Move to separate file.
static int eventModifierFlagsToVimModMask(int modifierFlags);
static int eventModifierFlagsToVimMouseModMask(int modifierFlags);
static int eventButtonNumberToVimMouseButton(int buttonNumber);

// Before exiting process, sleep for this many microseconds.  This is to allow
// any distributed object messages in transit to be received by MacVim before
// the process dies (otherwise an error message is logged by Cocoa).  Note that
// this delay is only necessary if an NSConnection to MacVim has been
// established.
static useconds_t MMExitProcessDelay = 300000;

// In gui_macvim.m
vimmenu_T *menu_for_descriptor(NSArray *desc);

static id evalExprCocoa(NSString * expr, NSString ** errstr);


enum {
    MMBlinkStateNone = 0,
    MMBlinkStateOn,
    MMBlinkStateOff
};

static NSString *MMSymlinkWarningString =
    @"\n\n\tMost likely this is because you have symlinked directly to\n"
     "\tthe Vim binary, which Cocoa does not allow.  Please use an\n"
     "\talias or the mvim shell script instead.  If you have not used\n"
     "\ta symlink, then your MacVim.app bundle is incomplete.\n\n";



@interface NSString (MMServerNameCompare)
- (NSComparisonResult)serverNameCompare:(NSString *)string;
@end




@interface MMBackend (Private)
- (void)waitForDialogReturn;
- (void)insertVimStateMessage;
- (void)processInputQueue;
- (void)handleInputEvent:(int)msgid data:(NSData *)data;
+ (NSDictionary *)specialKeys;
- (void)handleInsertText:(NSString *)text;
- (void)handleKeyDown:(NSString *)key modifiers:(int)mods;
- (void)queueMessage:(int)msgid data:(NSData *)data;
- (void)connectionDidDie:(NSNotification *)notification;
- (void)blinkTimerFired:(NSTimer *)timer;
- (void)focusChange:(BOOL)on;
- (void)handleToggleToolbar;
- (void)handleScrollbarEvent:(NSData *)data;
- (void)handleSetFont:(NSData *)data;
- (void)handleDropFiles:(NSData *)data;
- (void)handleDropString:(NSData *)data;
- (void)startOdbEditWithArguments:(NSDictionary *)args;
- (void)handleXcodeMod:(NSData *)data;
- (void)handleOpenWithArguments:(NSDictionary *)args;
- (BOOL)checkForModifiedBuffers;
- (void)addInput:(NSString *)input;
- (BOOL)unusedEditor;
- (void)redrawScreen;
- (void)handleFindReplace:(NSDictionary *)args;
@end



@interface MMBackend (ClientServer)
- (NSString *)connectionNameFromServerName:(NSString *)name;
- (NSConnection *)connectionForServerName:(NSString *)name;
- (NSConnection *)connectionForServerPort:(int)port;
- (void)serverConnectionDidDie:(NSNotification *)notification;
- (void)addClient:(NSDistantObject *)client;
- (NSString *)alternateServerNameForName:(NSString *)name;
@end



@implementation MMBackend

+ (MMBackend *)sharedInstance
{
    static MMBackend *singleton = nil;
    return singleton ? singleton : (singleton = [MMBackend new]);
}

- (id)init
{
    self = [super init];
    if (!self) return nil;

    fontContainerRef = loadFonts();

    outputQueue = [[NSMutableArray alloc] init];
    inputQueue = [[NSMutableArray alloc] init];
    drawData = [[NSMutableData alloc] initWithCapacity:1024];
    connectionNameDict = [[NSMutableDictionary alloc] init];
    clientProxyDict = [[NSMutableDictionary alloc] init];
    serverReplyDict = [[NSMutableDictionary alloc] init];

    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *path = [mainBundle pathForResource:@"Colors" ofType:@"plist"];
    if (path)
        colorDict = [[NSDictionary dictionaryWithContentsOfFile:path] retain];

    path = [mainBundle pathForResource:@"SystemColors" ofType:@"plist"];
    if (path)
        sysColorDict = [[NSDictionary dictionaryWithContentsOfFile:path]
            retain];

    path = [mainBundle pathForResource:@"Actions" ofType:@"plist"];
    if (path)
        actionDict = [[NSDictionary dictionaryWithContentsOfFile:path] retain];

    if (!(colorDict && sysColorDict && actionDict))
        NSLog(@"ERROR: Failed to load dictionaries.%@",
                MMSymlinkWarningString);

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [oldWideFont release];  oldWideFont = nil;
    [blinkTimer release];  blinkTimer = nil;
    [alternateServerName release];  alternateServerName = nil;
    [serverReplyDict release];  serverReplyDict = nil;
    [clientProxyDict release];  clientProxyDict = nil;
    [connectionNameDict release];  connectionNameDict = nil;
    [inputQueue release];  inputQueue = nil;
    [outputQueue release];  outputQueue = nil;
    [drawData release];  drawData = nil;
    [frontendProxy release];  frontendProxy = nil;
    [connection release];  connection = nil;
    [actionDict release];  actionDict = nil;
    [sysColorDict release];  sysColorDict = nil;
    [colorDict release];  colorDict = nil;

    [super dealloc];
}

- (void)setBackgroundColor:(int)color
{
    backgroundColor = MM_COLOR_WITH_TRANSP(color,p_transp);
}

- (void)setForegroundColor:(int)color
{
    foregroundColor = MM_COLOR(color);
}

- (void)setSpecialColor:(int)color
{
    specialColor = MM_COLOR(color);
}

- (void)setDefaultColorsBackground:(int)bg foreground:(int)fg
{
    defaultBackgroundColor = MM_COLOR_WITH_TRANSP(bg,p_transp);
    defaultForegroundColor = MM_COLOR(fg);

    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&defaultBackgroundColor length:sizeof(unsigned)];
    [data appendBytes:&defaultForegroundColor length:sizeof(unsigned)];

    [self queueMessage:SetDefaultColorsMsgID data:data];
}

- (NSConnection *)connection
{
    if (!connection) {
        // NOTE!  If the name of the connection changes here it must also be
        // updated in MMAppController.m.
        NSString *name = [NSString stringWithFormat:@"%@-connection",
               [[NSBundle mainBundle] bundlePath]];

        connection = [NSConnection connectionWithRegisteredName:name host:nil];
        [connection retain];
    }

    // NOTE: 'connection' may be nil here.
    return connection;
}

- (NSDictionary *)actionDict
{
    return actionDict;
}

- (int)initialWindowLayout
{
    return initialWindowLayout;
}

- (void)queueMessage:(int)msgid properties:(NSDictionary *)props
{
    [self queueMessage:msgid data:[props dictionaryAsData]];
}

- (BOOL)checkin
{
    if (![self connection]) {
        if (waitForAck) {
            // This is a preloaded process and as such should not cause the
            // MacVim to be opened.  We probably got here as a result of the
            // user quitting MacVim while the process was preloading, so exit
            // this process too.
            // (Don't use mch_exit() since it assumes the process has properly
            // started.)
            exit(0);
        }

        NSBundle *mainBundle = [NSBundle mainBundle];
#if 0
        OSStatus status;
        FSRef ref;

        // Launch MacVim using Launch Services (NSWorkspace would be nicer, but
        // the API to pass Apple Event parameters is broken on 10.4).
        NSString *path = [mainBundle bundlePath];
        status = FSPathMakeRef((const UInt8 *)[path UTF8String], &ref, NULL);
        if (noErr == status) {
            // Pass parameter to the 'Open' Apple Event that tells MacVim not
            // to open an untitled window.
            NSAppleEventDescriptor *desc =
                    [NSAppleEventDescriptor recordDescriptor];
            [desc setParamDescriptor:
                    [NSAppleEventDescriptor descriptorWithBoolean:NO]
                          forKeyword:keyMMUntitledWindow];

            LSLaunchFSRefSpec spec = { &ref, 0, NULL, [desc aeDesc],
                    kLSLaunchDefaults, NULL };
            status = LSOpenFromRefSpec(&spec, NULL);
        }

        if (noErr != status) {
        NSLog(@"ERROR: Failed to launch MacVim (path=%@).%@",
                path, MMSymlinkWarningString);
            return NO;
        }
#else
        // Launch MacVim using NSTask.  For some reason the above code using
        // Launch Services sometimes fails on LSOpenFromRefSpec() (when it
        // fails, the dock icon starts bouncing and never stops).  It seems
        // like rebuilding the Launch Services database takes care of this
        // problem, but the NSTask way seems more stable so stick with it.
        //
        // NOTE!  Using NSTask to launch the GUI has the negative side-effect
        // that the GUI won't be activated (or raised) so there is a hack in
        // MMAppController which raises the app when a new window is opened.
        NSMutableArray *args = [NSMutableArray arrayWithObjects:
            [NSString stringWithFormat:@"-%@", MMNoWindowKey], @"yes", nil];
        NSString *exeName = [[mainBundle infoDictionary]
                objectForKey:@"CFBundleExecutable"];
        NSString *path = [mainBundle pathForAuxiliaryExecutable:exeName];
        if (!path) {
            NSLog(@"ERROR: Could not find MacVim executable in bundle.%@",
                    MMSymlinkWarningString);
            return NO;
        }

        [NSTask launchedTaskWithLaunchPath:path arguments:args];
#endif

        // HACK!  Poll the mach bootstrap server until it returns a valid
        // connection to detect that MacVim has finished launching.  Also set a
        // time-out date so that we don't get stuck doing this forever.
        NSDate *timeOutDate = [NSDate dateWithTimeIntervalSinceNow:10];
        while (![self connection] &&
                NSOrderedDescending == [timeOutDate compare:[NSDate date]])
            [[NSRunLoop currentRunLoop]
                    runMode:NSDefaultRunLoopMode
                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:.1]];

        // NOTE: [self connection] will set 'connection' as a side-effect.
        if (!connection) {
            NSLog(@"WARNING: Timed-out waiting for GUI to launch.");
            return NO;
        }
    }

    BOOL ok = NO;
    @try {
        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(connectionDidDie:)
                    name:NSConnectionDidDieNotification object:connection];

        id proxy = [connection rootProxy];
        [proxy setProtocolForProxy:@protocol(MMAppProtocol)];

        int pid = [[NSProcessInfo processInfo] processIdentifier];

        frontendProxy = [proxy connectBackend:self pid:pid];
        if (frontendProxy) {
            [frontendProxy retain];
            [frontendProxy setProtocolForProxy:@protocol(MMAppProtocol)];
            ok = YES;
        }
    }
    @catch (NSException *e) {
        NSLog(@"Exception caught when trying to connect backend: \"%@\"", e);
    }

    return ok;
}

- (BOOL)openGUIWindow
{
    [self queueMessage:OpenWindowMsgID data:nil];
    return YES;
}

- (void)clearAll
{
    int type = ClearAllDrawType;

    // Any draw commands in queue are effectively obsolete since this clearAll
    // will negate any effect they have, therefore we may as well clear the
    // draw queue.
    [drawData setLength:0];

    [drawData appendBytes:&type length:sizeof(int)];
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1
                    toRow:(int)row2 column:(int)col2
{
    int type = ClearBlockDrawType;

    [drawData appendBytes:&type length:sizeof(int)];

    [drawData appendBytes:&defaultBackgroundColor length:sizeof(unsigned)];
    [drawData appendBytes:&row1 length:sizeof(int)];
    [drawData appendBytes:&col1 length:sizeof(int)];
    [drawData appendBytes:&row2 length:sizeof(int)];
    [drawData appendBytes:&col2 length:sizeof(int)];
}

- (void)deleteLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
{
    int type = DeleteLinesDrawType;

    [drawData appendBytes:&type length:sizeof(int)];

    [drawData appendBytes:&defaultBackgroundColor length:sizeof(unsigned)];
    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&count length:sizeof(int)];
    [drawData appendBytes:&bottom length:sizeof(int)];
    [drawData appendBytes:&left length:sizeof(int)];
    [drawData appendBytes:&right length:sizeof(int)];
}

- (void)drawString:(char*)s length:(int)len row:(int)row column:(int)col
             cells:(int)cells flags:(int)flags
{
    if (len <= 0 || cells <= 0) return;

    int type = DrawStringDrawType;

    [drawData appendBytes:&type length:sizeof(int)];

    [drawData appendBytes:&backgroundColor length:sizeof(unsigned)];
    [drawData appendBytes:&foregroundColor length:sizeof(unsigned)];
    [drawData appendBytes:&specialColor length:sizeof(unsigned)];
    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&col length:sizeof(int)];
    [drawData appendBytes:&cells length:sizeof(int)];
    [drawData appendBytes:&flags length:sizeof(int)];
    [drawData appendBytes:&len length:sizeof(int)];
    [drawData appendBytes:s length:len];
}

- (void)insertLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
{
    int type = InsertLinesDrawType;

    [drawData appendBytes:&type length:sizeof(int)];

    [drawData appendBytes:&defaultBackgroundColor length:sizeof(unsigned)];
    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&count length:sizeof(int)];
    [drawData appendBytes:&bottom length:sizeof(int)];
    [drawData appendBytes:&left length:sizeof(int)];
    [drawData appendBytes:&right length:sizeof(int)];
}

- (void)drawCursorAtRow:(int)row column:(int)col shape:(int)shape
               fraction:(int)percent color:(int)color
{
    int type = DrawCursorDrawType;
    unsigned uc = MM_COLOR(color);

    [drawData appendBytes:&type length:sizeof(int)];

    [drawData appendBytes:&uc length:sizeof(unsigned)];
    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&col length:sizeof(int)];
    [drawData appendBytes:&shape length:sizeof(int)];
    [drawData appendBytes:&percent length:sizeof(int)];
}

- (void)drawInvertedRectAtRow:(int)row column:(int)col numRows:(int)nr
                   numColumns:(int)nc invert:(int)invert
{
    int type = DrawInvertedRectDrawType;
    [drawData appendBytes:&type length:sizeof(int)];

    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&col length:sizeof(int)];
    [drawData appendBytes:&nr length:sizeof(int)];
    [drawData appendBytes:&nc length:sizeof(int)];
    [drawData appendBytes:&invert length:sizeof(int)];
}

- (void)update
{
    // Keep running the run-loop until there is no more input to process.
    while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true)
            == kCFRunLoopRunHandledSource)
        ;
}

- (void)flushQueue:(BOOL)force
{
    // NOTE: This variable allows for better control over when the queue is
    // flushed.  It can be set to YES at the beginning of a sequence of calls
    // that may potentially add items to the queue, and then restored back to
    // NO.
    if (flushDisabled) return;

    if ([drawData length] > 0) {
        // HACK!  Detect changes to 'guifontwide'.
        if (gui.wide_font != (GuiFont)oldWideFont) {
            [oldWideFont release];
            oldWideFont = [(NSFont*)gui.wide_font retain];
            [self setWideFont:oldWideFont];
        }

        int type = SetCursorPosDrawType;
        [drawData appendBytes:&type length:sizeof(type)];
        [drawData appendBytes:&gui.row length:sizeof(gui.row)];
        [drawData appendBytes:&gui.col length:sizeof(gui.col)];

        [self queueMessage:BatchDrawMsgID data:[drawData copy]];
        [drawData setLength:0];
    }

    if ([outputQueue count] > 0) {
        [self insertVimStateMessage];

        @try {
            [frontendProxy processCommandQueue:outputQueue];
        }
        @catch (NSException *e) {
            NSLog(@"Exception caught when processing command queue: \"%@\"", e);
            NSLog(@"outputQueue(len:%d)=%@", [outputQueue count]/2,
                    outputQueue);
            if (![connection isValid]) {
                NSLog(@"WARNING! Connection is invalid, exit now!");
                NSLog(@"waitForAck=%d got_int=%d isTerminating=%d",
                        waitForAck, got_int, isTerminating);
                mch_exit(-1);
            }
        }

        [outputQueue removeAllObjects];
    }
}

- (BOOL)waitForInput:(int)milliseconds
{
    // Return NO if we timed out waiting for input, otherwise return YES.
    BOOL inputReceived = NO;

    // Only start the run loop if the input queue is empty, otherwise process
    // the input first so that the input on queue isn't delayed.
    if ([inputQueue count]) {
        inputReceived = YES;
    } else {
        // Wait for the specified amount of time, unless 'milliseconds' is
        // negative in which case we wait "forever" (1e6 seconds translates to
        // approximately 11 days).
        CFTimeInterval dt = (milliseconds >= 0 ? .001*milliseconds : 1e6);

        while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, dt, true)
                == kCFRunLoopRunHandledSource) {
            // In order to ensure that all input on the run-loop has been
            // processed we set the timeout to 0 and keep processing until the
            // run-loop times out.
            dt = 0.0;
            inputReceived = YES;
        }
    }

    // The above calls may have placed messages on the input queue so process
    // it now.  This call may enter a blocking loop.
    if ([inputQueue count] > 0)
        [self processInputQueue];

    return inputReceived;
}

- (void)exit
{
    // NOTE: This is called if mch_exit() is called.  Since we assume here that
    // the process has started properly, be sure to use exit() instead of
    // mch_exit() to prematurely terminate a process.

    // To notify MacVim that this Vim process is exiting we could simply
    // invalidate the connection and it would automatically receive a
    // connectionDidDie: notification.  However, this notification seems to
    // take up to 300 ms to arrive which is quite a noticeable delay.  Instead
    // we immediately send a message to MacVim asking it to close the window
    // belonging to this process, and then we invalidate the connection (in
    // case the message got lost).

    // Make sure no connectionDidDie: notification is received now that we are
    // already exiting.
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if ([connection isValid]) {
        @try {
            // Flush the entire queue in case a VimLeave autocommand added
            // something to the queue.
            [self queueMessage:CloseWindowMsgID data:nil];
            [frontendProxy processCommandQueue:outputQueue];
        }
        @catch (NSException *e) {
            NSLog(@"Exception caught when sending CloseWindowMsgID: \"%@\"", e);
        }

        [connection invalidate];
    }

#ifdef MAC_CLIENTSERVER
    // The default connection is used for the client/server code.
    [[NSConnection defaultConnection] setRootObject:nil];
    [[NSConnection defaultConnection] invalidate];
#endif

    if (fontContainerRef) {
        ATSFontDeactivate(fontContainerRef, NULL, kATSOptionFlagsDefault);
        fontContainerRef = 0;
    }

    usleep(MMExitProcessDelay);
}

- (void)selectTab:(int)index
{
    //NSLog(@"%s%d", _cmd, index);

    index -= 1;
    NSData *data = [NSData dataWithBytes:&index length:sizeof(int)];
    [self queueMessage:SelectTabMsgID data:data];
}

- (void)updateTabBar
{
    //NSLog(@"%s", _cmd);

    NSMutableData *data = [NSMutableData data];

    int idx = tabpage_index(curtab) - 1;
    [data appendBytes:&idx length:sizeof(int)];

    tabpage_T *tp;
    for (tp = first_tabpage; tp != NULL; tp = tp->tp_next) {
        // This function puts the label of the tab in the global 'NameBuff'.
        get_tabline_label(tp, FALSE);
        char_u *s = NameBuff;
        int len = STRLEN(s);
        if (len <= 0) continue;

#ifdef FEAT_MBYTE
        s = CONVERT_TO_UTF8(s);
#endif

        // Count the number of windows in the tabpage.
        //win_T *wp = tp->tp_firstwin;
        //int wincount;
        //for (wincount = 0; wp != NULL; wp = wp->w_next, ++wincount);

        //[data appendBytes:&wincount length:sizeof(int)];
        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:s length:len];

#ifdef FEAT_MBYTE
        CONVERT_TO_UTF8_FREE(s);
#endif
    }

    [self queueMessage:UpdateTabBarMsgID data:data];
}

- (BOOL)tabBarVisible
{
    return tabBarVisible;
}

- (void)showTabBar:(BOOL)enable
{
    tabBarVisible = enable;

    int msgid = enable ? ShowTabBarMsgID : HideTabBarMsgID;
    [self queueMessage:msgid data:nil];
}

- (void)setRows:(int)rows columns:(int)cols
{
    //NSLog(@"[VimTask] setRows:%d columns:%d", rows, cols);

    int dim[] = { rows, cols };
    NSData *data = [NSData dataWithBytes:&dim length:2*sizeof(int)];

    [self queueMessage:SetTextDimensionsMsgID data:data];
}

- (void)setWindowTitle:(char *)title
{
    NSMutableData *data = [NSMutableData data];
    int len = strlen(title);
    if (len <= 0) return;

    [data appendBytes:&len length:sizeof(int)];
    [data appendBytes:title length:len];

    [self queueMessage:SetWindowTitleMsgID data:data];
}

- (void)setDocumentFilename:(char *)filename
{
    NSMutableData *data = [NSMutableData data];
    int len = filename ? strlen(filename) : 0;

    [data appendBytes:&len length:sizeof(int)];
    if (len > 0)
        [data appendBytes:filename length:len];

    [self queueMessage:SetDocumentFilenameMsgID data:data];
}

- (char *)browseForFileWithAttributes:(NSDictionary *)attr
{
    char_u *s = NULL;

    @try {
        [frontendProxy showSavePanelWithAttributes:attr];

        [self waitForDialogReturn];

        if (dialogReturn && [dialogReturn isKindOfClass:[NSString class]])
            s = [dialogReturn vimStringSave];

        [dialogReturn release];  dialogReturn = nil;
    }
    @catch (NSException *e) {
        NSLog(@"Exception caught when showing save panel: \"%@\"", e);
    }

    return (char *)s;
}

- (oneway void)setDialogReturn:(in bycopy id)obj
{
    // NOTE: This is called by
    //   - [MMVimController panelDidEnd:::], and
    //   - [MMVimController alertDidEnd:::],
    // to indicate that a save/open panel or alert has finished.

    // We want to distinguish between "no dialog return yet" and "dialog
    // returned nothing".  The former can be tested with dialogReturn == nil,
    // the latter with dialogReturn == [NSNull null].
    if (!obj) obj = [NSNull null];

    if (obj != dialogReturn) {
        [dialogReturn release];
        dialogReturn = [obj retain];
    }
}

- (int)showDialogWithAttributes:(NSDictionary *)attr textField:(char *)txtfield
{
    int retval = 0;

    @try {
        [frontendProxy presentDialogWithAttributes:attr];

        [self waitForDialogReturn];

        if (dialogReturn && [dialogReturn isKindOfClass:[NSArray class]]
                && [dialogReturn count]) {
            retval = [[dialogReturn objectAtIndex:0] intValue];
            if (txtfield && [dialogReturn count] > 1) {
                NSString *retString = [dialogReturn objectAtIndex:1];
                char_u *ret = (char_u*)[retString UTF8String];
#ifdef FEAT_MBYTE
                ret = CONVERT_FROM_UTF8(ret);
#endif
                vim_strncpy((char_u*)txtfield, ret, IOSIZE - 1);
#ifdef FEAT_MBYTE
                CONVERT_FROM_UTF8_FREE(ret);
#endif
            }
        }

        [dialogReturn release]; dialogReturn = nil;
    }
    @catch (NSException *e) {
        NSLog(@"Exception caught while showing alert dialog: \"%@\"", e);
    }

    return retval;
}

- (void)showToolbar:(int)enable flags:(int)flags
{
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&enable length:sizeof(int)];
    [data appendBytes:&flags length:sizeof(int)];

    [self queueMessage:ShowToolbarMsgID data:data];
}

- (void)createScrollbarWithIdentifier:(long)ident type:(int)type
{
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&ident length:sizeof(long)];
    [data appendBytes:&type length:sizeof(int)];

    [self queueMessage:CreateScrollbarMsgID data:data];
}

- (void)destroyScrollbarWithIdentifier:(long)ident
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&ident length:sizeof(long)];

    [self queueMessage:DestroyScrollbarMsgID data:data];
}

- (void)showScrollbarWithIdentifier:(long)ident state:(int)visible
{
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&ident length:sizeof(long)];
    [data appendBytes:&visible length:sizeof(int)];

    [self queueMessage:ShowScrollbarMsgID data:data];
}

- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident
{
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&ident length:sizeof(long)];
    [data appendBytes:&pos length:sizeof(int)];
    [data appendBytes:&len length:sizeof(int)];

    [self queueMessage:SetScrollbarPositionMsgID data:data];
}

- (void)setScrollbarThumbValue:(long)val size:(long)size max:(long)max
                    identifier:(long)ident
{
    float fval = max-size+1 > 0 ? (float)val/(max-size+1) : 0;
    float prop = (float)size/(max+1);
    if (fval < 0) fval = 0;
    else if (fval > 1.0f) fval = 1.0f;
    if (prop < 0) prop = 0;
    else if (prop > 1.0f) prop = 1.0f;

    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&ident length:sizeof(long)];
    [data appendBytes:&fval length:sizeof(float)];
    [data appendBytes:&prop length:sizeof(float)];

    [self queueMessage:SetScrollbarThumbMsgID data:data];
}

- (void)setFont:(NSFont *)font
{
    NSString *fontName = [font displayName];
    float size = [font pointSize];
    int len = [fontName lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (len > 0) {
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&size length:sizeof(float)];
        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:[fontName UTF8String] length:len];

        [self queueMessage:SetFontMsgID data:data];
    }
}

- (void)setWideFont:(NSFont *)font
{
    NSString *fontName = [font displayName];
    float size = [font pointSize];
    int len = [fontName lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&size length:sizeof(float)];
    [data appendBytes:&len length:sizeof(int)];
    if (len > 0)
        [data appendBytes:[fontName UTF8String] length:len];

    [self queueMessage:SetWideFontMsgID data:data];
}

- (void)executeActionWithName:(NSString *)name
{
    int len = [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    if (len > 0) {
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:[name UTF8String] length:len];

        [self queueMessage:ExecuteActionMsgID data:data];
    }
}

- (void)setMouseShape:(int)shape
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&shape length:sizeof(int)];
    [self queueMessage:SetMouseShapeMsgID data:data];
}

- (void)setBlinkWait:(int)wait on:(int)on off:(int)off
{
    // Vim specifies times in milliseconds, whereas Cocoa wants them in
    // seconds.
    blinkWaitInterval = .001f*wait;
    blinkOnInterval = .001f*on;
    blinkOffInterval = .001f*off;
}

- (void)startBlink
{
    if (blinkTimer) {
        [blinkTimer invalidate];
        [blinkTimer release];
        blinkTimer = nil;
    }

    if (blinkWaitInterval > 0 && blinkOnInterval > 0 && blinkOffInterval > 0
            && gui.in_focus) {
        blinkState = MMBlinkStateOn;
        blinkTimer =
            [[NSTimer scheduledTimerWithTimeInterval:blinkWaitInterval
                                              target:self
                                            selector:@selector(blinkTimerFired:)
                                            userInfo:nil repeats:NO] retain];
        gui_update_cursor(TRUE, FALSE);
        [self flushQueue:YES];
    }
}

- (void)stopBlink
{
    if (MMBlinkStateOff == blinkState) {
        gui_update_cursor(TRUE, FALSE);
        [self flushQueue:YES];
    }

    blinkState = MMBlinkStateNone;
}

- (void)adjustLinespace:(int)linespace
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&linespace length:sizeof(int)];
    [self queueMessage:AdjustLinespaceMsgID data:data];
}

- (void)activate
{
    [self queueMessage:ActivateMsgID data:nil];
}

- (void)setPreEditRow:(int)row column:(int)col
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&row length:sizeof(int)];
    [data appendBytes:&col length:sizeof(int)];
    [self queueMessage:SetPreEditPositionMsgID data:data];
}

- (int)lookupColorWithKey:(NSString *)key
{
    if (!(key && [key length] > 0))
        return INVALCOLOR;

    NSString *stripKey = [[[[key lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
            componentsSeparatedByString:@" "]
               componentsJoinedByString:@""];

    if (stripKey && [stripKey length] > 0) {
        // First of all try to lookup key in the color dictionary; note that
        // all keys in this dictionary are lowercase with no whitespace.
        id obj = [colorDict objectForKey:stripKey];
        if (obj) return [obj intValue];

        // The key was not in the dictionary; is it perhaps of the form
        // #rrggbb?
        if ([stripKey length] > 1 && [stripKey characterAtIndex:0] == '#') {
            NSScanner *scanner = [NSScanner scannerWithString:stripKey];
            [scanner setScanLocation:1];
            unsigned hex = 0;
            if ([scanner scanHexInt:&hex]) {
                return (int)hex;
            }
        }

        // As a last resort, check if it is one of the system defined colors.
        // The keys in this dictionary are also lowercase with no whitespace.
        obj = [sysColorDict objectForKey:stripKey];
        if (obj) {
            NSColor *col = [NSColor performSelector:NSSelectorFromString(obj)];
            if (col) {
                float r, g, b, a;
                col = [col colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                [col getRed:&r green:&g blue:&b alpha:&a];
                return (((int)(r*255+.5f) & 0xff) << 16)
                     + (((int)(g*255+.5f) & 0xff) << 8)
                     +  ((int)(b*255+.5f) & 0xff);
            }
        }
    }

    //NSLog(@"WARNING: No color with key %@ found.", stripKey);
    return INVALCOLOR;
}

- (BOOL)hasSpecialKeyWithValue:(NSString *)value
{
    NSEnumerator *e = [[MMBackend specialKeys] objectEnumerator];
    id obj;

    while ((obj = [e nextObject])) {
        if ([value isEqual:obj])
            return YES;
    }

    return NO;
}

- (void)enterFullscreen:(int)fuoptions background:(int)bg
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&fuoptions length:sizeof(int)];
    bg = MM_COLOR(bg);
    [data appendBytes:&bg length:sizeof(int)];
    [self queueMessage:EnterFullscreenMsgID data:data];
}

- (void)leaveFullscreen
{
    [self queueMessage:LeaveFullscreenMsgID data:nil];
}

- (void)setFullscreenBackgroundColor:(int)color
{
    NSMutableData *data = [NSMutableData data];
    color = MM_COLOR(color);
    [data appendBytes:&color length:sizeof(int)];

    [self queueMessage:SetFullscreenColorMsgID data:data];
}

- (void)setAntialias:(BOOL)antialias
{
    int msgid = antialias ? EnableAntialiasMsgID : DisableAntialiasMsgID;

    [self queueMessage:msgid data:nil];
}

- (void)updateModifiedFlag
{
    // Notify MacVim if _any_ buffer has changed from unmodified to modified or
    // vice versa.
    int msgid = [self checkForModifiedBuffers]
            ? BuffersModifiedMsgID : BuffersNotModifiedMsgID;

    [self queueMessage:msgid data:nil];
}

- (oneway void)processInput:(int)msgid data:(in bycopy NSData *)data
{
    // Look for Cmd-. and Ctrl-C immediately instead of waiting until the input
    // queue is processed since that only happens in waitForInput: (and Vim
    // regularly checks for Ctrl-C in between waiting for input).
    // Similarly, TerminateNowMsgID must be checked immediately otherwise code
    // which waits on the run loop will fail to detect this message (e.g. in
    // waitForConnectionAcknowledgement).

    BOOL shouldClearQueue = NO;
    if (InterruptMsgID == msgid) {
        shouldClearQueue = YES;
        got_int = TRUE;
    } else if (InsertTextMsgID == msgid && data != nil) {
        const void *bytes = [data bytes];
        bytes += sizeof(int);
        int len = *((int*)bytes);  bytes += sizeof(int);
        if (1 == len) {
            char_u *str = (char_u*)bytes;
            if ((str[0] == Ctrl_C && ctrl_c_interrupts) ||
                    (str[0] == intr_char && intr_char != Ctrl_C)) {
                shouldClearQueue = YES;
                got_int = TRUE;
            }
        }
    } else if (TerminateNowMsgID == msgid) {
        shouldClearQueue = YES;
        isTerminating = YES;
    }

    if (shouldClearQueue) {
        [inputQueue removeAllObjects];
        return;
    }

    // Remove all previous instances of this message from the input queue, else
    // the input queue may fill up as a result of Vim not being able to keep up
    // with the speed at which new messages are received.
    // Keyboard input is never dropped, unless the input represents and
    // auto-repeated key.

    BOOL isKeyRepeat = NO;
    BOOL isKeyboardInput = NO;

    if (data && (InsertTextMsgID == msgid || KeyDownMsgID == msgid ||
            CmdKeyMsgID == msgid)) {
        isKeyboardInput = YES;

        // The lowest bit of the first int is set if this key is a repeat.
        int flags = *((int*)[data bytes]);
        if (flags & 1)
            isKeyRepeat = YES;
    }

    // Keyboard input is not removed from the queue; repeats are ignored if
    // there already is keyboard input on the input queue.
    if (isKeyRepeat || !isKeyboardInput) {
        int i, count = [inputQueue count];
        for (i = 1; i < count; i+=2) {
            if ([[inputQueue objectAtIndex:i-1] intValue] == msgid) {
                if (isKeyRepeat)
                    return;

                [inputQueue removeObjectAtIndex:i];
                [inputQueue removeObjectAtIndex:i-1];
                break;
            }
        }
    }

    [inputQueue addObject:[NSNumber numberWithInt:msgid]];
    [inputQueue addObject:(data ? (id)data : [NSNull null])];
}

- (oneway void)processInputAndData:(in bycopy NSArray *)messages
{
    // This is just a convenience method that allows the frontend to delay
    // sending messages.
    int i, count = [messages count];
    for (i = 1; i < count; i+=2)
        [self processInput:[[messages objectAtIndex:i-1] intValue]
                      data:[messages objectAtIndex:i]];
}

- (id)evaluateExpressionCocoa:(in bycopy NSString *)expr
                  errorString:(out bycopy NSString **)errstr
{
    return evalExprCocoa(expr, errstr);
}


- (NSString *)evaluateExpression:(in bycopy NSString *)expr
{
    NSString *eval = nil;
    char_u *s = (char_u*)[expr UTF8String];

#ifdef FEAT_MBYTE
    s = CONVERT_FROM_UTF8(s);
#endif

    char_u *res = eval_client_expr_to_string(s);

#ifdef FEAT_MBYTE
    CONVERT_FROM_UTF8_FREE(s);
#endif

    if (res != NULL) {
        s = res;
#ifdef FEAT_MBYTE
        s = CONVERT_TO_UTF8(s);
#endif
        eval = [NSString stringWithUTF8String:(char*)s];
#ifdef FEAT_MBYTE
        CONVERT_TO_UTF8_FREE(s);
#endif
        vim_free(res);
    }

    return eval;
}

- (BOOL)starRegisterToPasteboard:(byref NSPasteboard *)pboard
{
    // TODO: This method should share code with clip_mch_request_selection().

    if (VIsual_active && (State & NORMAL) && clip_star.available) {
        // If there is no pasteboard, return YES to indicate that there is text
        // to copy.
        if (!pboard)
            return YES;

        clip_copy_selection();

        // Get the text to put on the pasteboard.
        long_u llen = 0; char_u *str = 0;
        int type = clip_convert_selection(&str, &llen, &clip_star);
        if (type < 0)
            return NO;
        
        // TODO: Avoid overflow.
        int len = (int)llen;
#ifdef FEAT_MBYTE
        if (output_conv.vc_type != CONV_NONE) {
            char_u *conv_str = string_convert(&output_conv, str, &len);
            if (conv_str) {
                vim_free(str);
                str = conv_str;
            }
        }
#endif

        NSString *string = [[NSString alloc]
            initWithBytes:str length:len encoding:NSUTF8StringEncoding];

        NSArray *types = [NSArray arrayWithObject:NSStringPboardType];
        [pboard declareTypes:types owner:nil];
        BOOL ok = [pboard setString:string forType:NSStringPboardType];
    
        [string release];
        vim_free(str);

        return ok;
    }

    return NO;
}

- (oneway void)addReply:(in bycopy NSString *)reply
                 server:(in byref id <MMVimServerProtocol>)server
{
    //NSLog(@"addReply:%@ server:%@", reply, (id)server);

    // Replies might come at any time and in any order so we keep them in an
    // array inside a dictionary with the send port used as key.

    NSConnection *conn = [(NSDistantObject*)server connectionForProxy];
    // HACK! Assume connection uses mach ports.
    int port = [(NSMachPort*)[conn sendPort] machPort];
    NSNumber *key = [NSNumber numberWithInt:port];

    NSMutableArray *replies = [serverReplyDict objectForKey:key];
    if (!replies) {
        replies = [NSMutableArray array];
        [serverReplyDict setObject:replies forKey:key];
    }

    [replies addObject:reply];
}

- (void)addInput:(in bycopy NSString *)input
                 client:(in byref id <MMVimClientProtocol>)client
{
    //NSLog(@"addInput:%@ client:%@", input, (id)client);

    [self addInput:input];
    [self addClient:(id)client];
}

- (NSString *)evaluateExpression:(in bycopy NSString *)expr
                 client:(in byref id <MMVimClientProtocol>)client
{
    [self addClient:(id)client];
    return [self evaluateExpression:expr];
}

- (void)registerServerWithName:(NSString *)name
{
    NSString *svrName = name;
    NSConnection *svrConn = [NSConnection defaultConnection];
    unsigned i;

    for (i = 0; i < MMServerMax; ++i) {
        NSString *connName = [self connectionNameFromServerName:svrName];

        if ([svrConn registerName:connName]) {
            //NSLog(@"Registered server with name: %@", svrName);

            // TODO: Set request/reply time-outs to something else?
            //
            // Don't wait for requests (time-out means that the message is
            // dropped).
            [svrConn setRequestTimeout:0];
            //[svrConn setReplyTimeout:MMReplyTimeout];
            [svrConn setRootObject:self];

            // NOTE: 'serverName' is a global variable
            serverName = [svrName vimStringSave];
#ifdef FEAT_EVAL
            set_vim_var_string(VV_SEND_SERVER, serverName, -1);
#endif
#ifdef FEAT_TITLE
	    need_maketitle = TRUE;
#endif
            [self queueMessage:SetServerNameMsgID data:
                    [svrName dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }

        svrName = [NSString stringWithFormat:@"%@%d", name, i+1];
    }
}

- (BOOL)sendToServer:(NSString *)name string:(NSString *)string
               reply:(char_u **)reply port:(int *)port expression:(BOOL)expr
              silent:(BOOL)silent
{
    // NOTE: If 'name' equals 'serverName' then the request is local (client
    // and server are the same).  This case is not handled separately, so a
    // connection will be set up anyway (this simplifies the code).

    NSConnection *conn = [self connectionForServerName:name];
    if (!conn) {
        if (!silent) {
            char_u *s = (char_u*)[name UTF8String];
#ifdef FEAT_MBYTE
            s = CONVERT_FROM_UTF8(s);
#endif
	    EMSG2(_(e_noserver), s);
#ifdef FEAT_MBYTE
            CONVERT_FROM_UTF8_FREE(s);
#endif
        }
        return NO;
    }

    if (port) {
        // HACK! Assume connection uses mach ports.
        *port = [(NSMachPort*)[conn sendPort] machPort];
    }

    id proxy = [conn rootProxy];
    [proxy setProtocolForProxy:@protocol(MMVimServerProtocol)];

    @try {
        if (expr) {
            NSString *eval = [proxy evaluateExpression:string client:self];
            if (reply) {
                if (eval) {
                    *reply = [eval vimStringSave];
                } else {
                    *reply = vim_strsave((char_u*)_(e_invexprmsg));
                }
            }

            if (!eval)
                return NO;
        } else {
            [proxy addInput:string client:self];
        }
    }
    @catch (NSException *e) {
        NSLog(@"WARNING: Caught exception in %s: \"%@\"", _cmd, e);
        return NO;
    }

    return YES;
}

- (NSArray *)serverList
{
    NSArray *list = nil;

    if ([self connection]) {
        id proxy = [connection rootProxy];
        [proxy setProtocolForProxy:@protocol(MMAppProtocol)];

        @try {
            list = [proxy serverList];
        }
        @catch (NSException *e) {
            NSLog(@"Exception caught when listing servers: \"%@\"", e);
        }
    } else {
        EMSG(_("E???: No connection to MacVim, server listing not possible."));
    }

    return list;
}

- (NSString *)peekForReplyOnPort:(int)port
{
    //NSLog(@"%s%d", _cmd, port);

    NSNumber *key = [NSNumber numberWithInt:port];
    NSMutableArray *replies = [serverReplyDict objectForKey:key];
    if (replies && [replies count]) {
        //NSLog(@"    %d replies, topmost is: %@", [replies count],
        //        [replies objectAtIndex:0]);
        return [replies objectAtIndex:0];
    }

    //NSLog(@"    No replies");
    return nil;
}

- (NSString *)waitForReplyOnPort:(int)port
{
    //NSLog(@"%s%d", _cmd, port);
    
    NSConnection *conn = [self connectionForServerPort:port];
    if (!conn)
        return nil;

    NSNumber *key = [NSNumber numberWithInt:port];
    NSMutableArray *replies = nil;
    NSString *reply = nil;

    // Wait for reply as long as the connection to the server is valid (unless
    // user interrupts wait with Ctrl-C).
    while (!got_int && [conn isValid] &&
            !(replies = [serverReplyDict objectForKey:key])) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate distantFuture]];
    }

    if (replies) {
        if ([replies count] > 0) {
            reply = [[replies objectAtIndex:0] retain];
            //NSLog(@"    Got reply: %@", reply);
            [replies removeObjectAtIndex:0];
            [reply autorelease];
        }

        if ([replies count] == 0)
            [serverReplyDict removeObjectForKey:key];
    }

    return reply;
}

- (BOOL)sendReply:(NSString *)reply toPort:(int)port
{
    id client = [clientProxyDict objectForKey:[NSNumber numberWithInt:port]];
    if (client) {
        @try {
            //NSLog(@"sendReply:%@ toPort:%d", reply, port);
            [client addReply:reply server:self];
            return YES;
        }
        @catch (NSException *e) {
            NSLog(@"WARNING: Exception caught in %s: \"%@\"", _cmd, e);
        }
    } else {
        EMSG2(_("E???: server2client failed; no client with id 0x%x"), port);
    }

    return NO;
}

- (BOOL)waitForAck
{
    return waitForAck;
}

- (void)setWaitForAck:(BOOL)yn
{
    waitForAck = yn;
}

- (void)waitForConnectionAcknowledgement
{
    if (!waitForAck) return;

    while (waitForAck && !got_int && [connection isValid] && !isTerminating) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate distantFuture]];
        //NSLog(@"  waitForAck=%d got_int=%d isTerminating=%d isValid=%d",
        //        waitForAck, got_int, isTerminating, [connection isValid]);
    }

    if (waitForAck) {
        // Never received a connection acknowledgement, so die.
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [frontendProxy release];  frontendProxy = nil;

        // NOTE: We intentionally do not call mch_exit() since this in turn
        // will lead to -[MMBackend exit] getting called which we want to
        // avoid.
        usleep(MMExitProcessDelay);
        exit(0);
    }

    [self processInputQueue];
}

- (oneway void)acknowledgeConnection
{
    //NSLog(@"%s", _cmd);
    waitForAck = NO;
}

@end // MMBackend



@implementation MMBackend (Private)

- (void)waitForDialogReturn
{
    // Keep processing the run loop until a dialog returns.  To avoid getting
    // stuck in an endless loop (could happen if the setDialogReturn: message
    // was lost) we also do some paranoia checks.
    //
    // Note that in Cocoa the user can still resize windows and select menu
    // items while a sheet is being displayed, so we can't just wait for the
    // first message to arrive and assume that is the setDialogReturn: call.

    while (nil == dialogReturn && !got_int && [connection isValid]
            && !isTerminating)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate distantFuture]];

    // Search for any resize messages on the input queue.  All other messages
    // on the input queue are dropped.  The reason why we single out resize
    // messages is because the user may have resized the window while a sheet
    // was open.
    int i, count = [inputQueue count];
    if (count > 0) {
        id textDimData = nil;
        if (count%2 == 0) {
            for (i = count-2; i >= 0; i -= 2) {
                int msgid = [[inputQueue objectAtIndex:i] intValue];
                if (SetTextDimensionsMsgID == msgid) {
                    textDimData = [[inputQueue objectAtIndex:i+1] retain];
                    break;
                }
            }
        }

        [inputQueue removeAllObjects];

        if (textDimData) {
            [inputQueue addObject:
                    [NSNumber numberWithInt:SetTextDimensionsMsgID]];
            [inputQueue addObject:textDimData];
            [textDimData release];
        }
    }
}

- (void)insertVimStateMessage
{
    // NOTE: This is the place to add Vim state that needs to be accessed from
    // MacVim.  Do not add state that could potentially require lots of memory
    // since this message gets sent each time the output queue is forcibly
    // flushed (e.g. storing the currently selected text would be a bad idea).
    // We take this approach of "pushing" the state to MacVim to avoid having
    // to make synchronous calls from MacVim to Vim in order to get state.

    BOOL mmta = curbuf ? curbuf->b_p_mmta : NO;

    NSDictionary *vimState = [NSDictionary dictionaryWithObjectsAndKeys:
        [[NSFileManager defaultManager] currentDirectoryPath], @"pwd",
        [NSNumber numberWithInt:p_mh], @"p_mh",
        [NSNumber numberWithBool:[self unusedEditor]], @"unusedEditor",
        [NSNumber numberWithBool:mmta], @"p_mmta",
        nil];

    // Put the state before all other messages.
    int msgid = SetVimStateMsgID;
    [outputQueue insertObject:[vimState dictionaryAsData] atIndex:0];
    [outputQueue insertObject:[NSData dataWithBytes:&msgid length:sizeof(int)]
                      atIndex:0];
}

- (void)processInputQueue
{
    if ([inputQueue count] == 0) return;

    // NOTE: One of the input events may cause this method to be called
    // recursively, so copy the input queue to a local variable and clear the
    // queue before starting to process input events (otherwise we could get
    // stuck in an endless loop).
    NSArray *q = [inputQueue copy];
    unsigned i, count = [q count];

    [inputQueue removeAllObjects];

    for (i = 1; i < count; i+=2) {
        int msgid = [[q objectAtIndex:i-1] intValue];
        id data = [q objectAtIndex:i];
        if ([data isEqual:[NSNull null]])
            data = nil;

        //NSLog(@"(%d) %s:%s", i, _cmd, MessageStrings[msgid]);
        [self handleInputEvent:msgid data:data];
    }

    [q release];
    //NSLog(@"Clear input event queue");
}

- (void)handleInputEvent:(int)msgid data:(NSData *)data
{
    if (InsertTextMsgID == msgid || KeyDownMsgID == msgid ||
            CmdKeyMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int mods = *((int*)bytes);  bytes += sizeof(int);
        int len = *((int*)bytes);  bytes += sizeof(int);
        NSString *key = [[NSString alloc] initWithBytes:bytes
                                                 length:len
                                               encoding:NSUTF8StringEncoding];
        mods = eventModifierFlagsToVimModMask(mods);

        if (InsertTextMsgID == msgid)
            [self handleInsertText:key];
        else
            [self handleKeyDown:key modifiers:mods];

        [key release];
    } else if (ScrollWheelMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];

        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);  bytes += sizeof(int);
        float dy = *((float*)bytes);  bytes += sizeof(float);

        int button = MOUSE_5;
        if (dy > 0) button = MOUSE_4;

        flags = eventModifierFlagsToVimMouseModMask(flags);

        int numLines = (int)round(dy);
        if (numLines < 0) numLines = -numLines;
        if (numLines == 0) numLines = 1;

#ifdef FEAT_GUI_SCROLL_WHEEL_FORCE
        gui.scroll_wheel_force = numLines;
#endif

        gui_send_mouse_event(button, col, row, NO, flags);
    } else if (MouseDownMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];

        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int button = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);  bytes += sizeof(int);
        int count = *((int*)bytes);  bytes += sizeof(int);

        button = eventButtonNumberToVimMouseButton(button);
        if (button >= 0) {
            flags = eventModifierFlagsToVimMouseModMask(flags);
            gui_send_mouse_event(button, col, row, count>1, flags);
        }
    } else if (MouseUpMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];

        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);  bytes += sizeof(int);

        flags = eventModifierFlagsToVimMouseModMask(flags);

        gui_send_mouse_event(MOUSE_RELEASE, col, row, NO, flags);
    } else if (MouseDraggedMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];

        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);  bytes += sizeof(int);

        flags = eventModifierFlagsToVimMouseModMask(flags);

        gui_send_mouse_event(MOUSE_DRAG, col, row, NO, flags);
    } else if (MouseMovedMsgID == msgid) {
        const void *bytes = [data bytes];
        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);

        gui_mouse_moved(col, row);
    } else if (AddInputMsgID == msgid) {
        NSString *string = [[NSString alloc] initWithData:data
                encoding:NSUTF8StringEncoding];
        if (string) {
            [self addInput:string];
            [string release];
        }
    } else if (SelectTabMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int idx = *((int*)bytes) + 1;
        //NSLog(@"Selecting tab %d", idx);
        send_tabline_event(idx);
    } else if (CloseTabMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int idx = *((int*)bytes) + 1;
        //NSLog(@"Closing tab %d", idx);
        send_tabline_menu_event(idx, TABLINE_MENU_CLOSE);
    } else if (AddNewTabMsgID == msgid) {
        //NSLog(@"Adding new tab");
        send_tabline_menu_event(0, TABLINE_MENU_NEW);
    } else if (DraggedTabMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        // NOTE! The destination index is 0 based, so do not add 1 to make it 1
        // based.
        int idx = *((int*)bytes);

        tabpage_move(idx);
    } else if (SetTextDimensionsMsgID == msgid || LiveResizeMsgID == msgid
            || SetTextRowsMsgID == msgid || SetTextColumnsMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int rows = Rows;
        if (SetTextColumnsMsgID != msgid) {
            rows = *((int*)bytes);  bytes += sizeof(int);
        }
        int cols = Columns;
        if (SetTextRowsMsgID != msgid) {
            cols = *((int*)bytes);  bytes += sizeof(int);
        }

        NSData *d = data;
        if (SetTextRowsMsgID == msgid || SetTextColumnsMsgID == msgid) {
            int dim[2] = { rows, cols };
            d = [NSData dataWithBytes:dim length:2*sizeof(int)];
            msgid = SetTextDimensionsReplyMsgID;
        }

        if (SetTextDimensionsMsgID == msgid)
            msgid = SetTextDimensionsReplyMsgID;

        // NOTE! Vim doesn't call gui_mch_set_shellsize() after
        // gui_resize_shell(), so we have to manually set the rows and columns
        // here since MacVim doesn't change the rows and columns to avoid
        // inconsistent states between Vim and MacVim.  The message sent back
        // indicates that it is a reply to a message that originated in MacVim
        // since we need to be able to determine where a message originated.
        [self queueMessage:msgid data:d];

        //NSLog(@"[VimTask] Resizing shell to %dx%d.", cols, rows);
        gui_resize_shell(cols, rows);
    } else if (ExecuteMenuMsgID == msgid) {
        NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
        if (attrs) {
            NSArray *desc = [attrs objectForKey:@"descriptor"];
            vimmenu_T *menu = menu_for_descriptor(desc);
            if (menu)
                gui_menu_cb(menu);
        }
    } else if (ToggleToolbarMsgID == msgid) {
        [self handleToggleToolbar];
    } else if (ScrollbarEventMsgID == msgid) {
        [self handleScrollbarEvent:data];
    } else if (SetFontMsgID == msgid) {
        [self handleSetFont:data];
    } else if (VimShouldCloseMsgID == msgid) {
        gui_shell_closed();
    } else if (DropFilesMsgID == msgid) {
        [self handleDropFiles:data];
    } else if (DropStringMsgID == msgid) {
        [self handleDropString:data];
    } else if (GotFocusMsgID == msgid) {
        if (!gui.in_focus)
            [self focusChange:YES];
    } else if (LostFocusMsgID == msgid) {
        if (gui.in_focus)
            [self focusChange:NO];
    } else if (SetMouseShapeMsgID == msgid) {
        const void *bytes = [data bytes];
        int shape = *((int*)bytes);  bytes += sizeof(int);
        update_mouseshape(shape);
    } else if (XcodeModMsgID == msgid) {
        [self handleXcodeMod:data];
    } else if (OpenWithArgumentsMsgID == msgid) {
        [self handleOpenWithArguments:[NSDictionary dictionaryWithData:data]];
    } else if (FindReplaceMsgID == msgid) {
        [self handleFindReplace:[NSDictionary dictionaryWithData:data]];
    } else {
        NSLog(@"WARNING: Unknown message received (msgid=%d)", msgid);
    }
}

+ (NSDictionary *)specialKeys
{
    static NSDictionary *specialKeys = nil;

    if (!specialKeys) {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *path = [mainBundle pathForResource:@"SpecialKeys"
                                              ofType:@"plist"];
        specialKeys = [[NSDictionary alloc] initWithContentsOfFile:path];
    }

    return specialKeys;
}

- (void)handleInsertText:(NSString *)text
{
    if (!text) return;

    char_u *str = (char_u*)[text UTF8String];
    int i, len = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

#ifdef FEAT_MBYTE
    char_u *conv_str = NULL;
    if (input_conv.vc_type != CONV_NONE) {
        conv_str = string_convert(&input_conv, str, &len);
        if (conv_str)
            str = conv_str;
    }
#endif

    for (i = 0; i < len; ++i) {
        add_to_input_buf(str+i, 1);
        if (CSI == str[i]) {
            // NOTE: If the converted string contains the byte CSI, then it
            // must be followed by the bytes KS_EXTRA, KE_CSI or things
            // won't work.
            static char_u extra[2] = { KS_EXTRA, KE_CSI };
            add_to_input_buf(extra, 2);
        }
    }

#ifdef FEAT_MBYTE
    if (conv_str)
        vim_free(conv_str);
#endif
}

- (void)handleKeyDown:(NSString *)key modifiers:(int)mods
{
    // TODO: This code is a horrible mess -- clean up!
    char_u special[3];
    char_u modChars[3];
    char_u *chars = (char_u*)[key UTF8String];
#ifdef FEAT_MBYTE
    char_u *conv_str = NULL;
#endif
    int length = [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    // Special keys (arrow keys, function keys, etc.) are stored in a plist so
    // that new keys can easily be added.
    NSString *specialString = [[MMBackend specialKeys]
            objectForKey:key];
    if (specialString && [specialString length] > 1) {
        //NSLog(@"special key: %@", specialString);
        int ikey = TO_SPECIAL([specialString characterAtIndex:0],
                [specialString characterAtIndex:1]);

        ikey = simplify_key(ikey, &mods);
        if (ikey == CSI)
            ikey = K_CSI;

        special[0] = CSI;
        special[1] = K_SECOND(ikey);
        special[2] = K_THIRD(ikey);

        chars = special;
        length = 3;
    } else if (1 == length && TAB == chars[0]) {
        // Tab is a trouble child:
        // - <Tab> is added to the input buffer as is
        // - <S-Tab> is translated to, {CSI,'k','B'} (i.e. 'Back-tab')
        // - <M-Tab> should be 0x80|TAB but this is not valid utf-8 so it needs
        //   to be converted to utf-8
        // - <S-M-Tab> is translated to <S-Tab> with ALT modifier
        // - <C-Tab> is reserved by Mac OS X
        // - <D-Tab> is reserved by Mac OS X
        chars = special;
        special[0] = TAB;
        length = 1;

        if (mods & MOD_MASK_SHIFT) {
            mods &= ~MOD_MASK_SHIFT;
            special[0] = CSI;
            special[1] = K_SECOND(K_S_TAB);
            special[2] = K_THIRD(K_S_TAB);
            length = 3;
        } else if (mods & MOD_MASK_ALT) {
            int mtab = 0x80 | TAB;
#ifdef FEAT_MBYTE
            if (enc_utf8) {
                // Convert to utf-8
                special[0] = (mtab >> 6) + 0xc0;
                special[1] = mtab & 0xbf;
                length = 2;
            } else
#endif
            {
                special[0] = mtab;
                length = 1;
            }
            mods &= ~MOD_MASK_ALT;
        }
    } else if (1 == length && chars[0] < 0x80 && (mods & MOD_MASK_ALT)) {
        // META key is treated separately.  This code was taken from gui_w48.c
        // and gui_gtk_x11.c.
        char_u string[7];
        int ch = simplify_key(chars[0], &mods);

        // Remove the SHIFT modifier for keys where it's already included,
        // e.g., '(' and '*'
        if (ch < 0x100 && !isalpha(ch) && isprint(ch))
            mods &= ~MOD_MASK_SHIFT;

        // Interpret the ALT key as making the key META, include SHIFT, etc.
        ch = extract_modifiers(ch, &mods);
        if (ch == CSI)
            ch = K_CSI;

        int len = 0;
        if (mods) {
            string[len++] = CSI;
            string[len++] = KS_MODIFIER;
            string[len++] = mods;
        }

        if (IS_SPECIAL(ch)) {
            string[len++] = CSI;
            string[len++] = K_SECOND(ch);
            string[len++] = K_THIRD(ch);
        } else {
            string[len++] = ch;
#ifdef FEAT_MBYTE
            // TODO: What if 'enc' is not "utf-8"?
            if (enc_utf8 && (ch & 0x80)) { // convert to utf-8
                string[len++] = ch & 0xbf;
                string[len-2] = ((unsigned)ch >> 6) + 0xc0;
                if (string[len-1] == CSI) {
                    string[len++] = KS_EXTRA;
                    string[len++] = (int)KE_CSI;
                }
            }
#endif
        }

        add_to_input_buf(string, len);
        return;
    } else if (length > 0) {
        unichar c = [key characterAtIndex:0];
        //NSLog(@"non-special: %@ (hex=%x, mods=%d)", key,
        //        [key characterAtIndex:0], mods);

        // HACK!  In most circumstances the Ctrl and Shift modifiers should be
        // cleared since they are already added to the key by the AppKit.
        // Unfortunately, the only way to deal with when to clear the modifiers
        // or not seems to be to have hard-wired rules like this.
        if ( !((' ' == c) || (0xa0 == c) || (mods & MOD_MASK_CMD)
                    || 0x9 == c || 0xd == c || ESC == c) ) {
            mods &= ~MOD_MASK_SHIFT;
            mods &= ~MOD_MASK_CTRL;
            //NSLog(@"clear shift ctrl");
        }

#ifdef FEAT_MBYTE
        if (input_conv.vc_type != CONV_NONE) {
            conv_str = string_convert(&input_conv, chars, &length);
            if (conv_str)
                chars = conv_str;
        }
#endif
    }

    if (chars && length > 0) {
        if (mods) {
            //NSLog(@"adding mods: %d", mods);
            modChars[0] = CSI;
            modChars[1] = KS_MODIFIER;
            modChars[2] = mods;
            add_to_input_buf(modChars, 3);
        }

        //NSLog(@"add to input buf: 0x%x", chars[0]);
        // TODO: Check for CSI bytes?
        add_to_input_buf(chars, length);
    }

#ifdef FEAT_MBYTE
    if (conv_str)
        vim_free(conv_str);
#endif
}

- (void)queueMessage:(int)msgid data:(NSData *)data
{
    //if (msgid != EnableMenuItemMsgID)
    //    NSLog(@"queueMessage:%s", MessageStrings[msgid]);

    [outputQueue addObject:[NSData dataWithBytes:&msgid length:sizeof(int)]];
    if (data)
        [outputQueue addObject:data];
    else
        [outputQueue addObject:[NSData data]];
}

- (void)connectionDidDie:(NSNotification *)notification
{
    // If the main connection to MacVim is lost this means that MacVim was
    // either quit (by the user chosing Quit on the MacVim menu), or it has
    // crashed.  In the former case the flag 'isTerminating' is set and we then
    // quit cleanly; in the latter case we make sure the swap files are left
    // for recovery.
    //
    // NOTE: This is not called if a Vim controller invalidates its connection.

    //NSLog(@"%s isTerminating=%d", _cmd, isTerminating);
    if (isTerminating)
        getout(0);
    else
        getout_preserve_modified(1);
}

- (void)blinkTimerFired:(NSTimer *)timer
{
    NSTimeInterval timeInterval = 0;

    [blinkTimer release];
    blinkTimer = nil;

    if (MMBlinkStateOn == blinkState) {
        gui_undraw_cursor();
        blinkState = MMBlinkStateOff;
        timeInterval = blinkOffInterval;
    } else if (MMBlinkStateOff == blinkState) {
        gui_update_cursor(TRUE, FALSE);
        blinkState = MMBlinkStateOn;
        timeInterval = blinkOnInterval;
    }

    if (timeInterval > 0) {
        blinkTimer = 
            [[NSTimer scheduledTimerWithTimeInterval:timeInterval target:self
                                            selector:@selector(blinkTimerFired:)
                                            userInfo:nil repeats:NO] retain];
        [self flushQueue:YES];
    }
}

- (void)focusChange:(BOOL)on
{
    gui_focus_change(on);
}

- (void)handleToggleToolbar
{
    // If 'go' contains 'T', then remove it, else add it.

    char_u go[sizeof(GO_ALL)+2];
    char_u *p;
    int len;

    STRCPY(go, p_go);
    p = vim_strchr(go, GO_TOOLBAR);
    len = STRLEN(go);

    if (p != NULL) {
        char_u *end = go + len;
        while (p < end) {
            p[0] = p[1];
            ++p;
        }
    } else {
        go[len] = GO_TOOLBAR;
        go[len+1] = NUL;
    }

    set_option_value((char_u*)"guioptions", 0, go, 0);

    [self redrawScreen];
}

- (void)handleScrollbarEvent:(NSData *)data
{
    if (!data) return;

    const void *bytes = [data bytes];
    long ident = *((long*)bytes);  bytes += sizeof(long);
    int hitPart = *((int*)bytes);  bytes += sizeof(int);
    float fval = *((float*)bytes);  bytes += sizeof(float);
    scrollbar_T *sb = gui_find_scrollbar(ident);

    if (sb) {
        scrollbar_T *sb_info = sb->wp ? &sb->wp->w_scrollbars[0] : sb;
        long value = sb_info->value;
        long size = sb_info->size;
        long max = sb_info->max;
        BOOL isStillDragging = NO;
        BOOL updateKnob = YES;

        switch (hitPart) {
        case NSScrollerDecrementPage:
            value -= (size > 2 ? size - 2 : 1);
            break;
        case NSScrollerIncrementPage:
            value += (size > 2 ? size - 2 : 1);
            break;
        case NSScrollerDecrementLine:
            --value;
            break;
        case NSScrollerIncrementLine:
            ++value;
            break;
        case NSScrollerKnob:
            isStillDragging = YES;
            // fall through ...
        case NSScrollerKnobSlot:
            value = (long)(fval * (max - size + 1));
            // fall through ...
        default:
            updateKnob = NO;
            break;
        }

        //NSLog(@"value %d -> %d", sb_info->value, value);
        gui_drag_scrollbar(sb, value, isStillDragging);

        if (updateKnob) {
            // Dragging the knob or option+clicking automatically updates
            // the knob position (on the actual NSScroller), so we only
            // need to set the knob position in the other cases.
            if (sb->wp) {
                // Update both the left&right vertical scrollbars.
                long identLeft = sb->wp->w_scrollbars[SBAR_LEFT].ident;
                long identRight = sb->wp->w_scrollbars[SBAR_RIGHT].ident;
                [self setScrollbarThumbValue:value size:size max:max
                                  identifier:identLeft];
                [self setScrollbarThumbValue:value size:size max:max
                                  identifier:identRight];
            } else {
                // Update the horizontal scrollbar.
                [self setScrollbarThumbValue:value size:size max:max
                                  identifier:ident];
            }
        }
    }
}

- (void)handleSetFont:(NSData *)data
{
    if (!data) return;

    const void *bytes = [data bytes];
    float pointSize = *((float*)bytes);  bytes += sizeof(float);
    //unsigned len = *((unsigned*)bytes);  bytes += sizeof(unsigned);
    bytes += sizeof(unsigned);  // len not used

    NSMutableString *name = [NSMutableString stringWithUTF8String:bytes];
    [name appendString:[NSString stringWithFormat:@":h%.2f", pointSize]];
    char_u *s = (char_u*)[name UTF8String];

#ifdef FEAT_MBYTE
    s = CONVERT_FROM_UTF8(s);
#endif

    set_option_value((char_u*)"guifont", 0, s, 0);

#ifdef FEAT_MBYTE
    CONVERT_FROM_UTF8_FREE(s);
#endif

    [self redrawScreen];
}

- (void)handleDropFiles:(NSData *)data
{
    // TODO: Get rid of this method; instead use Vim script directly.  At the
    // moment I know how to do this to open files in tabs, but I'm not sure how
    // to add the filenames to the command line when in command line mode.

    if (!data) return;

    NSMutableDictionary *args = [NSMutableDictionary dictionaryWithData:data];
    if (!args) return;

    id obj = [args objectForKey:@"forceOpen"];
    BOOL forceOpen = YES;
    if (obj)
        forceOpen = [obj boolValue];

    NSArray *filenames = [args objectForKey:@"filenames"];
    if (!(filenames && [filenames count] > 0)) return;

#ifdef FEAT_DND
    if (!forceOpen && (State & CMDLINE)) {
        // HACK!  If Vim is in command line mode then the files names
        // should be added to the command line, instead of opening the
        // files in tabs (unless forceOpen is set).  This is taken care of by
        // gui_handle_drop().
        int n = [filenames count];
        char_u **fnames = (char_u **)alloc(n * sizeof(char_u *));
        if (fnames) {
            int i = 0;
            for (i = 0; i < n; ++i)
                fnames[i] = [[filenames objectAtIndex:i] vimStringSave];

            // NOTE!  This function will free 'fnames'.
            // HACK!  It is assumed that the 'x' and 'y' arguments are
            // unused when in command line mode.
            gui_handle_drop(0, 0, 0, fnames, n);
        }
    } else
#endif // FEAT_DND
    {
        [self handleOpenWithArguments:args];
    }
}

- (void)handleDropString:(NSData *)data
{
    if (!data) return;

#ifdef FEAT_DND
    char_u  dropkey[3] = { CSI, KS_EXTRA, (char_u)KE_DROP };
    const void *bytes = [data bytes];
    int len = *((int*)bytes);  bytes += sizeof(int);
    NSMutableString *string = [NSMutableString stringWithUTF8String:bytes];

    // Replace unrecognized end-of-line sequences with \x0a (line feed).
    NSRange range = { 0, [string length] };
    unsigned n = [string replaceOccurrencesOfString:@"\x0d\x0a"
                                         withString:@"\x0a" options:0
                                              range:range];
    if (0 == n) {
        n = [string replaceOccurrencesOfString:@"\x0d" withString:@"\x0a"
                                       options:0 range:range];
    }

    len = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    char_u *s = (char_u*)[string UTF8String];
#ifdef FEAT_MBYTE
    if (input_conv.vc_type != CONV_NONE)
        s = string_convert(&input_conv, s, &len);
#endif
    dnd_yank_drag_data(s, len);
#ifdef FEAT_MBYTE
    if (input_conv.vc_type != CONV_NONE)
        vim_free(s);
#endif
    add_to_input_buf(dropkey, sizeof(dropkey));
#endif // FEAT_DND
}

- (void)startOdbEditWithArguments:(NSDictionary *)args
{
#ifdef FEAT_ODB_EDITOR
    id obj = [args objectForKey:@"remoteID"];
    if (!obj) return;

    OSType serverID = [obj unsignedIntValue];
    NSString *remotePath = [args objectForKey:@"remotePath"];

    NSAppleEventDescriptor *token = nil;
    NSData *tokenData = [args objectForKey:@"remoteTokenData"];
    obj = [args objectForKey:@"remoteTokenDescType"];
    if (tokenData && obj) {
        DescType tokenType = [obj unsignedLongValue];
        token = [NSAppleEventDescriptor descriptorWithDescriptorType:tokenType
                                                                data:tokenData];
    }

    NSArray *filenames = [args objectForKey:@"filenames"];
    unsigned i, numFiles = [filenames count];
    for (i = 0; i < numFiles; ++i) {
        NSString *filename = [filenames objectAtIndex:i];
        char_u *s = [filename vimStringSave];
        buf_T *buf = buflist_findname(s);
        vim_free(s);

        if (buf) {
            if (buf->b_odb_token) {
                [(NSAppleEventDescriptor*)(buf->b_odb_token) release];
                buf->b_odb_token = NULL;
            }

            if (buf->b_odb_fname) {
                vim_free(buf->b_odb_fname);
                buf->b_odb_fname = NULL;
            }

            buf->b_odb_server_id = serverID;

            if (token)
                buf->b_odb_token = [token retain];
            if (remotePath)
                buf->b_odb_fname = [remotePath vimStringSave];
        } else {
            NSLog(@"WARNING: Could not find buffer '%@' for ODB editing.",
                    filename);
        }
    }
#endif // FEAT_ODB_EDITOR
}

- (void)handleXcodeMod:(NSData *)data
{
#if 0
    const void *bytes = [data bytes];
    DescType type = *((DescType*)bytes);  bytes += sizeof(DescType);
    unsigned len = *((unsigned*)bytes);  bytes += sizeof(unsigned);
    if (0 == len)
        return;

    NSAppleEventDescriptor *replyEvent = [NSAppleEventDescriptor
            descriptorWithDescriptorType:type
                                   bytes:bytes
                                  length:len];
#endif
}

- (void)handleOpenWithArguments:(NSDictionary *)args
{
    // ARGUMENT:                DESCRIPTION:
    // -------------------------------------------------------------
    // filenames                list of filenames
    // dontOpen                 don't open files specified in above argument
    // layout                   which layout to use to open files
    // selectionRange           range of lines to select
    // searchText               string to search for
    // cursorLine               line to position the cursor on
    // cursorColumn             column to position the cursor on
    //                          (only valid when "cursorLine" is set)
    // remoteID                 ODB parameter
    // remotePath               ODB parameter
    // remoteTokenDescType      ODB parameter
    // remoteTokenData          ODB parameter

    //NSLog(@"%s%@ (starting=%d)", _cmd, args, starting);

    NSArray *filenames = [args objectForKey:@"filenames"];
    int i, numFiles = filenames ? [filenames count] : 0;
    BOOL openFiles = ![[args objectForKey:@"dontOpen"] boolValue];
    int layout = [[args objectForKey:@"layout"] intValue];

    // Change to directory of first file to open if this is an "unused" editor
    // (but do not do this if editing remotely).
    if (openFiles && numFiles > 0 && ![args objectForKey:@"remoteID"]
            && (starting || [self unusedEditor]) ) {
        char_u *s = [[filenames objectAtIndex:0] vimStringSave];
        vim_chdirfile(s);
        vim_free(s);
    }

    if (starting > 0) {
        // When Vim is starting we simply add the files to be opened to the
        // global arglist and Vim will take care of opening them for us.
        if (openFiles && numFiles > 0) {
            for (i = 0; i < numFiles; i++) {
                NSString *fname = [filenames objectAtIndex:i];
                char_u *p = NULL;

                if (ga_grow(&global_alist.al_ga, 1) == FAIL
                        || (p = [fname vimStringSave]) == NULL)
                    exit(2); // See comment in -[MMBackend exit]
                else
                    alist_add(&global_alist, p, 2);
            }

            // Vim will take care of arranging the files added to the arglist
            // in windows or tabs; all we must do is to specify which layout to
            // use.
            initialWindowLayout = layout;
        }
    } else {
        // When Vim is already open we resort to some trickery to open the
        // files with the specified layout.
        //
        // TODO: Figure out a better way to handle this?
        if (openFiles && numFiles > 0) {
            BOOL oneWindowInTab = topframe ? YES
                                           : (topframe->fr_layout == FR_LEAF);
            BOOL bufChanged = NO;
            BOOL bufHasFilename = NO;
            if (curbuf) {
                bufChanged = curbufIsChanged();
                bufHasFilename = curbuf->b_ffname != NULL;
            }

            // Temporarily disable flushing since the following code may
            // potentially cause multiple redraws.
            flushDisabled = YES;

            BOOL onlyOneTab = (first_tabpage->tp_next == NULL);
            if (WIN_TABS == layout && !onlyOneTab) {
                // By going to the last tabpage we ensure that the new tabs
                // will appear last (if this call is left out, the taborder
                // becomes messy).
                goto_tabpage(9999);
            }

            // Make sure we're in normal mode first.
            [self addInput:@"<C-\\><C-N>"];

            if (numFiles > 1) {
                // With "split layout" we open a new tab before opening
                // multiple files if the current tab has more than one window
                // or if there is exactly one window but whose buffer has a
                // filename.  (The :drop command ensures modified buffers get
                // their own window.)
                if ((WIN_HOR == layout || WIN_VER == layout) &&
                        (!oneWindowInTab || bufHasFilename))
                    [self addInput:@":tabnew<CR>"];

                // The files are opened by constructing a ":drop ..." command
                // and executing it.
                NSMutableString *cmd = (WIN_TABS == layout)
                        ? [NSMutableString stringWithString:@":tab drop"]
                        : [NSMutableString stringWithString:@":drop"];

                for (i = 0; i < numFiles; ++i) {
                    NSString *file = [filenames objectAtIndex:i];
                    file = [file stringByEscapingSpecialFilenameCharacters];
                    [cmd appendString:@" "];
                    [cmd appendString:file];
                }

                // Temporarily clear 'suffixes' so that the files are opened in
                // the same order as they appear in the "filenames" array.
                [self addInput:@":let mvim_oldsu=&su|set su=<CR>"];

                [self addInput:cmd];

                // Split the view into multiple windows if requested.
                if (WIN_HOR == layout)
                    [self addInput:@"|sall"];
                else if (WIN_VER == layout)
                    [self addInput:@"|vert sall"];

                // Restore the old value of 'suffixes'.
                [self addInput:@"|let &su=mvim_oldsu|unlet mvim_oldsu"];

                // Adding "|redr|f" ensures a "Hit ENTER" prompt is not shown.
                [self addInput:@"|redr|f<CR>"];
            } else {
                // When opening one file we try to reuse the current window,
                // but not if its buffer is modified or has a filename.
                // However, the 'arglist' layout always opens the file in the
                // current window.
                NSString *file = [[filenames lastObject]
                        stringByEscapingSpecialFilenameCharacters];
                NSString *cmd;
                if (WIN_HOR == layout) {
                    if (!(bufHasFilename || bufChanged))
                        cmd = [NSString stringWithFormat:@":e %@", file];
                    else
                        cmd = [NSString stringWithFormat:@":sp %@", file];
                } else if (WIN_VER == layout) {
                    if (!(bufHasFilename || bufChanged))
                        cmd = [NSString stringWithFormat:@":e %@", file];
                    else
                        cmd = [NSString stringWithFormat:@":vsp %@", file];
                } else if (WIN_TABS == layout) {
                    if (oneWindowInTab && !(bufHasFilename || bufChanged))
                        cmd = [NSString stringWithFormat:@":e %@", file];
                    else
                        cmd = [NSString stringWithFormat:@":tabe %@", file];
                } else {
                    // (The :drop command will split if there is a modified
                    // buffer.)
                    cmd = [NSString stringWithFormat:@":drop %@", file];
                }

                [self addInput:cmd];

                // Adding "|redr|f" ensures a "Hit ENTER" prompt is not shown.
                [self addInput:@"|redr|f<CR>"];
            }

            // Force screen redraw (does it have to be this complicated?).
            // (This code was taken from the end of gui_handle_drop().)
            update_screen(NOT_VALID);
            setcursor();
            out_flush();
            gui_update_cursor(FALSE, FALSE);
            maketitle();

            flushDisabled = NO;
        }
    }

    if ([args objectForKey:@"remoteID"]) {
        // NOTE: We have to delay processing any ODB related arguments since
        // the file(s) may not be opened until the input buffer is processed.
        [self performSelectorOnMainThread:@selector(startOdbEditWithArguments:)
                               withObject:args
                            waitUntilDone:NO];
    }

    NSString *lineString = [args objectForKey:@"cursorLine"];
    if (lineString && [lineString intValue] > 0) {
        NSString *columnString = [args objectForKey:@"cursorColumn"];
        if (!(columnString && [columnString intValue] > 0))
            columnString = @"1";

        NSString *cmd = [NSString stringWithFormat:@"<C-\\><C-N>:cal "
                "cursor(%@,%@)|norm! zz<CR>:f<CR>", lineString, columnString];
        [self addInput:cmd];
    }

    NSString *rangeString = [args objectForKey:@"selectionRange"];
    if (rangeString) {
        // Build a command line string that will select the given range of
        // lines.  If range.length == 0, then position the cursor on the given
        // line but do not select.
        NSRange range = NSRangeFromString(rangeString);
        NSString *cmd;
        if (range.length > 0) {
            cmd = [NSString stringWithFormat:@"<C-\\><C-N>%dGV%dGz.0",
                    NSMaxRange(range), range.location];
        } else {
            cmd = [NSString stringWithFormat:@"<C-\\><C-N>%dGz.0",
                    range.location];
        }

        [self addInput:cmd];
    }

    NSString *searchText = [args objectForKey:@"searchText"];
    if (searchText) {
        // TODO: Searching is an exclusive motion, so if the pattern would
        // match on row 0 column 0 then this pattern will miss that match.
        [self addInput:[NSString stringWithFormat:@"<C-\\><C-N>gg/\\c%@<CR>",
                searchText]];
    }
}

- (BOOL)checkForModifiedBuffers
{
    buf_T *buf;
    for (buf = firstbuf; buf != NULL; buf = buf->b_next) {
        if (bufIsChanged(buf)) {
            return YES;
        }
    }

    return NO;
}

- (void)addInput:(NSString *)input
{
    char_u *s = (char_u*)[input UTF8String];

#ifdef FEAT_MBYTE
    s = CONVERT_FROM_UTF8(s);
#endif

    server_to_input_buf(s);

#ifdef FEAT_MBYTE
    CONVERT_FROM_UTF8_FREE(s);
#endif
}

- (BOOL)unusedEditor
{
    BOOL oneWindowInTab = topframe ? YES
                                   : (topframe->fr_layout == FR_LEAF);
    BOOL bufChanged = NO;
    BOOL bufHasFilename = NO;
    if (curbuf) {
        bufChanged = curbufIsChanged();
        bufHasFilename = curbuf->b_ffname != NULL;
    }

    BOOL onlyOneTab = (first_tabpage->tp_next == NULL);

    return onlyOneTab && oneWindowInTab && !bufChanged && !bufHasFilename;
}

- (void)redrawScreen
{
    // Force screen redraw (does it have to be this complicated?).
    redraw_all_later(CLEAR);
    update_screen(NOT_VALID);
    setcursor();
    out_flush();
    gui_update_cursor(FALSE, FALSE);

    // HACK! The cursor is not put back at the command line by the above
    // "redraw commands".  The following test seems to do the trick though.
    if (State & CMDLINE)
        redrawcmdline();
}

- (void)handleFindReplace:(NSDictionary *)args
{
    if (!args) return;

    NSString *findString = [args objectForKey:@"find"];
    if (!findString) return;

    char_u *find = [findString vimStringSave];
    char_u *replace = [[args objectForKey:@"replace"] vimStringSave];
    int flags = [[args objectForKey:@"flags"] intValue];

    // NOTE: The flag 0x100 is used to indicate a backward search.
    gui_do_findrepl(flags, find, replace, (flags & 0x100) == 0);

    vim_free(find);
    vim_free(replace);
}

@end // MMBackend (Private)




@implementation MMBackend (ClientServer)

- (NSString *)connectionNameFromServerName:(NSString *)name
{
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

    return [[NSString stringWithFormat:@"%@.%@", bundlePath, name]
        lowercaseString];
}

- (NSConnection *)connectionForServerName:(NSString *)name
{
    // TODO: Try 'name%d' if 'name' fails.
    NSString *connName = [self connectionNameFromServerName:name];
    NSConnection *svrConn = [connectionNameDict objectForKey:connName];

    if (!svrConn) {
        svrConn = [NSConnection connectionWithRegisteredName:connName
                                                           host:nil];
        // Try alternate server...
        if (!svrConn && alternateServerName) {
            //NSLog(@"  trying to connect to alternate server: %@",
            //        alternateServerName);
            connName = [self connectionNameFromServerName:alternateServerName];
            svrConn = [NSConnection connectionWithRegisteredName:connName
                                                            host:nil];
        }

        // Try looking for alternate servers...
        if (!svrConn) {
            //NSLog(@"  looking for alternate servers...");
            NSString *alt = [self alternateServerNameForName:name];
            if (alt != alternateServerName) {
                //NSLog(@"  found alternate server: %@", string);
                [alternateServerName release];
                alternateServerName = [alt copy];
            }
        }

        // Try alternate server again...
        if (!svrConn && alternateServerName) {
            //NSLog(@"  trying to connect to alternate server: %@",
            //        alternateServerName);
            connName = [self connectionNameFromServerName:alternateServerName];
            svrConn = [NSConnection connectionWithRegisteredName:connName
                                                            host:nil];
        }

        if (svrConn) {
            [connectionNameDict setObject:svrConn forKey:connName];

            //NSLog(@"Adding %@ as connection observer for %@", self, svrConn);
            [[NSNotificationCenter defaultCenter] addObserver:self
                    selector:@selector(serverConnectionDidDie:)
                        name:NSConnectionDidDieNotification object:svrConn];
        }
    }

    return svrConn;
}

- (NSConnection *)connectionForServerPort:(int)port
{
    NSConnection *conn;
    NSEnumerator *e = [connectionNameDict objectEnumerator];

    while ((conn = [e nextObject])) {
        // HACK! Assume connection uses mach ports.
        if (port == [(NSMachPort*)[conn sendPort] machPort])
            return conn;
    }

    return nil;
}

- (void)serverConnectionDidDie:(NSNotification *)notification
{
    //NSLog(@"%s%@", _cmd, notification);

    NSConnection *svrConn = [notification object];

    //NSLog(@"Removing %@ as connection observer from %@", self, svrConn);
    [[NSNotificationCenter defaultCenter]
            removeObserver:self
                      name:NSConnectionDidDieNotification
                    object:svrConn];

    [connectionNameDict removeObjectsForKeys:
        [connectionNameDict allKeysForObject:svrConn]];

    // HACK! Assume connection uses mach ports.
    int port = [(NSMachPort*)[svrConn sendPort] machPort];
    NSNumber *key = [NSNumber numberWithInt:port];

    [clientProxyDict removeObjectForKey:key];
    [serverReplyDict removeObjectForKey:key];
}

- (void)addClient:(NSDistantObject *)client
{
    NSConnection *conn = [client connectionForProxy];
    // HACK! Assume connection uses mach ports.
    int port = [(NSMachPort*)[conn sendPort] machPort];
    NSNumber *key = [NSNumber numberWithInt:port];

    if (![clientProxyDict objectForKey:key]) {
        [client setProtocolForProxy:@protocol(MMVimClientProtocol)];
        [clientProxyDict setObject:client forKey:key];
    }

    // NOTE: 'clientWindow' is a global variable which is used by <client>
    clientWindow = port;
}

- (NSString *)alternateServerNameForName:(NSString *)name
{
    if (!(name && [name length] > 0))
        return nil;

    // Only look for alternates if 'name' doesn't end in a digit.
    unichar lastChar = [name characterAtIndex:[name length]-1];
    if (lastChar >= '0' && lastChar <= '9')
        return nil;

    // Look for alternates among all current servers.
    NSArray *list = [self serverList];
    if (!(list && [list count] > 0))
        return nil;

    // Filter out servers starting with 'name' and ending with a number. The
    // (?i) pattern ensures that the match is case insensitive.
    NSString *pat = [NSString stringWithFormat:@"(?i)%@[0-9]+\\z", name];
    NSPredicate *pred = [NSPredicate predicateWithFormat:
            @"SELF MATCHES %@", pat];
    list = [list filteredArrayUsingPredicate:pred];
    if ([list count] > 0) {
        list = [list sortedArrayUsingSelector:@selector(serverNameCompare:)];
        return [list objectAtIndex:0];
    }

    return nil;
}

@end // MMBackend (ClientServer)




@implementation NSString (MMServerNameCompare)
- (NSComparisonResult)serverNameCompare:(NSString *)string
{
    return [self compare:string
                 options:NSCaseInsensitiveSearch|NSNumericSearch];
}
@end




static int eventModifierFlagsToVimModMask(int modifierFlags)
{
    int modMask = 0;

    if (modifierFlags & NSShiftKeyMask)
        modMask |= MOD_MASK_SHIFT;
    if (modifierFlags & NSControlKeyMask)
        modMask |= MOD_MASK_CTRL;
    if (modifierFlags & NSAlternateKeyMask)
        modMask |= MOD_MASK_ALT;
    if (modifierFlags & NSCommandKeyMask)
        modMask |= MOD_MASK_CMD;

    return modMask;
}

static int eventModifierFlagsToVimMouseModMask(int modifierFlags)
{
    int modMask = 0;

    if (modifierFlags & NSShiftKeyMask)
        modMask |= MOUSE_SHIFT;
    if (modifierFlags & NSControlKeyMask)
        modMask |= MOUSE_CTRL;
    if (modifierFlags & NSAlternateKeyMask)
        modMask |= MOUSE_ALT;

    return modMask;
}

static int eventButtonNumberToVimMouseButton(int buttonNumber)
{
    static int mouseButton[] = { MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE };

    return (buttonNumber >= 0 && buttonNumber < 3)
            ? mouseButton[buttonNumber] : -1;
}



// This function is modeled after the VimToPython function found in if_python.c
// NB This does a deep copy by value, it does not lookup references like the
// VimToPython function does.  This is because I didn't want to deal with the
// retain cycles that this would create, and we can cover 99% of the use cases
// by ignoring it.  If we ever switch to using GC in MacVim then this
// functionality can be implemented easily.
static id vimToCocoa(typval_T * tv, int depth)
{
    id result = nil;
    id newObj = nil;


    // Avoid infinite recursion
    if (depth > 100) {
        return nil;
    }

    if (tv->v_type == VAR_STRING) {
        char_u * val = tv->vval.v_string;
        // val can be NULL if the string is empty
        if (!val) {
            result = [NSString string];
        } else {
#ifdef FEAT_MBYTE
            val = CONVERT_TO_UTF8(val);
#endif
            result = [NSString stringWithUTF8String:(char*)val];
#ifdef FEAT_MBYTE
            CONVERT_TO_UTF8_FREE(val);
#endif
        }
    } else if (tv->v_type == VAR_NUMBER) {
        // looks like sizeof(varnumber_T) is always <= sizeof(long)
        result = [NSNumber numberWithLong:(long)tv->vval.v_number];
    } else if (tv->v_type == VAR_LIST) {
        list_T * list = tv->vval.v_list;
        listitem_T * curr;

        NSMutableArray * arr = result = [NSMutableArray array];

        if (list != NULL) {
            for (curr = list->lv_first; curr != NULL; curr = curr->li_next) {
                newObj = vimToCocoa(&curr->li_tv, depth + 1);
                [arr addObject:newObj];
            }
        }
    } else if (tv->v_type == VAR_DICT) {
        NSMutableDictionary * dict = result = [NSMutableDictionary dictionary];

        if (tv->vval.v_dict != NULL) {
            hashtab_T * ht = &tv->vval.v_dict->dv_hashtab;
            int todo = ht->ht_used;
            hashitem_T * hi;
            dictitem_T * di;

            for (hi = ht->ht_array; todo > 0; ++hi) {
                if (!HASHITEM_EMPTY(hi)) {
                    --todo;

                    di = dict_lookup(hi);
                    newObj = vimToCocoa(&di->di_tv, depth + 1);

                    char_u * keyval = hi->hi_key;
#ifdef FEAT_MBYTE
                    keyval = CONVERT_TO_UTF8(keyval);
#endif
                    NSString * key = [NSString stringWithUTF8String:(char*)keyval];
#ifdef FEAT_MBYTE
                    CONVERT_TO_UTF8_FREE(keyval);
#endif
                    [dict setObject:newObj forKey:key];
                }
            }
        }
    } else { // only func refs should fall into this category?
        result = nil;
    }

    return result;
}


// This function is modeled after eval_client_expr_to_string found in main.c
// Returns nil if there was an error evaluating the expression, and writes a
// message to errorStr.
// TODO Get the error that occurred while evaluating the expression in vim
// somehow.
static id evalExprCocoa(NSString * expr, NSString ** errstr)
{

    char_u *s = (char_u*)[expr UTF8String];

#ifdef FEAT_MBYTE
    s = CONVERT_FROM_UTF8(s);
#endif

    int save_dbl = debug_break_level;
    int save_ro = redir_off;

    debug_break_level = -1;
    redir_off = 0;
    ++emsg_skip;

    typval_T * tvres = eval_expr(s, NULL);

    debug_break_level = save_dbl;
    redir_off = save_ro;
    --emsg_skip;

    setcursor();
    out_flush();

#ifdef FEAT_MBYTE
    CONVERT_FROM_UTF8_FREE(s);
#endif

#ifdef FEAT_GUI
    if (gui.in_use)
        gui_update_cursor(FALSE, FALSE);
#endif

    if (tvres == NULL) {
        free_tv(tvres);
        *errstr = @"Expression evaluation failed.";
    }

    id res = vimToCocoa(tvres, 1);

    free_tv(tvres);

    if (res == nil) {
        *errstr = @"Conversion to cocoa values failed.";
    }

    return res;
}



@implementation NSString (VimStrings)

+ (id)stringWithVimString:(char_u *)s
{
    // This method ensures a non-nil string is returned.  If 's' cannot be
    // converted to a utf-8 string it is assumed to be latin-1.  If conversion
    // still fails an empty NSString is returned.
    NSString *string = nil;
    if (s) {
#ifdef FEAT_MBYTE
        s = CONVERT_TO_UTF8(s);
#endif
        string = [NSString stringWithUTF8String:(char*)s];
        if (!string) {
            // HACK! Apparently 's' is not a valid utf-8 string, maybe it is
            // latin-1?
            string = [NSString stringWithCString:(char*)s
                                        encoding:NSISOLatin1StringEncoding];
        }
#ifdef FEAT_MBYTE
        CONVERT_TO_UTF8_FREE(s);
#endif
    }

    return string != nil ? string : [NSString string];
}

- (char_u *)vimStringSave
{
    char_u *s = (char_u*)[self UTF8String], *ret = NULL;

#ifdef FEAT_MBYTE
    s = CONVERT_FROM_UTF8(s);
#endif
    ret = vim_strsave(s);
#ifdef FEAT_MBYTE
    CONVERT_FROM_UTF8_FREE(s);
#endif

    return ret;
}

@end // NSString (VimStrings)
