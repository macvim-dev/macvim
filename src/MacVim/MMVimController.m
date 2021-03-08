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
 * MMVimController
 *
 * Coordinates input/output to/from backend.  A MMVimController sends input
 * directly to a MMBackend, but communication from MMBackend to MMVimController
 * goes via MMAppController so that it can coordinate all incoming distributed
 * object messages.
 *
 * MMVimController does not deal with visual presentation.  Essentially it
 * should be able to run with no window present.
 *
 * Output from the backend is received in processInputQueue: (this message is
 * called from MMAppController so it is not a DO call).  Input is sent to the
 * backend via sendMessage:data: or addVimInput:.  The latter allows execution
 * of arbitrary strings in the Vim process, much like the Vim script function
 * remote_send() does.  The messages that may be passed between frontend and
 * backend are defined in an enum in MacVim.h.
 */

#import "MMAppController.h"
#import "MMFindReplaceController.h"
#import "MMTextView.h"
#import "MMVimController.h"
#import "MMVimView.h"
#import "MMWindowController.h"
#import "Miscellaneous.h"
#import "MMCoreTextView.h"
#import "MMWindow.h"


static NSString * const MMDefaultToolbarImageName = @"Attention";
static int MMAlertTextFieldHeight = 22;

static NSString * const MMToolbarMenuName = @"ToolBar";
static NSString * const MMTouchbarMenuName = @"TouchBar";
static NSString * const MMWinBarMenuName = @"WinBar";
static NSString * const MMPopUpMenuPrefix = @"PopUp";
static NSString * const MMUserPopUpMenuPrefix = @"]";

// NOTE: By default a message sent to the backend will be dropped if it cannot
// be delivered instantly; otherwise there is a possibility that MacVim will
// 'beachball' while waiting to deliver DO messages to an unresponsive Vim
// process.  This means that you cannot rely on any message sent with
// sendMessage: to actually reach Vim.
static NSTimeInterval MMBackendProxyRequestTimeout = 0;

// Timeout used for setDialogReturn:.
static NSTimeInterval MMSetDialogReturnTimeout = 1.0;

static unsigned identifierCounter = 1;

static BOOL isUnsafeMessage(int msgid);


// HACK! AppKit private methods from NSToolTipManager.  As an alternative to
// using private methods, it would be possible to set the user default
// NSInitialToolTipDelay (in ms) on app startup, but then it is impossible to
// change the balloon delay without closing/reopening a window.
@interface NSObject (NSToolTipManagerPrivateAPI)
+ (id)sharedToolTipManager;
- (void)setInitialToolTipDelay:(double)arg1;
@end


@interface MMAlert : NSAlert {
    NSTextField *textField;
}
- (void)setTextFieldString:(NSString *)textFieldString;
- (NSTextField *)textField;
- (void)beginSheetModalForWindow:(NSWindow *)window
                   modalDelegate:(id)delegate;
@end


#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_12
@interface MMTouchBarInfo : NSObject;

@property (readonly) NSTouchBar *touchbar;
@property (readonly) NSMutableDictionary *itemDict;
@property (readonly) NSMutableArray *itemOrder;

@end

@interface MMTouchBarItemInfo : NSObject;

@property (readonly) NSTouchBarItem     *touchbarItem;
@property (readwrite) BOOL              enabled;
@property (readonly) NSString           *label;

@property (readonly) MMTouchBarInfo     *childTouchbar; // Set when this is a submenu

- (id)initWithItem:(NSTouchBarItem *)item label:(NSString *)label;
- (void)setTouchBarItem:(NSTouchBarItem *)item;
- (void)makeChildTouchBar;
@end

@interface MMTouchBarButton : NSButton {
    NSArray *_desc;
}
- (NSArray *)desc;
- (void)setDesc:(NSArray *)desc;
@end
#endif

@interface MMVimController (Private)
- (void)doProcessInputQueue:(NSArray *)queue;
- (void)handleMessage:(int)msgid data:(NSData *)data;
- (void)savePanelDidEnd:(NSSavePanel *)panel code:(int)code
                context:(void *)context;
- (void)alertDidEnd:(MMAlert *)alert code:(int)code context:(void *)context;
- (NSMenuItem *)menuItemForDescriptor:(NSArray *)desc;
- (NSMenu *)parentMenuForDescriptor:(NSArray *)desc;
- (NSMenu *)topLevelMenuForTitle:(NSString *)title;
- (void)addMenuWithDescriptor:(NSArray *)desc atIndex:(int)index;
- (void)addMenuItemWithDescriptor:(NSArray *)desc
                          atIndex:(int)index
                              tip:(NSString *)tip
                             icon:(NSString *)icon
                    keyEquivalent:(NSString *)keyEquivalent
                     modifierMask:(int)modifierMask
                           action:(NSString *)action
                      isAlternate:(BOOL)isAlternate;
- (void)removeMenuItemWithDescriptor:(NSArray *)desc;
- (void)enableMenuItemWithDescriptor:(NSArray *)desc state:(BOOL)on;
- (void)updateMenuItemTooltipWithDescriptor:(NSArray *)desc tip:(NSString *)tip;
- (void)addToolbarItemToDictionaryWithLabel:(NSString *)title
        toolTip:(NSString *)tip icon:(NSString *)icon;
- (void)addToolbarItemWithLabel:(NSString *)label
                          tip:(NSString *)tip icon:(NSString *)icon
                      atIndex:(int)idx;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
- (void)addTouchbarItemWithLabel:(NSString *)label
                            icon:(NSString *)icon
                             tip:(NSString *)tip
                         atIndex:(int)idx
                       isSubMenu:(BOOL)submenu
                            desc:(NSArray *)desc
                      atTouchBar:(MMTouchBarInfo *)touchbarInfo;
- (void)updateTouchbarItemLabel:(NSString *)label
                            tip:(NSString *)tip
                 atTouchBarItem:(MMTouchBarItemInfo*)item;
- (BOOL)touchBarItemForDescriptor:(NSArray *)desc
                         touchBar:(MMTouchBarInfo **)touchBarPtr
                     touchBarItem:(MMTouchBarItemInfo **)touchBarItemPtr;
#endif
- (void)popupMenuWithDescriptor:(NSArray *)desc
                          atRow:(NSNumber *)row
                         column:(NSNumber *)col;
- (void)popupMenuWithAttributes:(NSDictionary *)attrs;
- (void)connectionDidDie:(NSNotification *)notification;
- (void)scheduleClose;
- (void)handleBrowseForFile:(NSDictionary *)attr;
- (void)handleShowDialog:(NSDictionary *)attr;
- (void)handleDeleteSign:(NSDictionary *)attr;
- (void)setToolTipDelay;
@end




@implementation MMVimController

- (id)initWithBackend:(id)backend pid:(int)processIdentifier
{
    if (!(self = [super init]))
        return nil;

    // TODO: Come up with a better way of creating an identifier.
    identifier = identifierCounter++;

    windowController =
        [[MMWindowController alloc] initWithVimController:self];
    backendProxy = [backend retain];
    popupMenuItems = [[NSMutableArray alloc] init];
    toolbarItemDict = [[NSMutableDictionary alloc] init];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
    if (NSClassFromString(@"NSTouchBar")) {
        touchbarInfo = [[MMTouchBarInfo alloc] init];
    }
#endif
    pid = processIdentifier;
    creationDate = [[NSDate alloc] init];

    NSConnection *connection = [backendProxy connectionForProxy];

    // TODO: Check that this will not set the timeout for the root proxy
    // (in MMAppController).
    [connection setRequestTimeout:MMBackendProxyRequestTimeout];

    [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(connectionDidDie:)
                name:NSConnectionDidDieNotification object:connection];

    // Set up a main menu with only a "MacVim" menu (copied from a template
    // which itself is set up in MainMenu.nib).  The main menu is populated
    // by Vim later on.
    mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *appMenuItem = [[MMAppController sharedInstance]
                                        appMenuItemTemplate];
    appMenuItem = [[appMenuItem copy] autorelease];

    // Note: If the title of the application menu is anything but what
    // CFBundleName says then the application menu will not be typeset in
    // boldface for some reason.  (It should already be set when we copy
    // from the default main menu, but this is not the case for some
    // reason.)
    NSString *appName = [[NSBundle mainBundle]
            objectForInfoDictionaryKey:@"CFBundleName"];
    [appMenuItem setTitle:appName];

    [mainMenu addItem:appMenuItem];

    [self setToolTipDelay];

    isInitialized = YES;

    // After MMVimController's initialization is completed,
    // set up the variable `v:os_appearance`.
    [self appearanceChanged:getCurrentAppearance([windowController vimView].effectiveAppearance)];
    
    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    isInitialized = NO;

    [serverName release];  serverName = nil;
    [backendProxy release];  backendProxy = nil;

    [toolbarItemDict release];  toolbarItemDict = nil;
    [toolbar release];  toolbar = nil;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
    [touchbarInfo release]; touchbarInfo = nil;
#endif
    [popupMenuItems release];  popupMenuItems = nil;
    [windowController release];  windowController = nil;

    [vimState release];  vimState = nil;
    [mainMenu release];  mainMenu = nil;
    [creationDate release];  creationDate = nil;

    [super dealloc];
}

- (unsigned)vimControllerId
{
    return identifier;
}

- (MMWindowController *)windowController
{
    return windowController;
}

- (NSDictionary *)vimState
{
    return vimState;
}

- (id)objectForVimStateKey:(NSString *)key
{
    return [vimState objectForKey:key];
}

- (NSMenu *)mainMenu
{
    return mainMenu;
}

- (BOOL)isPreloading
{
    return isPreloading;
}

- (void)setIsPreloading:(BOOL)yn
{
    isPreloading = yn;
}

- (BOOL)hasModifiedBuffer
{
    return hasModifiedBuffer;
}

- (NSDate *)creationDate
{
    return creationDate;
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

- (void)dropFiles:(NSArray *)filenames forceOpen:(BOOL)force
{
    filenames = normalizeFilenames(filenames);
    ASLogInfo(@"filenames=%@ force=%d", filenames, force);

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // Default to opening in tabs if layout is invalid or set to "windows".
    int layout = [ud integerForKey:MMOpenLayoutKey];
    if (layout < 0 || layout > MMLayoutTabs)
        layout = MMLayoutTabs;

    BOOL splitVert = [ud boolForKey:MMVerticalSplitKey];
    if (splitVert && MMLayoutHorizontalSplit == layout)
        layout = MMLayoutVerticalSplit;

    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:layout],    @"layout",
            filenames,                          @"filenames",
            [NSNumber numberWithBool:force],    @"forceOpen",
            nil];

    [self sendMessage:DropFilesMsgID data:[args dictionaryAsData]];

    // Add dropped files to the "Recent Files" menu.
    [[NSDocumentController sharedDocumentController]
                                            noteNewRecentFilePaths:filenames];
}

// This is called when a file is dragged on top of a tab. We will open the file
// list similar to drag-and-dropped files.
- (void)file:(NSString *)filename draggedToTabAtIndex:(NSUInteger)tabIndex
{
    filename = normalizeFilename(filename);
    ASLogInfo(@"filename=%@ index=%ld", filename, tabIndex);

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    
    // This is similar to dropFiles:forceOpen: except we first switch to the
    // selected tab, and just open the first file (this could be modified in the
    // future to support multiple files). It also forces layout to be splits
    // because we specified one tab to receive the file so doesn't make sense to
    // open another tab.
    int layout = MMLayoutHorizontalSplit;
    if ([ud boolForKey:MMVerticalSplitKey])
        layout = MMLayoutVerticalSplit;
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithInt:layout],    @"layout",
                          @[filename],                        @"filenames",
                          [NSNumber numberWithInt:tabIndex + 1],    @"tabpage",
                          nil];
    
    [self sendMessage:OpenWithArgumentsMsgID data:[args dictionaryAsData]];
}

// This is called when a file is dragged on top of the tab bar but not a
// particular tab (e.g. the new tab button). We will open the file list similar
// to drag-and-dropped files.
- (void)filesDraggedToTabBar:(NSArray *)filenames
{
    filenames = normalizeFilenames(filenames);
    ASLogInfo(@"%@", filenames);
    
    // This is similar to dropFiles:forceOpen: except we just force layout to be
    // tabs (since the receipient is the tab bar, we assume that's the
    // intention) instead of loading from user defaults.
    int layout = MMLayoutTabs;
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithInt:layout],    @"layout",
                          filenames,                          @"filenames",
                          nil];
    
    [self sendMessage:OpenWithArgumentsMsgID data:[args dictionaryAsData]];
}

- (void)dropString:(NSString *)string
{
    ASLogInfo(@"%@", string);
    int len = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
    if (len > 0) {
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:[string UTF8String] length:len];

        [self sendMessage:DropStringMsgID data:data];
    }
}

- (void)appearanceChanged:(int)flag
{
    [self sendMessage:NotifyAppearanceChangeMsgID
                 data:[NSData dataWithBytes: &flag
               length:sizeof(flag)]];
}

- (void)passArguments:(NSDictionary *)args
{
    if (!args) return;

    ASLogDebug(@"args=%@", args);

    [self sendMessage:OpenWithArgumentsMsgID data:[args dictionaryAsData]];
}

- (void)sendMessage:(int)msgid data:(NSData *)data
{
    ASLogDebug(@"msg=%s (isInitialized=%d)",
               MMVimMsgIDStrings[msgid], isInitialized);

    if (!isInitialized) return;

    @try {
        [backendProxy processInput:msgid data:data];
    }
    @catch (NSException *ex) {
        ASLogDebug(@"processInput:data: failed: pid=%d id=%d msg=%s reason=%@",
                pid, identifier, MMVimMsgIDStrings[msgid], ex);
    }
}

- (BOOL)sendMessageNow:(int)msgid data:(NSData *)data
               timeout:(NSTimeInterval)timeout
{
    // Send a message with a timeout.  USE WITH EXTREME CAUTION!  Sending
    // messages in rapid succession with a timeout may cause MacVim to beach
    // ball forever.  In almost all circumstances sendMessage:data: should be
    // used instead.

    ASLogDebug(@"msg=%s (isInitialized=%d)",
               MMVimMsgIDStrings[msgid], isInitialized);

    if (!isInitialized)
        return NO;

    if (timeout < 0) timeout = 0;

    BOOL sendOk = YES;
    NSConnection *conn = [backendProxy connectionForProxy];
    NSTimeInterval oldTimeout = [conn requestTimeout];

    [conn setRequestTimeout:timeout];

    @try {
        [backendProxy processInput:msgid data:data];
    }
    @catch (NSException *ex) {
        sendOk = NO;
        ASLogDebug(@"processInput:data: failed: pid=%d id=%d msg=%s reason=%@",
                pid, identifier, MMVimMsgIDStrings[msgid], ex);
    }
    @finally {
        [conn setRequestTimeout:oldTimeout];
    }

    return sendOk;
}

- (void)addVimInput:(NSString *)string
{
    ASLogDebug(@"%@", string);

    // This is a very general method of adding input to the Vim process.  It is
    // basically the same as calling remote_send() on the process (see
    // ':h remote_send').
    if (string) {
        NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
        [self sendMessage:AddInputMsgID data:data];
    }
}

- (NSString *)evaluateVimExpression:(NSString *)expr
{
    NSString *eval = nil;

    @try {
        eval = [backendProxy evaluateExpression:expr];
        ASLogDebug(@"eval(%@)=%@", expr, eval);
    }
    @catch (NSException *ex) {
        ASLogDebug(@"evaluateExpression: failed: pid=%d id=%d reason=%@",
                pid, identifier, ex);
    }

    return eval;
}

- (id)evaluateVimExpressionCocoa:(NSString *)expr
                     errorString:(NSString **)errstr
{
    id eval = nil;

    @try {
        eval = [backendProxy evaluateExpressionCocoa:expr
                                         errorString:errstr];
        ASLogDebug(@"eval(%@)=%@", expr, eval);
    } @catch (NSException *ex) {
        ASLogDebug(@"evaluateExpressionCocoa: failed: pid=%d id=%d reason=%@",
                pid, identifier, ex);
        *errstr = [ex reason];
    }

    return eval;
}

- (id)backendProxy
{
    return backendProxy;
}

- (void)cleanup
{
    if (!isInitialized) return;

    // Remove any delayed calls made on this object.
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    isInitialized = NO;
    [toolbar setDelegate:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    //[[backendProxy connectionForProxy] invalidate];
    //[windowController close];
    [windowController cleanup];
}

- (void)processInputQueue:(NSArray *)queue
{
    if (!isInitialized) return;

    // NOTE: This method must not raise any exceptions (see comment in the
    // calling method).
    @try {
        [self doProcessInputQueue:queue];
        [windowController processInputQueueDidFinish];
    }
    @catch (NSException *ex) {
        ASLogDebug(@"Exception: pid=%d id=%d reason=%@", pid, identifier, ex);
    }
}

- (NSToolbarItem *)toolbar:(NSToolbar *)theToolbar
    itemForItemIdentifier:(NSString *)itemId
    willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item = [toolbarItemDict objectForKey:itemId];
    if (!item) {
        ASLogWarn(@"No toolbar item with id '%@'", itemId);
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
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
- (NSTouchBar *)makeTouchBarOn:(MMTouchBarInfo *)touchbarInfo
{
    NSMutableArray *filteredTouchbarItemOrder = [NSMutableArray array];
    NSMutableSet *filteredItems = [NSMutableSet set];
    for (NSString *label in touchbarInfo.itemOrder) {
        MMTouchBarItemInfo *itemInfo = [touchbarInfo.itemDict objectForKey:label];
        if ([itemInfo enabled]) {
            [filteredTouchbarItemOrder addObject:[itemInfo label]];
            
            if ([itemInfo touchbarItem]) {
                if ([itemInfo childTouchbar]) {
                    NSTouchBar *childTouchbar = [self makeTouchBarOn:[itemInfo childTouchbar]];
                    NSPopoverTouchBarItem *popoverItem = (NSPopoverTouchBarItem *)[itemInfo touchbarItem];
                    [popoverItem setPopoverTouchBar:childTouchbar];
                }

                [filteredItems addObject:itemInfo.touchbarItem];
            }
        }
    }
    [filteredTouchbarItemOrder addObject:NSTouchBarItemIdentifierOtherItemsProxy];
    
    touchbarInfo.touchbar.defaultItemIdentifiers = filteredTouchbarItemOrder;
    touchbarInfo.touchbar.templateItems = filteredItems;
    return touchbarInfo.touchbar;
}

- (NSTouchBar *)makeTouchBar
{
    return [self makeTouchBarOn:touchbarInfo];
}

#endif

@end // MMVimController


@implementation MMVimController (Private)

- (void)doProcessInputQueue:(NSArray *)queue
{
    NSMutableArray *delayQueue = nil;

    unsigned i, count = [queue count];
    if (count % 2) {
        ASLogWarn(@"Uneven number of components (%d) in command queue.  "
                  "Skipping...", count);
        return;
    }

    for (i = 0; i < count; i += 2) {
        NSData *value = [queue objectAtIndex:i];
        NSData *data = [queue objectAtIndex:i+1];

        int msgid = *((int*)[value bytes]);

        BOOL inDefaultMode = [[[NSRunLoop currentRunLoop] currentMode]
                                            isEqual:NSDefaultRunLoopMode];
        if (!inDefaultMode && isUnsafeMessage(msgid)) {
            // NOTE: Because we may be listening to DO messages in "event
            // tracking mode" we have to take extra care when doing things
            // like releasing view items (and other Cocoa objects).
            // Messages that may be potentially "unsafe" are delayed until
            // the run loop is back to default mode at which time they are
            // safe to call again.
            //   A problem with this approach is that it is hard to
            // classify which messages are unsafe.  As a rule of thumb, if
            // a message may release an object used by the Cocoa framework
            // (e.g. views) then the message should be considered unsafe.
            //   Delaying messages may have undesired side-effects since it
            // means that messages may not be processed in the order Vim
            // sent them, so beware.
            if (!delayQueue)
                delayQueue = [NSMutableArray array];

            ASLogDebug(@"Adding unsafe message '%s' to delay queue (mode=%@)",
                       MMVimMsgIDStrings[msgid],
                       [[NSRunLoop currentRunLoop] currentMode]);
            [delayQueue addObject:value];
            [delayQueue addObject:data];
        } else {
            [self handleMessage:msgid data:data];
        }
    }

    if (delayQueue) {
        ASLogDebug(@"    Flushing delay queue (%ld items)",
                   [delayQueue count]/2);
        [self performSelector:@selector(processInputQueue:)
                   withObject:delayQueue
                   afterDelay:0];
    }
}

- (void)handleMessage:(int)msgid data:(NSData *)data
{
    if (OpenWindowMsgID == msgid) {
        [windowController openWindow];
        if (!isPreloading) {
            [windowController presentWindow:nil];
        }
    } else if (BatchDrawMsgID == msgid) {
        [[[windowController vimView] textView] performBatchDrawWithData:data];
    } else if (SelectTabMsgID == msgid) {
#if 0   // NOTE: Tab selection is done inside updateTabsWithData:.
        const void *bytes = [data bytes];
        int idx = *((int*)bytes);
        [windowController selectTabWithIndex:idx];
#endif
    } else if (UpdateTabBarMsgID == msgid) {
        [windowController updateTabsWithData:data];
    } else if (ShowTabBarMsgID == msgid) {
        [windowController showTabBar:YES];
        [self sendMessage:BackingPropertiesChangedMsgID data:nil];
    } else if (HideTabBarMsgID == msgid) {
        [windowController showTabBar:NO];
        [self sendMessage:BackingPropertiesChangedMsgID data:nil];
    } else if (SetTextDimensionsMsgID == msgid || LiveResizeMsgID == msgid ||
            SetTextDimensionsNoResizeWindowMsgID == msgid ||
            SetTextDimensionsReplyMsgID == msgid) {
        const void *bytes = [data bytes];
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);

        // NOTE: When a resize message originated in the frontend, Vim
        // acknowledges it with a reply message.  When this happens the window
        // should not move (the frontend would already have moved the window).
        BOOL onScreen = SetTextDimensionsReplyMsgID!=msgid;
        
        BOOL keepGUISize = SetTextDimensionsNoResizeWindowMsgID == msgid;

        [windowController setTextDimensionsWithRows:rows
                                 columns:cols
                                  isLive:(LiveResizeMsgID==msgid)
                            keepGUISize:keepGUISize
                            keepOnScreen:onScreen];
    } else if (ResizeViewMsgID == msgid) {
        [windowController resizeView];
    } else if (SetWindowTitleMsgID == msgid) {
        const void *bytes = [data bytes];
        int len = *((int*)bytes);  bytes += sizeof(int);

        NSString *string = [[NSString alloc] initWithBytes:(void*)bytes
                length:len encoding:NSUTF8StringEncoding];

        [windowController setTitle:string];

        [string release];
    } else if (SetDocumentFilenameMsgID == msgid) {
        const void *bytes = [data bytes];
        int len = *((int*)bytes);  bytes += sizeof(int);

        if (len > 0) {
            NSString *filename = [[NSString alloc] initWithBytes:(void*)bytes
                    length:len encoding:NSUTF8StringEncoding];

            [windowController setDocumentFilename:filename];

            [filename release];
        } else {
            [windowController setDocumentFilename:@""];
        }
    } else if (AddMenuMsgID == msgid) {
        NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
        [self addMenuWithDescriptor:[attrs objectForKey:@"descriptor"]
                atIndex:[[attrs objectForKey:@"index"] intValue]];
    } else if (AddMenuItemMsgID == msgid) {
        NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
        [self addMenuItemWithDescriptor:[attrs objectForKey:@"descriptor"]
                      atIndex:[[attrs objectForKey:@"index"] intValue]
                          tip:[attrs objectForKey:@"tip"]
                         icon:[attrs objectForKey:@"icon"]
                keyEquivalent:[attrs objectForKey:@"keyEquivalent"]
                 modifierMask:[[attrs objectForKey:@"modifierMask"] intValue]
                       action:[attrs objectForKey:@"action"]
                  isAlternate:[[attrs objectForKey:@"isAlternate"] boolValue]];
    } else if (RemoveMenuItemMsgID == msgid) {
        NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
        [self removeMenuItemWithDescriptor:[attrs objectForKey:@"descriptor"]];
    } else if (EnableMenuItemMsgID == msgid) {
        NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
        [self enableMenuItemWithDescriptor:[attrs objectForKey:@"descriptor"]
                state:[[attrs objectForKey:@"enable"] boolValue]];
    } else if (UpdateMenuItemTooltipMsgID == msgid) {
        NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
        [self updateMenuItemTooltipWithDescriptor:[attrs objectForKey:@"descriptor"]
                                              tip:[attrs objectForKey:@"tip"]];
    } else if (ShowToolbarMsgID == msgid) {
        const void *bytes = [data bytes];
        int enable = *((int*)bytes);  bytes += sizeof(int);
        int flags = *((int*)bytes);

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
        int32_t ident = *((int32_t*)bytes);  bytes += sizeof(int32_t);
        int type = *((int*)bytes);

        [windowController createScrollbarWithIdentifier:ident type:type];
    } else if (DestroyScrollbarMsgID == msgid) {
        const void *bytes = [data bytes];
        int32_t ident = *((int32_t*)bytes);

        [windowController destroyScrollbarWithIdentifier:ident];
    } else if (ShowScrollbarMsgID == msgid) {
        const void *bytes = [data bytes];
        int32_t ident = *((int32_t*)bytes);  bytes += sizeof(int32_t);
        int visible = *((int*)bytes);

        [windowController showScrollbarWithIdentifier:ident state:visible];
    } else if (SetScrollbarPositionMsgID == msgid) {
        const void *bytes = [data bytes];
        int32_t ident = *((int32_t*)bytes);  bytes += sizeof(int32_t);
        int pos = *((int*)bytes);  bytes += sizeof(int);
        int len = *((int*)bytes);

        [windowController setScrollbarPosition:pos length:len
                                    identifier:ident];
    } else if (SetScrollbarThumbMsgID == msgid) {
        const void *bytes = [data bytes];
        int32_t ident = *((int32_t*)bytes);  bytes += sizeof(int32_t);
        float val = *((float*)bytes);  bytes += sizeof(float);
        float prop = *((float*)bytes);

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
        if (!font) {
            // This should only happen if the system default font has changed
            // name since MacVim was compiled in which case we fall back on
            // using the user fixed width font.
            ASLogInfo(@"Failed to load font '%@' / %f", name, size);
            font = [NSFont userFixedPitchFontOfSize:size];
        }

        [windowController setFont:font];
        [name release];
    } else if (SetWideFontMsgID == msgid) {
        const void *bytes = [data bytes];
        float size = *((float*)bytes);  bytes += sizeof(float);
        int len = *((int*)bytes);  bytes += sizeof(int);
        if (len > 0) {
            NSString *name = [[NSString alloc]
                    initWithBytes:(void*)bytes length:len
                         encoding:NSUTF8StringEncoding];
            NSFont *font = [NSFont fontWithName:name size:size];
            [windowController setWideFont:font];

            [name release];
        } else {
            [windowController setWideFont:nil];
        }
    } else if (SetDefaultColorsMsgID == msgid) {
        const void *bytes = [data bytes];
        unsigned bg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
        unsigned fg = *((unsigned*)bytes);
        NSColor *back = [NSColor colorWithArgbInt:bg];
        NSColor *fore = [NSColor colorWithRgbInt:fg];

        [windowController setDefaultColorsBackground:back foreground:fore];
    } else if (ExecuteActionMsgID == msgid) {
        const void *bytes = [data bytes];
        int len = *((int*)bytes);  bytes += sizeof(int);
        NSString *actionName = [[NSString alloc]
                initWithBytes:(void*)bytes length:len
                     encoding:NSUTF8StringEncoding];

        SEL sel = NSSelectorFromString(actionName);
        [NSApp sendAction:sel to:nil from:self];

        [actionName release];
    } else if (ShowPopupMenuMsgID == msgid) {
        NSDictionary *attrs = [NSDictionary dictionaryWithData:data];

        // The popup menu enters a modal loop so delay this call so that we
        // don't block inside processInputQueue:.
        [self performSelector:@selector(popupMenuWithAttributes:)
                   withObject:attrs
                   afterDelay:0];
    } else if (SetMouseShapeMsgID == msgid) {
        const void *bytes = [data bytes];
        int shape = *((int*)bytes);

        [windowController setMouseShape:shape];
    } else if (AdjustLinespaceMsgID == msgid) {
        const void *bytes = [data bytes];
        int linespace = *((int*)bytes);

        [windowController adjustLinespace:linespace];
    } else if (AdjustColumnspaceMsgID == msgid) {
        const void *bytes = [data bytes];
        int columnspace = *((int*)bytes);

        [windowController adjustColumnspace:columnspace];
    } else if (ActivateMsgID == msgid) {
        [NSApp activateIgnoringOtherApps:YES];
        [[windowController window] makeKeyAndOrderFront:self];
    } else if (SetServerNameMsgID == msgid) {
        NSString *name = [[NSString alloc] initWithData:data
                                               encoding:NSUTF8StringEncoding];
        [self setServerName:name];
        [name release];
    } else if (EnterFullScreenMsgID == msgid) {
        const void *bytes = [data bytes];
        int fuoptions = *((int*)bytes); bytes += sizeof(int);
        int bg = *((int*)bytes);
        NSColor *back = [NSColor colorWithArgbInt:bg];

        [windowController enterFullScreen:fuoptions backgroundColor:back];
    } else if (LeaveFullScreenMsgID == msgid) {
        [windowController leaveFullScreen];
    } else if (SetBuffersModifiedMsgID == msgid) {
        const void *bytes = [data bytes];
        // state < 0  <->  some buffer modified
        // state > 0  <->  current buffer modified
        int state = *((int*)bytes);

        // NOTE: The window controller tracks whether current buffer is
        // modified or not (and greys out the proxy icon as well as putting a
        // dot in the red "close button" if necessary).  The Vim controller
        // tracks whether any buffer has been modified (used to decide whether
        // to show a warning or not when quitting).
        //
        // TODO: Make 'hasModifiedBuffer' part of the Vim state?
        [windowController setBufferModified:(state > 0)];
        hasModifiedBuffer = (state != 0);
    } else if (SetPreEditPositionMsgID == msgid) {
        const int *dim = (const int*)[data bytes];
        [[[windowController vimView] textView] setPreEditRow:dim[0]
                                                      column:dim[1]];
    } else if (EnableAntialiasMsgID == msgid) {
        [[[windowController vimView] textView] setAntialias:YES];
    } else if (DisableAntialiasMsgID == msgid) {
        [[[windowController vimView] textView] setAntialias:NO];
    } else if (EnableLigaturesMsgID == msgid) {
        [[[windowController vimView] textView] setLigatures:YES];
    } else if (DisableLigaturesMsgID == msgid) {
        [[[windowController vimView] textView] setLigatures:NO];
    } else if (EnableThinStrokesMsgID == msgid) {
        [[[windowController vimView] textView] setThinStrokes:YES];
    } else if (DisableThinStrokesMsgID == msgid) {
        [[[windowController vimView] textView] setThinStrokes:NO];
    } else if (SetVimStateMsgID == msgid) {
        NSDictionary *dict = [NSDictionary dictionaryWithData:data];
        if (dict) {
            [vimState release];
            vimState = [dict retain];
        }
    } else if (CloseWindowMsgID == msgid) {
        [self scheduleClose];
    } else if (SetFullScreenColorMsgID == msgid) {
        const int *bg = (const int*)[data bytes];
        NSColor *color = [NSColor colorWithRgbInt:*bg];

        [windowController setFullScreenBackgroundColor:color];
    } else if (ShowFindReplaceDialogMsgID == msgid) {
        NSDictionary *dict = [NSDictionary dictionaryWithData:data];
        if (dict) {
            [[MMFindReplaceController sharedInstance]
                showWithText:[dict objectForKey:@"text"]
                       flags:[[dict objectForKey:@"flags"] intValue]];
        }
    } else if (ActivateKeyScriptMsgID == msgid) {
        [[[windowController vimView] textView] activateIm:YES];
    } else if (DeactivateKeyScriptMsgID == msgid) {
        [[[windowController vimView] textView] activateIm:NO];
    } else if (EnableImControlMsgID == msgid) {
        [[[windowController vimView] textView] setImControl:YES];
    } else if (DisableImControlMsgID == msgid) {
        [[[windowController vimView] textView] setImControl:NO];
    } else if (BrowseForFileMsgID == msgid) {
        NSDictionary *dict = [NSDictionary dictionaryWithData:data];
        if (dict)
            [self handleBrowseForFile:dict];
    } else if (ShowDialogMsgID == msgid) {
        [windowController runAfterWindowPresentedUsingBlock:^{
            NSDictionary *dict = [NSDictionary dictionaryWithData:data];
            if (dict)
                [self handleShowDialog:dict];
        }];
    } else if (DeleteSignMsgID == msgid) {
        NSDictionary *dict = [NSDictionary dictionaryWithData:data];
        if (dict)
            [self handleDeleteSign:dict];
    } else if (ZoomMsgID == msgid) {
        const void *bytes = [data bytes];
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);  bytes += sizeof(int);
        int state = *((int*)bytes);

        [windowController zoomWithRows:rows
                               columns:cols
                                 state:state];
    } else if (SetWindowPositionMsgID == msgid) {
        const void *bytes = [data bytes];
        int x = *((int*)bytes);  bytes += sizeof(int);
        int y = *((int*)bytes);

        // NOTE: Vim measures Y-coordinates from top of screen.
        NSRect frame = [[[windowController window] screen] frame];
        y = NSMaxY(frame) - y;

        [windowController setTopLeft:NSMakePoint(x,y)];
    } else if (SetTooltipMsgID == msgid) {
        id textView = [[windowController vimView] textView];
        NSDictionary *dict = [NSDictionary dictionaryWithData:data];
        NSString *toolTip = dict ? [dict objectForKey:@"toolTip"] : nil;
        if (toolTip && [toolTip length] > 0)
            [textView setToolTipAtMousePoint:toolTip];
        else
            [textView setToolTipAtMousePoint:nil];
    } else if (AddToMRUMsgID == msgid) {
        NSDictionary *dict = [NSDictionary dictionaryWithData:data];
        NSArray *filenames = dict ? [dict objectForKey:@"filenames"] : nil;
        if (filenames)
            [[NSDocumentController sharedDocumentController]
                                            noteNewRecentFilePaths:filenames];
    } else if (SetBackgroundOptionMsgID == msgid) {
        const void *bytes = [data bytes];
        int dark = *((int*)bytes);
        [windowController setBackgroundOption:dark];
    } else if (SetBlurRadiusMsgID == msgid) {
        const void *bytes = [data bytes];
        int radius = *((int*)bytes);
        [windowController setBlurRadius:radius];

    // IMPORTANT: When adding a new message, make sure to update
    // isUnsafeMessage() if necessary!
    } else {
        ASLogWarn(@"Unknown message received (msgid=%d)", msgid);
    }
}

- (void)savePanelDidEnd:(NSSavePanel *)panel code:(int)code
                context:(void *)context
{
    NSString *path = nil;
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10)
    if (code == NSModalResponseOK)
#else
    if (code == NSOKButton)
#endif
    {
        NSURL *url = [panel URL];
        if ([url isFileURL])
            path = [url path];
    }
    ASLogDebug(@"Open/save panel path=%@", path);

    // NOTE!  This causes the sheet animation to run its course BEFORE the rest
    // of this function is executed.  If we do not wait for the sheet to
    // disappear before continuing it can happen that the controller is
    // released from under us (i.e. we'll crash and burn) because this
    // animation is otherwise performed in the default run loop mode!
    [panel orderOut:self];

    // NOTE! setDialogReturn: is a synchronous call so set a proper timeout to
    // avoid waiting forever for it to finish.  We make this a synchronous call
    // so that we can be fairly certain that Vim doesn't think the dialog box
    // is still showing when MacVim has in fact already dismissed it.
    NSConnection *conn = [backendProxy connectionForProxy];
    NSTimeInterval oldTimeout = [conn requestTimeout];
    [conn setRequestTimeout:MMSetDialogReturnTimeout];

    @try {
        [backendProxy setDialogReturn:path];

        // Add file to the "Recent Files" menu (this ensures that files that
        // are opened/saved from a :browse command are added to this menu).
        if (path)
            [[NSDocumentController sharedDocumentController]
                                                noteNewRecentFilePath:path];
    }
    @catch (NSException *ex) {
        ASLogDebug(@"Exception: pid=%d id=%d reason=%@", pid, identifier, ex);
    }
    @finally {
        [conn setRequestTimeout:oldTimeout];
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

    ASLogDebug(@"Alert return=%@", ret);

    // NOTE!  This causes the sheet animation to run its course BEFORE the rest
    // of this function is executed.  If we do not wait for the sheet to
    // disappear before continuing it can happen that the controller is
    // released from under us (i.e. we'll crash and burn) because this
    // animation is otherwise performed in the default run loop mode!
    [[alert window] orderOut:self];

    @try {
        [backendProxy setDialogReturn:ret];
    }
    @catch (NSException *ex) {
        ASLogDebug(@"setDialogReturn: failed: pid=%d id=%d reason=%@",
                pid, identifier, ex);
    }
}

+ (bool) hasPopupPrefix: (NSString *) menuName
{
    return [menuName hasPrefix:MMPopUpMenuPrefix] || [menuName hasPrefix:MMUserPopUpMenuPrefix];
}

- (NSMenuItem *)menuItemForDescriptor:(NSArray *)desc
{
    if (!(desc && [desc count] > 0)) return nil;

    NSString *rootName = [desc objectAtIndex:0];
    bool popup = [MMVimController hasPopupPrefix:rootName];
    NSArray *rootItems =  popup ? popupMenuItems
                                : [mainMenu itemArray];

    NSMenuItem *item = nil;
    int i, count = [rootItems count];
    for (i = 0; i < count; ++i) {
        item = [rootItems objectAtIndex:i];
        if ([[item title] isEqual:rootName])
            break;
    }

    if (i == count) return nil;

    count = [desc count];
    for (i = 1; i < count; ++i) {
        item = [[item submenu] itemWithTitle:[desc objectAtIndex:i]];
        if (!item) return nil;
    }

    return item;
}

- (NSMenu *)parentMenuForDescriptor:(NSArray *)desc
{
    if (!(desc && [desc count] > 0)) return nil;

    NSString *rootName = [desc objectAtIndex:0];
    bool popup = [MMVimController hasPopupPrefix:rootName];
    NSArray *rootItems = popup ? popupMenuItems
                               : [mainMenu itemArray];

    NSMenu *menu = nil;
    int i, count = [rootItems count];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [rootItems objectAtIndex:i];
        if ([[item title] isEqual:rootName]) {
            menu = [item submenu];
            break;
        }
    }

    if (!menu) return nil;

    count = [desc count] - 1;
    for (i = 1; i < count; ++i) {
        NSMenuItem *item = [menu itemWithTitle:[desc objectAtIndex:i]];
        menu = [item submenu];
        if (!menu) return nil;
    }

    return menu;
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

    count = [mainMenu numberOfItems];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [mainMenu itemAtIndex:i];
        if ([title isEqual:[item title]])
            return [item submenu];
    }

    return nil;
}

- (void)addMenuWithDescriptor:(NSArray *)desc atIndex:(int)idx
{
    if (!(desc && [desc count] > 0 && idx >= 0)) return;

    NSString *rootName = [desc objectAtIndex:0];
    if ([rootName isEqual:MMToolbarMenuName]) {
        // The toolbar only has one menu, we take this as a hint to create a
        // toolbar, then we return.
        if (!toolbar) {
            // NOTE! Each toolbar must have a unique identifier, else each
            // window will have the same toolbar.
            NSString *ident = [NSString stringWithFormat:@"%d", identifier];
            toolbar = [[NSToolbar alloc] initWithIdentifier:ident];

            [toolbar setShowsBaselineSeparator:NO];
            [toolbar setDelegate:self];
            [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
            [toolbar setSizeMode:NSToolbarSizeModeSmall];

            [windowController setToolbar:toolbar];
        }

        return;
    }

    if ([rootName isEqual:MMTouchbarMenuName]) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
        if (NSClassFromString(@"NSTouchBar")) {
            if ([desc count] < 2) // Cannot be 1, as we need at least TouchBar.<menu_name>
                return;
            if ([desc count] >= 3) // Unfortunately currently Apple does not support nested popover's so we can only do one level nesting
                return;

            MMTouchBarInfo *submenuTouchbar = nil;
            if (![self touchBarItemForDescriptor:desc touchBar:&submenuTouchbar touchBarItem:nil]) {
                return;
            }
            // Icon is not supported for Touch Bar submenu for now, as "amenu" does not have a way of specifying "icon=<icon_path>" for submenus.
            NSString *title = [desc lastObject];
            [self addTouchbarItemWithLabel:title icon:nil tip:nil atIndex:idx isSubMenu:YES desc:desc atTouchBar:submenuTouchbar];
        }
#endif
        return;
    }

    if ([rootName isEqual:MMWinBarMenuName]) {
        // WinBar menus are completed handled within Vim windows. No need for GUI to do anything.
        return;
    }

    // This is either a main menu item or a popup menu item.
    NSString *title = [desc lastObject];
    NSMenuItem *item = [[NSMenuItem alloc] init];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];

    [item setTitle:title];
    [item setSubmenu:menu];

    NSMenu *parent = [self parentMenuForDescriptor:desc];
    const BOOL isPopup = [MMVimController hasPopupPrefix:rootName];
    if (!parent && isPopup) {
        if ([popupMenuItems count] <= idx) {
            [popupMenuItems addObject:item];
        } else {
            [popupMenuItems insertObject:item atIndex:idx];
        }
    } else {
        // If descriptor has no parent and its not a popup (or toolbar) menu,
        // then it must belong to main menu.
        if (!parent) {
            parent = mainMenu;
            idx += 1; // Main menu already has the application menu as the first item, so everything else must be shifted by one.
        }

        if ([parent numberOfItems] <= idx) {
            [parent addItem:item];
        } else {
            [parent insertItem:item atIndex:idx];
        }
    }

    [item release];
    [menu release];
    if (!isPopup)
        [[MMAppController sharedInstance] markMainMenuDirty:mainMenu];
}

- (void)addMenuItemWithDescriptor:(NSArray *)desc
                          atIndex:(int)idx
                              tip:(NSString *)tip
                             icon:(NSString *)icon
                    keyEquivalent:(NSString *)keyEquivalent
                     modifierMask:(int)modifierMask
                           action:(NSString *)action
                      isAlternate:(BOOL)isAlternate
{
    if (!(desc && [desc count] > 1 && idx >= 0)) return;

    NSString *title = [desc lastObject];
    NSString *rootName = [desc objectAtIndex:0];

    if ([rootName isEqual:MMToolbarMenuName]) {
        if (toolbar && [desc count] == 2)
            [self addToolbarItemWithLabel:title tip:tip icon:icon atIndex:idx];
        return;
    }
    if ([rootName isEqual:MMTouchbarMenuName]) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
        if ([desc count] >= 4) // Unfortunately currently Apple does not support nested popover's so we can only do one level nesting
            return;

        if (NSClassFromString(@"NSTouchBar")) {
            MMTouchBarInfo *submenuTouchbar = nil;
            if (![self touchBarItemForDescriptor:desc touchBar:&submenuTouchbar touchBarItem:nil]) {
                return;
            }

            [self addTouchbarItemWithLabel:title icon:icon tip:tip atIndex:idx isSubMenu:NO desc:desc atTouchBar:submenuTouchbar];
        }
#endif
        return;
    }
    if ([rootName isEqual:MMWinBarMenuName]) {
        // WinBar menus are completed handled within Vim windows. No need for GUI to do anything.
        return;
    }

    NSMenu *parent = [self parentMenuForDescriptor:desc];
    if (!parent) {
        ASLogWarn(@"Menu item '%@' has no parent",
                  [desc componentsJoinedByString:@"->"]);
        return;
    }

    NSMenuItem *item = nil;
    if (0 == [title length]
            || ([title hasPrefix:@"-"] && [title hasSuffix:@"-"])) {
        item = [NSMenuItem separatorItem];
        [item setTitle:title];
    } else {
        item = [[[NSMenuItem alloc] init] autorelease];
        [item setTitle:title];

        // Note: It is possible to set the action to a message that "doesn't
        // exist" without problems.  We take advantage of this when adding
        // "dummy items" e.g. when dealing with the "Recent Files" menu (in
        // which case a recentFilesDummy: action is set, although it is never
        // used).
        if ([action length] > 0)
            [item setAction:NSSelectorFromString(action)];
        else
            [item setAction:@selector(vimMenuItemAction:)];
        if ([tip length] > 0) [item setToolTip:tip];
        if ([keyEquivalent length] > 0) {
            [item setKeyEquivalent:keyEquivalent];
            [item setKeyEquivalentModifierMask:modifierMask];
        }
        [item setAlternate:isAlternate];

        // The tag is used to indicate whether Vim thinks a menu item should be
        // enabled or disabled.  By default Vim thinks menu items are enabled.
        [item setTag:1];
    }

    if ([parent numberOfItems] <= idx) {
        [parent addItem:item];
    } else {
        [parent insertItem:item atIndex:idx];
    }
    const BOOL isPopup = [MMVimController hasPopupPrefix:rootName];
    if (!isPopup)
        [[MMAppController sharedInstance] markMainMenuDirty:mainMenu];
}

- (void)removeMenuItemWithDescriptor:(NSArray *)desc
{
    if (!(desc && [desc count] > 0)) return;

    NSString *title = [desc lastObject];
    NSString *rootName = [desc objectAtIndex:0];
    if ([rootName isEqual:MMToolbarMenuName]) {
        if (toolbar) {
            // Only remove toolbar items, never actually remove the toolbar
            // itself or strange things may happen.
            if ([desc count] == 2) {
                NSUInteger idx = [toolbar indexOfItemWithItemIdentifier:title];
                if (idx != NSNotFound)
                    [toolbar removeItemAtIndex:idx];
            }
        }
        return;
    }
    if ([rootName isEqual:MMTouchbarMenuName]){
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
        if (NSClassFromString(@"NSTouchBar")) {
            MMTouchBarInfo *submenuTouchbar = nil;
            if (![self touchBarItemForDescriptor:desc touchBar:&submenuTouchbar touchBarItem:nil]) {
                return;
            }

            [[submenuTouchbar itemOrder] removeObject:title];
            [[submenuTouchbar itemDict] removeObjectForKey:title];
            [windowController setTouchBar:nil];
        }
#endif
        return;
    }
    NSMenuItem *item = [self menuItemForDescriptor:desc];
    if (!item) {
        ASLogWarn(@"Failed to remove menu item, descriptor not found: %@",
                  [desc componentsJoinedByString:@"->"]);
        return;
    }

    [item retain];

    if ([item menu] == [NSApp mainMenu] || ![item menu]) {
        // NOTE: To be on the safe side we try to remove the item from
        // both arrays (it is ok to call removeObject: even if an array
        // does not contain the object to remove).
        [popupMenuItems removeObject:item];
    }

    if ([item menu])
        [[item menu] removeItem:item];

    [item release];

    const BOOL isPopup = [MMVimController hasPopupPrefix:rootName];
    if (!isPopup)
        [[MMAppController sharedInstance] markMainMenuDirty:mainMenu];
}

- (void)enableMenuItemWithDescriptor:(NSArray *)desc state:(BOOL)on
{
    if (!(desc && [desc count] > 0)) return;

    NSString *rootName = [desc objectAtIndex:0];
    if ([rootName isEqual:MMToolbarMenuName]) {
        if (toolbar && [desc count] == 2) {
            NSString *title = [desc lastObject];
            [[toolbar itemWithItemIdentifier:title] setEnabled:on];
        }
        return;
    }

    if ([rootName isEqual:MMTouchbarMenuName]) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
        if (NSClassFromString(@"NSTouchBar")) {
            MMTouchBarItemInfo *touchbarItem = nil;
            if (![self touchBarItemForDescriptor:desc touchBar:nil touchBarItem:&touchbarItem]) {
                return;
            }
            [touchbarItem setEnabled:on];
            [windowController setTouchBar:nil];
        }
#endif
        return;
    }

    // Use tag to set whether item is enabled or disabled instead of
    // calling setEnabled:.  This way the menus can autoenable themselves
    // but at the same time Vim can set if a menu is enabled whenever it
    // wants to.
    [[self menuItemForDescriptor:desc] setTag:on];

    const BOOL isPopup = [MMVimController hasPopupPrefix:rootName];
    if (!isPopup)
        [[MMAppController sharedInstance] markMainMenuDirty:mainMenu];
}
    
- (void)updateMenuItemTooltipWithDescriptor:(NSArray *)desc
                                        tip:(NSString *)tip
{
    if (!(desc && [desc count] > 0)) return;
    
    NSString *rootName = [desc objectAtIndex:0];
    if ([rootName isEqual:MMToolbarMenuName]) {
        if (toolbar && [desc count] == 2) {
            NSString *title = [desc lastObject];
            [[toolbar itemWithItemIdentifier:title] setToolTip:tip];
        }
        return;
    }

    if ([rootName isEqual:MMTouchbarMenuName]) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
        if (NSClassFromString(@"NSTouchBar")) {
            MMTouchBarItemInfo *touchbarItem = nil;
            if (![self touchBarItemForDescriptor:desc touchBar:nil touchBarItem:&touchbarItem]) {
                return;
            }
            NSString *title = [desc lastObject];
            [self updateTouchbarItemLabel:title tip:tip atTouchBarItem:touchbarItem];
            [windowController setTouchBar:nil];
        }
#endif
        return;
    }

    [[self menuItemForDescriptor:desc] setToolTip:tip];

    const BOOL isPopup = [MMVimController hasPopupPrefix:rootName];
    if (!isPopup)
        [[MMAppController sharedInstance] markMainMenuDirty:mainMenu];
}

- (void)addToolbarItemToDictionaryWithLabel:(NSString *)title
                                    toolTip:(NSString *)tip
                                       icon:(NSString *)icon
{
    // If the item corresponds to a separator then do nothing, since it is
    // already defined by Cocoa.
    if (!title || [title isEqual:NSToolbarSeparatorItemIdentifier]
               || [title isEqual:NSToolbarSpaceItemIdentifier]
               || [title isEqual:NSToolbarFlexibleSpaceItemIdentifier])
        return;

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:title];
    [item setLabel:title];
    [item setToolTip:tip];
    [item setAction:@selector(vimToolbarItemAction:)];
    [item setAutovalidates:NO];

    NSImage *img = [NSImage imageNamed:icon];
    if (!img) {
        img = [[[NSImage alloc] initByReferencingFile:icon] autorelease];
        if (!(img && [img isValid]))
            img = nil;
    }
    if (!img) {
        ASLogNotice(@"Could not find image with name '%@' to use as toolbar"
            " image for identifier '%@';"
            " using default toolbar icon '%@' instead.",
            icon, title, MMDefaultToolbarImageName);

        img = [NSImage imageNamed:MMDefaultToolbarImageName];
    }

    [item setImage:img];

    [toolbarItemDict setObject:item forKey:title];

    [item release];
}

- (void)addToolbarItemWithLabel:(NSString *)label
                            tip:(NSString *)tip
                           icon:(NSString *)icon
                        atIndex:(int)idx
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

    [self addToolbarItemToDictionaryWithLabel:label toolTip:tip icon:icon];

    int maxIdx = [[toolbar items] count];
    if (maxIdx < idx) idx = maxIdx;

    [toolbar insertItemWithItemIdentifier:label atIndex:idx];
}
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
- (void)addTouchbarItemWithLabel:(NSString *)label
                            icon:(NSString *)icon
                             tip:(NSString *)tip
                         atIndex:(int)idx
                       isSubMenu:(BOOL)submenu
                            desc:(NSArray *)desc
                      atTouchBar:(MMTouchBarInfo *)touchbarInfo
{
    NSString *touchbarLabel = label;
    NSTouchBarItem *touchbarItem = nil;

    // Check for separator / special items first
    if ([label length] >= 2 && [label hasPrefix:@"-"]
                            && [label hasSuffix:@"-"]) {
        // The label begins and ends with '-'; decided which kind of separator
        // or special item it is by looking at the prefix.
        if ([label hasPrefix:@"-characterpicker"]) {
            touchbarLabel = NSTouchBarItemIdentifierCharacterPicker;
        }
        else if ([label hasPrefix:@"-space"]) {
            touchbarLabel = NSTouchBarItemIdentifierFixedSpaceSmall;
        } else if ([label hasPrefix:@"-flexspace"]) {
            touchbarLabel = NSTouchBarItemIdentifierFlexibleSpace;
        } else {
            touchbarLabel = NSTouchBarItemIdentifierFixedSpaceLarge;
        }
    } else if (submenu) {
        NSPopoverTouchBarItem *item = [[[NSPopoverTouchBarItem alloc] initWithIdentifier:label] autorelease];
        // Icons not supported for now until we find a way to send the information in from Vim
        [item setCollapsedRepresentationLabel:label];
        touchbarItem = item;
    } else {
        BOOL useTip = tip && [tip length] != 0;
        NSString *buttonTitle = useTip ? tip : label;
        MMTouchBarButton* button = [MMTouchBarButton buttonWithTitle:buttonTitle target:windowController action:@selector(vimTouchbarItemAction:)];
        [button setDesc:desc];
        NSCustomTouchBarItem *item =
            [[[NSCustomTouchBarItem alloc] initWithIdentifier:label] autorelease];
        NSImage *img = [NSImage imageNamed:icon];

        if (!img) {
            img = [[[NSImage alloc] initByReferencingFile:icon] autorelease];
            if (!(img && [img isValid]))
                img = nil;
        }
        if (img) {
            [button setImage: img];
            if (useTip) {
                // If the user has set a tooltip as label that means they always want to see it, so show both image and tooltip
                [button setImagePosition:NSImageLeft];
            } else {
                [button setImagePosition:NSImageOnly];
            }
        }

        [item setView:button];
        touchbarItem = item;
    }
    
    MMTouchBarItemInfo *touchbarItemInfo = [[[MMTouchBarItemInfo alloc] initWithItem:touchbarItem label:touchbarLabel] autorelease];
    if (submenu) {
        [touchbarItemInfo makeChildTouchBar];
    }
    [touchbarInfo.itemDict setObject:touchbarItemInfo forKey:label];

    int maxIdx = [touchbarInfo.itemOrder count];
    if (maxIdx < idx) idx = maxIdx;
    [touchbarInfo.itemOrder insertObject:label atIndex:idx];

    [windowController setTouchBar:nil];
}

- (void)updateTouchbarItemLabel:(NSString *)label
                            tip:(NSString *)tip
                 atTouchBarItem:(MMTouchBarItemInfo*)item
{
    // The logic here should match that in addTouchbarItemWithLabel: as otherwise we will
    // get weird results when adding/removing tooltips.
    BOOL useTip = tip && [tip length] != 0;
    NSString *buttonTitle = useTip ? tip : label;
    NSCustomTouchBarItem *touchbarItem = (NSCustomTouchBarItem*)item.touchbarItem;
    MMTouchBarButton *button = (MMTouchBarButton*)touchbarItem.view;
    [button setTitle:buttonTitle];
    if (button.image) {
        if (useTip) {
            [button setImagePosition:NSImageLeft];
        } else {
            [button setImagePosition:NSImageOnly];
        }
    } else {
        [button setImagePosition:NSNoImage];
    }
}

- (BOOL)touchBarItemForDescriptor:(NSArray *)desc
                         touchBar:(MMTouchBarInfo **)touchBarPtr
                     touchBarItem:(MMTouchBarItemInfo **)touchBarItemPtr
{
    MMTouchBarInfo *submenuTouchbar = touchbarInfo;
    for (int i = 1; i < [desc count] - 1; i++) {
        NSString *submenuName = [desc objectAtIndex:i];
        MMTouchBarItemInfo *submenu = [[submenuTouchbar itemDict] objectForKey:submenuName];
        if ([submenu childTouchbar]) {
            submenuTouchbar = [submenu childTouchbar];
        } else {
            ASLogWarn(@"No Touch Bar submenu with id '%@'", submenuName);
            return NO;
        }
    }
    if (touchBarPtr)
        *touchBarPtr = submenuTouchbar;
    if (touchBarItemPtr)
        *touchBarItemPtr = [[submenuTouchbar itemDict] objectForKey:[desc lastObject]];
    return YES;
}
#endif
- (void)popupMenuWithDescriptor:(NSArray *)desc
                          atRow:(NSNumber *)row
                         column:(NSNumber *)col
{
    NSMenu *menu = [[self menuItemForDescriptor:desc] submenu];
    if (!menu) return;

    id textView = [[windowController vimView] textView];
    NSPoint pt;
    if (row && col) {
        // TODO: Let textView convert (row,col) to NSPoint.
        int r = [row intValue];
        int c = [col intValue];
        NSSize cellSize = [textView cellSize];
        pt = NSMakePoint((c+1)*cellSize.width, (r+1)*cellSize.height);
        pt = [textView convertPoint:pt toView:nil];
    } else {
        pt = [[windowController window] mouseLocationOutsideOfEventStream];
    }

    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
                           location:pt
                      modifierFlags:0
                          timestamp:0
                       windowNumber:[[windowController window] windowNumber]
                            context:nil
                        eventNumber:0
                         clickCount:0
                           pressure:1.0];

    [NSMenu popUpContextMenu:menu withEvent:event forView:textView];
}

- (void)popupMenuWithAttributes:(NSDictionary *)attrs
{
    if (!attrs) return;

    [self popupMenuWithDescriptor:[attrs objectForKey:@"descriptor"]
                            atRow:[attrs objectForKey:@"row"]
                           column:[attrs objectForKey:@"column"]];
}

- (void)connectionDidDie:(NSNotification *)notification
{
    ASLogDebug(@"%@", notification);
    [self scheduleClose];
}

- (void)scheduleClose
{
    ASLogDebug(@"pid=%d id=%d", pid, identifier);

    // NOTE!  This message can arrive at pretty much anytime, e.g. while
    // the run loop is the 'event tracking' mode.  This means that Cocoa may
    // well be in the middle of processing some message while this message is
    // received.  If we were to remove the vim controller straight away we may
    // free objects that Cocoa is currently using (e.g. view objects).  The
    // following call ensures that the vim controller is not released until the
    // run loop is back in the 'default' mode.
    // Also, since the app may be multithreaded (e.g. as a result of showing
    // the open panel) we have to ensure this call happens on the main thread,
    // else there is a race condition that may lead to a crash.
    [[MMAppController sharedInstance]
            performSelectorOnMainThread:@selector(removeVimController:)
                             withObject:self
                          waitUntilDone:NO
                                  modes:[NSArray arrayWithObject:
                                         NSDefaultRunLoopMode]];
}

// NSSavePanel delegate
- (void)panel:(id)sender willExpand:(BOOL)expanding
{
    // Show or hide the "show hidden files" button
    if (expanding) {
        [sender setAccessoryView:showHiddenFilesView()];
    } else {
        [sender setShowsHiddenFiles:NO];
        [sender setAccessoryView:nil];
    }
}

- (void)handleBrowseForFile:(NSDictionary *)attr
{
    if (!isInitialized) return;

    NSString *dir = [attr objectForKey:@"dir"];
    BOOL saving = [[attr objectForKey:@"saving"] boolValue];
    BOOL browsedir = [[attr objectForKey:@"browsedir"] boolValue];

    if (!dir) {
        // 'dir == nil' means: set dir to the pwd of the Vim process, or let
        // open dialog decide (depending on the below user default).
        BOOL trackPwd = [[NSUserDefaults standardUserDefaults]
                boolForKey:MMDialogsTrackPwdKey];
        if (trackPwd)
            dir = [vimState objectForKey:@"pwd"];
    }

    dir = [dir stringByExpandingTildeInPath];
    NSURL *dirURL = dir ? [NSURL fileURLWithPath:dir isDirectory:YES] : nil;

    if (saving) {
        NSSavePanel *panel = [NSSavePanel savePanel];

        // The delegate will be notified when the panel is expanded at which
        // time we may hide/show the "show hidden files" button (this button is
        // always visible for the open panel since it is always expanded).
        [panel setDelegate:self];
        if ([panel isExpanded])
            [panel setAccessoryView:showHiddenFilesView()];
        if (dirURL)
            [panel setDirectoryURL:dirURL];

        [panel beginSheetModalForWindow:[windowController window]
                      completionHandler:^(NSInteger result) {
            [self savePanelDidEnd:panel code:result context:nil];
        }];
    } else {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setAllowsMultipleSelection:NO];
        [panel setAccessoryView:showHiddenFilesView()];

        if (browsedir) {
            [panel setCanChooseDirectories:YES];
            [panel setCanChooseFiles:NO];
        }

        if (dirURL)
            [panel setDirectoryURL:dirURL];

        [panel beginSheetModalForWindow:[windowController window]
                      completionHandler:^(NSInteger result) {
            [self savePanelDidEnd:panel code:result context:nil];
        }];
    }
}

- (void)handleShowDialog:(NSDictionary *)attr
{
    if (!isInitialized) return;

    NSArray *buttonTitles = [attr objectForKey:@"buttonTitles"];
    if (!(buttonTitles && [buttonTitles count])) return;

    int style = [[attr objectForKey:@"alertStyle"] intValue];
    NSString *message = [attr objectForKey:@"messageText"];
    NSString *text = [attr objectForKey:@"informativeText"];
    NSString *textFieldString = [attr objectForKey:@"textFieldString"];
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
                      modalDelegate:self];

    [alert release];
}

- (void)handleDeleteSign:(NSDictionary *)attr
{
    MMTextView *view = [[windowController vimView] textView];
    [view deleteSign:[attr objectForKey:@"imgName"]];
}

- (void)setToolTipDelay
{
    // HACK! NSToolTipManager is an AppKit private class.
    static Class TTM = nil;
    if (!TTM)
        TTM = NSClassFromString(@"NSToolTipManager");

    if (TTM) {
        [[TTM sharedToolTipManager] setInitialToolTipDelay:1e-6];
    } else {
        ASLogNotice(@"Failed to get NSToolTipManager");
    }
}

@end // MMVimController (Private)




@implementation MMAlert

- (void)dealloc
{
    ASLogDebug(@"");

    [textField release];  textField = nil;
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
{

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10
    [super beginSheetModalForWindow:window
                  completionHandler:^(NSModalResponse code) {
                      [delegate alertDidEnd:self code:code context:NULL];
                  }];
#else
    [super beginSheetModalForWindow:window
                      modalDelegate:delegate
                     didEndSelector:@selector(alertDidEnd:code:context:)
                        contextInfo:NULL];
#endif

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

#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_12
    
@implementation MMTouchBarInfo
    
- (id)init
{
    if (!(self = [super init])) {
        return nil;
    }

    _touchbar = [[NSTouchBar alloc] init];
    
    _itemDict = [[NSMutableDictionary alloc] init];
    _itemOrder = [[NSMutableArray alloc] init];
    return self;
}
    
- (void)dealloc
{
    [_touchbar release];  _touchbar = nil;

    [_itemDict release];  _itemDict = nil;
    [_itemOrder release];  _itemOrder = nil;
    [super dealloc];
}
    
@end // MMTouchBarInfo

@implementation MMTouchBarItemInfo

- (void)dealloc
{
    [_touchbarItem release];  _touchbarItem = nil;
    [_label release];  _label = nil;
    [_childTouchbar release];  _childTouchbar = nil;
    [super dealloc];
}
    
- (id)initWithItem:(NSTouchBarItem *)item label:(NSString *)label
{
    _touchbarItem = [item retain];
    _enabled = YES;
    _label = [label retain];
    return self;
}
    
- (void)setTouchBarItem:(NSTouchBarItem *)item
{
    _touchbarItem = item;
}
    
- (void)makeChildTouchBar
{
    _childTouchbar = [[MMTouchBarInfo alloc] init];
}

@end // MMTouchBarItemInfo
    
@implementation MMTouchBarButton
    
- (void)dealloc
{
    [_desc release];  _desc = nil;
    [super dealloc];
}
    
- (NSArray *)desc
{
    return _desc;
}
    
- (void)setDesc:(NSArray *)desc
{
    _desc = [desc retain];
}
    
@end // MMTouchBarButton
    
#endif


    static BOOL
isUnsafeMessage(int msgid)
{
    // Messages that may release Cocoa objects must be added to this list.  For
    // example, UpdateTabBarMsgID may delete NSTabViewItem objects so it goes
    // on this list.
    static int unsafeMessages[] = { // REASON MESSAGE IS ON THIS LIST:
        //OpenWindowMsgID,            // Changes lots of state
        UpdateTabBarMsgID,          // May delete NSTabViewItem
        RemoveMenuItemMsgID,        // Deletes NSMenuItem
        DestroyScrollbarMsgID,      // Deletes NSScroller
        ExecuteActionMsgID,         // Impossible to predict
        ShowPopupMenuMsgID,         // Enters modal loop
        ActivateMsgID,              // ?
        EnterFullScreenMsgID,       // Modifies delegate of window controller
        LeaveFullScreenMsgID,       // Modifies delegate of window controller
        CloseWindowMsgID,           // See note below
        BrowseForFileMsgID,         // Enters modal loop
        ShowDialogMsgID,            // Enters modal loop
    };

    // NOTE about CloseWindowMsgID: If this arrives at the same time as say
    // ExecuteActionMsgID, then the "execute" message will be lost due to it
    // being queued and handled after the "close" message has caused the
    // controller to cleanup...UNLESS we add CloseWindowMsgID to the list of
    // unsafe messages.  This is the _only_ reason it is on this list (since
    // all that happens in response to it is that we schedule another message
    // for later handling).

    int i, count = sizeof(unsafeMessages)/sizeof(unsafeMessages[0]);
    for (i = 0; i < count; ++i)
        if (msgid == unsafeMessages[i])
            return YES;

    return NO;
}
