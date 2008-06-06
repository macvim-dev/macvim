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
 * Coordinates input/output to/from backend.  Each MMBackend communicates
 * directly with a MMVimController.
 *
 * MMVimController does not deal with visual presentation.  Essentially it
 * should be able to run with no window present.
 *
 * Output from the backend is received in processCommandQueue:.  Input is sent
 * to the backend via sendMessage:data: or addVimInput:.  The latter allows
 * execution of arbitrary stings in the Vim process, much like the Vim script
 * function remote_send() does.  The messages that may be passed between
 * frontend and backend are defined in an enum in MacVim.h.
 */

#import "MMVimController.h"
#import "MMWindowController.h"
#import "MMAppController.h"
#import "MMVimView.h"
#import "MMTextView.h"
#import "MMAtsuiTextView.h"


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
- (void)addToolbarItemToDictionaryWithLabel:(NSString *)title
        toolTip:(NSString *)tip icon:(NSString *)icon;
- (void)addToolbarItemWithLabel:(NSString *)label
                          tip:(NSString *)tip icon:(NSString *)icon
                      atIndex:(int)idx;
- (void)popupMenuWithDescriptor:(NSArray *)desc
                          atRow:(NSNumber *)row
                         column:(NSNumber *)col;
- (void)connectionDidDie:(NSNotification *)notification;
#if MM_RESEND_LAST_FAILURE
- (void)resendTimerFired:(NSTimer *)timer;
#endif
@end


@interface NSToolbar (MMExtras)
- (int)indexOfItemWithItemIdentifier:(NSString *)identifier;
- (NSToolbarItem *)itemAtIndex:(int)idx;
- (NSToolbarItem *)itemWithItemIdentifier:(NSString *)identifier;
@end




@implementation MMVimController

- (id)initWithBackend:(id)backend pid:(int)processIdentifier
{
    if ((self = [super init])) {
        windowController =
            [[MMWindowController alloc] initWithVimController:self];
        backendProxy = [backend retain];
        sendQueue = [NSMutableArray new];
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

        // Copy the "MacVim menu" from the default main menu (we assume that it
        // is the first item on the default main menu).
        mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
        NSMenuItem *appMenuItem = [[[MMAppController sharedInstance]
                                            defaultMainMenu] itemAtIndex:0];
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
    [windowController release];  windowController = nil;

    [vimState release];  vimState = nil;
    [mainMenu release];  mainMenu = nil;

    [super dealloc];
}

- (MMWindowController *)windowController
{
    return windowController;
}

- (NSDictionary *)vimState
{
    return vimState;
}

- (NSMenu *)mainMenu
{
    return mainMenu;
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
    unsigned i, numberOfFiles = [filenames count];
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&force length:sizeof(BOOL)];
    [data appendBytes:&numberOfFiles length:sizeof(int)];

    for (i = 0; i < numberOfFiles; ++i) {
        NSString *file = [filenames objectAtIndex:i];
        int len = [file lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (len > 0) {
            ++len;  // include NUL as well
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

- (void)odbEdit:(NSArray *)filenames server:(OSType)theID path:(NSString *)path
          token:(NSAppleEventDescriptor *)token
{
    int len;
    unsigned i, numberOfFiles = [filenames count];
    NSMutableData *data = [NSMutableData data];

    if (0 == numberOfFiles || 0 == theID)
        return;

    [data appendBytes:&theID length:sizeof(theID)];

    if (path && [path length] > 0) {
        len = [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:[path UTF8String] length:len];
    } else {
        len = 0;
        [data appendBytes:&len length:sizeof(int)];
    }

    if (token) {
        DescType tokenType = [token descriptorType];
        NSData *tokenData = [token data];
        len = [tokenData length];

        [data appendBytes:&tokenType length:sizeof(tokenType)];
        [data appendBytes:&len length:sizeof(int)];
        if (len > 0)
            [data appendBytes:[tokenData bytes] length:len];
    } else {
        DescType tokenType = 0;
        len = 0;
        [data appendBytes:&tokenType length:sizeof(tokenType)];
        [data appendBytes:&len length:sizeof(int)];
    }

    [data appendBytes:&numberOfFiles length:sizeof(int)];

    for (i = 0; i < numberOfFiles; ++i) {
        NSString *file = [filenames objectAtIndex:i];
        len = [file lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (len > 0) {
            ++len;  // include NUL as well
            [data appendBytes:&len length:sizeof(unsigned)];
            [data appendBytes:[file UTF8String] length:len];
        }
    }

    [self sendMessage:ODBEditMsgID data:data];
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
    // Send a message with a timeout.  USE WITH EXTREME CAUTION!  Sending
    // messages in rapid succession with a timeout may cause MacVim to beach
    // ball forever.  In almost all circumstances sendMessage:data: should be
    // used instead.

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

- (void)addVimInput:(NSString *)string
{
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
    }
    @catch (NSException *ex) { /* do nothing */ }

    return eval;
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

    if (!dir) {
        // 'dir == nil' means: set dir to the pwd of the Vim process, or let
        // open dialog decide (depending on the below user default).
        BOOL trackPwd = [[NSUserDefaults standardUserDefaults]
                boolForKey:MMDialogsTrackPwdKey];
        if (trackPwd)
            dir = [vimState objectForKey:@"pwd"];
    }

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

- (oneway void)processCommandQueue:(in bycopy NSArray *)queue
{
    if (!isInitialized) return;

    @try {
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
            //NSLog(@"%s%s", _cmd, MessageStrings[msgid]);

            [self handleMessage:msgid data:data];
        }
        //NSLog(@"======== %s  END  ========", _cmd);

        [windowController processCommandQueueDidFinish];
    }
    @catch (NSException *e) {
        NSLog(@"Exception caught whilst processing command queue: %@", e);
    }

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
    //if (msgid != AddMenuMsgID && msgid != AddMenuItemMsgID)
    //    NSLog(@"%@ %s%s", [self className], _cmd, MessageStrings[msgid]);

    if (OpenVimWindowMsgID == msgid) {
        [windowController openWindow];
    } else if (BatchDrawMsgID == msgid) {
        [[[windowController vimView] textView] performBatchDrawWithData:data];
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
    } else if (SetTextDimensionsMsgID == msgid || LiveResizeMsgID == msgid) {
        const void *bytes = [data bytes];
        int rows = *((int*)bytes);  bytes += sizeof(int);
        int cols = *((int*)bytes);  bytes += sizeof(int);

        [windowController setTextDimensionsWithRows:rows columns:cols
                                               live:(LiveResizeMsgID==msgid)];
    } else if (SetWindowTitleMsgID == msgid) {
        const void *bytes = [data bytes];
        int len = *((int*)bytes);  bytes += sizeof(int);

        NSString *string = [[NSString alloc] initWithBytes:(void*)bytes
                length:len encoding:NSUTF8StringEncoding];

        [windowController setTitle:string];

        [string release];
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
        unsigned fg = *((unsigned*)bytes);  bytes += sizeof(unsigned);
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
        [self popupMenuWithDescriptor:[attrs objectForKey:@"descriptor"]
                                atRow:[attrs objectForKey:@"row"]
                               column:[attrs objectForKey:@"column"]];
    } else if (SetMouseShapeMsgID == msgid) {
        const void *bytes = [data bytes];
        int shape = *((int*)bytes);  bytes += sizeof(int);

        [windowController setMouseShape:shape];
    } else if (AdjustLinespaceMsgID == msgid) {
        const void *bytes = [data bytes];
        int linespace = *((int*)bytes);  bytes += sizeof(int);

        [windowController adjustLinespace:linespace];
    } else if (ActivateMsgID == msgid) {
        //NSLog(@"ActivateMsgID");
        [NSApp activateIgnoringOtherApps:YES];
        [[windowController window] makeKeyAndOrderFront:self];
    } else if (SetServerNameMsgID == msgid) {
        NSString *name = [[NSString alloc] initWithData:data
                                               encoding:NSUTF8StringEncoding];
        [self setServerName:name];
        [name release];
    } else if (EnterFullscreenMsgID == msgid) {
        const void *bytes = [data bytes];
        int fuoptions = *((int*)bytes); bytes += sizeof(int);
        int bg = *((int*)bytes);
        NSColor *back = [NSColor colorWithArgbInt:bg];

        [windowController enterFullscreen:fuoptions backgroundColor:back];
    } else if (LeaveFullscreenMsgID == msgid) {
        [windowController leaveFullscreen];
    } else if (BuffersNotModifiedMsgID == msgid) {
        [windowController setBuffersModified:NO];
    } else if (BuffersModifiedMsgID == msgid) {
        [windowController setBuffersModified:YES];
    } else if (SetPreEditPositionMsgID == msgid) {
        const int *dim = (const int*)[data bytes];
        [[[windowController vimView] textView] setPreEditRow:dim[0]
                                                      column:dim[1]];
    } else if (EnableAntialiasMsgID == msgid) {
        [[[windowController vimView] textView] setAntialias:YES];
    } else if (DisableAntialiasMsgID == msgid) {
        [[[windowController vimView] textView] setAntialias:NO];
    } else if (SetVimStateMsgID == msgid) {
        NSDictionary *dict = [NSDictionary dictionaryWithData:data];
        if (dict) {
            [vimState release];
            vimState = [dict retain];
        }
    } else {
        NSLog(@"WARNING: Unknown message received (msgid=%d)", msgid);
    }
}

- (void)savePanelDidEnd:(NSSavePanel *)panel code:(int)code
                context:(void *)context
{
    NSString *path = (code == NSOKButton) ? [panel filename] : nil;
    @try {
        [backendProxy setDialogReturn:path];

        // Add file to the "Recent Files" menu (this ensures that files that
        // are opened/saved from a :browse command are added to this menu).
        if (path)
            [[NSDocumentController sharedDocumentController]
                    noteNewRecentFilePath:path];
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

- (NSMenuItem *)menuItemForDescriptor:(NSArray *)desc
{
    if (!(desc && [desc count] > 0)) return nil;

    NSString *rootName = [desc objectAtIndex:0];
    NSArray *rootItems = [rootName hasPrefix:@"PopUp"] ? popupMenuItems
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
    NSArray *rootItems = [rootName hasPrefix:@"PopUp"] ? popupMenuItems
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
    if ([rootName isEqual:@"ToolBar"]) {
        // The toolbar only has one menu, we take this as a hint to create a
        // toolbar, then we return.
        if (!toolbar) {
            // NOTE! Each toolbar must have a unique identifier, else each
            // window will have the same toolbar.
            NSString *ident = [NSString stringWithFormat:@"%d", (int)self];
            toolbar = [[NSToolbar alloc] initWithIdentifier:ident];

            [toolbar setShowsBaselineSeparator:NO];
            [toolbar setDelegate:self];
            [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
            [toolbar setSizeMode:NSToolbarSizeModeSmall];

            [windowController setToolbar:toolbar];
        }

        return;
    }

    // This is either a main menu item or a popup menu item.
    NSString *title = [desc lastObject];
    NSMenuItem *item = [[NSMenuItem alloc] init];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];

    [item setTitle:title];
    [item setSubmenu:menu];

    NSMenu *parent = [self parentMenuForDescriptor:desc];
    if (!parent && [rootName hasPrefix:@"PopUp"]) {
        if ([popupMenuItems count] <= idx) {
            [popupMenuItems addObject:item];
        } else {
            [popupMenuItems insertObject:item atIndex:idx];
        }
    } else {
        // If descriptor has no parent and its not a popup (or toolbar) menu,
        // then it must belong to main menu.
        if (!parent) parent = mainMenu;

        if ([parent numberOfItems] <= idx) {
            [parent addItem:item];
        } else {
            [parent insertItem:item atIndex:idx];
        }
    }

    [item release];
    [menu release];
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

    if ([rootName isEqual:@"ToolBar"]) {
        if (toolbar && [desc count] == 2)
            [self addToolbarItemWithLabel:title tip:tip icon:icon atIndex:idx];
        return;
    }

    NSMenu *parent = [self parentMenuForDescriptor:desc];
    if (!parent) {
        NSLog(@"WARNING: Menu item '%@' has no parent",
                [desc componentsJoinedByString:@"->"]);
        return;
    }

    NSMenuItem *item = nil;
    if (0 == [title length]
            || ([title hasPrefix:@"-"] && [title hasSuffix:@"-"])) {
        item = [NSMenuItem separatorItem];
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
}

- (void)removeMenuItemWithDescriptor:(NSArray *)desc
{
    if (!(desc && [desc count] > 0)) return;

    NSString *title = [desc lastObject];
    NSString *rootName = [desc objectAtIndex:0];
    if ([rootName isEqual:@"ToolBar"]) {
        if (toolbar) {
            if ([desc count] == 1) {
                [windowController setToolbar:nil];
                [toolbar release];  toolbar = nil;
            } else if ([desc count] == 2) {
                int idx = [toolbar indexOfItemWithItemIdentifier:title];
                if (idx != NSNotFound)
                    [toolbar removeItemAtIndex:idx];
            }
        }
        return;
    }

    NSMenuItem *item = [self menuItemForDescriptor:desc];
    if (!item) {
        NSLog(@"Failed to remove menu item, descriptor not found: %@",
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
}

- (void)enableMenuItemWithDescriptor:(NSArray *)desc state:(BOOL)on
{
    if (!(desc && [desc count] > 0)) return;

    /*NSLog(@"%sable item %@", on ? "En" : "Dis",
            [desc componentsJoinedByString:@"->"]);*/

    NSString *rootName = [desc objectAtIndex:0];
    if ([rootName isEqual:@"ToolBar"]) {
        if (toolbar && [desc count] == 2) {
            NSString *title = [desc lastObject];
            [[toolbar itemWithItemIdentifier:title] setEnabled:on];
        }
    } else {
        // Use tag to set whether item is enabled or disabled instead of
        // calling setEnabled:.  This way the menus can autoenable themselves
        // but at the same time Vim can set if a menu is enabled whenever it
        // wants to.
        [[self menuItemForDescriptor:desc] setTag:on];
    }
}

- (void)addToolbarItemToDictionaryWithLabel:(NSString *)title
        toolTip:(NSString *)tip icon:(NSString *)icon
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

- (void)addToolbarItemWithLabel:(NSString *)label tip:(NSString
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

    [self addToolbarItemToDictionaryWithLabel:label toolTip:tip icon:icon];

    int maxIdx = [[toolbar items] count];
    if (maxIdx < idx) idx = maxIdx;

    [toolbar insertItemWithItemIdentifier:label atIndex:idx];
}

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

    NSEvent *event = [NSEvent mouseEventWithType:NSRightMouseDown
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

- (void)connectionDidDie:(NSNotification *)notification
{
    //NSLog(@"%@ %s%@", [self className], _cmd, notification);

    [self cleanup];

    // NOTE!  This causes the call to removeVimController: to be delayed.
    [[MMAppController sharedInstance]
            performSelectorOnMainThread:@selector(removeVimController:)
                             withObject:self waitUntilDone:NO];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ : isInitialized=%d inProcessCommandQueue=%d mainMenu=%@ popupMenuItems=%@ toolbar=%@", [self className], isInitialized, inProcessCommandQueue, mainMenu, popupMenuItems, toolbar];
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




@implementation NSToolbar (MMExtras)

- (int)indexOfItemWithItemIdentifier:(NSString *)identifier
{
    NSArray *items = [self items];
    int i, count = [items count];
    for (i = 0; i < count; ++i) {
        id item = [items objectAtIndex:i];
        if ([[item itemIdentifier] isEqual:identifier])
            return i;
    }

    return NSNotFound;
}

- (NSToolbarItem *)itemAtIndex:(int)idx
{
    NSArray *items = [self items];
    if (idx < 0 || idx >= [items count])
        return nil;

    return [items objectAtIndex:idx];
}

- (NSToolbarItem *)itemWithItemIdentifier:(NSString *)identifier
{
    int idx = [self indexOfItemWithItemIdentifier:identifier];
    return idx != NSNotFound ? [self itemAtIndex:idx] : nil;
}

@end // NSToolbar (MMExtras)




@implementation MMAlert
- (void)dealloc
{
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
