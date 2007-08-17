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
#import "vim.h"



static float MMFlushTimeoutInterval = 0.1f;


// TODO: Move to separate file.
static int eventModifierFlagsToVimModMask(int modifierFlags);
static int vimModMaskToEventModifierFlags(int mods);
static int eventModifierFlagsToVimMouseModMask(int modifierFlags);
static int eventButtonNumberToVimMouseButton(int buttonNumber);
static int specialKeyToNSKey(int key);


@interface MMBackend (Private)
- (void)handleMessage:(int)msgid data:(NSData *)data;
+ (NSDictionary *)specialKeys;
- (void)handleKeyDown:(NSString *)key modifiers:(int)mods;
- (void)queueMessage:(int)msgid data:(NSData *)data;
- (void)connectionDidDie:(NSNotification *)notification;
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
        queue = [[NSMutableArray alloc] init];
        drawData = [[NSMutableData alloc] initWithCapacity:1024];
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Colors"
                                                         ofType:@"plist"];
        colorDict = [[NSDictionary dictionaryWithContentsOfFile:path] retain];
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [queue release];
    [drawData release];
    [frontendProxy release];
    [connection release];
    [colorDict release];

    [super dealloc];
}

- (void)setBackgroundColor:(int)color
{
    backgroundColor = color;
}

- (void)setForegroundColor:(int)color
{
    foregroundColor = color;
}

- (void)setDefaultColorsBackground:(int)bg foreground:(int)fg
{
    defaultBackgroundColor = bg;
    defaultForegroundColor = fg;

    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&bg length:sizeof(int)];
    [data appendBytes:&fg length:sizeof(int)];

    [self queueMessage:SetDefaultColorsMsgID data:data];
}

- (BOOL)checkin
{
    NSBundle *mainBundle = [NSBundle mainBundle];

    // NOTE!  If the name of the connection changes here it must also be
    // updated in MMAppController.m.
    NSString *name = [NSString stringWithFormat:@"%@-connection",
             [mainBundle bundleIdentifier]];
    connection = [NSConnection connectionWithRegisteredName:name host:nil];
    if (!connection) {
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

            connection = [NSConnection connectionWithRegisteredName:name
                                                               host:nil];
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
    frontendProxy = [(NSDistantObject*)[proxy connectBackend:self
                                                         pid:pid] retain];
    if (frontendProxy) {
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

    [drawData appendBytes:&defaultBackgroundColor length:sizeof(int)];
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1
                    toRow:(int)row2 column:(int)col2
{
    int type = ClearBlockDrawType;

    [drawData appendBytes:&type length:sizeof(int)];

    [drawData appendBytes:&defaultBackgroundColor length:sizeof(int)];
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

    [drawData appendBytes:&defaultBackgroundColor length:sizeof(int)];
    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&count length:sizeof(int)];
    [drawData appendBytes:&bottom length:sizeof(int)];
    [drawData appendBytes:&left length:sizeof(int)];
    [drawData appendBytes:&right length:sizeof(int)];
}

- (void)replaceString:(char*)s length:(int)len row:(int)row column:(int)col
                flags:(int)flags
{
    int type = ReplaceStringDrawType;

    [drawData appendBytes:&type length:sizeof(int)];

    [drawData appendBytes:&backgroundColor length:sizeof(int)];
    [drawData appendBytes:&foregroundColor length:sizeof(int)];
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

    [drawData appendBytes:&defaultBackgroundColor length:sizeof(int)];
    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&count length:sizeof(int)];
    [drawData appendBytes:&bottom length:sizeof(int)];
    [drawData appendBytes:&left length:sizeof(int)];
    [drawData appendBytes:&right length:sizeof(int)];
}

- (void)flushQueue:(BOOL)force
{
    // NOTE! This method gets called a lot; if we were to flush every time it
    // was called MacVim would feel unresponsive.  So there is a time out which
    // ensures that the queue isn't flushed too often.
    if (!force && lastFlushDate && -[lastFlushDate timeIntervalSinceNow]
            < MMFlushTimeoutInterval)
        return;

    if ([drawData length] > 0) {
        [self queueMessage:BatchDrawMsgID data:[drawData copy]];
        [drawData setLength:0];
    }

    if ([queue count] > 0) {
        // TODO: Come up with a better way to handle the insertion point.
        [self updateInsertionPoint];

        [frontendProxy processCommandQueue:queue];
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
    // By invalidating the NSConnection the MMWindowController immediately
    // finds out that the connection is down and as a result
    // [MMWindowController connectionDidDie:] is invoked.
    //NSLog(@"%@ %s", [self className], _cmd);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [connection invalidate];
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
        int len = strlen((char*)NameBuff);

        // Count the number of windows in the tabpage.
        //win_T *wp = tp->tp_firstwin;
        //int wincount;
        //for (wincount = 0; wp != NULL; wp = wp->w_next, ++wincount);

        //[data appendBytes:&wincount length:sizeof(int)];
        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:NameBuff length:len];
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

- (void)setVimWindowTitle:(char *)title
{
    NSMutableData *data = [NSMutableData data];
    int len = strlen(title);

    [data appendBytes:&len length:sizeof(int)];
    [data appendBytes:title length:len];

    [self queueMessage:SetVimWindowTitleMsgID data:data];
}

- (oneway void)setBrowseForFileString:(in bycopy NSString *)string
{
    // NOTE: This is called by [MMVimController panelDidEnd:::] to indicate
    // that the save/open panel has finished.  If 'string == nil' that means
    // the user pressed cancel.
    browseForFileString = string ? [string copy] : nil;
}

- (char *)browseForFileInDirectory:(char *)dir title:(char *)title
                            saving:(int)saving
{
    //NSLog(@"browseForFileInDirectory:%s title:%s saving:%d", dir, title,
    //        saving);

    NSString *ds = dir
            ? [NSString stringWithCString:dir encoding:NSUTF8StringEncoding]
            : nil;
    NSString *ts = title
            ? [NSString stringWithCString:title encoding:NSUTF8StringEncoding]
            : nil;
    [frontendProxy showSavePanelForDirectory:ds title:ts saving:saving];

    // Wait until a reply is sent from MMVimController.
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate distantFuture]];
    if (!browseForFileString)
        return nil;

    char_u *s = vim_strsave((char_u*)[browseForFileString UTF8String]);
    [browseForFileString release];  browseForFileString = nil;

    return (char *)s;
}

- (oneway void)setAlertReturn:(int)val
{
    alertReturn = val;
}

- (int)presentDialogWithType:(int)type title:(char *)title message:(char *)msg
                     buttons:(char *)btns
{
    int style = NSInformationalAlertStyle;
    if (VIM_WARNING == type) style = NSWarningAlertStyle;
    else if (VIM_ERROR == type) style = NSCriticalAlertStyle;

    NSString *hotkey = [NSString stringWithFormat:@"%c", DLG_HOTKEY_CHAR];
    NSMutableString *btnString = [NSMutableString stringWithUTF8String:btns];
    [btnString replaceOccurrencesOfString:hotkey
                               withString:@""
                                  options:0
                                    range:NSMakeRange(0, [btnString length])];

    NSString *separator = [NSString stringWithFormat:@"%c", DLG_BUTTON_SEP];
    NSArray *buttons = [btnString componentsSeparatedByString:separator];

    NSString *message = [NSString stringWithUTF8String:title];
    NSString *text = [NSString stringWithUTF8String:msg];

    [frontendProxy presentDialogWithStyle:style message:message
                          informativeText:text buttons:buttons];

    // Wait until a reply is sent from MMVimController.
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate distantFuture]];

    int ret = alertReturn;
    alertReturn = 0;

    return ret;
}

- (void)updateInsertionPoint
{
    NSMutableData *data = [NSMutableData data];

    int state = get_shape_idx(FALSE);
    state = (state == SHAPE_IDX_I) || (state == SHAPE_IDX_CI);

    [data appendBytes:&defaultForegroundColor length:sizeof(int)];
    [data appendBytes:&gui.row length:sizeof(int)];
    [data appendBytes:&gui.col length:sizeof(int)];
    [data appendBytes:&state length:sizeof(int)];

    [self queueMessage:UpdateInsertionPointMsgID data:data];
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
    NSMutableData *data = [NSMutableData data];
    int len = strlen(name);
    int row = -1, col = -1;

    if (!mouse && curwin) {
        row = curwin->w_wrow;
        col = curwin->w_wcol;
    }

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
    NSString *fontName;
    float size = 0.0f;
    BOOL parseFailed = NO;

    if (name) {
        fontName = [[[NSString alloc] initWithCString:name
                encoding:NSUTF8StringEncoding] autorelease];
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
    } else {
        fontName = [[NSFont userFixedPitchFontOfSize:0] displayName];
    }

    if (!parseFailed && [fontName length] > 0) {
        if (size < 6 || size > 100) {
            // Font size 0.0 tells NSFont to use the 'user default size'.
            size = 0.0f;
        }

        NSFont *font = [NSFont fontWithName:fontName size:size];
        if (font) {
            //NSLog(@"Setting font '%@' of size %.2f", fontName, size);
            NSMutableData *data = [NSMutableData data];
            int len = [fontName
                    lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

            [data appendBytes:&size length:sizeof(float)];
            [data appendBytes:&len length:sizeof(int)];
            [data appendBytes:[fontName UTF8String] length:len];

            [self queueMessage:SetFontMsgID data:data];
            return YES;
        }
    }

    NSLog(@"WARNING: Cannot set font with name '%@' of size %.2f",
            fontName, size);
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

- (int)lookupColorWithKey:(NSString *)key
{
    if (!(key && [key length] > 0))
        return INVALCOLOR;

    // First of all try to lookup key in the color dictionary; note that all
    // keys in this dictionary are lowercase with no whitespace.

    NSString *stripKey = [[[[key lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
            componentsSeparatedByString:@" "]
               componentsJoinedByString:@""];

    if (stripKey && [stripKey length] > 0) {
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
    }

    NSLog(@"WARNING: No color with key %@ found.", stripKey);
    return INVALCOLOR;
}

- (oneway void)processInput:(int)msgid data:(in NSData *)data
{
    [lastFlushDate release];
    lastFlushDate = [[NSDate date] retain];

    [self handleMessage:msgid data:data];
    inputReceived = YES;
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
        long_u len = 0; char_u *str = 0;
        int type = clip_convert_selection(&str, &len, &clip_star);
        if (type < 0)
            return NO;
        
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

- (BOOL)starRegisterFromPasteboard:(byref NSPasteboard *)pboard
{
    if (curbuf && !curbuf->b_p_ro) {
        return YES;
    }

    return NO;
}

@end // MMBackend



@implementation MMBackend (Private)

- (void)handleMessage:(int)msgid data:(NSData *)data
{
    if (KillTaskMsgID == msgid) {
        //NSLog(@"VimTask received kill message; exiting now.");
        // Set this flag here so that exit does not send TaskExitedMsgID back
        // to MMVimController.
        receivedKillTaskMsg = YES;
        getout(0);
    } else if (InsertTextMsgID == msgid) {
        if (!data) return;
        NSString *key = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
        char_u *chars = (char_u*)[key UTF8String];
        int i, len = [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        for (i = 0; i < len; ++i) {
            add_to_input_buf(chars+i, 1);
            if (CSI == chars[i]) {
                // NOTE: If the converted string contains the byte CSI, then it
                // must be followed by the bytes KS_EXTRA, KE_CSI or things
                // won't work.
                static char_u extra[2] = { KS_EXTRA, KE_CSI };
                add_to_input_buf(extra, 2);
            }
        }

        [key release];
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

        gui_send_mouse_event(button, col, row, 0 != count, flags);
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
    } else if (ScrollbarEventMsgID == msgid) {
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
    } else if (SetFontMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        float pointSize = *((float*)bytes);  bytes += sizeof(float);
        //unsigned len = *((unsigned*)bytes);  bytes += sizeof(unsigned);
        bytes += sizeof(unsigned);  // len not used

        NSMutableString *name = [NSMutableString stringWithUTF8String:bytes];
        [name appendString:[NSString stringWithFormat:@":h%.2f", pointSize]];

        set_option_value((char_u*)"gfn", 0, (char_u*)[name UTF8String], 0);

        // Force screen redraw (does it have to be this complicated?).
	redraw_all_later(CLEAR);
	update_screen(NOT_VALID);
	setcursor();
	out_flush();
	gui_update_cursor(FALSE, FALSE);
	gui_mch_flush();
    } else if (VimShouldCloseMsgID == msgid) {
        gui_shell_closed();
    } else if (DropFilesMsgID == msgid) {
#ifdef FEAT_DND
        const void *bytes = [data bytes];
        int n = *((int*)bytes);  bytes += sizeof(int);

#if 0
        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);

	char_u **fnames = (char_u **)alloc(n * sizeof(char_u *));
        if (fnames) {
            const void *end = [data bytes] + [data length];
            int i = 0;
            while (bytes < end && i < n) {
                int len = *((int*)bytes);  bytes += sizeof(int);
                fnames[i++] = vim_strnsave((char_u*)bytes, len);
                bytes += len;
            }

            // NOTE!  This function will free 'fnames'.
            gui_handle_drop(col, row, 0, fnames, i < n ? i : n);
        }
#else
        // HACK!  I'm not sure how to get Vim to open a list of files in tabs,
        // so instead I create a ':tab drop' command with all the files to open
        // and execute it.
        NSMutableString *cmd = (n > 1)
                ? [NSMutableString stringWithString:@":tab drop"]
                : [NSMutableString stringWithString:@":drop"];

        const void *end = [data bytes] + [data length];
        int i;
        for (i = 0; i < n && bytes < end; ++i) {
            int len = *((int*)bytes);  bytes += sizeof(int);
            NSMutableString *file =
                    [NSMutableString stringWithUTF8String:bytes];
            [file replaceOccurrencesOfString:@" "
                                  withString:@"\\ "
                                     options:0
                                       range:NSMakeRange(0, [file length])];
            bytes += len;

            [cmd appendString:@" "];
            [cmd appendString:file];
        }

        // By going to the last tabpage we ensure that the new tabs will appear
        // last (if this call is left out, the taborder becomes messy).
        goto_tabpage(9999);

        do_cmdline_cmd((char_u*)[cmd UTF8String]);

        // Force screen redraw (does it have to be this complicated?).
        // (This code was taken from the end of gui_handle_drop().)
	update_screen(NOT_VALID);
	setcursor();
	out_flush();
	gui_update_cursor(FALSE, FALSE);
	gui_mch_flush();
#endif
#endif // FEAT_DND
    } else if (DropStringMsgID == msgid) {
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
        dnd_yank_drag_data((char_u*)[string UTF8String], len);
        add_to_input_buf(dropkey, sizeof(dropkey));
#endif // FEAT_DND
    } else if (GotFocusMsgID == msgid) {
        gui_focus_change(YES);
    } else if (LostFocusMsgID == msgid) {
        gui_focus_change(NO);
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

- (void)handleKeyDown:(NSString *)key modifiers:(int)mods
{
    char_u special[3];
    char_u modChars[3];
    char_u *chars = 0;
    int length = 0;

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
    } else if ([key length] > 0) {
        chars = (char_u*)[key UTF8String];
        length = [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        unichar c = [key characterAtIndex:0];

        //NSLog(@"non-special: %@ (hex=%x, mods=%d)", key,
        //        [key characterAtIndex:0], mods);

        // HACK!  In most circumstances the Ctrl and Shift modifiers should be
        // cleared since they are already added to the key by the AppKit.
        // Unfortunately, the only way to deal with when to clear the modifiers
        // or not seems to be to have hard-wired rules like this.
        if ( !((' ' == c) || (0xa0 == c) || (mods & MOD_MASK_CMD)) ) {
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

@end // MMBackend (Private)




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
