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
- (NSImage*)findToolbarIcon:(NSString*)icon;
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

    // Use a random identifier. Currently, MMBackend connects using a public
    // NSConnection, which has security implications. Using random identifiers
    // make it much harder for third-party attacker to spoof.
    int secSuccess = SecRandomCopyBytes(kSecRandomDefault, sizeof(identifier), &identifier);
    if (secSuccess != errSecSuccess) {
        // Don't know what concrete reasons secure random would fail, but just
        // as a failsafe, use a less secure option.
        identifier = ((unsigned long)arc4random()) << 32 | (unsigned long)arc4random();
    }

    windowController =
        [[MMWindowController alloc] initWithVimController:self];
    backendProxy = [backend retain];
    popupMenuItems = [[NSMutableArray alloc] init];
    toolbarItemDict = [[NSMutableDictionary alloc] init];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
    if (AVAILABLE_MAC_OS_PATCH(10, 12, 2)) {
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

    [_systemFontNamesToAlias release];  _systemFontNamesToAlias = nil;

    [super dealloc];
}

/// This should only be called by MMAppController when it's doing an app quit.
/// We just wait for all Vim processes to terminate instad of individually
/// closing each MMVimController. We simply unset isInitialized to prevent it
/// from handling and sending messages to now invalid Vim connections.
- (void)uninitialize
{
    isInitialized = NO;
}

- (unsigned long)vimControllerId
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
    NSInteger layout = [ud integerForKey:MMOpenLayoutKey];
    if (layout < 0 || layout > MMLayoutTabs)
        layout = MMLayoutTabs;

    BOOL splitVert = [ud boolForKey:MMVerticalSplitKey];
    if (splitVert && MMLayoutHorizontalSplit == layout)
        layout = MMLayoutVerticalSplit;

    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:(int)layout], @"layout",
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
                          [NSNumber numberWithInt:(int)tabIndex + 1],    @"tabpage",
                          nil];
    
    [self sendMessage:OpenWithArgumentsMsgID data:[args dictionaryAsData]];
}

// This is called when a file is dragged on top of the tab bar but not a
// particular tab (e.g. the new tab button). We will open the file list similar
// to drag-and-dropped files.
- (void)filesDraggedToTabline:(NSArray *)filenames
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
    NSUInteger len = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
    if (len > 0 && len < INT_MAX) {
        NSMutableData *data = [NSMutableData data];
        int len_int = (int)len;

        [data appendBytes:&len_int length:sizeof(int)];
        [data appendBytes:[string UTF8String] length:len_int];

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
        ASLogDebug(@"processInput:data: failed: pid=%d id=%lu msg=%s reason=%@",
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
        ASLogDebug(@"processInput:data: failed: pid=%d id=%lu msg=%s reason=%@",
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
        ASLogDebug(@"evaluateExpression: failed: pid=%d id=%lu reason=%@",
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
        ASLogDebug(@"evaluateExpressionCocoa: failed: pid=%d id=%lu reason=%@",
                pid, identifier, ex);
        *errstr = [ex reason];
    }

    return eval;
}

- (BOOL)hasSelectedText
{
    BOOL hasSelectedText = NO;
    if (backendProxy) {
        @try {
            hasSelectedText = [backendProxy hasSelectedText];
        }
        @catch (NSException *ex) {
            ASLogDebug(@"hasSelectedText: failed: pid=%d reason=%@",
                    pid, ex);
        }
    }
    return hasSelectedText;
}

- (NSString *)selectedText
{
    NSString *selectedText = nil;
    if (backendProxy) {
        @try {
            selectedText = [backendProxy selectedText];
        }
        @catch (NSException *ex) {
            ASLogDebug(@"selectedText: failed: pid=%d reason=%@",
                    pid, ex);
        }
    }
    return selectedText;
}

- (void)replaceSelectedText:(NSString *)text
{
    if (backendProxy) {
        @try {
            [backendProxy replaceSelectedText:text];
        }
        @catch (NSException *ex) {
            ASLogDebug(@"replaceSelectedText: failed: pid=%d reason=%@",
                    pid, ex);
        }
    }
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

    _isHandlingInputQueue = YES;

    // NOTE: This method must not raise any exceptions (see comment in the
    // calling method).
    @try {
        [self doProcessInputQueue:queue];
        [windowController processInputQueueDidFinish];
    }
    @catch (NSException *ex) {
        ASLogDebug(@"Exception: pid=%d id=%lu reason=%@", pid, identifier, ex);
    }
    _isHandlingInputQueue = NO;
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

    unsigned i, count = (unsigned)[queue count];
    if (count % 2) {
        ASLogWarn(@"Uneven number of components (%u) in command queue.  "
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
    switch (msgid) {
        case OpenWindowMsgID:
        {
            [windowController openWindow];
            if (!isPreloading) {
                [windowController presentWindow:nil];
            }
        }
        break;
        case BatchDrawMsgID:
        {
            if ([windowController isRenderBlocked]) {
                // Drop all batch draw commands while blocked. If we end up
                // changing out mind later we will need to ask Vim to redraw.
                break;
            }
            [[[windowController vimView] textView] performBatchDrawWithData:data];
        }
        break;
        case SelectTabMsgID:
        {
    #if 0   // NOTE: Tab selection is done inside updateTabsWithData:.
            const void *bytes = [data bytes];
            int idx = *((int*)bytes);
            [windowController selectTabWithIndex:idx];
    #endif
        }
        break;
        case UpdateTabBarMsgID:
        {
            [windowController updateTabsWithData:data];
        }
        break;
        case ShowTabBarMsgID:
        {
            [windowController showTabline:YES];
        }
        break;
        case HideTabBarMsgID:
        {
            [windowController showTabline:NO];
        }
        break;

        case SetTextDimensionsMsgID:
        case LiveResizeMsgID:
        case SetTextDimensionsNoResizeWindowMsgID:
        case SetTextDimensionsReplyMsgID:
        {
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
        }
        break;

        case ResizeViewMsgID:
        {
            // This is sent when Vim wants MacVim to resize Vim to fit
            // everything within the GUI window, usually because go+=k is set.
            // Other gVim usually blocks on this but for MacVim it is async
            // to reduce synchronization points so we schedule a resize for
            // later. We ask to block any render from happening until we are
            // done resizing to avoid a momentary annoying flicker.
            [windowController resizeVimViewBlockRender];
        }
        break;
        case SetWindowTitleMsgID:
        {
            const void *bytes = [data bytes];
            int len = *((int*)bytes);  bytes += sizeof(int);

            NSString *string = [[NSString alloc] initWithBytes:(void*)bytes
                    length:len encoding:NSUTF8StringEncoding];

            [windowController setTitle:string];

            [string release];
        }
        break;
        case SetDocumentFilenameMsgID:
        {
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
        }
        break;
        case AddMenuMsgID:
        {
            NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
            [self addMenuWithDescriptor:[attrs objectForKey:@"descriptor"]
                    atIndex:[[attrs objectForKey:@"index"] intValue]];
        }
        break;
        case AddMenuItemMsgID:
        {
            NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
            [self addMenuItemWithDescriptor:[attrs objectForKey:@"descriptor"]
                          atIndex:[[attrs objectForKey:@"index"] intValue]
                              tip:[attrs objectForKey:@"tip"]
                             icon:[attrs objectForKey:@"icon"]
                    keyEquivalent:[attrs objectForKey:@"keyEquivalent"]
                     modifierMask:[[attrs objectForKey:@"modifierMask"] intValue]
                           action:[attrs objectForKey:@"action"]
                      isAlternate:[[attrs objectForKey:@"isAlternate"] boolValue]];
        }
        break;
        case RemoveMenuItemMsgID:
        {
            NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
            [self removeMenuItemWithDescriptor:[attrs objectForKey:@"descriptor"]];
        }
        break;
        case EnableMenuItemMsgID:
        {
            NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
            [self enableMenuItemWithDescriptor:[attrs objectForKey:@"descriptor"]
                    state:[[attrs objectForKey:@"enable"] boolValue]];
        }
        break;
        case UpdateMenuItemTooltipMsgID:
        {
            NSDictionary *attrs = [NSDictionary dictionaryWithData:data];
            [self updateMenuItemTooltipWithDescriptor:[attrs objectForKey:@"descriptor"]
                                                  tip:[attrs objectForKey:@"tip"]];
        }
        break;
        case ShowToolbarMsgID:
        {
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
        }
        break;
        case CreateScrollbarMsgID:
        {
            const void *bytes = [data bytes];
            int32_t ident = *((int32_t*)bytes);  bytes += sizeof(int32_t);
            int type = *((int*)bytes);

            [windowController createScrollbarWithIdentifier:ident type:type];
        }
        break;
        case DestroyScrollbarMsgID:
        {
            const void *bytes = [data bytes];
            int32_t ident = *((int32_t*)bytes);

            [windowController destroyScrollbarWithIdentifier:ident];
        }
        break;
        case ShowScrollbarMsgID:
        {
            const void *bytes = [data bytes];
            int32_t ident = *((int32_t*)bytes);  bytes += sizeof(int32_t);
            int visible = *((int*)bytes);

            [windowController showScrollbarWithIdentifier:ident state:visible];
        }
        break;
        case SetScrollbarPositionMsgID:
        {
            const void *bytes = [data bytes];
            int32_t ident = *((int32_t*)bytes);  bytes += sizeof(int32_t);
            int pos = *((int*)bytes);  bytes += sizeof(int);
            int len = *((int*)bytes);

            [windowController setScrollbarPosition:pos length:len
                                        identifier:ident];
        }
        break;
        case SetScrollbarThumbMsgID:
        {
            const void *bytes = [data bytes];
            int32_t ident = *((int32_t*)bytes);  bytes += sizeof(int32_t);
            float val = *((float*)bytes);  bytes += sizeof(float);
            float prop = *((float*)bytes);

            [windowController setScrollbarThumbValue:val proportion:prop
                                          identifier:ident];
        }
        break;
        case SetFontMsgID:
        {
            const void *bytes = [data bytes];
            float size = *((float*)bytes);  bytes += sizeof(float);
            int len = *((int*)bytes);  bytes += sizeof(int);
            NSString *name = [[NSString alloc]
                    initWithBytes:(void*)bytes length:len
                         encoding:NSUTF8StringEncoding];
            NSFont *font = nil;
            if ([name hasPrefix:MMSystemFontAlias]) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_15
                if (@available(macos 10.15, *)) {
                    NSFontWeight fontWeight = NSFontWeightRegular;
                    if (name.length > MMSystemFontAlias.length) {
                        const NSRange cmpRange = NSMakeRange(MMSystemFontAlias.length, name.length - MMSystemFontAlias.length);
                        if ([name compare:@"UltraLight" options:NSCaseInsensitiveSearch range:cmpRange] == NSOrderedSame)
                            fontWeight = NSFontWeightUltraLight;
                        else if ([name compare:@"Thin" options:NSCaseInsensitiveSearch range:cmpRange] == NSOrderedSame)
                            fontWeight = NSFontWeightThin;
                        else if ([name compare:@"Light" options:NSCaseInsensitiveSearch range:cmpRange] == NSOrderedSame)
                            fontWeight = NSFontWeightLight;
                        else if ([name compare:@"Regular" options:NSCaseInsensitiveSearch range:cmpRange] == NSOrderedSame)
                            fontWeight = NSFontWeightRegular;
                        else if ([name compare:@"Medium" options:NSCaseInsensitiveSearch range:cmpRange] == NSOrderedSame)
                            fontWeight = NSFontWeightMedium;
                        else if ([name compare:@"Semibold" options:NSCaseInsensitiveSearch range:cmpRange] == NSOrderedSame)
                            fontWeight = NSFontWeightSemibold;
                        else if ([name compare:@"Bold" options:NSCaseInsensitiveSearch range:cmpRange] == NSOrderedSame)
                            fontWeight = NSFontWeightBold;
                        else if ([name compare:@"Heavy" options:NSCaseInsensitiveSearch range:cmpRange] == NSOrderedSame)
                            fontWeight = NSFontWeightHeavy;
                        else if ([name compare:@"Black" options:NSCaseInsensitiveSearch range:cmpRange] == NSOrderedSame)
                            fontWeight = NSFontWeightBlack;
                    }
                    font = [NSFont monospacedSystemFontOfSize:size weight:fontWeight];

                    // We cache the internal name -> user-facing alias mapping
                    // to allow fontSizeUp/Down actions to be able to retain
                    // the user-facing font name in 'guifont'.
                    if (_systemFontNamesToAlias == nil) {
                        _systemFontNamesToAlias = [[NSMutableDictionary alloc] initWithCapacity:9];
                    }
                    _systemFontNamesToAlias[font.fontName] = name;
                }
                else
#endif
                {
                    // Fallback to Menlo on older macOS versions that don't support the system monospace font API
                    font = [NSFont fontWithName:@"Menlo-Regular" size:size];
                }
            }
            else {
                font = [NSFont fontWithName:name size:size];
            }
            if (!font) {
                // This should only happen if the system default font has changed
                // name since MacVim was compiled in which case we fall back on
                // using the user fixed width font.
                ASLogInfo(@"Failed to load font '%@' / %f", name, size);
                font = [NSFont userFixedPitchFontOfSize:size];
            }

            [windowController setFont:font];

            // Notify Vim of updated cell size for getcellpixels(). Note that
            // this is asynchronous, which means getcellpixels() will not be
            // immediately reflected after setting guifont.
            NSSize cellsize = windowController.vimView.textView.cellSize;
            [self sendMessage:UpdateCellSizeMsgID
                         data:[NSData dataWithBytes:&cellsize length:sizeof(cellsize)]];

            [name release];
        }
        break;
        case SetWideFontMsgID:
        {
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
        }
        break;
        case SetTablineColorsMsgID:
        {
            const void *bytes = [data bytes];
            unsigned argbTabBg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            unsigned argbTabFg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            unsigned argbFillBg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            unsigned argbFillFg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            unsigned argbSelBg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            unsigned argbSelFg = *((unsigned*)bytes);  bytes += sizeof(unsigned);

            NSColor *tabBg = [NSColor colorWithRgbInt:argbTabBg];
            NSColor *tabFg = [NSColor colorWithRgbInt:argbTabFg];
            NSColor *fillBg = [NSColor colorWithRgbInt:argbFillBg];
            NSColor *fillFg = [NSColor colorWithRgbInt:argbFillFg];
            NSColor *selBg = [NSColor colorWithRgbInt:argbSelBg];
            NSColor *selFg = [NSColor colorWithRgbInt:argbSelFg];

            [windowController setTablineColorsTabBg:tabBg tabFg:tabFg fillBg:fillBg fillFg:fillFg selBg:selBg selFg:selFg];
        }
        break;
        case SetDefaultColorsMsgID:
        {
            const void *bytes = [data bytes];
            unsigned bg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            unsigned fg = *((unsigned*)bytes);
            NSColor *back = [NSColor colorWithArgbInt:bg];
            NSColor *fore = [NSColor colorWithRgbInt:fg];

            [windowController setDefaultColorsBackground:back foreground:fore];
        }
        break;
        case ExecuteActionMsgID:
        {
            const void *bytes = [data bytes];
            int len = *((int*)bytes);  bytes += sizeof(int);
            NSString *actionName = [[NSString alloc]
                    initWithBytes:(void*)bytes length:len
                         encoding:NSUTF8StringEncoding];

            SEL sel = NSSelectorFromString(actionName);
            [NSApp sendAction:sel to:nil from:self];

            [actionName release];
        }
        break;
        case ShowPopupMenuMsgID:
        {
            NSDictionary *attrs = [NSDictionary dictionaryWithData:data];

            // The popup menu enters a modal loop so delay this call so that we
            // don't block inside processInputQueue:.
            [self performSelector:@selector(popupMenuWithAttributes:)
                       withObject:attrs
                       afterDelay:0];
        }
        break;
        case SetMouseShapeMsgID:
        {
            const void *bytes = [data bytes];
            int shape = *((int*)bytes);

            [windowController setMouseShape:shape];
        }
        break;
        case AdjustLinespaceMsgID:
        {
            const void *bytes = [data bytes];
            int linespace = *((int*)bytes);

            [windowController adjustLinespace:linespace];
        }
        break;
        case AdjustColumnspaceMsgID:
        {
            const void *bytes = [data bytes];
            int columnspace = *((int*)bytes);

            [windowController adjustColumnspace:columnspace];
        }
        break;
        case ActivateMsgID:
        {
            [NSApp activateIgnoringOtherApps:YES];
            [[windowController window] makeKeyAndOrderFront:self];
        }
        break;
        case SetServerNameMsgID:
        {
            NSString *name = [[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding];
            [self setServerName:name];
            [name release];
        }
        break;
        case EnterFullScreenMsgID:
        {
            const void *bytes = [data bytes];
            int fuoptions = *((int*)bytes); bytes += sizeof(int);
            int bg = *((int*)bytes);
            NSColor *back = [NSColor colorWithArgbInt:bg];

            [windowController enterFullScreen:fuoptions backgroundColor:back];
        }
        break;
        case LeaveFullScreenMsgID:
        {
            [windowController leaveFullScreen];
        }
        break;
        case SetBuffersModifiedMsgID:
        {
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
        }
        break;
        case SetPreEditPositionMsgID:
        {
            const int *dim = (const int*)[data bytes];
            [[[windowController vimView] textView] setPreEditRow:dim[0]
                                                          column:dim[1]];
        }
        break;
        case EnableAntialiasMsgID:
        {
            [[[windowController vimView] textView] setAntialias:YES];
        }
        break;
        case DisableAntialiasMsgID:
        {
            [[[windowController vimView] textView] setAntialias:NO];
        }
        break;
        case EnableLigaturesMsgID:
        {
            [[[windowController vimView] textView] setLigatures:YES];
        }
        break;
        case DisableLigaturesMsgID:
        {
            [[[windowController vimView] textView] setLigatures:NO];
        }
        break;
        case EnableThinStrokesMsgID:
        {
            [[[windowController vimView] textView] setThinStrokes:YES];
        }
        break;
        case DisableThinStrokesMsgID:
        {
            [[[windowController vimView] textView] setThinStrokes:NO];
        }
        break;
        case SetVimStateMsgID:
        {
            NSDictionary *dict = [NSDictionary dictionaryWithData:data];
            if (dict) {
                [vimState release];
                vimState = [dict retain];
            }
        }
        break;
        case CloseWindowMsgID:
        {
            [self scheduleClose];
        }
        break;
        case SetFullScreenColorMsgID:
        {
            const int *bg = (const int*)[data bytes];
            NSColor *color = [NSColor colorWithArgbInt:*bg];

            [windowController setFullScreenBackgroundColor:color];
        }
        break;
        case ShowFindReplaceDialogMsgID:
        {
            NSDictionary *dict = [NSDictionary dictionaryWithData:data];
            if (dict) {
                [[MMFindReplaceController sharedInstance]
                    showWithText:[dict objectForKey:@"text"]
                           flags:[[dict objectForKey:@"flags"] intValue]];
            }
        }
        break;
        case ActivateKeyScriptMsgID:
        {
            [[[windowController vimView] textView] activateIm:YES];
        }
        break;
        case DeactivateKeyScriptMsgID:
        {
            [[[windowController vimView] textView] activateIm:NO];
        }
        break;
        case EnableImControlMsgID:
        {
            [[[windowController vimView] textView] setImControl:YES];
        }
        break;
        case DisableImControlMsgID:
        {
            [[[windowController vimView] textView] setImControl:NO];
        }
        break;
        case BrowseForFileMsgID:
        {
            NSDictionary *dict = [NSDictionary dictionaryWithData:data];
            if (dict)
                [self handleBrowseForFile:dict];
        }
        break;
        case ShowDialogMsgID:
        {
            [windowController runAfterWindowPresentedUsingBlock:^{
                NSDictionary *dict = [NSDictionary dictionaryWithData:data];
                if (dict)
                    [self handleShowDialog:dict];
            }];
        }
        break;
        case DeleteSignMsgID:
        {
            NSDictionary *dict = [NSDictionary dictionaryWithData:data];
            if (dict)
                [self handleDeleteSign:dict];
        }
        break;
        case ZoomMsgID:
        {
            const void *bytes = [data bytes];
            int rows = *((int*)bytes);  bytes += sizeof(int);
            int cols = *((int*)bytes);  bytes += sizeof(int);
            int state = *((int*)bytes);

            [windowController zoomWithRows:rows
                                   columns:cols
                                     state:state];
        }
        break;
        case SetWindowPositionMsgID:
        {
            const void *bytes = [data bytes];
            int x = *((int*)bytes);  bytes += sizeof(int);
            int y = *((int*)bytes);

            // NOTE: Vim measures Y-coordinates from top of screen.
            NSRect frame = [[[windowController window] screen] frame];
            y = NSMaxY(frame) - y;

            [windowController setTopLeft:NSMakePoint(x,y)];
        }
        break;
        case SetTooltipMsgID:
        {
            id textView = [[windowController vimView] textView];
            NSDictionary *dict = [NSDictionary dictionaryWithData:data];
            NSString *toolTip = dict ? [dict objectForKey:@"toolTip"] : nil;
            if (toolTip && [toolTip length] > 0)
                [textView setToolTipAtMousePoint:toolTip];
            else
                [textView setToolTipAtMousePoint:nil];
        }
        break;
        case AddToMRUMsgID:
        {
            NSDictionary *dict = [NSDictionary dictionaryWithData:data];
            NSArray *filenames = dict ? [dict objectForKey:@"filenames"] : nil;
            if (filenames)
                [[NSDocumentController sharedDocumentController]
                                                noteNewRecentFilePaths:filenames];
        }
        break;
        case SetBackgroundOptionMsgID:
        {
            const void *bytes = [data bytes];
            int dark = *((int*)bytes);
            [windowController setBackgroundOption:dark];
        }
        break;
        case SetBlurRadiusMsgID:
        {
            const void *bytes = [data bytes];
            int radius = *((int*)bytes);
            [windowController setBlurRadius:radius];
        }
        break;

        case ShowDefinitionMsgID:
        {
            const void* bytes = [data bytes];
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            NSUInteger len = *((NSUInteger*)bytes);  bytes += sizeof(NSUInteger);
            if (len > 0) {
                NSString *text = [[[NSString alloc] initWithBytes:(void*)bytes
                                                           length:len
                                                         encoding:NSUTF8StringEncoding] autorelease];

                // Convert from 1-indexed (Vim-style) to 0-indexed.
                row -= 1;
                col -= 1;

                MMTextView *view = [[windowController vimView] textView];
                [view showDefinitionForCustomString:text row:row col:col];
            }
        }
        break;

        // IMPORTANT: When adding a new message, make sure to update
        // isUnsafeMessage() if necessary!
        default:
        {
            ASLogWarn(@"Unknown message received (msgid=%d)", msgid);
        }
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
        ASLogDebug(@"Exception: pid=%d id=%lu reason=%@", pid, identifier, ex);
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
        ASLogDebug(@"setDialogReturn: failed: pid=%d id=%lu reason=%@",
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
    NSUInteger i, count;
    for (i = 0, count = rootItems.count; i < count; ++i) {
        item = [rootItems objectAtIndex:i];
        if ([[item title] isEqual:rootName])
            break;
    }

    if (i == count) return nil;

    for (i = 1, count = desc.count; i < count; ++i) {
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
    for (NSUInteger i = 0, count = rootItems.count; i < count; ++i) {
        NSMenuItem *item = [rootItems objectAtIndex:i];
        if ([[item title] isEqual:rootName]) {
            menu = [item submenu];
            break;
        }
    }

    if (!menu) return nil;

    for (NSUInteger i = 1, count = desc.count - 1; i < count; ++i) {
        NSMenuItem *item = [menu itemWithTitle:[desc objectAtIndex:i]];
        menu = [item submenu];
        if (!menu) return nil;
    }

    return menu;
}

- (NSMenu *)topLevelMenuForTitle:(NSString *)title
{
    // Search only the top-level menus.

    for (NSUInteger i = 0, count = popupMenuItems.count; i < count; ++i) {
        NSMenuItem *item = [popupMenuItems objectAtIndex:i];
        if ([title isEqual:[item title]])
            return [item submenu];
    }

    for (NSInteger i = 0, count = mainMenu.numberOfItems; i < count; ++i) {
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
            NSString *ident = [NSString stringWithFormat:@"%lu", identifier];
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
        if (AVAILABLE_MAC_OS_PATCH(10, 12, 2)) {
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

        if (AVAILABLE_MAC_OS_PATCH(10, 12, 2)) {
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

        NSImage *img = [self findToolbarIcon:icon];
        if (img) {
            [item setImage: img];
        }

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
        if (AVAILABLE_MAC_OS_PATCH(10, 12, 2)) {
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
        if (AVAILABLE_MAC_OS_PATCH(10, 12, 2)) {
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

    // We are using auto-enabling of menu items, where instead of directly
    // calling setEnabled:, we rely on validateMenuItem: callbacks in each
    // target to handle whether they want each menu item to be enabled or not.
    // This allows us to more easily control the enabled states of OS-injected
    // menu items if we want to. To remember whether we want to enable/disable
    // a Vim menu, we use item.tag to remember it. See each validateMenuItem:
    // implementation for details.
    //
    // See https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MenuList/Articles/EnablingMenuItems.html
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
        if (AVAILABLE_MAC_OS_PATCH(10, 12, 2)) {
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

/// Load an icon image for the provided name. This will try multiple things to find the best image that fits the name.
/// @param icon Can be an SF Symbol name (with colon-separated formatting strings), named system image, or just a file.
- (NSImage*)findToolbarIcon:(NSString*)icon
{
    if ([icon length] == 0) {
        return nil;
    }
    NSImage *img = nil;

    // Detect whether this is explicitly specified to be a template image, via a ":template" configuration suffix.
    BOOL template = NO;
    if ([icon hasSuffix:@":template"]) {
        icon = [icon substringToIndex:([icon length] - 9)];
        template = YES;
    }

    // Attempt 1: Load an SF Symbol image. This is first try because it's what Apple is pushing for and also likely
    //            what our users are going to want to use. We also allows for customization of the symbol.
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_11_0
    if (@available(macos 11.0, *)) {
        // All SF Symbol functionality were introduced in macOS 11.0.
        NSString *sfSymbolName = icon;

        BOOL monochrome = NO, hierarchical = NO, palette = NO, multicolor = NO;
        double variableValue = -1;

        if ([sfSymbolName rangeOfString:@":"].location != NSNotFound) {
            // We support using colon-separated strings to customize the symbol. First item is the icon name itself.
            NSArray<NSString*> *splitComponents = [sfSymbolName componentsSeparatedByString:@":"];
            sfSymbolName = splitComponents[0];

            for (NSUInteger i = 1, count = splitComponents.count; i < count; i++) {
                NSString *component = splitComponents[i];
                if ([component isEqualToString:@"monochrome"]) {
                    monochrome = YES;
                } else if ([component isEqualToString:@"hierarchical"]) {
                    hierarchical = YES;
                } else if ([component isEqualToString:@"palette"]) {
                    palette = YES;
                } else if ([component isEqualToString:@"multicolor"]) {
                    multicolor = YES;
                } else if ([component hasPrefix:@"variable-"]) {
                    NSString *variableString = [component substringFromIndex:9];
                    variableValue = [variableString floatValue];
                }
            }
        }

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_13_0
        if (@available(macos 13.0, *)) {
            if (variableValue >= 0.0 && variableValue <= 1.0) {
                img = [NSImage imageWithSystemSymbolName:sfSymbolName variableValue:variableValue accessibilityDescription:nil];
            }
        }
#endif // MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_13_0

        if (img == nil) {
            img = [NSImage imageWithSystemSymbolName:sfSymbolName accessibilityDescription:nil];
        }

        // Apply style customization to the symbol. This feature was added in macOS 12.
        if (img) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_12_0
            if (@available(macos 12.0, *)) {
                NSImageSymbolConfiguration *config = nil;
                if (monochrome) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_13_0
                    if (@available(macos 13.0, *)) {
                        config = [NSImageSymbolConfiguration configurationPreferringMonochrome];
                    }
#endif
                }
                if (hierarchical) {
                    NSImageSymbolConfiguration *config2;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_13_0
                    if (@available(macos 13.0, *))
                    {
                        // This version is preferred as it seems to set the color up automatically and therefore will use the correct ones.
                        config2 = [NSImageSymbolConfiguration configurationPreferringHierarchical];
                    }
                    else
#endif
                    {
                        // Just guess which color to use. AppKit doesn't really give you a color that you can pick so we just guess one.
                        config2 = [NSImageSymbolConfiguration configurationWithHierarchicalColor:NSColor.controlTextColor];
                    }
                    if (config) {
                        config = [config configurationByApplyingConfiguration:config2];
                    } else {
                        config = config2;
                    }
                }
                if (palette) {
                    // The palette colors aren't completely correct. It doesn't appear for there to be a good way to query the primary colors
                    // for Touch Bar, tool bar, etc, so we just use controlTextColor. It would be nice if Apple just provides a "Preferring"
                    // version of this API like the other ones.
                    NSImageSymbolConfiguration *config2 = [NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.controlTextColor, NSColor.controlAccentColor]];
                    if (config) {
                        config = [config configurationByApplyingConfiguration:config2];
                    } else {
                        config = config2;
                    }
                }
                if (multicolor) {
                    NSImageSymbolConfiguration *config2 = [NSImageSymbolConfiguration configurationPreferringMulticolor];
                    if (config) {
                        config = [config configurationByApplyingConfiguration:config2];
                    } else {
                        config = config2;
                    }
                }

                if (config) {
                    NSImage *img2 = [img imageWithSymbolConfiguration:config];
                    if (img2) {
                        img = img2;
                    }
                }
            }
#endif // MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_12_0

            // Just mark them as used so compiling on older SDKs won't complain about unused variables.
            (void)multicolor;
            (void)hierarchical;
            (void)palette;
            (void)variableValue;
        }
    }
#endif // MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_11_0

    // Attempt 2: Load a named image.
    if (!img) {
        img = [NSImage imageNamed:icon];
    }

    // Attempt 3: Load from a file.
    if (!img) {
        img = [[[NSImage alloc] initByReferencingFile:icon] autorelease];
        if (!(img && [img isValid]))
            img = nil;
    }

    if (img && template) {
        [img setTemplate:YES];
    }
    return img;
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

    NSImage *img = [self findToolbarIcon:icon];
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

    int maxIdx = (int)[[toolbar items] count];
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

        NSImage *img = [self findToolbarIcon:icon];;
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

    int maxIdx = (int)[touchbarInfo.itemOrder count];
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
    ASLogDebug(@"pid=%d id=%lu", pid, identifier);

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
            [self savePanelDidEnd:panel code:(int)result context:nil];
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
            [self savePanelDidEnd:panel code:(int)result context:nil];
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

    for (NSUInteger i = 0, count = buttonTitles.count; i < count; ++i) {
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
                      [delegate alertDidEnd:self code:(int)code context:NULL];
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
    for (NSUInteger i = 0, count = subviews.count; i < count; ++i) {
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
