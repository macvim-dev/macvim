/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMVimController.h"
#import "MMWindowController.h"
#import "MMTextView.h"
#import "MMAppController.h"
#import "MMTextStorage.h"


// This is taken from gui.h
#define DRAW_CURSOR 0x20

static NSString *MMDefaultToolbarImageName = @"Attention";
static int MMAlertTextFieldHeight = 22;

// NOTE: By default a message sent to the backend will be dropped if it cannot
// be delivered instantly; otherwise there is a possibility that MacVim will
// 'beachball' while waiting to deliver DO messages to an unresponsive Vim
// process.  This means that you cannot rely on any message sent with
// sendMessage: to actually reach Vim.
static NSTimeInterval MMBackendProxyRequestTimeout = 0;

#if MM_RESEND_LAST_FAILURE
// If a message send fails, the message will be resent after this many seconds
// have passed.  (No queue is kept, only the very last message is resent.)
static NSTimeInterval MMResendInterval = 0.5;
#endif


@interface MMAlert : NSAlert {
    NSTextField *textField;
}
- (void)setTextFieldString:(NSString *)textFieldString;
- (NSTextField *)textField;
@end


@interface MMVimController (Private)
- (void)handleMessage:(int)msgid data:(NSData *)data;
- (void)performBatchDrawWithData:(NSData *)data;
- (void)savePanelDidEnd:(NSSavePanel *)panel code:(int)code
                context:(void *)context;
- (void)alertDidEnd:(MMAlert *)alert code:(int)code context:(void *)context;
- (NSMenuItem *)menuItemForTag:(int)tag;
- (NSMenu *)menuForTag:(int)tag;
- (NSMenu *)topLevelMenuForTitle:(NSString *)title;
- (void)addMenuWithTag:(int)tag parent:(int)parentTag title:(NSString *)title
               atIndex:(int)idx;
- (void)addMenuItemWithTag:(int)tag parent:(NSMenu *)parent
                     title:(NSString *)title tip:(NSString *)tip
             keyEquivalent:(int)key modifiers:(int)mask
                    action:(NSString *)action atIndex:(int)idx;
- (void)updateMainMenu;
- (NSToolbarItem *)toolbarItemForTag:(int)tag index:(int *)index;
- (void)addToolbarItemToDictionaryWithTag:(int)tag label:(NSString *)title
        toolTip:(NSString *)tip icon:(NSString *)icon;
- (void)addToolbarItemWithTag:(int)tag label:(NSString *)label
                          tip:(NSString *)tip icon:(NSString *)icon
                      atIndex:(int)idx;
- (void)connectionDidDie:(NSNotification *)notification;
#if MM_RESEND_LAST_FAILURE
- (void)resendTimerFired:(NSTimer *)timer;
#endif
@end



// TODO: Move to separate file
@interface NSColor (MMProtocol)
+ (NSColor *)colorWithRgbInt:(unsigned)rgb;
+ (NSColor *)colorWithArgbInt:(unsigned)argb;
@end



static NSMenuItem *findMenuItemWithTagInMenu(NSMenu *root, int tag)
{
    if (root) {
        NSMenuItem *item = [root itemWithTag:tag];
        if (item) return item;

        NSArray *items = [root itemArray];
        unsigned i, count = [items count];
        for (i = 0; i < count; ++i) {
            item = [items objectAtIndex:i];
            if ([item hasSubmenu]) {
                item = findMenuItemWithTagInMenu([item submenu], tag);
                if (item) return item;
            }
        }
    }

    return nil;
}



@implementation MMVimController

- (id)initWithBackend:(id)backend pid:(int)processIdentifier
{
    if ((self = [super init])) {
        windowController =
            [[MMWindowController alloc] initWithVimController:self];
        backendProxy = [backend retain];
        sendQueue = [NSMutableArray new];
        mainMenuItems = [[NSMutableArray alloc] init];
        popupMenuItems = [[NSMutableArray alloc] init];
        toolbarItemDict = [[NSMutableDictionary alloc] init];
        pid = processIdentifier;

        NSConnection *connection = [backendProxy connectionForProxy];

        // TODO: Check that this will not set the timeout for the root proxy
        // (in MMAppController).
        [connection setRequestTimeout:MMBackendProxyRequestTimeout];

        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(connectionDidDie:)
                    name:NSConnectionDidDieNotification object:connection];


        NSWindow *win = [windowController window];

        [[NSNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(windowDidBecomeMain:)
                       name:NSWindowDidBecomeMainNotification
                     object:win];

        isInitialized = YES;
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);
    isInitialized = NO;

#if MM_RESEND_LAST_FAILURE
    [resendData release];  resendData = nil;
#endif

    [serverName release];  serverName = nil;
    [backendProxy release];  backendProxy = nil;
    [sendQueue release];  sendQueue = nil;

    [toolbarItemDict release];  toolbarItemDict = nil;
    [toolbar release];  toolbar = nil;
    [popupMenuItems release];  popupMenuItems = nil;
    [mainMenuItems release];  mainMenuItems = nil;
    [windowController release];  windowController = nil;

    [super dealloc];
}

- (MMWindowController *)windowController
{
    return windowController;
}

- (void)setServerName:(NSString *)name
{
    if (name != serverName) {
        [serverName release];
        serverName = [name copy];
    }
}

- (NSString *)serverName
{
    return serverName;
}

- (int)pid
{
    return pid;
}

- (void)dropFiles:(NSArray *)filenames
{
    int i, numberOfFiles = [filenames count];
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&numberOfFiles length:sizeof(int)];

    for (i = 0; i < numberOfFiles; ++i) {
        NSString *file = [filenames objectAtIndex:i];
        int len = [file lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (len > 0) {
            ++len;  // append NUL as well
            [data appendBytes:&len length:sizeof(int)];
            [data appendBytes:[file UTF8String] length:len];
        }
    }

    [self sendMessage:DropFilesMsgID data:data];
}

- (void)dropString:(NSString *)string
{
    int len = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
    if (len > 0) {
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:[string UTF8String] length:len];

        [self sendMessage:DropStringMsgID data:data];
    }
}

- (void)sendMessage:(int)msgid data:(NSData *)data
{
    //NSLog(@"sendMessage:%s (isInitialized=%d inProcessCommandQueue=%d)",
    //        MessageStrings[msgid], isInitialized, inProcessCommandQueue);

    if (!isInitialized) return;

    if (inProcessCommandQueue) {
        //NSLog(@"In process command queue; delaying message send.");
        [sendQueue addObject:[NSNumber numberWithInt:msgid]];
        if (data)
            [sendQueue addObject:data];
        else
            [sendQueue addObject:[NSNull null]];
        return;
    }

#if MM_RESEND_LAST_FAILURE
    if (resendTimer) {
        //NSLog(@"cancelling scheduled resend of %s",
        //        MessageStrings[resendMsgid]);

        [resendTimer invalidate];
        [resendTimer release];
        resendTimer = nil;
    }

    if (resendData) {
        [resendData release];
        resendData = nil;
    }
#endif

    @try {
        [backendProxy processInput:msgid data:data];
    }
    @catch (NSException *e) {
        //NSLog(@"%@ %s Exception caught during DO call: %@",
        //        [self className], _cmd, e);
#if MM_RESEND_LAST_FAILURE
        //NSLog(@"%s failed, scheduling message %s for resend", _cmd,
        //        MessageStrings[msgid]);

        resendMsgid = msgid;
        resendData = [data retain];
        resendTimer = [NSTimer
            scheduledTimerWithTimeInterval:MMResendInterval
                                    target:self
                                  selector:@selector(resendTimerFired:)
                                  userInfo:nil
                                   repeats:NO];
        [resendTimer retain];
#endif
    }
}

- (BOOL)sendMessageNow:(int)msgid data:(NSData *)data
               timeout:(NSTimeInterval)timeout
{
    if (!isInitialized || inProcessCommandQueue)
        return NO;

    if (timeout < 0) timeout = 0;

    BOOL sendOk = YES;
    NSConnection *conn = [backendProxy connectionForProxy];
    NSTimeInterval oldTimeout = [conn requestTimeout];

    [conn setRequestTimeout:timeout];

    @try {
        [backendProxy processInput:msgid data:data];
    }
    @catch (NSException *e) {
        sendOk = NO;
    }
    @finally {
        [conn setRequestTimeout:oldTimeout];
    }

    return sendOk;
}

- (id)backendProxy
{
    return backendProxy;
}

- (void)cleanup
{
    //NSLog(@"%@ %s", [self className], _cmd);
    if (!isInitialized) return;

    isInitialized = NO;
    [toolbar setDelegate:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [windowController cleanup];
}

- (oneway void)showSavePanelForDirectory:(in bycopy NSString *)dir
                                   title:(in bycopy NSString *)title
                                  saving:(int)saving
{
    if (!isInitialized) return;

    if (saving) {
        [[NSSavePanel savePanel] beginSheetForDirectory:dir file:nil
                modalForWindow:[windowController window]
                 modalDelegate:self
                didEndSelector:@selector(savePanelDidEnd:code:context:)
                   contextInfo:NULL];
    } else {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setAllowsMultipleSelection:NO];
        [panel beginSheetForDirectory:dir file:nil types:nil
                modalForWindow:[windowController window]
                 modalDelegate:self
                didEndSelector:@selector(savePanelDidEnd:code:context:)
                   contextInfo:NULL];
    }
}

- (oneway void)presentDialogWithStyle:(int)style
                              message:(in bycopy NSString *)message
                      informativeText:(in bycopy NSString *)text
                         buttonTitles:(in bycopy NSArray *)buttonTitles
                      textFieldString:(in bycopy NSString *)textFieldString
{
    if (!(windowController && buttonTitles && [buttonTitles count])) return;

    MMAlert *alert = [[MMAlert alloc] init];

    // NOTE! This has to be done before setting the informative text.
    if (textFieldString)
        [alert setTextFieldString:textFieldString];

    [alert setAlertStyle:style];

    if (message) {
        [alert setMessageText:message];
    } else {
        // If no message text is specified 'Alert' is used, which we don't
        // want, so set an empty string as message text.
        [alert setMessageText:@""];
    }

    if (text) {
        [alert setInformativeText:text];
    } else if (textFieldString) {
        // Make sure there is always room for the input text field.
        [alert setInformativeText:@""];
    }

    unsigned i, count = [buttonTitles count];
    for (i = 0; i < count; ++i) {
        NSString *title = [buttonTitles objectAtIndex:i];
        // NOTE: The title of the button may contain the character '&' to
        // indicate that the following letter should be the key equivalent
        // associated with the button.  Extract this letter and lowercase it.
        NSString *keyEquivalent = nil;
        NSRange hotkeyRange = [title rangeOfString:@"&"];
        if (NSNotFound != hotkeyRange.location) {
            if ([title length] > NSMaxRange(hotkeyRange)) {
                NSRange keyEquivRange = NSMakeRange(hotkeyRange.location+1, 1);
                keyEquivalent = [[title substringWithRange:keyEquivRange]
                    lowercaseString];
            }

            NSMutableString *string = [NSMutableString stringWithString:title];
            [string deleteCharactersInRange:hotkeyRange];
            title = string;
        }

        [alert addButtonWithTitle:title];

        // Set key equivalent for the button, but only if NSAlert hasn't
        // already done so.  (Check the documentation for
        // - [NSAlert addButtonWithTitle:] to see what key equivalents are
        // automatically assigned.)
        NSButton *btn = [[alert buttons] lastObject];
        if ([[btn keyEquivalent] length] == 0 && keyEquivalent) {
            [btn setKeyEquivalent:keyEquivalent];
        }
    }

    [alert beginSheetModalForWindow:[windowController window]
                      modalDelegate:self
                     didEndSelector:@selector(alertDidEnd:code:context:)
                        contextInfo:NULL];

    [alert release];
}

- (oneway void)processCommandQueue:(in NSArray *)queue
{
    if (!isInitialized) return;

    unsigned i, count = [queue count];
    if (count % 2) {
        NSLog(@"WARNING: Uneven number of components (%d) in flush queue "
                "message; ignoring this message.", count);
        return;
    }

    inProcessCommandQueue = YES;

    //NSLog(@"======== %s BEGIN ========", _cmd);
    for (i = 0; i < count; i += 2) {
        NSData *value = [queue objectAtIndex:i];
        NSData *data = [queue objectAtIndex:i+1];

        int msgid = *((int*)[value bytes]);
#if 0
        if (msgid != EnableMenuItemMsgID && msgid != AddMenuItemMsgID
                && msgid != AddMenuMsgID) {
            NSLog(@"%s%s", _cmd, MessageStrings[msgid]);
        }
#endif

        [self handleMessage:msgid data:data];
    }
    //NSLog(@"======== %s  END  ========", _cmd);

    if (shouldUpdateMainMenu) {
        [self updateMainMenu];
    }

    [windowController processCommandQueueDidFinish];

    inProcessCommandQueue = NO;

    if ([sendQueue count] > 0) {
        @try {
            [backendProxy processInputAndData:sendQueue];
        }
        @catch (NSException *e) {
            // Connection timed out, just ignore this.
            //NSLog(@"WARNING! Connection timed out in %s", _cmd);
        }

        [sendQueue removeAllObjects];
    }
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    if (isInitialized)
        [self updateMainMenu];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)theToolbar
    itemForItemIdentifier:(NSString *)itemId
    willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item = [toolbarItemDict objectForKey:itemId];
    if (!item) {
        NSLog(@"WARNING:  No toolbar item with id '%@'", itemId);
    }

    return item;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)theToolbar
{
    return nil;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)theToolbar
{
    return nil;
}

@end // MMVimController



@implementation MMVimController (Private)

- (void)handleMessage:(int)msgid data:(NSData *)data
{
    //NSLog(@"%@ %s", [self className], _cmd);

    if (OpenVimWindowMsgID == msgid) {
        [windowController openWindow];
    } else if (BatchDrawMsgID == msgid) {
        [self performBatchDrawWithData:data];
    } else if (SelectTabMsgID == msgid) {
#if 0   // NOTE: Tab selection is done inside updateTabsWithData:.
        const void *bytes = [data bytes];
        int idx = *((int*)bytes);
        //NSLog(@"Selecting tab with index %d", idx);
        [windowController selectTabWithIndex:idx];
#endif
    } else if (UpdateTabBarMsgID == msgid) {
        [windowController updateTabsWithData:data];
    } else if (ShowTabBarMsgID == msgid) {
        [windowController showTabBar:YES];
    } else if (HideTabBarMsgID == msgid) {
        [windowController showTabBar:NO];
    } else if (SetTextDimensionsMsgID == msgid) {
        const void *bytes = [data bytes];
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);  bytes += sizeof(int);

        [windowController setTextDimensionsWithRows:rows columns:cols];
    } else if (SetWindowTitleMsgID == msgid) {
        const void *bytes = [data bytes];
        int len = *((int*)bytes);  bytes += sizeof(int);

        NSString *string = [[NSString alloc] initWithBytes:(void*)bytes
                length:len encoding:NSUTF8StringEncoding];

        [[windowController window] setTitle:string];

        [string release];
    } else if (AddMenuMsgID == msgid) {
        NSString *title = nil;
        const void *bytes = [data bytes];
        int tag = *((int*)bytes);  bytes += sizeof(int);
        int parentTag = *((int*)bytes);  bytes += sizeof(int);
        int len = *((int*)bytes);  bytes += sizeof(int);
        if (len > 0) {
            title = [[NSString alloc] initWithBytes:(void*)bytes length:len
                                           encoding:NSUTF8StringEncoding];
            bytes += len;
        }
        int idx = *((int*)bytes);  bytes += sizeof(int);

        if (MenuToolbarType == parentTag) {
            if (!toolbar) {
                // NOTE! Each toolbar must have a unique identifier, else each
                // window will have the same toolbar.
                NSString *ident = [NSString stringWithFormat:@"%d.%d",
                         (int)self, tag];
                toolbar = [[NSToolbar alloc] initWithIdentifier:ident];

                [toolbar setShowsBaselineSeparator:NO];
                [toolbar setDelegate:self];
                [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
                [toolbar setSizeMode:NSToolbarSizeModeSmall];

                NSWindow *win = [windowController window];
                [win setToolbar:toolbar];

                // HACK! Redirect the pill button so that we can ask Vim to
                // hide the toolbar.
                NSButton *pillButton = [win
                    standardWindowButton:NSWindowToolbarButton];
                if (pillButton) {
                    [pillButton setAction:@selector(toggleToolbar:)];
                    [pillButton setTarget:windowController];
                }
            }
        } else if (title) {
            [self addMenuWithTag:tag parent:parentTag title:title atIndex:idx];
        }

        [title release];
    } else if (AddMenuItemMsgID == msgid) {
        NSString *title = nil, *tip = nil, *icon = nil, *action = nil;
        const void *bytes = [data bytes];
        int tag = *((int*)bytes);  bytes += sizeof(int);
        int parentTag = *((int*)bytes);  bytes += sizeof(int);
        int namelen = *((int*)bytes);  bytes += sizeof(int);
        if (namelen > 0) {
            title = [[NSString alloc] initWithBytes:(void*)bytes length:namelen
                                           encoding:NSUTF8StringEncoding];
            bytes += namelen;
        }
        int tiplen = *((int*)bytes);  bytes += sizeof(int);
        if (tiplen > 0) {
            tip = [[NSString alloc] initWithBytes:(void*)bytes length:tiplen
                                           encoding:NSUTF8StringEncoding];
            bytes += tiplen;
        }
        int iconlen = *((int*)bytes);  bytes += sizeof(int);
        if (iconlen > 0) {
            icon = [[NSString alloc] initWithBytes:(void*)bytes length:iconlen
                                           encoding:NSUTF8StringEncoding];
            bytes += iconlen;
        }
        int actionlen = *((int*)bytes);  bytes += sizeof(int);
        if (actionlen > 0) {
            action = [[NSString alloc] initWithBytes:(void*)bytes
                                              length:actionlen
                                            encoding:NSUTF8StringEncoding];
            bytes += actionlen;
        }
        int idx = *((int*)bytes);  bytes += sizeof(int);
        if (idx < 0) idx = 0;
        int key = *((int*)bytes);  bytes += sizeof(int);
        int mask = *((int*)bytes);  bytes += sizeof(int);

        NSString *ident = [NSString stringWithFormat:@"%d.%d",
                (int)self, parentTag];
        if (toolbar && [[toolbar identifier] isEqual:ident]) {
            [self addToolbarItemWithTag:tag label:title tip:tip icon:icon
                                atIndex:idx];
        } else {
            NSMenu *parent = [self menuForTag:parentTag];
            [self addMenuItemWithTag:tag parent:parent title:title tip:tip
                       keyEquivalent:key modifiers:mask action:action
                             atIndex:idx];
        }

        [title release];
        [tip release];
        [icon release];
        [action release];
    } else if (RemoveMenuItemMsgID == msgid) {
        const void *bytes = [data bytes];
        int tag = *((int*)bytes);  bytes += sizeof(int);

        id item;
        int idx;
        if ((item = [self toolbarItemForTag:tag index:&idx])) {
            [toolbar removeItemAtIndex:idx];
        } else if ((item = [self menuItemForTag:tag])) {
            [item retain];

            if ([item menu] == [NSApp mainMenu] || ![item menu]) {
                // NOTE: To be on the safe side we try to remove the item from
                // both arrays (it is ok to call removeObject: even if an array
                // does not contain the object to remove).
                [mainMenuItems removeObject:item];
                [popupMenuItems removeObject:item];
            }

            if ([item menu])
                [[item menu] removeItem:item];

            [item release];
        }
    } else if (EnableMenuItemMsgID == msgid) {
        const void *bytes = [data bytes];
        int tag = *((int*)bytes);  bytes += sizeof(int);
        int state = *((int*)bytes);  bytes += sizeof(int);

        id item = [self toolbarItemForTag:tag index:NULL];
        if (!item)
            item = [self menuItemForTag:tag];

        [item setEnabled:state];
    } else if (ShowToolbarMsgID == msgid) {
        const void *bytes = [data bytes];
        int enable = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);  bytes += sizeof(int);

        int mode = NSToolbarDisplayModeDefault;
        if (flags & ToolbarLabelFlag) {
            mode = flags & ToolbarIconFlag ? NSToolbarDisplayModeIconAndLabel
                    : NSToolbarDisplayModeLabelOnly;
        } else if (flags & ToolbarIconFlag) {
            mode = NSToolbarDisplayModeIconOnly;
        }

        int size = flags & ToolbarSizeRegularFlag ? NSToolbarSizeModeRegular
                : NSToolbarSizeModeSmall;

        [windowController showToolbar:enable size:size mode:mode];
    } else if (CreateScrollbarMsgID == msgid) {
        const void *bytes = [data bytes];
        long ident = *((long*)bytes);  bytes += sizeof(long);
        int type = *((int*)bytes);  bytes += sizeof(int);

        [windowController createScrollbarWithIdentifier:ident type:type];
    } else if (DestroyScrollbarMsgID == msgid) {
        const void *bytes = [data bytes];
        long ident = *((long*)bytes);  bytes += sizeof(long);

        [windowController destroyScrollbarWithIdentifier:ident];
    } else if (ShowScrollbarMsgID == msgid) {
        const void *bytes = [data bytes];
        long ident = *((long*)bytes);  bytes += sizeof(long);
        int visible = *((int*)bytes);  bytes += sizeof(int);

        [windowController showScrollbarWithIdentifier:ident state:visible];
    } else if (SetScrollbarPositionMsgID == msgid) {
        const void *bytes = [data bytes];
        long ident = *((long*)bytes);  bytes += sizeof(long);
        int pos = *((int*)bytes);  bytes += sizeof(int);
        int len = *((int*)bytes);  bytes += sizeof(int);

        [windowController setScrollbarPosition:pos length:len
                                    identifier:ident];
    } else if (SetScrollbarThumbMsgID == msgid) {
        const void *bytes = [data bytes];
        long ident = *((long*)bytes);  bytes += sizeof(long);
        float val = *((float*)bytes);  bytes += sizeof(float);
        float prop = *((float*)bytes);  bytes += sizeof(float);

        [windowController setScrollbarThumbValue:val proportion:prop
                                      identifier:ident];
    } else if (SetFontMsgID == msgid) {
        const void *bytes = [data bytes];
        float size = *((float*)bytes);  bytes += sizeof(float);
        int len = *((int*)bytes);  bytes += sizeof(int);
        NSString *name = [[NSString alloc]
                initWithBytes:(void*)bytes length:len
                     encoding:NSUTF8StringEncoding];
        NSFont *font = [NSFont fontWithName:name size:size];

        if (font)
            [windowController setFont:font];

        [name release];
    } else if (SetDefaultColorsMsgID == msgid) {
        const void *bytes = [data bytes];
        unsigned bg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
        unsigned fg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
        NSColor *back = [NSColor colorWithArgbInt:bg];
        NSColor *fore = [NSColor colorWithRgbInt:fg];

        [windowController setDefaultColorsBackground:back foreground:fore];
    } else if (ExecuteActionMsgID == msgid) {
        const void *bytes = [data bytes];
        int len = *((int*)bytes);  bytes += sizeof(int);
        NSString *actionName = [[NSString alloc]
                initWithBytesNoCopy:(void*)bytes
                             length:len
                           encoding:NSUTF8StringEncoding
                       freeWhenDone:NO];

        SEL sel = NSSelectorFromString(actionName);
        [NSApp sendAction:sel to:nil from:self];

        [actionName release];
    } else if (ShowPopupMenuMsgID == msgid) {
        const void *bytes = [data bytes];
        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int len = *((int*)bytes);  bytes += sizeof(int);
        NSString *title = [[NSString alloc]
                initWithBytesNoCopy:(void*)bytes
                             length:len
                           encoding:NSUTF8StringEncoding
                       freeWhenDone:NO];

        NSMenu *menu = [self topLevelMenuForTitle:title];
        if (menu) {
            [windowController popupMenu:menu atRow:row column:col];
        } else {
            NSLog(@"WARNING: Cannot popup menu with title %@; no such menu.",
                    title);
        }

        [title release];
    } else if (SetMouseShapeMsgID == msgid) {
        const void *bytes = [data bytes];
        int shape = *((int*)bytes);  bytes += sizeof(int);

        [windowController setMouseShape:shape];
    } else if (AdjustLinespaceMsgID == msgid) {
        const void *bytes = [data bytes];
        int linespace = *((int*)bytes);  bytes += sizeof(int);

        [windowController adjustLinespace:linespace];
    } else if (ActivateMsgID == msgid) {
        [NSApp activateIgnoringOtherApps:YES];
        [[windowController window] makeKeyAndOrderFront:self];
    } else if (SetServerNameMsgID == msgid) {
        NSString *name = [[NSString alloc] initWithData:data
                                               encoding:NSUTF8StringEncoding];
        [self setServerName:name];
        [name release];
    } else {
        NSLog(@"WARNING: Unknown message received (msgid=%d)", msgid);
    }
}


#define MM_DEBUG_DRAWING 0

- (void)performBatchDrawWithData:(NSData *)data
{
    // TODO!  Move to window controller.
    MMTextStorage *textStorage = [windowController textStorage];
    MMTextView *textView = [windowController textView];
    if (!(textStorage && textView))
        return;

    const void *bytes = [data bytes];
    const void *end = bytes + [data length];

#if MM_DEBUG_DRAWING
    NSLog(@"====> BEGIN %s", _cmd);
#endif
    [textStorage beginEditing];

    // TODO: Sanity check input

    while (bytes < end) {
        int type = *((int*)bytes);  bytes += sizeof(int);

        if (ClearAllDrawType == type) {
#if MM_DEBUG_DRAWING
            NSLog(@"   Clear all");
#endif
            [textStorage clearAll];
        } else if (ClearBlockDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row1 = *((int*)bytes);  bytes += sizeof(int);
            int col1 = *((int*)bytes);  bytes += sizeof(int);
            int row2 = *((int*)bytes);  bytes += sizeof(int);
            int col2 = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            NSLog(@"   Clear block (%d,%d) -> (%d,%d)", row1, col1,
                    row2,col2);
#endif
            [textStorage clearBlockFromRow:row1 column:col1
                    toRow:row2 column:col2
                    color:[NSColor colorWithArgbInt:color]];
        } else if (DeleteLinesDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            NSLog(@"   Delete %d line(s) from %d", count, row);
#endif
            [textStorage deleteLinesFromRow:row lineCount:count
                    scrollBottom:bot left:left right:right
                           color:[NSColor colorWithArgbInt:color]];
        } else if (ReplaceStringDrawType == type) {
            int bg = *((int*)bytes);  bytes += sizeof(int);
            int fg = *((int*)bytes);  bytes += sizeof(int);
            int sp = *((int*)bytes);  bytes += sizeof(int);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int flags = *((int*)bytes);  bytes += sizeof(int);
            int len = *((int*)bytes);  bytes += sizeof(int);
            NSString *string = [[NSString alloc]
                    initWithBytesNoCopy:(void*)bytes
                                 length:len
                               encoding:NSUTF8StringEncoding
                           freeWhenDone:NO];
            bytes += len;

#if MM_DEBUG_DRAWING
            NSLog(@"   Draw string at (%d,%d) length=%d flags=%d fg=0x%x "
                    "bg=0x%x sp=0x%x (%@)", row, col, len, flags, fg, bg, sp,
                    len > 0 ? [string substringToIndex:1] : @"");
#endif
            // NOTE: If this is a call to draw the (block) cursor, then cancel
            // any previous request to draw the insertion point, or it might
            // get drawn as well.
            if (flags & DRAW_CURSOR) {
                [textView setShouldDrawInsertionPoint:NO];
                //[textView drawInsertionPointAtRow:row column:col
                //                            shape:MMInsertionPointBlock
                //                            color:[NSColor colorWithRgbInt:bg]];
            }
            [textStorage replaceString:string
                                 atRow:row column:col
                             withFlags:flags
                       foregroundColor:[NSColor colorWithRgbInt:fg]
                       backgroundColor:[NSColor colorWithArgbInt:bg]
                          specialColor:[NSColor colorWithRgbInt:sp]];

            [string release];
        } else if (InsertLinesDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            NSLog(@"   Insert %d line(s) at row %d", count, row);
#endif
            [textStorage insertLinesAtRow:row lineCount:count
                             scrollBottom:bot left:left right:right
                                    color:[NSColor colorWithArgbInt:color]];
        } else if (DrawCursorDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int shape = *((int*)bytes);  bytes += sizeof(int);
            int percent = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            NSLog(@"   Draw cursor at (%d,%d)", row, col);
#endif
            [textView drawInsertionPointAtRow:row column:col shape:shape
                                     fraction:percent
                                        color:[NSColor colorWithRgbInt:color]];
        } else {
            NSLog(@"WARNING: Unknown draw type (type=%d)", type);
        }
    }

    [textStorage endEditing];
#if MM_DEBUG_DRAWING
    NSLog(@"<==== END   %s", _cmd);
#endif
}

- (void)savePanelDidEnd:(NSSavePanel *)panel code:(int)code
                context:(void *)context
{
    NSString *string = (code == NSOKButton) ? [panel filename] : nil;
    @try {
        [backendProxy setDialogReturn:string];
    }
    @catch (NSException *e) {
        NSLog(@"Exception caught in %s %@", _cmd, e);
    }
}

- (void)alertDidEnd:(MMAlert *)alert code:(int)code context:(void *)context
{
    NSArray *ret = nil;

    code = code - NSAlertFirstButtonReturn + 1;

    if ([alert isKindOfClass:[MMAlert class]] && [alert textField]) {
        ret = [NSArray arrayWithObjects:[NSNumber numberWithInt:code],
            [[alert textField] stringValue], nil];
    } else {
        ret = [NSArray arrayWithObject:[NSNumber numberWithInt:code]];
    }

    @try {
        [backendProxy setDialogReturn:ret];
    }
    @catch (NSException *e) {
        NSLog(@"Exception caught in %s %@", _cmd, e);
    }
}

- (NSMenuItem *)menuItemForTag:(int)tag
{
    // Search the main menu.
    int i, count = [mainMenuItems count];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [mainMenuItems objectAtIndex:i];
        if ([item tag] == tag) return item;
        item = findMenuItemWithTagInMenu([item submenu], tag);
        if (item) return item;
    }

    // Search the popup menus.
    count = [popupMenuItems count];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [popupMenuItems objectAtIndex:i];
        if ([item tag] == tag) return item;
        item = findMenuItemWithTagInMenu([item submenu], tag);
        if (item) return item;
    }

    return nil;
}

- (NSMenu *)menuForTag:(int)tag
{
    return [[self menuItemForTag:tag] submenu];
}

- (NSMenu *)topLevelMenuForTitle:(NSString *)title
{
    // Search only the top-level menus.

    unsigned i, count = [popupMenuItems count];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [popupMenuItems objectAtIndex:i];
        if ([title isEqual:[item title]])
            return [item submenu];
    }

    count = [mainMenuItems count];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [mainMenuItems objectAtIndex:i];
        if ([title isEqual:[item title]])
            return [item submenu];
    }

    return nil;
}

- (void)addMenuWithTag:(int)tag parent:(int)parentTag title:(NSString *)title
               atIndex:(int)idx
{
    NSMenu *parent = [self menuForTag:parentTag];
    NSMenuItem *item = [[NSMenuItem alloc] init];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];

    [menu setAutoenablesItems:NO];
    [item setTag:tag];
    [item setTitle:title];
    [item setSubmenu:menu];

    if (parent) {
        if ([parent numberOfItems] <= idx) {
            [parent addItem:item];
        } else {
            [parent insertItem:item atIndex:idx];
        }
    } else {
        NSMutableArray *items = (MenuPopupType == parentTag)
            ? popupMenuItems : mainMenuItems;
        if ([items count] <= idx) {
            [items addObject:item];
        } else {
            [items insertObject:item atIndex:idx];
        }

        shouldUpdateMainMenu = (MenuPopupType != parentTag);
    }

    [item release];
    [menu release];
}

- (void)addMenuItemWithTag:(int)tag parent:(NSMenu *)parent
                     title:(NSString *)title tip:(NSString *)tip
             keyEquivalent:(int)key modifiers:(int)mask
                    action:(NSString *)action atIndex:(int)idx
{
    if (parent) {
        NSMenuItem *item = nil;
        if (!title || ([title hasPrefix:@"-"] && [title hasSuffix:@"-"])) {
            item = [NSMenuItem separatorItem];
        } else {
            item = [[[NSMenuItem alloc] init] autorelease];
            [item setTitle:title];
            // TODO: Check that 'action' is a valid action (nothing will happen
            // if it isn't, but it would be nice with a warning).
            if (action) [item setAction:NSSelectorFromString(action)];
            else        [item setAction:@selector(vimMenuItemAction:)];
            if (tip) [item setToolTip:tip];

            if (key != 0) {
                NSString *keyString =
                    [NSString stringWithFormat:@"%C", key];
                [item setKeyEquivalent:keyString];
                [item setKeyEquivalentModifierMask:mask];
            }
        }

        // NOTE!  The tag is used to idenfity which menu items were
        // added by Vim (tag != 0) and which were added by the AppKit
        // (tag == 0).
        [item setTag:tag];

        if ([parent numberOfItems] <= idx) {
            [parent addItem:item];
        } else {
            [parent insertItem:item atIndex:idx];
        }
    } else {
        NSLog(@"WARNING: Menu item '%@' (tag=%d) has no parent.", title, tag);
    }
}

- (void)updateMainMenu
{
    NSMenu *mainMenu = [NSApp mainMenu];

    // Stop NSApp from updating the Window menu.
    [NSApp setWindowsMenu:nil];

    // Remove all menus from main menu (except the MacVim menu).
    int i, count = [mainMenu numberOfItems];
    for (i = count-1; i > 0; --i) {
        [mainMenu removeItemAtIndex:i];
    }

    // Add menus from 'mainMenuItems' to main menu.
    count = [mainMenuItems count];
    for (i = 0; i < count; ++i) {
        [mainMenu addItem:[mainMenuItems objectAtIndex:i]];
    }

    // Set the new Window menu.
    // TODO!  Need to look for 'Window' in all localized languages.
    NSMenu *windowMenu = [[mainMenu itemWithTitle:@"Window"] submenu];
    if (windowMenu) {
        // Remove all AppKit owned menu items (tag == 0); they will be added
        // again when setWindowsMenu: is called.
        count = [windowMenu numberOfItems];
        for (i = count-1; i >= 0; --i) {
            NSMenuItem *item = [windowMenu itemAtIndex:i];
            if (![item tag]) {
                [windowMenu removeItem:item];
            }
        }

        [NSApp setWindowsMenu:windowMenu];
    }

    shouldUpdateMainMenu = NO;
}

- (NSToolbarItem *)toolbarItemForTag:(int)tag index:(int *)index
{
    if (!toolbar) return nil;

    NSArray *items = [toolbar items];
    int i, count = [items count];
    for (i = 0; i < count; ++i) {
        NSToolbarItem *item = [items objectAtIndex:i];
        if ([item tag] == tag) {
            if (index) *index = i;
            return item;
        }
    }

    return nil;
}

- (void)addToolbarItemToDictionaryWithTag:(int)tag label:(NSString *)title
        toolTip:(NSString *)tip icon:(NSString *)icon
{
    // If the item corresponds to a separator then do nothing, since it is
    // already defined by Cocoa.
    if (!title || [title isEqual:NSToolbarSeparatorItemIdentifier]
               || [title isEqual:NSToolbarSpaceItemIdentifier]
               || [title isEqual:NSToolbarFlexibleSpaceItemIdentifier])
        return;

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:title];
    [item setTag:tag];
    [item setLabel:title];
    [item setToolTip:tip];
    [item setAction:@selector(vimMenuItemAction:)];
    [item setAutovalidates:NO];

    NSImage *img = [NSImage imageNamed:icon];
    if (!img) {
        NSLog(@"WARNING: Could not find image with name '%@' to use as toolbar"
               " image for identifier '%@';"
               " using default toolbar icon '%@' instead.",
               icon, title, MMDefaultToolbarImageName);

        img = [NSImage imageNamed:MMDefaultToolbarImageName];
    }

    [item setImage:img];

    [toolbarItemDict setObject:item forKey:title];

    [item release];
}

- (void)addToolbarItemWithTag:(int)tag label:(NSString *)label tip:(NSString
                   *)tip icon:(NSString *)icon atIndex:(int)idx
{
    if (!toolbar) return;

    // Check for separator items.
    if (!label) {
        label = NSToolbarSeparatorItemIdentifier;
    } else if ([label length] >= 2 && [label hasPrefix:@"-"]
                                   && [label hasSuffix:@"-"]) {
        // The label begins and ends with '-'; decided which kind of separator
        // item it is by looking at the prefix.
        if ([label hasPrefix:@"-space"]) {
            label = NSToolbarSpaceItemIdentifier;
        } else if ([label hasPrefix:@"-flexspace"]) {
            label = NSToolbarFlexibleSpaceItemIdentifier;
        } else {
            label = NSToolbarSeparatorItemIdentifier;
        }
    }

    [self addToolbarItemToDictionaryWithTag:tag label:label toolTip:tip
                                       icon:icon];

    int maxIdx = [[toolbar items] count];
    if (maxIdx < idx) idx = maxIdx;

    [toolbar insertItemWithItemIdentifier:label atIndex:idx];
}

- (void)connectionDidDie:(NSNotification *)notification
{
    //NSLog(@"%@ %s%@", [self className], _cmd, notification);

    [self cleanup];

    // NOTE!  This causes the call to removeVimController: to be delayed.
    [[NSApp delegate]
            performSelectorOnMainThread:@selector(removeVimController:)
                             withObject:self waitUntilDone:NO];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ : isInitialized=%d inProcessCommandQueue=%d mainMenuItems=%@ popupMenuItems=%@ toolbar=%@", [self className], isInitialized, inProcessCommandQueue, mainMenuItems, popupMenuItems, toolbar];
}

#if MM_RESEND_LAST_FAILURE
- (void)resendTimerFired:(NSTimer *)timer
{
    int msgid = resendMsgid;
    NSData *data = nil;

    [resendTimer release];
    resendTimer = nil;

    if (!isInitialized)
        return;

    if (resendData)
        data = [resendData copy];

    //NSLog(@"Resending message: %s", MessageStrings[msgid]);
    [self sendMessage:msgid data:data];
}
#endif

@end // MMVimController (Private)



@implementation NSColor (MMProtocol)

+ (NSColor *)colorWithRgbInt:(unsigned)rgb
{
    float r = ((rgb>>16) & 0xff)/255.0f;
    float g = ((rgb>>8) & 0xff)/255.0f;
    float b = (rgb & 0xff)/255.0f;

    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0f];
}

+ (NSColor *)colorWithArgbInt:(unsigned)argb
{
    float a = ((argb>>24) & 0xff)/255.0f;
    float r = ((argb>>16) & 0xff)/255.0f;
    float g = ((argb>>8) & 0xff)/255.0f;
    float b = (argb & 0xff)/255.0f;

    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
}

@end // NSColor (MMProtocol)



@implementation MMAlert
- (void)dealloc
{
    [textField release];
    [super dealloc];
}

- (void)setTextFieldString:(NSString *)textFieldString
{
    [textField release];
    textField = [[NSTextField alloc] init];
    [textField setStringValue:textFieldString];
}

- (NSTextField *)textField
{
    return textField;
}

- (void)setInformativeText:(NSString *)text
{
    if (textField) {
        // HACK! Add some space for the text field.
        [super setInformativeText:[text stringByAppendingString:@"\n\n\n"]];
    } else {
        [super setInformativeText:text];
    }
}

- (void)beginSheetModalForWindow:(NSWindow *)window
                   modalDelegate:(id)delegate
                  didEndSelector:(SEL)didEndSelector
                     contextInfo:(void *)contextInfo
{
    [super beginSheetModalForWindow:window
                      modalDelegate:delegate
                     didEndSelector:didEndSelector
                        contextInfo:contextInfo];

    // HACK! Place the input text field at the bottom of the informative text
    // (which has been made a bit larger by adding newline characters).
    NSView *contentView = [[self window] contentView];
    NSRect rect = [contentView frame];
    rect.origin.y = rect.size.height;

    NSArray *subviews = [contentView subviews];
    unsigned i, count = [subviews count];
    for (i = 0; i < count; ++i) {
        NSView *view = [subviews objectAtIndex:i];
        if ([view isKindOfClass:[NSTextField class]]
                && [view frame].origin.y < rect.origin.y) {
            // NOTE: The informative text field is the lowest NSTextField in
            // the alert dialog.
            rect = [view frame];
        }
    }

    rect.size.height = MMAlertTextFieldHeight;
    [textField setFrame:rect];
    [contentView addSubview:textField];
    [textField becomeFirstResponder];
}

@end // MMAlert
