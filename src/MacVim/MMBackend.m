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
 * for the backend to update [MMAppController processInput:forIdentifier:].
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

#ifdef FEAT_BEVAL
// Seconds to delay balloon evaluation after mouse event (subtracted from
// p_bdlay so that this effectively becomes the smallest possible delay).
NSTimeInterval MMBalloonEvalInternalDelay = 0.1;
#endif

// TODO: Move to separate file.
static int eventModifierFlagsToVimModMask(int modifierFlags);
static int eventModifierFlagsToVimMouseModMask(int modifierFlags);
static int eventButtonNumberToVimMouseButton(int buttonNumber);

// In gui_macvim.m
vimmenu_T *menu_for_descriptor(NSArray *desc);

static id evalExprCocoa(NSString * expr, NSString ** errstr);

extern void im_preedit_start_macvim();
extern void im_preedit_end_macvim();
extern void im_preedit_abandon_macvim();
extern void im_preedit_changed_macvim(char *preedit_string, int cursor_index);

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


// Keycodes recognized by Vim (struct taken from gui_x11.c and gui_w48.c)
// (The key codes were taken from Carbon/HIToolbox/Events.)
static struct specialkey
{
    unsigned    key_sym;
    char_u      vim_code0;
    char_u      vim_code1;
} special_keys[] =
{
    {0x7e /*kVK_UpArrow*/,       'k', 'u'},
    {0x7d /*kVK_DownArrow*/,     'k', 'd'},
    {0x7b /*kVK_LeftArrow*/,     'k', 'l'},
    {0x7c /*kVK_RightArrow*/,    'k', 'r'},

    {0x7a /*kVK_F1*/,            'k', '1'},
    {0x78 /*kVK_F2*/,            'k', '2'},
    {0x63 /*kVK_F3*/,            'k', '3'},
    {0x76 /*kVK_F4*/,            'k', '4'},
    {0x60 /*kVK_F5*/,            'k', '5'},
    {0x61 /*kVK_F6*/,            'k', '6'},
    {0x62 /*kVK_F7*/,            'k', '7'},
    {0x64 /*kVK_F8*/,            'k', '8'},
    {0x65 /*kVK_F9*/,            'k', '9'},
    {0x6d /*kVK_F10*/,           'k', ';'},

    {0x67 /*kVK_F11*/,           'F', '1'},
    {0x6f /*kVK_F12*/,           'F', '2'},
    {0x69 /*kVK_F13*/,           'F', '3'},
    {0x6b /*kVK_F14*/,           'F', '4'},
    {0x71 /*kVK_F15*/,           'F', '5'},
    {0x6a /*kVK_F16*/,           'F', '6'},
    {0x40 /*kVK_F17*/,           'F', '7'},
    {0x4f /*kVK_F18*/,           'F', '8'},
    {0x50 /*kVK_F19*/,           'F', '9'},
    {0x5a /*kVK_F20*/,           'F', 'A'},

    {0x72 /*kVK_Help*/,          '%', '1'},
    {0x33 /*kVK_Delete*/,        'k', 'b'},
    {0x75 /*kVK_ForwardDelete*/, 'k', 'D'},
    {0x73 /*kVK_Home*/,          'k', 'h'},
    {0x77 /*kVK_End*/,           '@', '7'},
    {0x74 /*kVK_PageUp*/,        'k', 'P'},
    {0x79 /*kVK_PageDown*/,      'k', 'N'},

    /* Keypad keys: */
    {0x45 /*kVK_ANSI_KeypadPlus*/,       'K', '6'},
    {0x4e /*kVK_ANSI_KeypadMinus*/,      'K', '7'},
    {0x4b /*kVK_ANSI_KeypadDivide*/,     'K', '8'},
    {0x43 /*kVK_ANSI_KeypadMultiply*/,   'K', '9'},
    {0x4c /*kVK_ANSI_KeypadEnter*/,      'K', 'A'},
    {0x41 /*kVK_ANSI_KeypadDecimal*/,    'K', 'B'},
    {0x47 /*kVK_ANSI_KeypadClear*/,      KS_EXTRA, (char_u)KE_KDEL},

    {0x52 /*kVK_ANSI_Keypad0*/,  'K', 'C'},
    {0x53 /*kVK_ANSI_Keypad1*/,  'K', 'D'},
    {0x54 /*kVK_ANSI_Keypad2*/,  'K', 'E'},
    {0x55 /*kVK_ANSI_Keypad3*/,  'K', 'F'},
    {0x56 /*kVK_ANSI_Keypad4*/,  'K', 'G'},
    {0x57 /*kVK_ANSI_Keypad5*/,  'K', 'H'},
    {0x58 /*kVK_ANSI_Keypad6*/,  'K', 'I'},
    {0x59 /*kVK_ANSI_Keypad7*/,  'K', 'J'},
    {0x5b /*kVK_ANSI_Keypad8*/,  'K', 'K'},
    {0x5c /*kVK_ANSI_Keypad9*/,  'K', 'L'},

    /* Keys that we want to be able to use any modifier with: */
    {0x31 /*kVK_Space*/,         ' ', NUL},
    {0x30 /*kVK_Tab*/,           TAB, NUL},
    {0x35 /*kVK_Escape*/,        ESC, NUL},
    {0x24 /*kVK_Return*/,        CAR, NUL},

    /* End of list marker: */
    {0, 0, 0}
};


extern GuiFont gui_mch_retain_font(GuiFont font);


@interface NSString (MMServerNameCompare)
- (NSComparisonResult)serverNameCompare:(NSString *)string;
@end


@interface MMBackend (Private)
- (void)clearDrawData;
- (void)didChangeWholeLine;
- (void)waitForDialogReturn;
- (void)insertVimStateMessage;
- (void)processInputQueue;
- (void)handleInputEvent:(int)msgid data:(NSData *)data;
- (void)doKeyDown:(NSString *)key
          keyCode:(unsigned)code
        modifiers:(int)mods;
- (BOOL)handleSpecialKey:(NSString *)key
                 keyCode:(unsigned)code
               modifiers:(int)mods;
- (BOOL)handleMacMetaKey:(int)ikey modifiers:(int)mods;
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
- (int)checkForModifiedBuffers;
- (void)addInput:(NSString *)input;
- (void)redrawScreen;
- (void)handleFindReplace:(NSDictionary *)args;
- (void)handleMarkedText:(NSData *)data;
- (void)handleGesture:(NSData *)data;
#ifdef FEAT_BEVAL
- (void)bevalCallback:(id)sender;
#endif
#ifdef MESSAGE_QUEUE
- (void)checkForProcessEvents:(NSTimer *)timer;
#endif
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

    if (!(colorDict && sysColorDict && actionDict)) {
        ASLogNotice(@"Failed to load dictionaries.%@", MMSymlinkWarningString);
    }

    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    gui_mch_free_font(oldWideFont);  oldWideFont = NOFONT;
    [blinkTimer release];  blinkTimer = nil;
    [alternateServerName release];  alternateServerName = nil;
    [serverReplyDict release];  serverReplyDict = nil;
    [clientProxyDict release];  clientProxyDict = nil;
    [connectionNameDict release];  connectionNameDict = nil;
    [inputQueue release];  inputQueue = nil;
    [outputQueue release];  outputQueue = nil;
    [drawData release];  drawData = nil;
    [connection release];  connection = nil;
    [actionDict release];  actionDict = nil;
    [sysColorDict release];  sysColorDict = nil;
    [colorDict release];  colorDict = nil;
    [vimServerConnection release];  vimServerConnection = nil;
#ifdef FEAT_BEVAL
    [lastToolTip release];  lastToolTip = nil;
#endif

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

- (void)getWindowPositionX:(int*)x Y:(int*)y
{
    // NOTE: winposX and winposY are set by the SetWindowPositionMsgID message.
    if (x) *x = winposX;
    if (y) *y = winposY;
}

- (void)setWindowPositionX:(int)x Y:(int)y
{
    // NOTE: Setting the window position has no immediate effect on the cached
    // variables winposX and winposY.  These are set by the frontend when the
    // window actually moves (see SetWindowPositionMsgID).
    ASLogDebug(@"x=%d y=%d", x, y);
    int pos[2] = { x, y };
    NSData *data = [NSData dataWithBytes:pos length:2*sizeof(int)];
    [self queueMessage:SetWindowPositionMsgID data:data];
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
        ASLogCrit(@"Failed to launch MacVim (path=%@).%@",
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
            ASLogCrit(@"Could not find MacVim executable in bundle.%@",
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
            ASLogCrit(@"Timed-out waiting for GUI to launch.");
            return NO;
        }
    }

    @try {
        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(connectionDidDie:)
                    name:NSConnectionDidDieNotification object:connection];

        appProxy = [[connection rootProxy] retain];
        [appProxy setProtocolForProxy:@protocol(MMAppProtocol)];

        // NOTE: We do not set any new timeout values for the connection to the
        // frontend.  This means that if the frontend is "stuck" (e.g. in a
        // modal loop) then any calls to the frontend will block indefinitely
        // (the default timeouts are huge).

        int pid = [[NSProcessInfo processInfo] processIdentifier];

        identifier = [appProxy connectBackend:self pid:pid];
        return YES;
    }
    @catch (NSException *ex) {
        ASLogDebug(@"Connect backend failed: reason=%@", ex);
    }

    return NO;
}

- (BOOL)openGUIWindow
{
    if (gui_win_x != -1 && gui_win_y != -1) {
        // NOTE: the gui_win_* coordinates are both set to -1 if no :winpos
        // command is in .[g]vimrc.  (This way of detecting if :winpos has been
        // used may cause problems if a second monitor is located to the left
        // and underneath the main monitor as it will have negative
        // coordinates.  However, this seems like a minor problem that is not
        // worth fixing since all GUIs work this way.)
        ASLogDebug(@"default x=%d y=%d", gui_win_x, gui_win_y);
        int pos[2] = { gui_win_x, gui_win_y };
        NSData *data = [NSData dataWithBytes:pos length:2*sizeof(int)];
        [self queueMessage:SetWindowPositionMsgID data:data];
    }

    [self queueMessage:OpenWindowMsgID data:nil];

    // HACK: Clear window immediately upon opening to avoid it flashing white.
    [self clearAll];

    return YES;
}

- (void)clearAll
{
    int type = ClearAllDrawType;

    // Any draw commands in queue are effectively obsolete since this clearAll
    // will negate any effect they have, therefore we may as well clear the
    // draw queue.
    [self clearDrawData];

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

    if (left == 0 && right == gui.num_cols-1)
        [self didChangeWholeLine];
}

- (void)drawString:(char_u*)s length:(int)len row:(int)row
            column:(int)col cells:(int)cells flags:(int)flags
{
    if (len <= 0) return;

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

    if (left == 0 && right == gui.num_cols-1)
        [self didChangeWholeLine];
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

- (void)drawSign:(NSString *)imgName
           atRow:(int)row
          column:(int)col
           width:(int)width
          height:(int)height
{
    int type = DrawSignDrawType;
    [drawData appendBytes:&type length:sizeof(int)];

    const char* utf8String = [imgName UTF8String];
    int strSize = (int)strlen(utf8String) + 1;
    [drawData appendBytes:&strSize length:sizeof(int)];
    [drawData appendBytes:utf8String length:strSize];

    [drawData appendBytes:&col length:sizeof(int)];
    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&width length:sizeof(int)];
    [drawData appendBytes:&height length:sizeof(int)];
}

- (void)update
{
    // Keep running the run-loop until there is no more input to process.
    while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true)
            == kCFRunLoopRunHandledSource)
        ;   // do nothing
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
        if (gui.wide_font != oldWideFont) {
            gui_mch_free_font(oldWideFont);
            oldWideFont = gui_mch_retain_font(gui.wide_font);
            [self setFont:oldWideFont wide:YES];
        }

        int type = SetCursorPosDrawType;
        [drawData appendBytes:&type length:sizeof(type)];
        [drawData appendBytes:&gui.row length:sizeof(gui.row)];
        [drawData appendBytes:&gui.col length:sizeof(gui.col)];

        [self queueMessage:BatchDrawMsgID data:[[drawData copy] autorelease]];
        [self clearDrawData];
    }

    if ([outputQueue count] > 0) {
        [self insertVimStateMessage];

        @try {
            ASLogDebug(@"Flushing queue: %@",
                       debugStringForMessageQueue(outputQueue));
            [appProxy processInput:outputQueue forIdentifier:identifier];
        }
        @catch (NSException *ex) {
            ASLogDebug(@"processInput:forIdentifer failed: reason=%@", ex);
            if (![connection isValid]) {
                ASLogDebug(@"Connection is invalid, exit now!");
                ASLogDebug(@"waitForAck=%d got_int=%d", waitForAck, got_int);
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
    if ([inputQueue count] > 0 || input_available() || got_int) {
        inputReceived = YES;
    } else {
        // Wait for the specified amount of time, unless 'milliseconds' is
        // negative in which case we wait "forever" (1e6 seconds translates to
        // approximately 11 days).
        CFTimeInterval dt = (milliseconds >= 0 ? .001*milliseconds : 1e6);
        NSTimer *timer = nil;

        // Set interval timer which checks for the events of job and channel
        // when there is any pending job or channel.
        if (dt > 0.1 && (has_any_channel() || has_pending_job())) {
            timer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                     target:self
                                                   selector:@selector(checkForProcessEvents:)
                                                   userInfo:nil
                                                    repeats:YES];
            [[NSRunLoop currentRunLoop] addTimer:timer
                                         forMode:NSDefaultRunLoopMode];
        }

        while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, dt, true)
                == kCFRunLoopRunHandledSource) {
            // In order to ensure that all input on the run-loop has been
            // processed we set the timeout to 0 and keep processing until the
            // run-loop times out.
            dt = 0.0;
            if ([inputQueue count] > 0 || input_available() || got_int)
                inputReceived = YES;
        }

        if ([inputQueue count] > 0 || input_available() || got_int)
            inputReceived = YES;

        [timer invalidate];
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
    // mch_exit() to prematurely terminate a process (or set 'isTerminating'
    // first).

    // Make sure no connectionDidDie: notification is received now that we are
    // already exiting.
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // The 'isTerminating' flag indicates that the frontend is also exiting so
    // there is no need to flush any more output since the frontend won't look
    // at it anyway.
    if (!isTerminating && [connection isValid]) {
        @try {
            // Flush the entire queue in case a VimLeave autocommand added
            // something to the queue.
            [self queueMessage:CloseWindowMsgID data:nil];
            ASLogDebug(@"Flush output queue before exit: %@",
                       debugStringForMessageQueue(outputQueue));
            [appProxy processInput:outputQueue forIdentifier:identifier];
        }
        @catch (NSException *ex) {
            ASLogDebug(@"CloseWindowMsgID send failed: reason=%@", ex);
        }

        // NOTE: If Cmd-w was pressed to close the window the menu is briefly
        // highlighted and during this pause the frontend won't receive any DO
        // messages.  If the Vim process exits before this highlighting has
        // finished Cocoa will emit the following error message:
        //   *** -[NSMachPort handlePortMessage:]: dropping incoming DO message
        //   because the connection or ports are invalid
        // To avoid this warning we delay here.  If the warning still appears
        // this delay may need to be increased.
        usleep(150000);
    }

#ifdef MAC_CLIENTSERVER
    // The default connection is used for the client/server code.
    if (vimServerConnection) {
        [vimServerConnection setRootObject:nil];
        [vimServerConnection invalidate];
    }
#endif
}

- (void)selectTab:(int)index
{
    index -= 1;
    NSData *data = [NSData dataWithBytes:&index length:sizeof(int)];
    [self queueMessage:SelectTabMsgID data:data];
}

- (void)updateTabBar
{
    NSMutableData *data = [NSMutableData data];

    int idx = tabpage_index(curtab) - 1;
    [data appendBytes:&idx length:sizeof(int)];

    tabpage_T *tp;
    for (tp = first_tabpage; tp != NULL; tp = tp->tp_next) {
        // Count the number of windows in the tabpage.
        //win_T *wp = tp->tp_firstwin;
        //int wincount;
        //for (wincount = 0; wp != NULL; wp = wp->w_next, ++wincount);
        //[data appendBytes:&wincount length:sizeof(int)];

        int tabProp = MMTabInfoCount;
        [data appendBytes:&tabProp length:sizeof(int)];
        for (tabProp = MMTabLabel; tabProp < MMTabInfoCount; ++tabProp) {
            // This function puts the label of the tab in the global 'NameBuff'.
            get_tabline_label(tp, (tabProp == MMTabToolTip));
            NSString *s = [NSString stringWithVimString:NameBuff];
            int len = [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            if (len < 0)
                len = 0;

            [data appendBytes:&len length:sizeof(int)];
            if (len > 0)
                [data appendBytes:[s UTF8String] length:len];
        }
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
    int dim[] = { rows, cols };
    NSData *data = [NSData dataWithBytes:&dim length:2*sizeof(int)];

    [self queueMessage:SetTextDimensionsMsgID data:data];
}

- (void)resizeView
{
    [self queueMessage:ResizeViewMsgID data:nil];
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

    [self queueMessage:BrowseForFileMsgID properties:attr];
    [self flushQueue:YES];

    @try {
        [self waitForDialogReturn];

        if (dialogReturn && [dialogReturn isKindOfClass:[NSString class]])
            s = [dialogReturn vimStringSave];

        [dialogReturn release];  dialogReturn = nil;
    }
    @catch (NSException *ex) {
        ASLogDebug(@"Exception: reason=%@", ex);
    }

    return (char *)s;
}

- (oneway void)setDialogReturn:(in bycopy id)obj
{
    ASLogDebug(@"%@", obj);

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

    [self queueMessage:ShowDialogMsgID properties:attr];
    [self flushQueue:YES];

    @try {
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
    @catch (NSException *ex) {
        ASLogDebug(@"Exception: reason=%@", ex);
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

- (void)createScrollbarWithIdentifier:(int32_t)ident type:(int)type
{
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&ident length:sizeof(int32_t)];
    [data appendBytes:&type length:sizeof(int)];

    [self queueMessage:CreateScrollbarMsgID data:data];
}

- (void)destroyScrollbarWithIdentifier:(int32_t)ident
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&ident length:sizeof(int32_t)];

    [self queueMessage:DestroyScrollbarMsgID data:data];
}

- (void)showScrollbarWithIdentifier:(int32_t)ident state:(int)visible
{
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&ident length:sizeof(int32_t)];
    [data appendBytes:&visible length:sizeof(int)];

    [self queueMessage:ShowScrollbarMsgID data:data];
}

- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(int32_t)ident
{
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&ident length:sizeof(int32_t)];
    [data appendBytes:&pos length:sizeof(int)];
    [data appendBytes:&len length:sizeof(int)];

    [self queueMessage:SetScrollbarPositionMsgID data:data];
}

- (void)setScrollbarThumbValue:(long)val size:(long)size max:(long)max
                    identifier:(int32_t)ident
{
    float fval = max-size+1 > 0 ? (float)val/(max-size+1) : 0;
    float prop = (float)size/(max+1);
    if (fval < 0) fval = 0;
    else if (fval > 1.0f) fval = 1.0f;
    if (prop < 0) prop = 0;
    else if (prop > 1.0f) prop = 1.0f;

    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&ident length:sizeof(int32_t)];
    [data appendBytes:&fval length:sizeof(float)];
    [data appendBytes:&prop length:sizeof(float)];

    [self queueMessage:SetScrollbarThumbMsgID data:data];
}

- (void)setFont:(GuiFont)font wide:(BOOL)wide
{
    NSString *fontName = (NSString *)font;
    float size = 0;
    NSArray *components = [fontName componentsSeparatedByString:@":h"];
    if ([components count] == 2) {
        size = [[components lastObject] floatValue];
        fontName = [components objectAtIndex:0];
    }

    int len = [fontName lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&size length:sizeof(float)];
    [data appendBytes:&len length:sizeof(int)];

    if (len > 0)
        [data appendBytes:[fontName UTF8String] length:len];
    else if (!wide)
        return;     // Only the wide font can be set to nothing

    [self queueMessage:(wide ? SetWideFontMsgID : SetFontMsgID) data:data];
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

- (void)stopBlink:(BOOL)updateCursor
{
    if (MMBlinkStateOff == blinkState && updateCursor) {
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

- (void)adjustColumnspace:(int)columnspace
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&columnspace length:sizeof(int)];
    [self queueMessage:AdjustColumnspaceMsgID data:data];
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
                CGFloat r, g, b, a;
                col = [col colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                [col getRed:&r green:&g blue:&b alpha:&a];
                return (((int)(r*255+.5f) & 0xff) << 16)
                     + (((int)(g*255+.5f) & 0xff) << 8)
                     +  ((int)(b*255+.5f) & 0xff);
            }
        }
    }

    ASLogNotice(@"No color with key %@ found.", stripKey);
    return INVALCOLOR;
}

- (BOOL)hasSpecialKeyWithValue:(char_u *)value
{
    int i;
    for (i = 0; special_keys[i].key_sym != 0; i++) {
        if (value[0] == special_keys[i].vim_code0
                && value[1] == special_keys[i].vim_code1)
            return YES;
    }

    return NO;
}

- (void)enterFullScreen:(int)fuoptions background:(int)bg
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&fuoptions length:sizeof(int)];
    bg = MM_COLOR(bg);
    [data appendBytes:&bg length:sizeof(int)];
    [self queueMessage:EnterFullScreenMsgID data:data];
}

- (void)leaveFullScreen
{
    [self queueMessage:LeaveFullScreenMsgID data:nil];
}

- (void)setFullScreenBackgroundColor:(int)color
{
    NSMutableData *data = [NSMutableData data];
    color = MM_COLOR(color);
    [data appendBytes:&color length:sizeof(int)];

    [self queueMessage:SetFullScreenColorMsgID data:data];
}

- (void)setAntialias:(BOOL)antialias
{
    int msgid = antialias ? EnableAntialiasMsgID : DisableAntialiasMsgID;

    [self queueMessage:msgid data:nil];
}

- (void)setLigatures:(BOOL)ligatures
{
    int msgid = ligatures ? EnableLigaturesMsgID : DisableLigaturesMsgID;

    [self queueMessage:msgid data:nil];
}

- (void)setThinStrokes:(BOOL)thinStrokes
{
    int msgid = thinStrokes ? EnableThinStrokesMsgID : DisableThinStrokesMsgID;

    [self queueMessage:msgid data:nil];
}

- (void)setBlurRadius:(int)radius
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&radius length:sizeof(int)];

    [self queueMessage:SetBlurRadiusMsgID data:data];
}

- (void)updateModifiedFlag
{
    int state = [self checkForModifiedBuffers];
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&state length:sizeof(int)];
    [self queueMessage:SetBuffersModifiedMsgID data:data];
}

- (oneway void)processInput:(int)msgid data:(in bycopy NSData *)data
{
    //
    // This is a DO method which is called from inside MacVim to add new input
    // to this Vim process.  It may get called when the run loop is updated.
    //
    // NOTE: DO NOT MODIFY VIM STATE IN THIS METHOD! (Adding data to input
    // buffers is OK however.)
    //
    // Add keyboard input to Vim's input buffer immediately.  We have to do
    // this because in many places Vim polls the input buffer whilst waiting
    // for keyboard input (so Vim may lock up forever otherwise).
    //
    // Similarly, TerminateNowMsgID must be checked immediately otherwise code
    // which waits on the run loop will fail to detect this message (e.g. in
    // waitForConnectionAcknowledgement).
    //
    // All other input is processed when processInputQueue is called (typically
    // this happens in waitForInput:).
    //
    // TODO: Process mouse events here as well?  Anything else?
    //

    if (KeyDownMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        unsigned mods = *((unsigned*)bytes);  bytes += sizeof(unsigned);
        unsigned code = *((unsigned*)bytes);  bytes += sizeof(unsigned);
        unsigned len  = *((unsigned*)bytes);  bytes += sizeof(unsigned);

        if (ctrl_c_interrupts && 1 == len) {
            // NOTE: the flag ctrl_c_interrupts is 0 e.g. when the user has
            // mappings to something like <C-c>g.  Also it seems the flag
            // intr_char is 0 when MacVim was started from Finder whereas it is
            // 0x03 (= Ctrl_C) when started from Terminal.
            char_u *str = (char_u*)bytes;
            if (str[0] == Ctrl_C || (str[0] == intr_char && intr_char != 0)) {
                ASLogDebug(@"Got INT, str[0]=%#x ctrl_c_interrupts=%d "
                        "intr_char=%#x", str[0], ctrl_c_interrupts, intr_char);
                got_int = TRUE;
                [inputQueue removeAllObjects];
                return;
            }
        }

        // The lowest bit of the modifiers is set if this key is a repeat.
        BOOL isKeyRepeat = (mods & 1) != 0;

        // Ignore key press if the input buffer has something in it and this
        // key is a repeat (since this means Vim can't keep up with the speed
        // with which new input is being received).
        if (!isKeyRepeat || vim_is_input_buf_empty()) {
            NSString *key = [[NSString alloc] initWithBytes:bytes
                                                 length:len
                                               encoding:NSUTF8StringEncoding];
            mods = eventModifierFlagsToVimModMask(mods);

            [self doKeyDown:key keyCode:code modifiers:mods];
            [key release];
        } else {
            ASLogDebug(@"Dropping repeated keyboard input");
        }
    } else if (SetMarkedTextMsgID == msgid) {
        // NOTE: This message counts as keyboard input...
        [self handleMarkedText:data];
    } else if (TerminateNowMsgID == msgid) {
        // Terminate immediately (the frontend is about to quit or this process
        // was aborted).  Don't preserve modified files since the user would
        // already have been presented with a dialog warning if there were any
        // modified files when we get here.
        isTerminating = YES;
        getout(0);
    } else {
        // First remove previous instances of this message from the input
        // queue, else the input queue may fill up as a result of Vim not being
        // able to keep up with the speed at which new messages are received.
        // TODO: Remove all previous instances (there could be many)?
        int i, count = [inputQueue count];
        for (i = 1; i < count; i += 2) {
            if ([[inputQueue objectAtIndex:i-1] intValue] == msgid) {
                ASLogDebug(@"Input queue filling up, remove message: %s",
                                                        MessageStrings[msgid]);
                [inputQueue removeObjectAtIndex:i];
                [inputQueue removeObjectAtIndex:i-1];
                break;
            }
        }

        // Now add message to input queue.  Add null data if necessary to
        // ensure that input queue has even length.
        [inputQueue addObject:[NSNumber numberWithInt:msgid]];
        [inputQueue addObject:(data ? (id)data : [NSNull null])];
    }
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

        // The code below used to be clip_copy_selection() but it is now
        // static, so do it manually.
        clip_update_selection(&clip_star);
        clip_free_selection(&clip_star);
        clip_get_selection(&clip_star);
        clip_gen_set_selection(&clip_star);

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
    ASLogDebug(@"reply=%@ server=%@", reply, (id)server);

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
    ASLogDebug(@"input=%@ client=%@", input, (id)client);

    // NOTE: We don't call addInput: here because it differs from
    // server_to_input_buf() in that it always sets the 'silent' flag and we
    // don't want the MacVim client/server code to behave differently from
    // other platforms.
    char_u *s = [input vimStringSave];
    server_to_input_buf(s);
    vim_free(s);

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
    unsigned i;

    if (vimServerConnection) // Paranoia check, should always be nil
        [vimServerConnection release];

    vimServerConnection = [[NSConnection alloc]
                                            initWithReceivePort:[NSPort port]
                                                       sendPort:nil];

    for (i = 0; i < MMServerMax; ++i) {
        NSString *connName = [self connectionNameFromServerName:svrName];

        if ([vimServerConnection registerName:connName]) {
            ASLogInfo(@"Registered server with name: %@", svrName);

            // TODO: Set request/reply time-outs to something else?
            //
            // Don't wait for requests (time-out means that the message is
            // dropped).
            [vimServerConnection setRequestTimeout:0];
            //[vimServerConnection setReplyTimeout:MMReplyTimeout];
            [vimServerConnection setRootObject:self];

            // NOTE: 'serverName' is a global variable
            serverName = [svrName vimStringSave];
#ifdef FEAT_EVAL
            set_vim_var_string(VV_SEND_SERVER, serverName, -1);
#endif
#ifdef FEAT_TITLE
	    need_maketitle = TRUE;
#endif
            [self queueMessage:SetServerNameMsgID
                        data:[svrName dataUsingEncoding:NSUTF8StringEncoding]];
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
    @catch (NSException *ex) {
        ASLogDebug(@"Exception: reason=%@", ex);
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
        @catch (NSException *ex) {
            ASLogDebug(@"serverList failed: reason=%@", ex);
        }
    } else {
        // We get here if a --remote flag is used before MacVim has started.
        ASLogInfo(@"No connection to MacVim, server listing not possible.");
    }

    return list;
}

- (NSString *)peekForReplyOnPort:(int)port
{
    ASLogDebug(@"port=%d", port);

    NSNumber *key = [NSNumber numberWithInt:port];
    NSMutableArray *replies = [serverReplyDict objectForKey:key];
    if (replies && [replies count]) {
        ASLogDebug(@"    %ld replies, topmost is: %@", [replies count],
                   [replies objectAtIndex:0]);
        return [replies objectAtIndex:0];
    }

    ASLogDebug(@"    No replies");
    return nil;
}

- (NSString *)waitForReplyOnPort:(int)port
{
    ASLogDebug(@"port=%d", port);
    
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
            ASLogDebug(@"    Got reply: %@", reply);
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
            ASLogDebug(@"reply=%@ port=%d", reply, port);
            [client addReply:reply server:self];
            return YES;
        }
        @catch (NSException *ex) {
            ASLogDebug(@"addReply:server: failed: reason=%@", ex);
        }
    } else {
        ASLogNotice(@"server2client failed; no client with id %d", port);
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

    while (waitForAck && !got_int && [connection isValid]) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate distantFuture]];
        ASLogDebug(@"  waitForAck=%d got_int=%d isValid=%d",
                   waitForAck, got_int, [connection isValid]);
    }

    if (waitForAck) {
        ASLogDebug(@"Never received a connection acknowledgement");
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [appProxy release];  appProxy = nil;

        // NOTE: We intentionally do not call mch_exit() since this in turn
        // will lead to -[MMBackend exit] getting called which we want to
        // avoid.
        exit(0);
    }

    ASLogInfo(@"Connection acknowledgement received");
    [self processInputQueue];
}

- (oneway void)acknowledgeConnection
{
    ASLogDebug(@"");
    waitForAck = NO;
}

- (BOOL)imState
{
    return imState;
}

- (void)setImState:(BOOL)activated
{
    imState = activated;

    gui_update_cursor(TRUE, FALSE);
    [self flushQueue:YES];
}

#ifdef FEAT_BEVAL
- (void)setLastToolTip:(NSString *)toolTip
{
    if (toolTip != lastToolTip) {
        [lastToolTip release];
        lastToolTip = [toolTip copy];
    }
}
#endif

- (void)addToMRU:(NSArray *)filenames
{
    [self queueMessage:AddToMRUMsgID properties:
            [NSDictionary dictionaryWithObject:filenames forKey:@"filenames"]];
}

@end // MMBackend



@implementation MMBackend (Private)

- (void)clearDrawData
{
    [drawData setLength:0];
    numWholeLineChanges = offsetForDrawDataPrune = 0;
}

- (void)didChangeWholeLine
{
    // It may happen that draw queue is filled up with lots of changes that
    // affect a whole row.  If the number of such changes equals twice the
    // number of visible rows then we can prune some commands off the queue.
    //
    // NOTE: If we don't perform this pruning the draw queue may grow
    // indefinitely if Vim were to repeatedly send draw commands without ever
    // waiting for new input (that's when the draw queue is flushed).  The one
    // instance I know where this can happen is when a command is executed in
    // the shell (think ":grep" with thousands of matches).

    ++numWholeLineChanges;
    if (numWholeLineChanges == gui.num_rows) {
        // Remember the offset to prune up to.
        offsetForDrawDataPrune = [drawData length];
    } else if (numWholeLineChanges == 2*gui.num_rows) {
        // Delete all the unnecessary draw commands.
        NSMutableData *d = [[NSMutableData alloc]
                    initWithBytes:[drawData bytes] + offsetForDrawDataPrune
                           length:[drawData length] - offsetForDrawDataPrune];
        offsetForDrawDataPrune = [d length];
        numWholeLineChanges -= gui.num_rows;
        [drawData release];
        drawData = d;
    }
}

- (void)waitForDialogReturn
{
    // Keep processing the run loop until a dialog returns.  To avoid getting
    // stuck in an endless loop (could happen if the setDialogReturn: message
    // was lost) we also do some paranoia checks.
    //
    // Note that in Cocoa the user can still resize windows and select menu
    // items while a sheet is being displayed, so we can't just wait for the
    // first message to arrive and assume that is the setDialogReturn: call.

    while (nil == dialogReturn && !got_int && [connection isValid])
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
    int numTabs = tabpage_index(NULL) - 1;
    if (numTabs < 0)
        numTabs = 0;

    NSDictionary *vimState = [NSDictionary dictionaryWithObjectsAndKeys:
        [[NSFileManager defaultManager] currentDirectoryPath], @"pwd",
        [NSNumber numberWithInt:p_mh], @"p_mh",
        [NSNumber numberWithBool:mmta], @"p_mmta",
        [NSNumber numberWithInt:numTabs], @"numTabs",
        [NSNumber numberWithInt:fuoptions_flags], @"fullScreenOptions",
        [NSNumber numberWithLong:p_mouset], @"p_mouset",
        nil];

    // Put the state before all other messages.
    // TODO: If called multiple times the oldest state will be used! Should
    // remove any current Vim state messages from the queue first.
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

        ASLogDebug(@"(%d) %s", i, MessageStrings[msgid]);
        [self handleInputEvent:msgid data:data];
    }

    [q release];
}


- (void)handleInputEvent:(int)msgid data:(NSData *)data
{
    if (ScrollWheelMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];

        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);  bytes += sizeof(int);
        float dy = *((float*)bytes);  bytes += sizeof(float);
        float dx = *((float*)bytes);  bytes += sizeof(float);

        int button = MOUSE_5;
        if (dy < 0) button = MOUSE_5;
        else if (dy > 0) button = MOUSE_4;
        else if (dx < 0) button = MOUSE_6;
        else if (dx > 0) button = MOUSE_7;

        flags = eventModifierFlagsToVimMouseModMask(flags);

        int numLines = (dy != 0) ? (int)round(dy) : (int)round(dx);
        if (numLines < 0) numLines = -numLines;

        if (numLines != 0) {
#ifdef FEAT_GUI_SCROLL_WHEEL_FORCE
            gui.scroll_wheel_force = numLines;
#endif
            gui_send_mouse_event(button, col, row, NO, flags);
        }

#ifdef FEAT_BEVAL
        if (p_beval && balloonEval) {
            // Update the balloon eval message after a slight delay (to avoid
            // calling it too often).
            [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(bevalCallback:)
                                               object:nil];
            [self performSelector:@selector(bevalCallback:)
                       withObject:nil
                       afterDelay:MMBalloonEvalInternalDelay];
        }
#endif
    } else if (MouseDownMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];

        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int button = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);  bytes += sizeof(int);
        int repeat = *((int*)bytes);  bytes += sizeof(int);

        button = eventButtonNumberToVimMouseButton(button);
        if (button >= 0) {
            flags = eventModifierFlagsToVimMouseModMask(flags);
            gui_send_mouse_event(button, col, row, repeat, flags);
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

#ifdef FEAT_BEVAL
        if (p_beval && balloonEval) {
            balloonEval->x = col;
            balloonEval->y = row;

            // Update the balloon eval message after a slight delay (to avoid
            // calling it too often).
            [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(bevalCallback:)
                                               object:nil];
            [self performSelector:@selector(bevalCallback:)
                       withObject:nil
                       afterDelay:MMBalloonEvalInternalDelay];
        }
#endif
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
        send_tabline_event(idx);
    } else if (CloseTabMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int idx = *((int*)bytes) + 1;
        send_tabline_menu_event(idx, TABLINE_MENU_CLOSE);
        [self redrawScreen];
    } else if (AddNewTabMsgID == msgid) {
        send_tabline_menu_event(0, TABLINE_MENU_NEW);
        [self redrawScreen];
    } else if (DraggedTabMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        // NOTE! The destination index is 0 based, so do not add 1 to make it 1
        // based.
        int idx = *((int*)bytes);

        tabpage_move(idx);
    } else if (SetTextDimensionsMsgID == msgid || LiveResizeMsgID == msgid
            || SetTextDimensionsNoResizeWindowMsgID == msgid
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

        gui_resize_shell(cols, rows);
    } else if (ResizeViewMsgID == msgid) {
        [self queueMessage:msgid data:data];
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
    } else if (ZoomMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);  bytes += sizeof(int);
        //int zoom = *((int*)bytes);  bytes += sizeof(int);

        // NOTE: The frontend sends zoom messages here causing us to
        // immediately resize the shell and mirror the message back to the
        // frontend.  This is done to ensure that the draw commands reach the
        // frontend before the window actually changes size in order to avoid
        // flickering.  (Also see comment in SetTextDimensionsReplyMsgID
        // regarding resizing.)
        [self queueMessage:ZoomMsgID data:data];
        gui_resize_shell(cols, rows);
    } else if (SetWindowPositionMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        winposX = *((int*)bytes);  bytes += sizeof(int);
        winposY = *((int*)bytes);  bytes += sizeof(int);
        ASLogDebug(@"SetWindowPositionMsgID: x=%d y=%d", winposX, winposY);
    } else if (GestureMsgID == msgid) {
        [self handleGesture:data];
    } else if (ActivatedImMsgID == msgid) {
        [self setImState:YES];
    } else if (DeactivatedImMsgID == msgid) {
        [self setImState:NO];
    } else if (BackingPropertiesChangedMsgID == msgid) {
        [self redrawScreen];
    } else {
        ASLogWarn(@"Unknown message received (msgid=%d)", msgid);
    }
}

- (void)doKeyDown:(NSString *)key
          keyCode:(unsigned)code
        modifiers:(int)mods
{
    ASLogDebug(@"key='%@' code=%#x mods=%#x length=%ld", key, code, mods,
            [key length]);
    if (!key) return;

    char_u *str = (char_u*)[key UTF8String];
    int i, len = [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    if ([self handleSpecialKey:key keyCode:code modifiers:mods])
        return;

#ifdef FEAT_MBYTE
    char_u *conv_str = NULL;
    if (input_conv.vc_type != CONV_NONE) {
        conv_str = string_convert(&input_conv, str, &len);
        if (conv_str)
            str = conv_str;
    }
#endif

    if (mods & MOD_MASK_CMD) {
        // NOTE: For normal input (non-special, 'macmeta' off) the modifier
        // flags are already included in the key event.  However, the Cmd key
        // flag is special and must always be added manually.
        // The Shift flag is already included in the key when the Command
        // key is held.  The same goes for Alt, unless Ctrl is held or
        // 'macmeta' is set.  It is important that these flags are cleared
        // _after_ special keys have been handled, since they should never be
        // cleared for special keys.
        mods &= ~MOD_MASK_SHIFT;
        if (!(mods & MOD_MASK_CTRL)) {
            BOOL mmta = curbuf ? curbuf->b_p_mmta : YES;
            if (!mmta)
                mods &= ~MOD_MASK_ALT;
        }

        ASLogDebug(@"add mods=%#x", mods);
        char_u modChars[3] = { CSI, KS_MODIFIER, mods };
        add_to_input_buf(modChars, 3);
    } else if (mods & MOD_MASK_ALT && 1 == len && str[0] < 0x80
            && curbuf && curbuf->b_p_mmta) {
        // HACK! The 'macmeta' is set so we have to handle Alt key presses
        // separately.  Normally Alt key presses are interpreted by the
        // frontend but now we have to manually set the 8th bit and deal with
        // UTF-8 conversion.
        if ([self handleMacMetaKey:str[0] modifiers:mods])
            return;
    }


    for (i = 0; i < len; ++i) {
        ASLogDebug(@"add byte [%d/%d]: %#x", i, len, str[i]);
        add_to_input_buf(str+i, 1);
        if (CSI == str[i]) {
            // NOTE: If the converted string contains the byte CSI, then it
            // must be followed by the bytes KS_EXTRA, KE_CSI or things
            // won't work.
            static char_u extra[2] = { KS_EXTRA, KE_CSI };
            ASLogDebug(@"add KS_EXTRA, KE_CSI");
            add_to_input_buf(extra, 2);
        }
    }

#ifdef FEAT_MBYTE
    if (conv_str)
        vim_free(conv_str);
#endif
}

- (BOOL)handleSpecialKey:(NSString *)key
                 keyCode:(unsigned)code
               modifiers:(int)mods
{
    int i;
    for (i = 0; special_keys[i].key_sym != 0; i++) {
        if (special_keys[i].key_sym == code) {
            ASLogDebug(@"Special key: %#x", code);
            break;
        }
    }
    if (special_keys[i].key_sym == 0)
        return NO;

    int ikey = special_keys[i].vim_code1 == NUL ? special_keys[i].vim_code0 :
            TO_SPECIAL(special_keys[i].vim_code0, special_keys[i].vim_code1);
    ikey = simplify_key(ikey, &mods);
    if (ikey == CSI)
        ikey = K_CSI;

    char_u chars[4];
    int len = 0;

    if (IS_SPECIAL(ikey)) {
        chars[0] = CSI;
        chars[1] = K_SECOND(ikey);
        chars[2] = K_THIRD(ikey);
        len = 3;
    } else if (mods & MOD_MASK_ALT && special_keys[i].vim_code1 == 0
#ifdef FEAT_MBYTE
            && !enc_dbcs    // TODO: ?  (taken from gui_gtk_x11.c)
#endif
            ) {
        ASLogDebug(@"Alt special=%d", ikey);

        // NOTE: The last entries in the special_keys struct when pressed
        // together with Alt need to be handled separately or they will not
        // work.
        // The following code was gleaned from gui_gtk_x11.c.
        mods &= ~MOD_MASK_ALT;
        int mkey = 0x80 | ikey;
#ifdef FEAT_MBYTE
        if (enc_utf8) {  // TODO: What about other encodings?
            // Convert to utf-8
            chars[0] = (mkey >> 6) + 0xc0;
            chars[1] = mkey & 0xbf;
            if (chars[1] == CSI) {
                // We end up here when ikey == ESC
                chars[2] = KS_EXTRA;
                chars[3] = KE_CSI;
                len = 4;
            } else {
                len = 2;
            }
        } else
#endif
        {
            chars[0] = mkey;
            len = 1;
        }
    } else {
        ASLogDebug(@"Just ikey=%d", ikey);
        chars[0] = ikey;
        len = 1;
    }

    if (len > 0) {
        if (mods) {
            ASLogDebug(@"Adding mods to special: %d", mods);
            char_u modChars[3] = { CSI, KS_MODIFIER, (char_u)mods };
            add_to_input_buf(modChars, 3);
        }

        ASLogDebug(@"Adding special (%d): %x,%x,%x", len,
                chars[0], chars[1], chars[2]);
        add_to_input_buf(chars, len);
    }

    return YES;
}

- (BOOL)handleMacMetaKey:(int)ikey modifiers:(int)mods
{
    ASLogDebug(@"ikey=%d mods=%d", ikey, mods);

    // This code was taken from gui_w48.c and gui_gtk_x11.c.
    char_u string[7];
    int ch = simplify_key(ikey, &mods);

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

    add_to_input_buf(string, len);
    return YES;
}

- (void)queueMessage:(int)msgid data:(NSData *)data
{
    [outputQueue addObject:[NSData dataWithBytes:&msgid length:sizeof(int)]];
    if (data)
        [outputQueue addObject:data];
    else
        [outputQueue addObject:[NSData data]];
}

- (void)connectionDidDie:(NSNotification *)notification
{
    // If the main connection to MacVim is lost this means that either MacVim
    // has crashed or this process did not receive its termination message
    // properly (e.g. if the TerminateNowMsgID was dropped).
    //
    // NOTE: This is not called if a Vim controller invalidates its connection.

    ASLogNotice(@"Main connection was lost before process had a chance "
                "to terminate; preserving swap files.");
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
}

- (void)handleScrollbarEvent:(NSData *)data
{
    if (!data) return;

    const void *bytes = [data bytes];
    int32_t ident = *((int32_t*)bytes);  bytes += sizeof(int32_t);
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

        gui_drag_scrollbar(sb, value, isStillDragging);

        if (updateKnob) {
            // Dragging the knob or option+clicking automatically updates
            // the knob position (on the actual NSScroller), so we only
            // need to set the knob position in the other cases.
            if (sb->wp) {
                // Update both the left&right vertical scrollbars.
                int32_t idL = (int32_t)sb->wp->w_scrollbars[SBAR_LEFT].ident;
                int32_t idR = (int32_t)sb->wp->w_scrollbars[SBAR_RIGHT].ident;
                [self setScrollbarThumbValue:value size:size max:max
                                  identifier:idL];
                [self setScrollbarThumbValue:value size:size max:max
                                  identifier:idR];
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
    int pointSize = (int)*((float*)bytes);  bytes += sizeof(float);

    unsigned len = *((unsigned*)bytes);  bytes += sizeof(unsigned);
    NSMutableString *name = [NSMutableString stringWithUTF8String:bytes];
    bytes += len;

    [name appendString:[NSString stringWithFormat:@":h%d", pointSize]];
    char_u *s = (char_u*)[name UTF8String];

    unsigned wlen = *((unsigned*)bytes);  bytes += sizeof(unsigned);
    char_u *ws = NULL;
    if (wlen > 0) {
        NSMutableString *wname = [NSMutableString stringWithUTF8String:bytes];
        bytes += wlen;

        [wname appendString:[NSString stringWithFormat:@":h%d", pointSize]];
        ws = (char_u*)[wname UTF8String];
    }

#ifdef FEAT_MBYTE
    s = CONVERT_FROM_UTF8(s);
    if (ws) {
        ws = CONVERT_FROM_UTF8(ws);
    }
#endif

    set_option_value((char_u*)"guifont", 0, s, 0);

    if (ws && gui.wide_font != NOFONT) {
        // NOTE: This message is sent on Cmd-+/Cmd-- and as such should only
        // change the wide font if 'gfw' is non-empty (the frontend always has
        // some wide font set, even if 'gfw' is empty).
        set_option_value((char_u*)"guifontwide", 0, ws, 0);
    }

#ifdef FEAT_MBYTE
    if (ws) {
        CONVERT_FROM_UTF8_FREE(ws);
    }
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
            ASLogWarn(@"Could not find buffer '%@' for ODB editing.", filename);
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
    // selectionRange           range of characters to select
    // searchText               string to search for
    // cursorLine               line to position the cursor on
    // cursorColumn             column to position the cursor on
    //                          (only valid when "cursorLine" is set)
    // remoteID                 ODB parameter
    // remotePath               ODB parameter
    // remoteTokenDescType      ODB parameter
    // remoteTokenData          ODB parameter

    ASLogDebug(@"args=%@ (starting=%d)", args, starting);

    NSArray *filenames = [args objectForKey:@"filenames"];
    int i, numFiles = filenames ? [filenames count] : 0;
    BOOL openFiles = ![[args objectForKey:@"dontOpen"] boolValue];
    int layout = [[args objectForKey:@"layout"] intValue];

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

            // Change to directory of first file to open.
            // NOTE: This is only done when Vim is starting to avoid confusion:
            // if a window is already open the pwd is never touched.
            if (openFiles && numFiles > 0 && ![args objectForKey:@"remoteID"])
            {
                char_u *s = [[filenames objectAtIndex:0] vimStringSave];
                if (mch_isdir(s)) {
                    mch_chdir((char*)s);
                } else {
                    vim_chdirfile(s, "drop");
                }
                vim_free(s);
            }
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
                [self addInput:@"|let &su=mvim_oldsu|unlet mvim_oldsu<CR>"];
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
                [self addInput:@"<CR>"];
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
        [self performSelector:@selector(startOdbEditWithArguments:)
                   withObject:args
                   afterDelay:0];
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
        // characters.  If range.length == 0, then position the cursor on the
        // line at start of range but do not select.
        NSRange range = NSRangeFromString(rangeString);
        NSString *cmd;
        if (range.length > 0) {
            // TODO: This only works for encodings where 1 byte == 1 character
            cmd = [NSString stringWithFormat:@"<C-\\><C-N>%ldgov%ldgo",
                    range.location, NSMaxRange(range)-1];
        } else {
            cmd = [NSString stringWithFormat:@"<C-\\><C-N>%ldGz.0",
                    range.location];
        }

        [self addInput:cmd];
    }

    NSString *searchText = [args objectForKey:@"searchText"];
    if (searchText) {
        // NOTE: This command may be overkill to simply search for some text,
        // but it is consistent with what is used in MMAppController.
        [self addInput:[NSString stringWithFormat:@"<C-\\><C-N>:if search("
                        "'\\V\\c%@','cW')|let @/='\\V\\c%@'|set hls|endif<CR>",
                        searchText, searchText]];
    }
}

- (int)checkForModifiedBuffers
{
    // Return 1 if current buffer is modified, -1 if other buffer is modified,
    // otherwise return 0.

    if (curbuf && bufIsChanged(curbuf))
        return 1;

    buf_T *buf;
    for (buf = firstbuf; buf != NULL; buf = buf->b_next) {
        if (bufIsChanged(buf)) {
            return -1;
        }
    }

    return 0;
}

- (void)addInput:(NSString *)input
{
    // NOTE: This code is essentially identical to server_to_input_buf(),
    // except the 'silent' flag is TRUE in the call to ins_typebuf() below.
    char_u *string = [input vimStringSave];
    if (!string) return;

    /* Set 'cpoptions' the way we want it.
     *    B set - backslashes are *not* treated specially
     *    k set - keycodes are *not* reverse-engineered
     *    < unset - <Key> sequences *are* interpreted
     *  The last but one parameter of replace_termcodes() is TRUE so that the
     *  <lt> sequence is recognised - needed for a real backslash.
     */
    char_u *ptr = NULL;
    char_u *cpo_save = p_cpo;
    p_cpo = (char_u *)"Bk";
    char_u *str = replace_termcodes((char_u *)string, &ptr, FALSE, TRUE, FALSE);
    p_cpo = cpo_save;

    if (*ptr != NUL)	/* trailing CTRL-V results in nothing */
    {
	/*
	 * Add the string to the input stream.
	 * Can't use add_to_input_buf() here, we now have K_SPECIAL bytes.
	 *
	 * First clear typed characters from the typeahead buffer, there could
	 * be half a mapping there.  Then append to the existing string, so
	 * that multiple commands from a client are concatenated.
	 */
	if (typebuf.tb_maplen < typebuf.tb_len)
	    del_typebuf(typebuf.tb_len - typebuf.tb_maplen, typebuf.tb_maplen);
	(void)ins_typebuf(str, REMAP_NONE, typebuf.tb_len, TRUE, TRUE);

	/* Let input_available() know we inserted text in the typeahead
	 * buffer. */
	typebuf_was_filled = TRUE;
    }
    vim_free(ptr);
    vim_free(string);
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


- (void)handleMarkedText:(NSData *)data
{
    const void *bytes = [data bytes];
    int32_t pos = *((int32_t*)bytes);  bytes += sizeof(int32_t);
    unsigned len = *((unsigned*)bytes);  bytes += sizeof(unsigned);
    char *chars = (char *)bytes;

    ASLogDebug(@"pos=%d len=%d chars=%s", pos, len, chars);

    if (pos < 0) {
        im_preedit_abandon_macvim();
    } else if (len == 0) {
	im_preedit_end_macvim();
    } else {
        if (!preedit_get_status())
            im_preedit_start_macvim();

	im_preedit_changed_macvim(chars, pos);
    }
}

- (void)handleGesture:(NSData *)data
{
    const void *bytes = [data bytes];
    int flags = *((int*)bytes);  bytes += sizeof(int);
    int gesture = *((int*)bytes);  bytes += sizeof(int);
    int modifiers = eventModifierFlagsToVimModMask(flags);
    char_u string[6];

    string[3] = CSI;
    string[4] = KS_EXTRA;
    switch (gesture) {
        case MMGestureSwipeLeft:    string[5] = KE_SWIPELEFT;	break;
        case MMGestureSwipeRight:   string[5] = KE_SWIPERIGHT;	break;
        case MMGestureSwipeUp:	    string[5] = KE_SWIPEUP;	break;
        case MMGestureSwipeDown:    string[5] = KE_SWIPEDOWN;	break;
        default: return;
    }

    if (modifiers == 0) {
        add_to_input_buf(string + 3, 3);
    } else {
        string[0] = CSI;
        string[1] = KS_MODIFIER;
        string[2] = modifiers;
        add_to_input_buf(string, 6);
    }
}

#ifdef FEAT_BEVAL
- (void)bevalCallback:(id)sender
{
    if (!(p_beval && balloonEval))
        return;

    if (balloonEval->msgCB != NULL) {
        // HACK! We have no way of knowing whether the balloon evaluation
        // worked or not, so we keep track of it using a local tool tip
        // variable.  (The reason we need to know is due to how the Cocoa tool
        // tips work: if there is no tool tip we must set it to nil explicitly
        // or it might never go away.)
        [self setLastToolTip:nil];

        (*balloonEval->msgCB)(balloonEval, 0);

        [self queueMessage:SetTooltipMsgID properties:
            [NSDictionary dictionaryWithObject:(lastToolTip ? lastToolTip : @"")
                                        forKey:@"toolTip"]];
        [self flushQueue:YES];
    }
}
#endif

#ifdef MESSAGE_QUEUE
- (void)checkForProcessEvents:(NSTimer *)timer
{
# ifdef FEAT_TIMERS
    did_add_timer = FALSE;
# endif

    parse_queued_messages();

    if (input_available()
# ifdef FEAT_TIMERS
            || did_add_timer
# endif
            )
        CFRunLoopStop(CFRunLoopGetCurrent());
}
#endif

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
            ASLogInfo(@"  trying to connect to alternate server: %@",
                      alternateServerName);
            connName = [self connectionNameFromServerName:alternateServerName];
            svrConn = [NSConnection connectionWithRegisteredName:connName
                                                            host:nil];
        }

        // Try looking for alternate servers...
        if (!svrConn) {
            ASLogInfo(@"  looking for alternate servers...");
            NSString *alt = [self alternateServerNameForName:name];
            if (alt != alternateServerName) {
                ASLogInfo(@"  found alternate server: %@", alt);
                [alternateServerName release];
                alternateServerName = [alt copy];
            }
        }

        // Try alternate server again...
        if (!svrConn && alternateServerName) {
            ASLogInfo(@"  trying to connect to alternate server: %@",
                      alternateServerName);
            connName = [self connectionNameFromServerName:alternateServerName];
            svrConn = [NSConnection connectionWithRegisteredName:connName
                                                            host:nil];
        }

        if (svrConn) {
            [connectionNameDict setObject:svrConn forKey:connName];

            ASLogDebug(@"Adding %@ as connection observer for %@",
                       self, svrConn);
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
    ASLogDebug(@"notification=%@", notification);

    NSConnection *svrConn = [notification object];

    ASLogDebug(@"Removing %@ as connection observer from %@", self, svrConn);
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

    if (modifierFlags & NSEventModifierFlagShift)
        modMask |= MOD_MASK_SHIFT;
    if (modifierFlags & NSEventModifierFlagControl)
        modMask |= MOD_MASK_CTRL;
    if (modifierFlags & NSEventModifierFlagOption)
        modMask |= MOD_MASK_ALT;
    if (modifierFlags & NSEventModifierFlagCommand)
        modMask |= MOD_MASK_CMD;

    return modMask;
}

static int eventModifierFlagsToVimMouseModMask(int modifierFlags)
{
    int modMask = 0;

    if (modifierFlags & NSEventModifierFlagShift)
        modMask |= MOUSE_SHIFT;
    if (modifierFlags & NSEventModifierFlagControl)
        modMask |= MOUSE_CTRL;
    if (modifierFlags & NSEventModifierFlagOption)
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
