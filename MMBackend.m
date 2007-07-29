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



// TODO: Move to separate file.
static int eventModifierFlagsToVimModMask(int modifierFlags);
static int eventModifierFlagsToVimMouseModMask(int modifierFlags);
static int eventButtonNumberToVimMouseButton(int buttonNumber);


@interface MMBackend (Private)
- (void)handleMessage:(int)msgid data:(NSData *)data;
+ (NSDictionary *)specialKeys;
- (void)handleKeyDown:(NSString *)key modifiers:(int)mods;
- (void)queueMessage:(int)msgid data:(NSData *)data;
#if MM_USE_DO
- (void)connectionDidDie:(NSNotification *)notification;
#endif
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [queue release];
    [drawData release];
#if MM_USE_DO
    [frontendProxy release];
    [connection release];
#else
    [sendPort release];
    [receivePort release];
#endif
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
#if MM_USE_DO
    // NOTE!  If the name of the connection changes here it must also be
    // updated in MMAppController.m.
    NSString *name = [NSString stringWithFormat:@"%@-connection",
             [[NSBundle mainBundle] bundleIdentifier]];
    connection = [NSConnection connectionWithRegisteredName:name host:nil];
    if (!connection)
#else
    // NOTE!  If the name of the port changes here it must also be updated in
    // MMAppController.m.
    NSString *portName = [NSString stringWithFormat:@"%@-taskport",
             [[NSBundle mainBundle] bundleIdentifier]];

    NSPort *port = [[[NSMachBootstrapServer sharedInstance]
            portForName:portName host:nil] retain];
    if (!port)
#endif
    {
#if 0
        NSString *path = [[NSBundle mainBundle] bundlePath];
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
        NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-nowindow",
                       @"yes", nil];
        NSString *path = [[NSBundle mainBundle]
                pathForAuxiliaryExecutable:@"MacVim"];
        [NSTask launchedTaskWithLaunchPath:path arguments:args];
#endif

        // HACK!  The NSWorkspaceDidLaunchApplicationNotification does not work
        // for tasks like this, so poll the mach bootstrap server until it
        // returns a valid port.  Also set a time-out date so that we don't get
        // stuck doing this forever.
        NSDate *timeOutDate = [NSDate dateWithTimeIntervalSinceNow:15];
        while (
#if MM_USE_DO
                !connection
#else
                !port
#endif
                && NSOrderedDescending == [timeOutDate compare:[NSDate date]])
        {
            [[NSRunLoop currentRunLoop]
                    runMode:NSDefaultRunLoopMode
                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
#if MM_USE_DO
            connection = [NSConnection connectionWithRegisteredName:name
                                                               host:nil];
#else
            port = [[NSMachBootstrapServer sharedInstance]
                    portForName:portName];
#endif
        }

#if MM_USE_DO
        if (!connection)
#else
        if (!port)
#endif
        {
            NSLog(@"WARNING: Timed-out waiting for GUI to launch.");
            return NO;
        }
    }

#if MM_USE_DO
    id proxy = [connection rootProxy];
    [proxy setProtocolForProxy:@protocol(MMAppProtocol)];

    [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(connectionDidDie:)
                name:NSConnectionDidDieNotification object:connection];

    frontendProxy = [(NSDistantObject*)[proxy connectBackend:self] retain];
    if (frontendProxy) {
        [frontendProxy setProtocolForProxy:@protocol(MMAppProtocol)];
    }

    return connection && frontendProxy;
#else
    receivePort = [NSMachPort new];
    [receivePort setDelegate:self];

    [[NSRunLoop currentRunLoop] addPort:receivePort
                                forMode:NSDefaultRunLoopMode];

    [NSPortMessage sendMessage:CheckinMsgID withSendPort:port
                   receivePort:receivePort wait:YES];

    return YES;
#endif
}

- (BOOL)openVimWindowWithRows:(int)rows columns:(int)cols
{
#if !MM_USE_DO
    if (!sendPort) {
#if 0
        // TODO: Wait until connected---maybe time out at some point?
        // Note that if we return 'NO' Vim will be started in terminal mode
        // (i.e.  output goes to stdout).
        NSLog(@"WARNING: Trying to open VimWindow but sendPort==nil;"
               " waiting for connected message.");

        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate distantFuture]];
        if (!sendPort)
            return NO;
#else
        // Wait until the sendPort has actually been set.
        //
        // TODO: Come up with a more elegant solution to this problem---this
        // message should not be called before the sendPort has been
        // initialized.
        while (!sendPort) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate distantFuture]];
        }
#endif
    }
#endif // !MM_USE_DO

    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&rows length:sizeof(int)];
    [data appendBytes:&cols length:sizeof(int)];

    [self queueMessage:OpenVimWindowMsgID data:data];

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
    [drawData appendBytes:&Rows length:sizeof(int)];
    [drawData appendBytes:&Columns length:sizeof(int)];

    [drawData appendBytes:&defaultBackgroundColor length:sizeof(int)];
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1
                    toRow:(int)row2 column:(int)col2
{
    int type = ClearBlockDrawType;

    [drawData appendBytes:&type length:sizeof(int)];
    [drawData appendBytes:&Rows length:sizeof(int)];
    [drawData appendBytes:&Columns length:sizeof(int)];

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
    [drawData appendBytes:&Rows length:sizeof(int)];
    [drawData appendBytes:&Columns length:sizeof(int)];

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
    [drawData appendBytes:&Rows length:sizeof(int)];
    [drawData appendBytes:&Columns length:sizeof(int)];

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
    [drawData appendBytes:&Rows length:sizeof(int)];
    [drawData appendBytes:&Columns length:sizeof(int)];

    [drawData appendBytes:&defaultBackgroundColor length:sizeof(int)];
    [drawData appendBytes:&row length:sizeof(int)];
    [drawData appendBytes:&count length:sizeof(int)];
    [drawData appendBytes:&bottom length:sizeof(int)];
    [drawData appendBytes:&left length:sizeof(int)];
    [drawData appendBytes:&right length:sizeof(int)];
}

- (void)flush
{
    if ([drawData length] > 0) {
        [self queueMessage:BatchDrawMsgID data:[drawData copy]];
        [drawData setLength:0];
    }
}

- (void)flushQueue
{
    [self flush];

    if ([drawData length] > 0 || [queue count] > 0) {
        // TODO: Come up with a better way to handle the insertion point.
        [self updateInsertionPoint];

#if MM_USE_DO
        [frontendProxy processCommandQueue:queue];
#else
        [NSPortMessage sendMessage:FlushQueueMsgID withSendPort:sendPort
                              components:queue wait:YES];
#endif
        [queue removeAllObjects];
    }
}

- (BOOL)waitForInput:(int)milliseconds
{
#if !MM_USE_DO
    if (![receivePort isValid]) {
        // This should only happen if the GUI crashes.
        NSLog(@"ERROR: The receive port is no longer valid, quitting...");
        getout(0);
    }
#endif

    NSDate *date = milliseconds > 0 ?
            [NSDate dateWithTimeIntervalSinceNow:.001*milliseconds] : 
            [NSDate distantFuture];

    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:date];

    // I know of no way to figure out if the run loop exited because input was
    // found or because of a time out, so I need to manually indicate when
    // input was received in handlePortMessage and then reset it every time
    // here.
    BOOL yn = inputReceived;
    inputReceived = NO;

    return yn;
}

- (void)exit
{
#if MM_USE_DO
    // By invalidating the NSConnection the MMWindowController immediately
    // finds out that the connection is down and as a result
    // [MMWindowController connectionDidDie:] is invoked.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [connection invalidate];
#else
    if (!receivedKillTaskMsg) {
        [NSPortMessage sendMessage:TaskExitedMsgID withSendPort:sendPort
                       receivePort:receivePort wait:YES];
    }
#endif
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

- (char *)browseForFileInDirectory:(char *)dir title:(char *)title
                            saving:(int)saving
{
#if MM_USE_DO
    return nil;
#else
    //NSLog(@"browseForFileInDirectory:%s title:%s saving:%d", dir, title,
    //        saving);

    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&saving length:sizeof(int)];

    int len = dir ? strlen(dir) : 0;
    [data appendBytes:&len length:sizeof(int)];
    if (len > 0)
        [data appendBytes:dir length:len];

    len = title ? strlen(title) : 0;
    [data appendBytes:&len length:sizeof(int)];
    if (len > 0)
        [data appendBytes:title length:len];

    if (![NSPortMessage sendMessage:BrowseForFileMsgID withSendPort:sendPort
                                 data:data wait:YES])
        return nil;

    // Wait until a reply is sent from MMVimController.
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate distantFuture]];

    // Something went wrong if replyData is nil.
    if (!replyData)
        return nil;

    const void *bytes = [replyData bytes];
    int ok = *((int*)bytes);  bytes += sizeof(int);
    len = *((int*)bytes);  bytes += sizeof(int);

    char_u *s = NULL;
    if (ok && len > 0) {
        NSString *name = [[NSString alloc] initWithBytes:(void*)bytes
                length:len encoding:NSUTF8StringEncoding];
        s = vim_strsave((char_u*)[name UTF8String]);
    }

    [replyData release];  replyData = nil;
    return (char*)s;
#endif // MM_USE_DO
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
                       tip:(char *)tip icon:(char *)icon atIndex:(int)index
{
    //NSLog(@"addMenuItemWithTag:%d parent:%d name:%s tip:%s atIndex:%d", tag,
    //        parentTag, name, tip, index);

    int namelen = name ? strlen(name) : 0;
    int tiplen = tip ? strlen(tip) : 0;
    int iconlen = icon ? strlen(icon) : 0;
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&tag length:sizeof(int)];
    [data appendBytes:&parentTag length:sizeof(int)];
    [data appendBytes:&namelen length:sizeof(int)];
    if (namelen > 0) [data appendBytes:name length:namelen];
    [data appendBytes:&tiplen length:sizeof(int)];
    if (tiplen > 0) [data appendBytes:tip length:tiplen];
    [data appendBytes:&iconlen length:sizeof(int)];
    if (iconlen > 0) [data appendBytes:icon length:iconlen];
    [data appendBytes:&index length:sizeof(int)];

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

#if MM_USE_DO
- (oneway void)processInput:(int)msgid data:(in NSData *)data
{
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

#else // MM_USE_DO

- (void)handlePortMessage:(NSPortMessage *)portMessage
{
    unsigned msgid = [portMessage msgid];

    if (ConnectedMsgID == msgid) {
        sendPort = [[portMessage sendPort] retain];
        //NSLog(@"VimTask connected to MMVimController.");
    } else if (TaskShouldTerminateMsgID == msgid) {
        int reply = TerminateReplyYesMsgID;
        buf_T *buf;
        for (buf = firstbuf; buf != NULL; buf = buf->b_next) {
            if (bufIsChanged(buf)) {
                reply = TerminateReplyNoMsgID;
                break;
            }
        }

        //NSLog(@"TaskShouldTerminateMsgID = %s",
        //        reply == TerminateReplyYesMsgID ? "YES" : "NO");

        [NSPortMessage sendMessage:reply withSendPort:[portMessage sendPort]
                              wait:YES];
    } else {
        NSArray *components = [portMessage components];
        NSData *data = [components count] > 0 ?
                [components objectAtIndex:0] : nil;
        [self handleMessage:msgid data:data];
    }
}
#endif // MM_USE_DO

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
        //NSLog(@"insert text: %@  (hex=%x)", key, [key characterAtIndex:0]);
        add_to_input_buf((char_u*)[key UTF8String],
                [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
        [key release];

        inputReceived = YES;
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
        inputReceived = YES;
    } else if (SelectTabMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int idx = *((int*)bytes) + 1;
        //NSLog(@"Selecting tab %d", idx);
        send_tabline_event(idx);
        inputReceived = YES;
    } else if (CloseTabMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int idx = *((int*)bytes) + 1;
        //NSLog(@"Closing tab %d", idx);
        send_tabline_menu_event(idx, TABLINE_MENU_CLOSE);
        inputReceived = YES;
    } else if (AddNewTabMsgID == msgid) {
        //NSLog(@"Adding new tab");
        send_tabline_menu_event(0, TABLINE_MENU_NEW);
        inputReceived = YES;
    } else if (DraggedTabMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        // NOTE! The destination index is 0 based, so do not add 1 to make it 1
        // based.
        int idx = *((int*)bytes);

#if 0
        tabpage_T *tp = find_tabpage(oldIdx);
        if (tp) {
            // HACK!  tabpage_move(idx) moves 'curtab' to 'idx', but since it
            // is also possible to drag tabs which are not selected we must
            // first set 'curtab' to the tab that was actually dragged and then
            // reset 'curtab' to what it used to be.
            tabpage_T *oldcur = curtab;
            curtab = tp;
            tabpage_move(idx);
            curtab = oldcur;
        }
#else
        tabpage_move(idx);
#endif
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
        inputReceived = YES;
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

        inputReceived = YES;
    } else if (MouseUpMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];

        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);  bytes += sizeof(int);

        flags = eventModifierFlagsToVimMouseModMask(flags);

        gui_send_mouse_event(MOUSE_RELEASE, col, row, NO, flags);
        inputReceived = YES;
    } else if (MouseDraggedMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];

        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);  bytes += sizeof(int);

        flags = eventModifierFlagsToVimMouseModMask(flags);

        gui_send_mouse_event(MOUSE_DRAG, col, row, NO, flags);
        inputReceived = YES;
    } 
#if !MM_USE_DO
    else if (BrowseForFileReplyMsgID == msgid) {
        if (!data) return;
        [replyData release];
        replyData = [data copy];
    }
#endif
    else if (SetTextDimensionsMsgID == msgid) {
        if (!data) return;
        const void *bytes = [data bytes];
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);  bytes += sizeof(int);

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
            inputReceived = YES;
        }
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

            inputReceived = YES;
        }
    } else if (VimShouldCloseMsgID == msgid) {
        gui_shell_closed();
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

#if MM_USE_DO
- (void)connectionDidDie:(NSNotification *)notification
{
    // If the main connection to MacVim is lost this means that MacVim was
    // either quit (by the user chosing Quit on the MacVim menu), or it has
    // crashed.  In either case our only option is to quit now.
    // TODO: Write backup file?

    //NSLog(@"A Vim process lots its connection to MacVim; quitting.");
    getout(0);
}
#endif // MM_USE_DO

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
