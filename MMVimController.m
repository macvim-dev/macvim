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
#import "MMAppController.h"
#import "MMTextView.h"
#import "MMTextStorage.h"


//static NSString *AttentionToolbarItemID = @"Attention";
static NSString *DefaultToolbarImageName = @"Attention";


@interface MMVimController (Private)
- (void)handleMessage:(int)msgid data:(NSData *)data;
- (void)performBatchDrawWithData:(NSData *)data;
- (void)panelDidEnd:(NSSavePanel *)panel code:(int)code
            context:(void *)context;
- (NSMenuItem *)menuItemForTag:(int)tag;
- (NSMenu *)menuForTag:(int)tag;
- (void)updateMainMenu;
- (NSToolbarItem *)toolbarItemForTag:(int)tag index:(int *)index;
- (IBAction)toolbarAction:(id)sender;
- (void)addToolbarItemToDictionaryWithTag:(int)tag label:(NSString *)title
        toolTip:(NSString *)tip icon:(NSString *)icon;
- (void)connectionDidDie:(NSNotification *)notification;
@end



// TODO: Move to separate file
@interface NSColor (MMProtocol)
+ (NSColor *)colorWithRgbInt:(int)rgb;
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

#if MM_USE_DO
- (id)initWithBackend:(id)backend
#else
- (id)initWithPort:(NSPort *)port
#endif
{
    if ((self = [super init])) {
        windowController =
            [[MMWindowController alloc] initWithVimController:self];
#if MM_USE_DO
        backendProxy = [backend retain];

        NSConnection *connection = [backendProxy connectionForProxy];
        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(connectionDidDie:)
                    name:NSConnectionDidDieNotification object:connection];
#else
        sendPort = [port retain];

        // Init receive port and send connected message to VimTask
        receivePort = [NSMachPort new];
        [receivePort setDelegate:self];

        // Add to the default run loop mode as well as the event tracking mode;
        // the latter ensures that updates from the VimTask reaches
        // MMVimController whilst the user resizes a window with the mouse.
        [[NSRunLoop currentRunLoop] addPort:receivePort
                                    forMode:NSDefaultRunLoopMode];
        [[NSRunLoop currentRunLoop] addPort:receivePort
                                    forMode:NSEventTrackingRunLoopMode];

        [NSPortMessage sendMessage:ConnectedMsgID withSendPort:sendPort
                       receivePort:receivePort wait:YES];
#endif

        mainMenuItems = [[NSMutableArray alloc] init];

        toolbarItemDict = [[NSMutableDictionary alloc] init];
        //[self addToolbarItemToDictionaryWithTag:0 label:@"Attention"
        //                                toolTip:@"A toolbar item is missing"
        //                                   icon:@"Attention"];

        [[NSNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(windowWillClose:)
                       name:NSWindowWillCloseNotification
                     object:[windowController window]];
        [[NSNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(windowDidBecomeMain:)
                       name:NSWindowDidBecomeMainNotification
                     object:[windowController window]];

    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);

    [[NSNotificationCenter defaultCenter] removeObserver:self];

#if MM_USE_DO
    [backendProxy release];
#else
    if (sendPort) {
        // Kill task immediately
        [NSPortMessage sendMessage:KillTaskMsgID withSendPort:sendPort
                       receivePort:receivePort wait:NO];
    }

    [sendPort release];
    [receivePort release];
#endif

    [toolbarItemDict release];
    [toolbar release];
    [mainMenuItems release];
    [windowController release];

    [super dealloc];
}

- (id)backendProxy
{
    return backendProxy;
}

- (void)sendMessage:(int)msgid data:(NSData *)data wait:(BOOL)wait
{
#if MM_USE_DO
    if (wait) {
        [backendProxy processInput:msgid data:data];
    } else {
        // Do not wait for the message to be sent, i.e. drop the message if it
        // can't be delivered immediately.
        NSConnection *connection = [backendProxy connectionForProxy];
        if (connection) {
            NSTimeInterval req = [connection requestTimeout];
            [connection setRequestTimeout:0];
            [backendProxy processInput:msgid data:data];
            [connection setRequestTimeout:req];
        }
    }
#else
    [NSPortMessage sendMessage:msgid withSendPort:sendPort data:data
                          wait:wait];
#endif
}

#if MM_USE_DO
- (oneway void)processCommandQueue:(in NSArray *)queue
{
    unsigned i, count = [queue count];
    if (count % 2) {
        NSLog(@"WARNING: Uneven number of components (%d) in flush queue "
                "message; ignoring this message.", count);
        return;
    }

    for (i = 0; i < count; i += 2) {
        NSData *value = [queue objectAtIndex:i];
        NSData *data = [queue objectAtIndex:i+1];

        [self handleMessage:*((int*)[value bytes]) data:data];
    }
}

#else // MM_USE_DO

- (NSPort *)sendPort
{
    return sendPort;
}

- (void)handlePortMessage:(NSPortMessage *)portMessage
{
    //NSLog(@"%@ %s %@", [self className], _cmd, portMessage);

    NSArray *components = [portMessage components];
    unsigned msgid = [portMessage msgid];

    //NSLog(@"%s%d", _cmd, msgid);

    if (FlushQueueMsgID == msgid) {
        unsigned i, count = [components count];
        if (count % 2) {
            NSLog(@"WARNING: Uneven number of components (%d) in flush queue "
                    "message; ignoring this message.", count);
            return;
        }

        for (i = 0; i < count; i += 2) {
            NSData *value = [components objectAtIndex:i];
            NSData *data = [components objectAtIndex:i+1];

            [self handleMessage:*((int*)[value bytes]) data:data];
        }
    } else {
        NSData *data = nil;
        if ([components count] > 0)
            data = [components objectAtIndex:0];

        [self handleMessage:msgid data:data];
    }

    if (shouldUpdateMainMenu)
        [self updateMainMenu];
}
#endif // MM_USE_DO

- (void)windowWillClose:(NSNotification *)notification
{
    // NOTE!  This causes the call to removeVimController: to be delayed.
    [[NSApp delegate]
            performSelectorOnMainThread:@selector(removeVimController:)
                             withObject:self waitUntilDone:NO];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    [self updateMainMenu];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)theToolbar
    itemForItemIdentifier:(NSString *)itemId
    willBeInsertedIntoToolbar:(BOOL)flag
{
    //NSLog(@"%s", _cmd);

    NSToolbarItem *item = [toolbarItemDict objectForKey:itemId];
    if (!item) {
        NSLog(@"WARNING:  No toolbar item with id '%@'", itemId);
    }

    return item;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)theToolbar
{
    //NSLog(@"%s", _cmd);
    return nil;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)theToolbar
{
    //NSLog(@"%s", _cmd);
    return nil;
}

@end // MMVimController



@implementation MMVimController (Private)

- (void)handleMessage:(int)msgid data:(NSData *)data
{
    //NSLog(@"%@ %s", [self className], _cmd);

    if (OpenVimWindowMsgID == msgid) {
        const void *bytes = [data bytes];
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);  bytes += sizeof(int);

        //NSLog(@"Received open VimWindow (%dx%d) message from VimTask.",
        //        cols, rows);

        [windowController openWindowWithRows:rows columns:cols];
    }
#if !MM_USE_DO
    else if (TaskExitedMsgID == msgid) {
        //NSLog(@"Received task exited message from VimTask; closing window.");

        // Release sendPort immediately to avoid dealloc trying to send a 'kill
        // task' message to the task.
        [sendPort release];  sendPort = nil;
        // NOTE!  This causes windowWillClose: to be called, which in turn asks
        // the MMAppController to remove this MMVimController.
        [windowController close];

        // HACK! Make sure no menu updating is done, we're about to close.
        shouldUpdateMainMenu = NO;
    }
#endif // !MM_USE_DO
    else if (BatchDrawMsgID == msgid) {
        //NSLog(@"Received batch draw message from VimTask.");

        [self performBatchDrawWithData:data];
    } else if (SelectTabMsgID == msgid) {
        const void *bytes = [data bytes];
        int idx = *((int*)bytes);
        //NSLog(@"Selecting tab with index %d", idx);
        [windowController selectTabWithIndex:idx];
    } else if (UpdateTabBarMsgID == msgid) {
        //NSLog(@"Updating tabs");
        [windowController updateTabsWithData:data];
    } else if (ShowTabBarMsgID == msgid) {
        //NSLog(@"Showing tab bar");

        // The tab bar has it's own baseline separator, so hide the one
        // belonging to the toolbar whenever the tab bar is visible.
        // BUG: The window auto shows the separator when clicking the show/hide
        // toolbar button.
        [toolbar setShowsBaselineSeparator:NO];

        // HACK! Vim sends several draw commands etc. after the show message
        // and these can mess up the display when showing the tab bar results
        // in the window having to resize to fit the screen; delaying this
        // message alleviates this problem.
        [windowController performSelectorOnMainThread:@selector(showTabBar:)
                                           withObject:self waitUntilDone:NO];
        //[windowController showTabBar:self];
    } else if (HideTabBarMsgID == msgid) {
        //NSLog(@"Hiding tab bar");

        // The tab bar has it's own baseline separator, so hide the one
        // belonging to the toolbar whenever the tab bar is visible.
        // BUG: The window auto shows the separator when clicking the show/hide
        // toolbar button.
        [toolbar setShowsBaselineSeparator:YES];

        [windowController hideTabBar:self];
    } else if (SetTextDimensionsMsgID == msgid) {
        const void *bytes = [data bytes];
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);  bytes += sizeof(int);

        [windowController setTextDimensionsWithRows:rows columns:cols];
    } else if (SetVimWindowTitleMsgID == msgid) {
        const void *bytes = [data bytes];
        int len = *((int*)bytes);  bytes += sizeof(int);

#if 0
        // BUG!  Using this call leads to ALL windows getting the same title
        // and then the app crashes if you :q a window.
        NSString *string = [[NSString alloc]
                initWithBytesNoCopy:(void*)bytes
                             length:len
                           encoding:NSUTF8StringEncoding
                       freeWhenDone:NO];
#else
        NSString *string = [[NSString alloc] initWithBytes:(void*)bytes
                length:len encoding:NSUTF8StringEncoding];
#endif

        [[windowController window] setTitle:string];

        [string release];
    } else if (BrowseForFileMsgID == msgid) {
        const void *bytes = [data bytes];
        int save = *((int*)bytes);  bytes += sizeof(int);

        int len = *((int*)bytes);  bytes += sizeof(int);
        NSString *dir = nil;
        if (len > 0) {
            dir = [[NSString alloc] initWithBytes:(void*)bytes
                                           length:len
                                         encoding:NSUTF8StringEncoding];
            bytes += len;
        }

        len = *((int*)bytes);  bytes += sizeof(int);
        if (len > 0) {
            NSString *title = [[NSString alloc]
                    initWithBytes:(void*)bytes length:len
                         encoding:NSUTF8StringEncoding];
            bytes += len;

            [windowController setStatusText:title];
            [title release];
        }

        if (save) {
            [[NSSavePanel savePanel] beginSheetForDirectory:dir file:nil
                modalForWindow:[windowController window]
                 modalDelegate:self
                didEndSelector:@selector(panelDidEnd:code:context:)
                   contextInfo:NULL];
        } else {
            NSOpenPanel *panel = [NSOpenPanel openPanel];
            [panel setAllowsMultipleSelection:NO];
            [panel beginSheetForDirectory:dir file:nil types:nil
                    modalForWindow:[windowController window]
                     modalDelegate:self
                    didEndSelector:@selector(panelDidEnd:code:context:)
                       contextInfo:NULL];
        }

        [dir release];
    } else if (UpdateInsertionPointMsgID == msgid) {
        const void *bytes = [data bytes];
        int color = *((int*)bytes);  bytes += sizeof(int);
        int row = *((int*)bytes);  bytes += sizeof(int);
        int col = *((int*)bytes);  bytes += sizeof(int);
        int state = *((int*)bytes);  bytes += sizeof(int);

        // TODO! Move to window controller.
        MMTextView *textView = [windowController textView];
        if (textView) {
            MMTextStorage *textStorage = (MMTextStorage*)[textView textStorage];
            unsigned off = [textStorage offsetFromRow:row column:col];

            [textView setInsertionPointColor:[NSColor colorWithRgbInt:color]];
            [textView setSelectedRange:NSMakeRange(off, 0)];
            [textView setShouldDrawInsertionPoint:state];
        }
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
                NSString *ident = [NSString stringWithFormat:@"%d.%d",
                         (int)self, tag];
                //NSLog(@"Creating toolbar with identifier %@", ident);
                toolbar = [[NSToolbar alloc] initWithIdentifier:ident];

                [toolbar setDelegate:self];
                [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
                [toolbar setSizeMode:NSToolbarSizeModeSmall];

                [[windowController window] setToolbar:toolbar];
            }
        } else if (MenuPopupType == parentTag) {
            // TODO!
        } else if (title) {
            NSMenuItem *item = [[NSMenuItem alloc] init];
            NSMenu *menu = [[NSMenu alloc] initWithTitle:title];

            [menu setAutoenablesItems:NO];
            [item setTag:tag];
            [item setTitle:title];
            [item setSubmenu:menu];

            NSMenu *parent = [self menuForTag:parentTag];
            if (parent) {
                if ([parent numberOfItems] <= idx) {
                    [parent addItem:item];
                } else {
                    [parent insertItem:item atIndex:idx];
                }
            } else {
                if ([mainMenuItems count] <= idx) {
                    [mainMenuItems addObject:item];
                } else {
                    [mainMenuItems insertObject:item atIndex:idx];
                }

                shouldUpdateMainMenu = YES;
            }

            [item release];
            [menu release];
        }

        [title release];
    } else if (AddMenuItemMsgID == msgid) {
        NSString *title = nil, *tip = nil, *icon = nil;
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
        int idx = *((int*)bytes);  bytes += sizeof(int);
        if (idx < 0) idx = 0;

        NSString *ident = [NSString stringWithFormat:@"%d.%d",
                (int)self, parentTag];
        if (toolbar && [[toolbar identifier] isEqual:ident]) {
            //NSLog(@"Toolbar add: title=%@ icon=%@ tip=%@", title, icon, tip);
            [self addToolbarItemToDictionaryWithTag:tag label:title toolTip:tip
                                               icon:icon];

            int maxIdx = [[toolbar items] count];
            if (maxIdx < idx) idx = maxIdx;

            // If 'title' is nul, insert a separator.
            if (!title) title = NSToolbarSeparatorItemIdentifier;
            [toolbar insertItemWithItemIdentifier:title atIndex:idx];
        } else {
            NSMenu *parent = [self menuForTag:parentTag];
            if (parent) {
                NSMenuItem *item = nil;
                if (title) {
                    item = [[[NSMenuItem alloc] init] autorelease];
                    [item setTag:tag];
                    [item setTitle:title];
                    [item setAction:@selector(vimMenuItemAction:)];
                    if (tip) [item setToolTip:tip];
                } else {
                    item = [NSMenuItem separatorItem];
                }

                if ([parent numberOfItems] <= idx) {
                    [parent addItem:item];
                } else {
                    [parent insertItem:item atIndex:idx];
                }
            }
        }

        [title release];
        [tip release];
    } else if (RemoveMenuItemMsgID == msgid) {
        const void *bytes = [data bytes];
        int tag = *((int*)bytes);  bytes += sizeof(int);

        // TODO: Search for tag in popup menus.
        id item;
        int idx;
        if ((item = [self toolbarItemForTag:tag index:&idx])) {
            [toolbar removeItemAtIndex:idx];
        } else if ((item = [self menuItemForTag:tag])) {
            if ([item menu] == [NSApp mainMenu]) {
                [mainMenuItems removeObject:item];
            }
            [[item menu] removeItem:item];
        }
    } else if (EnableMenuItemMsgID == msgid) {
        const void *bytes = [data bytes];
        int tag = *((int*)bytes);  bytes += sizeof(int);
        int state = *((int*)bytes);  bytes += sizeof(int);

        // TODO: Search for tag in popup menus.
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

        [toolbar setSizeMode:size];
        [toolbar setDisplayMode:mode];
        [toolbar setVisible:enable];
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

        if (font && [windowController textStorage]) {
            [[windowController textStorage] setFont:font];
        }

        [name release];
    } else if (SetDefaultColorsMsgID == msgid) {
        const void *bytes = [data bytes];
        int bg = *((int*)bytes);  bytes += sizeof(int);
        int fg = *((int*)bytes);  bytes += sizeof(int);

        MMTextStorage *textStorage = [windowController textStorage];
        if (textStorage) {
            [textStorage
                    setDefaultColorsBackground:[NSColor colorWithRgbInt:bg]
                                    foreground:[NSColor colorWithRgbInt:fg]];
        }
    } else {
        NSLog(@"WARNING: Unknown message received (msgid=%d)", msgid);
    }
}

- (void)performBatchDrawWithData:(NSData *)data
{
    // TODO!  Move to window controller.
    MMTextStorage *textStorage = [windowController textStorage];
    if (!textStorage)
        return;

    const void *bytes = [data bytes];
    const void *end = bytes + [data length];

    [textStorage beginEditing];

    // TODO:
    // 1. Sanity check input
    // 2. Cache rgb -> NSColor lookups?

    while (bytes < end) {
        int type = *((int*)bytes);  bytes += sizeof(int);
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);  bytes += sizeof(int);

        if (ClearAllDrawType != type) {
            // All draw types except clear all rely on the text storage have
            // the appropriate dimensions, so set it before attempting to
            // modify the text storage.
            [textStorage setMaxRows:rows columns:cols];
        }

        if (ClearAllDrawType == type) {
            int color = *((int*)bytes);  bytes += sizeof(int);

            [textStorage clearAllWithColor:[NSColor colorWithRgbInt:color]];
        } else if (ClearBlockDrawType == type) {
            int color = *((int*)bytes);  bytes += sizeof(int);
            int row1 = *((int*)bytes);  bytes += sizeof(int);
            int col1 = *((int*)bytes);  bytes += sizeof(int);
            int row2 = *((int*)bytes);  bytes += sizeof(int);
            int col2 = *((int*)bytes);  bytes += sizeof(int);

            [textStorage clearBlockFromRow:row1 column:col1
                    toRow:row2 column:col2
                    color:[NSColor colorWithRgbInt:color]];
        } else if (DeleteLinesDrawType == type) {
            int color = *((int*)bytes);  bytes += sizeof(int);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

            [textStorage deleteLinesFromRow:row lineCount:count
                    scrollBottom:bot left:left right:right
                           color:[NSColor colorWithRgbInt:color]];
        } else if (ReplaceStringDrawType == type) {
            int bg = *((int*)bytes);  bytes += sizeof(int);
            int fg = *((int*)bytes);  bytes += sizeof(int);
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

            [textStorage replaceString:string
                                 atRow:row column:col
                             withFlags:flags
                       foregroundColor:[NSColor colorWithRgbInt:fg]
                       backgroundColor:[NSColor colorWithRgbInt:bg]];

            [string release];
        } else if (InsertLinesDrawType == type) {
            int color = *((int*)bytes);  bytes += sizeof(int);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

            [textStorage insertLinesAtRow:row lineCount:count
                             scrollBottom:bot left:left right:right
                                    color:[NSColor colorWithRgbInt:color]];
        } else {
            NSLog(@"WARNING: Unknown draw type (type=%d)", type);
        }
    }

    [textStorage endEditing];
}

- (void)panelDidEnd:(NSSavePanel *)panel code:(int)code context:(void *)context
{
#if !MM_USE_DO
    NSMutableData *data = [NSMutableData data];
    int ok = (code == NSOKButton);
    NSString *filename = [panel filename];
    int len = [filename lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    [data appendBytes:&ok length:sizeof(int)];
    [data appendBytes:&len length:sizeof(int)];
    if (len > 0)
        [data appendBytes:[filename UTF8String] length:len];

    if (![NSPortMessage sendMessage:BrowseForFileReplyMsgID
                       withSendPort:sendPort data:data wait:YES]) {
        NSLog(@"WARNING: Failed to send browse for files reply back to "
                "VimTask.");
    }

    [windowController setStatusText:@""];
#endif // !MM_USE_DO
}

- (NSMenuItem *)menuItemForTag:(int)tag
{
    int i, count = [mainMenuItems count];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [mainMenuItems objectAtIndex:i];
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

- (void)updateMainMenu
{
    shouldUpdateMainMenu = NO;

    // HACK!  Add the vim menu named 'Window' as the submenu with index 5 of an
    // already existing menu with the same name.  The 'Window' menu is set up
    // in Interface Builder.
    NSMenu *mainMenu = [NSApp mainMenu];
    NSMenu *windowMenu = nil;

    // Remove all existing menus, except for 'Window'.
    int i, count = [mainMenu numberOfItems];
    for (i = count-1; i > 0; --i) {
        NSMenuItem *item = [mainMenu itemAtIndex:i];
        NSMenu *submenu = [item submenu];
        if ([[submenu title] isEqual:@"Window"]) {
            windowMenu = submenu;
        } else {
            [mainMenu removeItem:item];
        }
    }

    // Add menus from 'mainMenuItems'
    count = [mainMenuItems count];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [mainMenuItems objectAtIndex:i];

        if (windowMenu && [windowMenu numberOfItems] > 6
                && [[item title] isEqual:@"Window"]) {
            // Item 5 of the Window menu is replaced with vim's Window menu.
            [windowMenu removeItemAtIndex:5];
            [windowMenu insertItem:item atIndex:5];
        } else {
            [mainMenu insertItem:item atIndex:i+1];
        }
    }
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

- (IBAction)toolbarAction:(id)sender
{
    NSLog(@"%s%@", _cmd, sender);
}

- (void)addToolbarItemToDictionaryWithTag:(int)tag label:(NSString *)title
        toolTip:(NSString *)tip icon:(NSString *)icon
{
    // NOTE!  'title' is nul for separator item.  Since this is already defined
    // by Coca, we don't need to do anything here.
    if (!title) return;

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
               icon, title, DefaultToolbarImageName);

        img = [NSImage imageNamed:DefaultToolbarImageName];
    }

    [item setImage:img];

    [toolbarItemDict setObject:item forKey:title];

    [item release];
}

#if MM_USE_DO
- (void)connectionDidDie:(NSNotification *)notification
{
    //NSLog(@"A MMVimController lost its connection to the backend; "
    //       "closing the controller.");
    [windowController close];
}
#endif // MM_USE_DO

@end // MMVimController (Private)



@implementation NSColor (MMProtocol)

+ (NSColor *)colorWithRgbInt:(int)rgb
{
    float r = ((rgb>>16) & 0xff)/255.0f;
    float g = ((rgb>>8) & 0xff)/255.0f;
    float b = (rgb & 0xff)/255.0f;

    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0f];
}

@end // NSColor (MMProtocol)
