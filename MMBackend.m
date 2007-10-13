/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMBackend.h"



// NOTE: Colors in MMBackend are stored as unsigned ints on the form 0xaarrggbb
// whereas colors in Vim are int without the alpha component.  Also note that
// 'transp' is assumed to be a value between 0 and 100.
#define MM_COLOR(col) ((unsigned)( ((col)&0xffffff) | 0xff000000 ))
#define MM_COLOR_WITH_TRANSP(col,transp) \
    ((unsigned)( ((col)&0xffffff) \
        | ((((unsigned)((((100-(transp))*255)/100)+.5f))&0xff)<<24) ))


// This constant controls how often the command queue may be flushed.  If it is
// too small the app might feel unresponsive; if it is too large there might be
// long periods without the screen updating (e.g. when sourcing a large session
// file).  (The unit is seconds.)
static float MMFlushTimeoutInterval = 0.1f;
static int MMFlushQueueLenHint = 80*40;

static unsigned MMServerMax = 1000;

// NOTE: The default font is bundled with the application.
static NSString *MMDefaultFontName = @"DejaVu Sans Mono";
static float MMDefaultFontSize = 12.0f;

// TODO: Move to separate file.
static int eventModifierFlagsToVimModMask(int modifierFlags);
static int vimModMaskToEventModifierFlags(int mods);
static int eventModifierFlagsToVimMouseModMask(int modifierFlags);
static int eventButtonNumberToVimMouseButton(int buttonNumber);
static int specialKeyToNSKey(int key);

enum {
    MMBlinkStateNone = 0,
    MMBlinkStateOn,
    MMBlinkStateOff
};



@interface NSString (MMServerNameCompare)
- (NSComparisonResult)serverNameCompare:(NSString *)string;
@end



@interface MMBackend (Private)
- (void)handleMessage:(int)msgid data:(NSData *)data;
+ (NSDictionary *)specialKeys;
- (void)handleInsertText:(NSData *)data;
- (void)handleKeyDown:(NSString *)key modifiers:(int)mods;
- (void)queueMessage:(int)msgid data:(NSData *)data;
- (void)connectionDidDie:(NSNotification *)notification;
- (void)blinkTimerFired:(NSTimer *)timer;
- (void)focusChange:(BOOL)on;
- (void)processInputBegin;
- (void)processInputEnd;
- (void)handleToggleToolbar;
- (void)handleScrollbarEvent:(NSData *)data;
- (void)handleSetFont:(NSData *)data;
- (void)handleDropFiles:(NSData *)data;
- (void)handleDropString:(NSData *)data;
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
    if ((self = [super init])) {
        fontContainerRef = loadFonts();

        queue = [[NSMutableArray alloc] init];
#if MM_USE_INPUT_QUEUE
        inputQueue = [[NSMutableArray alloc] init];
#endif
        drawData = [[NSMutableData alloc] initWithCapacity:1024];
        connectionNameDict = [[NSMutableDictionary alloc] init];
        clientProxyDict = [[NSMutableDictionary alloc] init];
        serverReplyDict = [[NSMutableDictionary alloc] init];

        NSString *path = [[NSBundle mainBundle] pathForResource:@"Colors"
                                                         ofType:@"plist"];
        if (path) {
            colorDict = [[NSDictionary dictionaryWithContentsOfFile:path]
                retain];
        } else {
            NSLog(@"WARNING: Could not locate Colors.plist.");
        }

        path = [[NSBundle mainBundle] pathForResource:@"SystemColors"
                                               ofType:@"plist"];
        if (path) {
            sysColorDict = [[NSDictionary dictionaryWithContentsOfFile:path]
                retain];
        } else {
            NSLog(@"WARNING: Could not locate SystemColors.plist.");
        }
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [blinkTimer release];  blinkTimer = nil;
#if MM_USE_INPUT_QUEUE
    [inputQueue release];  inputQueue = nil;
#endif
    [alternateServerName release];  alternateServerName = nil;
    [serverReplyDict release];  serverReplyDict = nil;
    [clientProxyDict release];  clientProxyDict = nil;
    [connectionNameDict release];  connectionNameDict = nil;
    [queue release];  queue = nil;
    [drawData release];  drawData = nil;
    [frontendProxy release];  frontendProxy = nil;
    [connection release];  connection = nil;
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
               [[NSBundle mainBundle] bundleIdentifier]];

        connection = [NSConnection connectionWithRegisteredName:name host:nil];
        [connection retain];
    }

    // NOTE: 'connection' may be nil here.
    return connection;
}

- (BOOL)checkin
{
    if (![self connection]) {
        NSBundle *mainBundle = [NSBundle mainBundle];
#if 0
        NSString *path = [mainBundle bundlePath];
        if (![[NSWorkspace sharedWorkspace] launchApplication:path]) {
            NSLog(@"WARNING: Failed to launch GUI with path %@", path);
            return NO;
        }
#else
        // HACK!  It would be preferable to launch the GUI using NSWorkspace,
        // however I have not managed to figure out how to pass arguments using
        // NSWorkspace.
        //
        // NOTE!  Using NSTask to launch the GUI has the negative side-effect
        // that the GUI won't be activated (or raised) so there is a hack in
        // MMWindowController which always raises the app when a new window is
        // opened.
        NSMutableArray *args = [NSMutableArray arrayWithObjects:
            [NSString stringWithFormat:@"-%@", MMNoWindowKey], @"yes", nil];
        NSString *exeName = [[mainBundle infoDictionary]
                objectForKey:@"CFBundleExecutable"];
        NSString *path = [mainBundle pathForAuxiliaryExecutable:exeName];
        if (!path) {
            NSLog(@"ERROR: Could not find MacVim executable in bundle");
            return NO;
        }

        [NSTask launchedTaskWithLaunchPath:path arguments:args];
#endif

        // HACK!  The NSWorkspaceDidLaunchApplicationNotification does not work
        // for tasks like this, so poll the mach bootstrap server until it
        // returns a valid connection.  Also set a time-out date so that we
        // don't get stuck doing this forever.
        NSDate *timeOutDate = [NSDate dateWithTimeIntervalSinceNow:15];
        while (!connection &&
                NSOrderedDescending == [timeOutDate compare:[NSDate date]])
        {
            [[NSRunLoop currentRunLoop]
                    runMode:NSDefaultRunLoopMode
                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];

            // NOTE: This call will set 'connection' as a side-effect.
            [self connection];
        }

        if (!connection) {
            NSLog(@"WARNING: Timed-out waiting for GUI to launch.");
            return NO;
        }
    }

    id proxy = [connection rootProxy];
    [proxy setProtocolForProxy:@protocol(MMAppProtocol)];

    [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(connectionDidDie:)
                name:NSConnectionDidDieNotification object:connection];

    int pid = [[NSProcessInfo processInfo] processIdentifier];

    @try {
        frontendProxy = [proxy connectBackend:self pid:pid];
    }
    @catch (NSException *e) {
        NSLog(@"Exception caught when trying to connect backend: \"%@\"", e);
    }

    if (frontendProxy) {
        [frontendProxy retain];
        [frontendProxy setProtocolForProxy:@protocol(MMAppProtocol)];
    }

    return connection && frontendProxy;
}

- (BOOL)openVimWindow
{
    [self queueMessage:OpenVimWindowMsgID data:nil];
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

- (void)replaceString:(char*)s length:(int)len row:(int)row column:(int)col
                flags:(int)flags
{
    if (len <= 0) return;

    int type = ReplaceStringDrawType;

    [drawData appendBytes:&type length:sizeof(int)];

    [drawData appendBytes:&backgroundColor length:sizeof(unsigned)];
    [drawData appendBytes:&foregroundColor length:sizeof(unsigned)];
    [drawData appendBytes:&specialColor length:sizeof(unsigned)];
    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&col length:sizeof(int)];
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

- (void)flushQueue:(BOOL)force
{
    // NOTE! This method gets called a lot; if we were to flush every time it
    // was called MacVim would feel unresponsive.  So there is a time out which
    // ensures that the queue isn't flushed too often.
    if (!force && lastFlushDate && -[lastFlushDate timeIntervalSinceNow]
            < MMFlushTimeoutInterval
 	    && [drawData length] < MMFlushQueueLenHint)
        return;

    if ([drawData length] > 0) {
        [self queueMessage:BatchDrawMsgID data:[drawData copy]];
        [drawData setLength:0];
    }

    if ([queue count] > 0) {
        @try {
            [frontendProxy processCommandQueue:queue];
        }
        @catch (NSException *e) {
            NSLog(@"Exception caught when processing command queue: \"%@\"", e);
        }

        [queue removeAllObjects];

        [lastFlushDate release];
        lastFlushDate = [[NSDate date] retain];
    }
}

- (BOOL)waitForInput:(int)milliseconds
{
    NSDate *date = milliseconds > 0 ?
            [NSDate dateWithTimeIntervalSinceNow:.001*milliseconds] : 
            [NSDate distantFuture];

    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:date];

    // I know of no way to figure out if the run loop exited because input was
    // found or because of a time out, so I need to manually indicate when
    // input was received in processInput:data: and then reset it every time
    // here.
    BOOL yn = inputReceived;
    inputReceived = NO;

    return yn;
}

- (void)exit
{
#ifdef MAC_CLIENTSERVER
    // The default connection is used for the client/server code.
    [[NSConnection defaultConnection] setRootObject:nil];
    [[NSConnection defaultConnection] invalidate];
#endif

    // By invalidating the NSConnection the MMWindowController immediately
    // finds out that the connection is down and as a result
    // [MMWindowController connectionDidDie:] is invoked.
    //NSLog(@"%@ %s", [self className], _cmd);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [connection invalidate];

    if (fontContainerRef) {
        ATSFontDeactivate(fontContainerRef, NULL, kATSOptionFlagsDefault);
        fontContainerRef = 0;
    }

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

#if MM_ENABLE_CONV
        s = CONVERT_TO_UTF8(s);
#endif

        // Count the number of windows in the tabpage.
        //win_T *wp = tp->tp_firstwin;
        //int wincount;
        //for (wincount = 0; wp != NULL; wp = wp->w_next, ++wincount);

        //[data appendBytes:&wincount length:sizeof(int)];
        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:s length:len];

#if MM_ENABLE_CONV
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

- (char *)browseForFileInDirectory:(char *)dir title:(char *)title
                            saving:(int)saving
{
    //NSLog(@"browseForFileInDirectory:%s title:%s saving:%d", dir, title,
    //        saving);

    char_u *s = NULL;
    NSString *ds = dir ? [NSString stringWithUTF8String:dir] : nil;
    NSString *ts = title ? [NSString stringWithUTF8String:title] : nil;
    @try {
        [frontendProxy showSavePanelForDirectory:ds title:ts saving:saving];

        // Wait until a reply is sent from MMVimController.
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate distantFuture]];

        if (dialogReturn && [dialogReturn isKindOfClass:[NSString class]]) {
            char_u *ret = (char_u*)[dialogReturn UTF8String];
#if MM_ENABLE_CONV
            ret = CONVERT_FROM_UTF8(ret);
#endif
            s = vim_strsave(ret);
#if MM_ENABLE_CONV
            CONVERT_FROM_UTF8_FREE(ret);
#endif
        }

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

    if (obj != dialogReturn) {
        [dialogReturn release];
        dialogReturn = [obj retain];
    }
}

- (int)presentDialogWithType:(int)type title:(char *)title message:(char *)msg
                     buttons:(char *)btns textField:(char *)txtfield
{
    int retval = 0;
    NSString *message = nil, *text = nil, *textFieldString = nil;
    NSArray *buttons = nil;
    int style = NSInformationalAlertStyle;

    if (VIM_WARNING == type) style = NSWarningAlertStyle;
    else if (VIM_ERROR == type) style = NSCriticalAlertStyle;

    if (btns) {
        NSString *btnString = [NSString stringWithUTF8String:btns];
        buttons = [btnString componentsSeparatedByString:@"\n"];
    }
    if (title)
        message = [NSString stringWithUTF8String:title];
    if (msg) {
        text = [NSString stringWithUTF8String:msg];
        if (!message) {
            // HACK! If there is a '\n\n' or '\n' sequence in the message, then
            // make the part up to there into the title.  We only do this
            // because Vim has lots of dialogs without a title and they look
            // ugly that way.
            // TODO: Fix the actual dialog texts.
            NSRange eolRange = [text rangeOfString:@"\n\n"];
            if (NSNotFound == eolRange.location)
                eolRange = [text rangeOfString:@"\n"];
            if (NSNotFound != eolRange.location) {
                message = [text substringToIndex:eolRange.location];
                text = [text substringFromIndex:NSMaxRange(eolRange)];
            }
        }
    }
    if (txtfield)
        textFieldString = [NSString stringWithUTF8String:txtfield];

    @try {
        [frontendProxy presentDialogWithStyle:style message:message
                              informativeText:text buttonTitles:buttons
                              textFieldString:textFieldString];

        // Wait until a reply is sent from MMVimController.
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate distantFuture]];

        if (dialogReturn && [dialogReturn isKindOfClass:[NSArray class]]
                && [dialogReturn count]) {
            retval = [[dialogReturn objectAtIndex:0] intValue];
            if (txtfield && [dialogReturn count] > 1) {
                NSString *retString = [dialogReturn objectAtIndex:1];
                char_u *ret = (char_u*)[retString UTF8String];
#if MM_ENABLE_CONV
                ret = CONVERT_FROM_UTF8(ret);
#endif
                vim_strncpy((char_u*)txtfield, ret, IOSIZE - 1);
#if MM_ENABLE_CONV
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

- (void)addMenuWithTag:(int)tag parent:(int)parentTag name:(char *)name
               atIndex:(int)index
{
    //NSLog(@"addMenuWithTag:%d parent:%d name:%s atIndex:%d", tag, parentTag,
    //        name, index);

    int namelen = name ? strlen(name) : 0;
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&tag length:sizeof(int)];
    [data appendBytes:&parentTag length:sizeof(int)];
    [data appendBytes:&namelen length:sizeof(int)];
    if (namelen > 0) [data appendBytes:name length:namelen];
    [data appendBytes:&index length:sizeof(int)];

    [self queueMessage:AddMenuMsgID data:data];
}

- (void)addMenuItemWithTag:(int)tag parent:(int)parentTag name:(char *)name
                       tip:(char *)tip icon:(char *)icon
             keyEquivalent:(int)key modifiers:(int)mods
                    action:(NSString *)action atIndex:(int)index
{
    //NSLog(@"addMenuItemWithTag:%d parent:%d name:%s tip:%s atIndex:%d", tag,
    //        parentTag, name, tip, index);

    int namelen = name ? strlen(name) : 0;
    int tiplen = tip ? strlen(tip) : 0;
    int iconlen = icon ? strlen(icon) : 0;
    int eventFlags = vimModMaskToEventModifierFlags(mods);
    int actionlen = [action lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *data = [NSMutableData data];

    key = specialKeyToNSKey(key);

    [data appendBytes:&tag length:sizeof(int)];
    [data appendBytes:&parentTag length:sizeof(int)];
    [data appendBytes:&namelen length:sizeof(int)];
    if (namelen > 0) [data appendBytes:name length:namelen];
    [data appendBytes:&tiplen length:sizeof(int)];
    if (tiplen > 0) [data appendBytes:tip length:tiplen];
    [data appendBytes:&iconlen length:sizeof(int)];
    if (iconlen > 0) [data appendBytes:icon length:iconlen];
    [data appendBytes:&actionlen length:sizeof(int)];
    if (actionlen > 0) [data appendBytes:[action UTF8String] length:actionlen];
    [data appendBytes:&index length:sizeof(int)];
    [data appendBytes:&key length:sizeof(int)];
    [data appendBytes:&eventFlags length:sizeof(int)];

    [self queueMessage:AddMenuItemMsgID data:data];
}

- (void)removeMenuItemWithTag:(int)tag
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&tag length:sizeof(int)];

    [self queueMessage:RemoveMenuItemMsgID data:data];
}

- (void)enableMenuItemWithTag:(int)tag state:(int)enabled
{
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&tag length:sizeof(int)];
    [data appendBytes:&enabled length:sizeof(int)];

    [self queueMessage:EnableMenuItemMsgID data:data];
}

- (void)showPopupMenuWithName:(char *)name atMouseLocation:(BOOL)mouse
{
    int len = strlen(name);
    int row = -1, col = -1;

    if (len <= 0) return;

    if (!mouse && curwin) {
        row = curwin->w_wrow;
        col = curwin->w_wcol;
    }

    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&row length:sizeof(int)];
    [data appendBytes:&col length:sizeof(int)];
    [data appendBytes:&len length:sizeof(int)];
    [data appendBytes:name length:len];

    [self queueMessage:ShowPopupMenuMsgID data:data];
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

- (BOOL)setFontWithName:(char *)name
{
    NSString *fontName = MMDefaultFontName;
    float size = MMDefaultFontSize;
    BOOL parseFailed = NO;

    if (name) {
        fontName = [NSString stringWithUTF8String:name];

        if ([fontName isEqual:@"*"]) {
            // :set gfn=* shows the font panel.
            do_cmdline_cmd((char_u*)":action orderFrontFontPanel:");
            return NO;
        }

        NSArray *components = [fontName componentsSeparatedByString:@":"];
        if ([components count] == 2) {
            NSString *sizeString = [components lastObject];
            if ([sizeString length] > 0
                    && [sizeString characterAtIndex:0] == 'h') {
                sizeString = [sizeString substringFromIndex:1];
                if ([sizeString length] > 0) {
                    size = [sizeString floatValue];
                    fontName = [components objectAtIndex:0];
                }
            } else {
                parseFailed = YES;
            }
        } else if ([components count] > 2) {
            parseFailed = YES;
        }
    }

    if (!parseFailed && [fontName length] > 0) {
        if (size < 6 || size > 100) {
            // Font size 0.0 tells NSFont to use the 'user default size'.
            size = 0.0f;
        }

        NSFont *font = [NSFont fontWithName:fontName size:size];

        if (!font && MMDefaultFontName == fontName) {
            // If for some reason the MacVim default font is not in the app
            // bundle, then fall back on the system default font.
            size = 0;
            font = [NSFont userFixedPitchFontOfSize:size];
            fontName = [font displayName];
        }

        if (font) {
            //NSLog(@"Setting font '%@' of size %.2f", fontName, size);
            int len = [fontName
                    lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            if (len > 0) {
                NSMutableData *data = [NSMutableData data];

                [data appendBytes:&size length:sizeof(float)];
                [data appendBytes:&len length:sizeof(int)];
                [data appendBytes:[fontName UTF8String] length:len];

                [self queueMessage:SetFontMsgID data:data];
                return YES;
            }
        }
    }

    //NSLog(@"WARNING: Cannot set font with name '%@' of size %.2f",
    //        fontName, size);
    return NO;
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

    NSLog(@"WARNING: No color with key %@ found.", stripKey);
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

- (void)enterFullscreen
{
    [self queueMessage:EnterFullscreenMsgID data:nil];
}

- (void)leaveFullscreen
{
    [self queueMessage:LeaveFullscreenMsgID data:nil];
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
    // NOTE: This method might get called whenever the run loop is tended to.
    // Thus it might get called whilst input is being processed.  Normally this
    // is not a problem, but if it gets called often then it might become
    // dangerous.  E.g. say a message causes the screen to be redrawn and then
    // another message is received causing another simultaneous screen redraw;
    // this is not good.  To deal with this problem at the moment, we simply
    // drop messages that are received while other input is being processed.
    if (inProcessInput) {
#if MM_USE_INPUT_QUEUE
        [inputQueue addObject:[NSNumber numberWithInt:msgid]];
        [inputQueue addObject:data];
#else
        // Just drop the input
        //NSLog(@"WARNING: Dropping input in %s", _cmd);
#endif
    } else {
        [self processInputBegin];
        [self handleMessage:msgid data:data];
        [self processInputEnd];
    }
}

- (oneway void)processInputAndData:(in bycopy NSArray *)messages
{
    // NOTE: See comment in processInput:data:.
    unsigned i, count = [messages count];
    if (count % 2) {
        NSLog(@"WARNING: [messages count] is odd in %s", _cmd);
        return;
    }

    if (inProcessInput) {
#if MM_USE_INPUT_QUEUE
        [inputQueue addObjectsFromArray:messages];
#else
        // Just drop the input
        //NSLog(@"WARNING: Dropping input in %s", _cmd);
#endif
    } else {
        [self processInputBegin];

        for (i = 0; i < count; i += 2) {
            int msgid = [[messages objectAtIndex:i] intValue];
            id data = [messages objectAtIndex:i+1];
            if ([data isEqual:[NSNull null]])
                data = nil;

            [self handleMessage:msgid data:data];
        }

        [self processInputEnd];
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

- (BOOL)starRegisterToPasteboard:(byref NSPasteboard *)pboard
{
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
#if MM_ENABLE_CONV
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

    char_u *s = (char_u*)[input UTF8String];

#if MM_ENABLE_CONV
    s = CONVERT_FROM_UTF8(s);
#endif

    server_to_input_buf(s);

#if MM_ENABLE_CONV
    CONVERT_FROM_UTF8_FREE(s);
#endif

    [self addClient:(id)client];

    inputReceived = YES;
}

- (NSString *)evaluateExpression:(in bycopy NSString *)expr
                 client:(in byref id <MMVimClientProtocol>)client
{
    //NSLog(@"evaluateExpression:%@ client:%@", expr, (id)client);

    NSString *eval = nil;
    char_u *s = (char_u*)[expr UTF8String];

#if MM_ENABLE_CONV
    s = CONVERT_FROM_UTF8(s);
#endif

    char_u *res = eval_client_expr_to_string(s);

#if MM_ENABLE_CONV
    CONVERT_FROM_UTF8_FREE(s);
#endif

    if (res != NULL) {
        s = res;
#if MM_ENABLE_CONV
        s = CONVERT_TO_UTF8(s);
#endif
        eval = [NSString stringWithUTF8String:(char*)s];
#if MM_ENABLE_CONV
        CONVERT_TO_UTF8_FREE(s);
#endif
        vim_free(res);
    }

    [self addClient:(id)client];

    return eval;
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

            char_u *s = (char_u*)[svrName UTF8String];
#if MM_ENABLE_CONV
            s = CONVERT_FROM_UTF8(s);
#endif
            // NOTE: 'serverName' is a global variable
            serverName = vim_strsave(s);
#if MM_ENABLE_CONV
            CONVERT_FROM_UTF8_FREE(s);
#endif
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
#if MM_ENABLE_CONV
            s = CONVERT_FROM_UTF8(s);
#endif
	    EMSG2(_(e_noserver), s);
#if MM_ENABLE_CONV
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
                    char_u *r = (char_u*)[eval UTF8String];
#if MM_ENABLE_CONV
                    r = CONVERT_FROM_UTF8(r);
#endif
                    *reply = vim_strsave(r);
#if MM_ENABLE_CONV
                    CONVERT_FROM_UTF8_FREE(r);
#endif
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

@end // MMBackend



@implementation MMBackend (Private)

- (void)handleMessage:(int)msgid data:(NSData *)data
{
    if (InsertTextMsgID == msgid) {
        [self handleInsertText:data];
    } else if (KeyDownMsgID == msgid || CmdKeyMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int mods = *((int*)bytes);  bytes += sizeof(int);
        int len = *((int*)bytes);  bytes += sizeof(int);
        NSString *key = [[NSString alloc] initWithBytes:bytes length:len
                                              encoding:NSUTF8StringEncoding];
        mods = eventModifierFlagsToVimModMask(mods);

        [self handleKeyDown:key modifiers:mods];

        [key release];
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
        flags = eventModifierFlagsToVimMouseModMask(flags);

        gui_send_mouse_event(button, col, row, count>1, flags);
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
    } else if (SetTextDimensionsMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);  bytes += sizeof(int);

        // NOTE! Vim doesn't call gui_mch_set_shellsize() after
        // gui_resize_shell(), so we have to manually set the rows and columns
        // here.  (MacVim doesn't change the rows and columns to avoid
        // inconsistent states between Vim and MacVim.)
        [self setRows:rows columns:cols];

        //NSLog(@"[VimTask] Resizing shell to %dx%d.", cols, rows);
        gui_resize_shell(cols, rows);
    } else if (ExecuteMenuMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int tag = *((int*)bytes);  bytes += sizeof(int);

        vimmenu_T *menu = (vimmenu_T*)tag;
        // TODO!  Make sure 'menu' is a valid menu pointer!
        if (menu) {
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
    } else if (MouseMovedMsgID == msgid) {
        const void *bytes = [data bytes];
        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);

        gui_mouse_moved(col, row);
    } else if (SetMouseShapeMsgID == msgid) {
        const void *bytes = [data bytes];
        int shape = *((int*)bytes);  bytes += sizeof(int);
        update_mouseshape(shape);
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

- (void)handleInsertText:(NSData *)data
{
    if (!data) return;

    NSString *key = [[NSString alloc] initWithData:data
                                          encoding:NSUTF8StringEncoding];
    char_u *str = (char_u*)[key UTF8String];
    int i, len = [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

#if MM_ENABLE_CONV
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

#if MM_ENABLE_CONV
    if (conv_str)
        vim_free(conv_str);
#endif
    [key release];
}

- (void)handleKeyDown:(NSString *)key modifiers:(int)mods
{
    char_u special[3];
    char_u modChars[3];
    char_u *chars = (char_u*)[key UTF8String];
#if MM_ENABLE_CONV
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
            if (enc_utf8) {
                // Convert to utf-8
                special[0] = (mtab >> 6) + 0xc0;
                special[1] = mtab & 0xbf;
                length = 2;
            } else {
                special[0] = mtab;
                length = 1;
            }
            mods &= ~MOD_MASK_ALT;
        }
    } else if (length > 0) {
        unichar c = [key characterAtIndex:0];

        //NSLog(@"non-special: %@ (hex=%x, mods=%d)", key,
        //        [key characterAtIndex:0], mods);

        if (length == 1 && ((c == Ctrl_C && ctrl_c_interrupts)
                || (c == intr_char && intr_char != Ctrl_C))) {
            trash_input_buf();
            got_int = TRUE;
        }

        // HACK!  In most circumstances the Ctrl and Shift modifiers should be
        // cleared since they are already added to the key by the AppKit.
        // Unfortunately, the only way to deal with when to clear the modifiers
        // or not seems to be to have hard-wired rules like this.
        if ( !((' ' == c) || (0xa0 == c) || (mods & MOD_MASK_CMD)
                    || 0x9 == c || 0xd == c) ) {
            mods &= ~MOD_MASK_SHIFT;
            mods &= ~MOD_MASK_CTRL;
            //NSLog(@"clear shift ctrl");
        }

        // HACK!  All Option+key presses go via 'insert text' messages, except
        // for <M-Space>.  If the Alt flag is not cleared for <M-Space> it does
        // not work to map to it.
        if (0xa0 == c && !(mods & MOD_MASK_CMD)) {
            //NSLog(@"clear alt");
            mods &= ~MOD_MASK_ALT;
        }

#if MM_ENABLE_CONV
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

#if MM_ENABLE_CONV
    if (conv_str)
        vim_free(conv_str);
#endif
}

- (void)queueMessage:(int)msgid data:(NSData *)data
{
    [queue addObject:[NSData dataWithBytes:&msgid length:sizeof(int)]];
    if (data)
        [queue addObject:data];
    else
        [queue addObject:[NSData data]];
}

- (void)connectionDidDie:(NSNotification *)notification
{
    // If the main connection to MacVim is lost this means that MacVim was
    // either quit (by the user chosing Quit on the MacVim menu), or it has
    // crashed.  In either case our only option is to quit now.
    // TODO: Write backup file?

    //NSLog(@"A Vim process lots its connection to MacVim; quitting.");
    getout(0);
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

- (void)processInputBegin
{
    inProcessInput = YES;

    // Don't flush too soon or update speed will suffer.
    [lastFlushDate release];
    lastFlushDate = [[NSDate date] retain];
}

- (void)processInputEnd
{
#if MM_USE_INPUT_QUEUE
    int count = [inputQueue count];
    if (count % 2) {
        // TODO: This is troubling, but it is not hard to get Vim to end up
        // here.  Why does this happen?
        NSLog(@"WARNING: inputQueue has odd number of objects (%d)", count);
        [inputQueue removeAllObjects];
    } else if (count > 0) {
        // TODO: Dispatch these messages?  Maybe not; usually when the
        // 'inputQueue' is non-empty it means that a LOT of messages has been
        // sent simultaneously.  The only way this happens is when Vim is being
        // tormented, e.g. if the user holds down <D-`> to rapidly switch
        // windows.
        unsigned i;
        for (i = 0; i < count; i+=2) {
            int msgid = [[inputQueue objectAtIndex:i] intValue];
            NSLog(@"%s: Dropping message %s", _cmd, MessageStrings[msgid]);
        }

        [inputQueue removeAllObjects];
    }
#endif

    inputReceived = YES;
    inProcessInput = NO;
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

    // Force screen redraw (does it have to be this complicated?).
    redraw_all_later(CLEAR);
    update_screen(NOT_VALID);
    setcursor();
    out_flush();
    gui_update_cursor(FALSE, FALSE);
    gui_mch_flush();
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

#if MM_ENABLE_CONV
    s = CONVERT_FROM_UTF8(s);
#endif

    set_option_value((char_u*)"guifont", 0, s, 0);

#if MM_ENABLE_CONV
    CONVERT_FROM_UTF8_FREE(s);
#endif

    // Force screen redraw (does it have to be this complicated?).
    redraw_all_later(CLEAR);
    update_screen(NOT_VALID);
    setcursor();
    out_flush();
    gui_update_cursor(FALSE, FALSE);
    gui_mch_flush();
}

- (void)handleDropFiles:(NSData *)data
{
    if (!data) return;

#ifdef FEAT_DND
    const void *bytes = [data bytes];
    const void *end = [data bytes] + [data length];
    int n = *((int*)bytes);  bytes += sizeof(int);

    if (State & CMDLINE) {
        // HACK!  If Vim is in command line mode then the files names
        // should be added to the command line, instead of opening the
        // files in tabs.  This is taken care of by gui_handle_drop().
        char_u **fnames = (char_u **)alloc(n * sizeof(char_u *));
        if (fnames) {
            int i = 0;
            while (bytes < end && i < n) {
                int len = *((int*)bytes);  bytes += sizeof(int);
                char_u *s = (char_u*)bytes;
#if MM_ENABLE_CONV
                s = CONVERT_FROM_UTF8(s);
#endif
                fnames[i++] = vim_strsave(s);
#if MM_ENABLE_CONV
                CONVERT_FROM_UTF8_FREE(s);
#endif
                bytes += len;
            }

            // NOTE!  This function will free 'fnames'.
            // HACK!  It is assumed that the 'x' and 'y' arguments are
            // unused when in command line mode.
            gui_handle_drop(0, 0, 0, fnames, i < n ? i : n);
        }
    } else {
        // HACK!  I'm not sure how to get Vim to open a list of files in
        // tabs, so instead I create a ':tab drop' command with all the
        // files to open and execute it.
        NSMutableString *cmd = (n > 1)
                ? [NSMutableString stringWithString:@":tab drop"]
                : [NSMutableString stringWithString:@":drop"];

        int i;
        for (i = 0; i < n && bytes < end; ++i) {
            int len = *((int*)bytes);  bytes += sizeof(int);
            NSString *file = [NSString stringWithUTF8String:bytes];
            file = [file stringByEscapingSpecialFilenameCharacters];
            bytes += len;

            [cmd appendString:@" "];
            [cmd appendString:file];
        }

        // By going to the last tabpage we ensure that the new tabs will
        // appear last (if this call is left out, the taborder becomes
        // messy).
        goto_tabpage(9999);

        char_u *s = (char_u*)[cmd UTF8String];
#if MM_ENABLE_CONV
        s = CONVERT_FROM_UTF8(s);
#endif
        do_cmdline_cmd(s);
#if MM_ENABLE_CONV
        CONVERT_FROM_UTF8_FREE(s);
#endif

        // Force screen redraw (does it have to be this complicated?).
        // (This code was taken from the end of gui_handle_drop().)
        update_screen(NOT_VALID);
        setcursor();
        out_flush();
        gui_update_cursor(FALSE, FALSE);
        gui_mch_flush();
    }
#endif // FEAT_DND
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
#if MM_ENABLE_CONV
    if (input_conv.vc_type != CONV_NONE)
        s = string_convert(&input_conv, s, &len);
#endif
    dnd_yank_drag_data(s, len);
#if MM_ENABLE_CONV
    if (input_conv.vc_type != CONV_NONE)
        vim_free(s);
#endif
    add_to_input_buf(dropkey, sizeof(dropkey));
#endif // FEAT_DND
}

@end // MMBackend (Private)




@implementation MMBackend (ClientServer)

- (NSString *)connectionNameFromServerName:(NSString *)name
{
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];

    return [[NSString stringWithFormat:@"%@.%@", bundleIdentifier, name]
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

static int vimModMaskToEventModifierFlags(int mods)
{
    int flags = 0;

    if (mods & MOD_MASK_SHIFT)
        flags |= NSShiftKeyMask;
    if (mods & MOD_MASK_CTRL)
        flags |= NSControlKeyMask;
    if (mods & MOD_MASK_ALT)
        flags |= NSAlternateKeyMask;
    if (mods & MOD_MASK_CMD)
        flags |= NSCommandKeyMask;

    return flags;
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
    static int mouseButton[] = { MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE,
            MOUSE_X1, MOUSE_X2 };

    return mouseButton[buttonNumber < 5 ? buttonNumber : 0];
}

static int specialKeyToNSKey(int key)
{
    if (!IS_SPECIAL(key))
        return key;

    static struct {
        int special;
        int nskey;
    } sp2ns[] = {
        { K_UP, NSUpArrowFunctionKey },
        { K_DOWN, NSDownArrowFunctionKey },
        { K_LEFT, NSLeftArrowFunctionKey },
        { K_RIGHT, NSRightArrowFunctionKey },
        { K_F1, NSF1FunctionKey },
        { K_F2, NSF2FunctionKey },
        { K_F3, NSF3FunctionKey },
        { K_F4, NSF4FunctionKey },
        { K_F5, NSF5FunctionKey },
        { K_F6, NSF6FunctionKey },
        { K_F7, NSF7FunctionKey },
        { K_F8, NSF8FunctionKey },
        { K_F9, NSF9FunctionKey },
        { K_F10, NSF10FunctionKey },
        { K_F11, NSF11FunctionKey },
        { K_F12, NSF12FunctionKey },
        { K_F13, NSF13FunctionKey },
        { K_F14, NSF14FunctionKey },
        { K_F15, NSF15FunctionKey },
        { K_F16, NSF16FunctionKey },
        { K_F17, NSF17FunctionKey },
        { K_F18, NSF18FunctionKey },
        { K_F19, NSF19FunctionKey },
        { K_F20, NSF20FunctionKey },
        { K_F21, NSF21FunctionKey },
        { K_F22, NSF22FunctionKey },
        { K_F23, NSF23FunctionKey },
        { K_F24, NSF24FunctionKey },
        { K_F25, NSF25FunctionKey },
        { K_F26, NSF26FunctionKey },
        { K_F27, NSF27FunctionKey },
        { K_F28, NSF28FunctionKey },
        { K_F29, NSF29FunctionKey },
        { K_F30, NSF30FunctionKey },
        { K_F31, NSF31FunctionKey },
        { K_F32, NSF32FunctionKey },
        { K_F33, NSF33FunctionKey },
        { K_F34, NSF34FunctionKey },
        { K_F35, NSF35FunctionKey },
        { K_DEL, NSBackspaceCharacter },
        { K_BS, NSDeleteCharacter },
        { K_HOME, NSHomeFunctionKey },
        { K_END, NSEndFunctionKey },
        { K_PAGEUP, NSPageUpFunctionKey },
        { K_PAGEDOWN, NSPageDownFunctionKey }
    };

    int i;
    for (i = 0; i < sizeof(sp2ns)/sizeof(sp2ns[0]); ++i) {
        if (sp2ns[i].special == key)
            return sp2ns[i].nskey;
    }

    return 0;
}
