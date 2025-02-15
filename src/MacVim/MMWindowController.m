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
 * MMWindowController
 *
 * Handles resizing of windows, acts as an mediator between MMVimView and
 * MMVimController.
 *
 * Resizing in windowed mode:
 *
 * In windowed mode resizing can occur either due to the window frame changing
 * size (e.g. when the user drags to resize), or due to Vim changing the number
 * of (rows,columns).  The former case is dealt with by letting the vim view
 * fill the entire content view when the window has resized.  In the latter
 * case we ensure that vim view fits on the screen.
 *
 * The vim view notifies Vim if the number of (rows,columns) does not match the
 * current number whenver the view size is about to change.  Upon receiving a
 * dimension change message, Vim notifies the window controller and the window
 * resizes.  However, the window is never resized programmatically during a
 * live resize (in order to avoid jittering).
 *
 * The window size is constrained to not become too small during live resize,
 * and it is also constrained to always fit an integer number of
 * (rows,columns).
 *
 * In windowed mode we have to manually draw a tabline separator (due to bugs
 * in the way Cocoa deals with the toolbar separator) when certain conditions
 * are met.  The rules for this are as follows:
 *
 *   Tabline visible & Toolbar visible  =>  Separator visible
 *   =====================================================================
 *         NO        &        NO        =>  YES, if the window is textured
 *                                           NO, otherwise
 *         NO        &       YES        =>  YES
 *        YES        &        NO        =>   NO
 *        YES        &       YES        =>   NO
 *
 *
 * Resizing in custom full-screen mode:
 *
 * The window never resizes since it fills the screen, however the vim view may
 * change size, e.g. when the user types ":set lines=60", or when a scrollbar
 * is toggled.
 *
 * It is ensured that the vim view never becomes larger than the screen size
 * and that it always stays in the center of the screen.
 *
 *
 * Resizing in native full-screen mode (Mac OS X 10.7+):
 *
 * The window is always kept centered and resizing works more or less the same
 * way as in windowed mode.
 *  
 */

#import "MMAppController.h"
#import "MMFindReplaceController.h"
#import "MMFullScreenWindow.h"
#import "MMTextView.h"
#import "MMTypesetter.h"
#import "MMVimController.h"
#import "MMVimView.h"
#import "MMWindow.h"
#import "MMWindowController.h"
#import "Miscellaneous.h"
#import "MMTabline/MMTabline.h"


// These have to be the same as in option.h
#define FUOPT_MAXVERT         0x001
#define FUOPT_MAXHORZ         0x002
#define FUOPT_BGCOLOR_HLGROUP 0x004


@interface MMWindowController (Private)
- (NSSize)contentSize;
- (void)resizeWindowToFitContentSize:(NSSize)contentSize
                        keepOnScreen:(BOOL)onScreen;
- (NSSize)constrainContentSizeToScreenSize:(NSSize)contentSize;
- (NSRect)constrainFrame:(NSRect)frame;
- (void)updateTablineSeparator;
- (void)hideTablineSeparator:(BOOL)hide;
- (void)doFindNext:(BOOL)next;
- (void)updateToolbar;
- (void)applicationDidChangeScreenParameters:(NSNotification *)notification;
- (void)enterNativeFullScreen;
- (void)processAfterWindowPresentedQueue;
@end


@interface NSWindow (NSWindowPrivate)
// Note: This hack allows us to set content shadowing separately from
// the window shadow.  This is apparently what webkit and terminal do.
- (void)_setContentHasShadow:(BOOL)shadow; // new Tiger private method

// This is a private api that makes textured windows not have rounded corners.
// We want this on Leopard.
- (void)setBottomCornerRounded:(BOOL)rounded;
@end


@interface NSWindow (NSLeopardOnly)
// Note: These functions are Leopard-only, use -[NSObject respondsToSelector:]
// before calling them to make sure everything works on Tiger too.
- (void)setAutorecalculatesContentBorderThickness:(BOOL)b forEdge:(NSRectEdge)e;
- (void)setContentBorderThickness:(CGFloat)b forEdge:(NSRectEdge)e;
@end




@implementation MMWindowController

- (id)initWithVimController:(MMVimController *)controller
{
    backgroundDark = NO;
    
    unsigned styleMask = NSWindowStyleMaskTitled
                       | NSWindowStyleMaskClosable
                       | NSWindowStyleMaskMiniaturizable
                       | NSWindowStyleMaskResizable
                       | NSWindowStyleMaskUnifiedTitleAndToolbar;

    // Textured background has been a deprecated feature for a while. For a
    // while we kept using it to avoid showing a black line below the title
    // bar, but since macOS 11.0 this flag is completely ignored and
    // deprecated. Since it's hard to test older versions of macOS well, simply
    // preserve the existing functionality on older macOS versions, while not
    // setting it in macOS 11+.
    BOOL usingTexturedBackground = NO;
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_VERSION_11_0
    if (AVAILABLE_MAC_OS(11, 0)) {
        // Don't set the textured background because it's been completely deprecated and won't do anything.
    } else {
        styleMask = styleMask | NSWindowStyleMaskTexturedBackground;
        usingTexturedBackground = YES;
    }
#endif

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if ([userDefaults boolForKey:MMNoTitleBarWindowKey]) {
        // No title bar setting
        styleMask &= ~NSWindowStyleMaskTitled;
    }

    // NOTE: The content rect is only used the very first time MacVim is
    // started (or rather, when ~/Library/Preferences/org.vim.MacVim.plist does
    // not exist).  The chosen values will put the window somewhere near the
    // top and in the middle of a 1024x768 screen.
    MMWindow *win = [[MMWindow alloc]
            initWithContentRect:NSMakeRect(242,364,480,360)
                      styleMask:styleMask
                        backing:NSBackingStoreBuffered
                          defer:YES];
    [win autorelease];

    self = [super initWithWindow:win];
    if (!self) return nil;

    resizingDueToMove = NO;

    vimController = controller;
    decoratedWindow = [win retain];
    
    [self refreshApperanceMode];

    // Window cascading is handled by MMAppController.
    [self setShouldCascadeWindows:NO];

    // NOTE: Autoresizing is enabled for the content view, but only used
    // for the tabline separator.  The vim view must be resized manually
    // because of full-screen considerations, and because its size depends
    // on whether the tabline separator is visible or not.
    NSView *contentView = [win contentView];
    [contentView setAutoresizesSubviews:YES];
    contentView.wantsLayer = YES;

    vimView = [[MMVimView alloc] initWithFrame:[contentView frame]
                                 vimController:vimController];
    [vimView setAutoresizingMask:NSViewNotSizable];
    [contentView addSubview:vimView];

    [win setDelegate:self];
    [win setInitialFirstResponder:[vimView textView]];

    if (usingTexturedBackground) {
        // On Leopard, we want to have a textured window to have nice
        // looking tabs. But the textured window look implies rounded
        // corners, which looks really weird -- disable them. This is a
        // private api, though.
        if ([win respondsToSelector:@selector(setBottomCornerRounded:)])
            [win setBottomCornerRounded:NO];

        // When the tab bar is toggled, it changes color for the fraction
        // of a second, probably because vim sends us events in a strange
        // order, confusing appkit's content border heuristic for a short
        // while.  This can be worked around with these two methods.  There
        // might be a better way, but it's good enough.
        if ([win respondsToSelector:@selector(
                setAutorecalculatesContentBorderThickness:forEdge:)])
            [win setAutorecalculatesContentBorderThickness:NO
                                                   forEdge:NSMaxYEdge];
        if ([win respondsToSelector:
                @selector(setContentBorderThickness:forEdge:)])
            [win setContentBorderThickness:0 forEdge:NSMaxYEdge];
    }

    // Make us safe on pre-tiger OSX
    if ([win respondsToSelector:@selector(_setContentHasShadow:)])
        [win _setContentHasShadow:NO];
    
    // This adds the title bar full-screen button (which calls
    // toggleFullScreen:) and also populates the Window menu itmes for full
    // screen tiling. Even if we are using non-native full screen, we still set
    // this just so we have that button to override. We also intentionally
    // don't set the flag NSWindowCollectionBehaviorFullScreenDisallowsTiling
    // in that case because MacVim still works when macOS tries to do native
    // full screen tiling so we'll allow it.
    NSWindowCollectionBehavior wcb = win.collectionBehavior;
    wcb &= ~(NSWindowCollectionBehaviorFullScreenAuxiliary);
    wcb &= ~(NSWindowCollectionBehaviorFullScreenNone);
    wcb |= NSWindowCollectionBehaviorFullScreenPrimary;
    [win setCollectionBehavior:wcb];

    // This makes windows animate when opened
    if (![[NSUserDefaults standardUserDefaults]
          boolForKey:MMDisableLaunchAnimationKey]) {
        [win setAnimationBehavior:NSWindowAnimationBehaviorDocumentWindow];
    }

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 110000
    if (@available(macos 11.0, *)) {
        // macOS 11 will default to a unified toolbar style unless you use the new
        // toolbarStyle to tell it to use a "preference" style, which makes it look nice
        // and centered.
        win.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
    }
#endif

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationDidChangeScreenParameters:)
               name:NSApplicationDidChangeScreenParametersNotification
             object:NSApp];

    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [decoratedWindow release];  decoratedWindow = nil;
    [fullScreenWindow release]; fullScreenWindow = nil;
    [windowAutosaveKey release];  windowAutosaveKey = nil;
    [vimView release];  vimView = nil;
    [toolbar release];  toolbar = nil;
    // in case processAfterWindowPresentedQueue wasn't called
    [afterWindowPresentedQueue release];  afterWindowPresentedQueue = nil;
    [lastSetTitle release]; lastSetTitle = nil;
    [documentFilename release]; documentFilename = nil;

    [super dealloc];
}

- (NSString *)description
{
    NSString *format =
        @"%@ : setupDone=%d windowAutosaveKey=%@ vimController=%@";
    return [NSString stringWithFormat:format,
        [self className], setupDone, windowAutosaveKey, vimController];
}

- (MMVimController *)vimController
{
    return vimController;
}

- (MMVimView *)vimView
{
    return vimView;
}

- (MMFullScreenWindow *)fullScreenWindow
{
    return fullScreenWindow;
}

- (NSString *)windowAutosaveKey
{
    return windowAutosaveKey;
}

- (void)setWindowAutosaveKey:(NSString *)key
{
    [windowAutosaveKey autorelease];
    windowAutosaveKey = [key copy];
}

- (void)cleanup
{
    ASLogDebug(@"");

    // NOTE: Must set this before possibly leaving full-screen.
    setupDone = NO;

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    vimController = nil;

    [vimView removeFromSuperviewWithoutNeedingDisplay];
    [vimView cleanup];

    // It is feasible (though unlikely) that the user quits before the window
    // controller is released, make sure the edit flag is cleared so no warning
    // dialog is displayed.
    [decoratedWindow setDocumentEdited:NO];

    [[self window] close];
}

- (void)openWindow
{
    // Indicates that the window is ready to be displayed, but do not display
    // (or place) it yet -- that is done in showWindow.
    //
    // TODO: Remove this method?  Everything can probably be done in
    // presentWindow: but must carefully check dependencies on 'setupDone'
    // flag.
    setupDone = YES;
}

- (BOOL)presentWindow:(id)unused
{
    // If openWindow hasn't already been called then the window will be
    // displayed later.
    if (!setupDone) return NO;

    // Place the window now.  If there are multiple screens then a choice is
    // made as to which screen the window should be on.  This means that all
    // code that is executed before this point must not depend on the screen!

    [[MMAppController sharedInstance] windowControllerWillOpen:self];
    [self updateResizeConstraints:NO];
    [self resizeWindowToFitContentSize:[vimView desiredSize]
                          keepOnScreen:YES];


    [decoratedWindow makeKeyAndOrderFront:self];

    [decoratedWindow setBlurRadius:blurRadius];

    // Flag that the window is now placed on screen.  From now on it is OK for
    // code to depend on the screen state.  (Such as constraining views etc.)
    windowPresented = YES;

    // Process deferred blocks
    [self processAfterWindowPresentedQueue];

    if (fullScreenWindow) {
        // Delayed entering of full-screen happens here (a ":set fu" in a
        // GUIEnter auto command could cause this).
        [fullScreenWindow enterFullScreen];
        fullScreenEnabled = YES;
        if (blurRadius != 0)
            [MMWindow setBlurRadius:blurRadius onWindow:fullScreenWindow];
        shouldResizeVimView = YES;
    } else if (delayEnterFullScreen) {
        [self enterNativeFullScreen];
    }

    return YES;
}

- (void)moveWindowAcrossScreens:(NSPoint)topLeft
{
    // HACK! This method moves a window to a new origin and to a different
    // screen. This is primarily useful to avoid a scenario where such a move
    // will trigger a resize, even though the frame didn't actually change size.
    resizingDueToMove = YES;
    [[self window] setFrameTopLeftPoint:topLeft];
    resizingDueToMove = NO;
}

- (void)updateTabsWithData:(NSData *)data
{
    [vimView updateTabsWithData:data];
}

- (void)setTextDimensionsWithRows:(int)rows columns:(int)cols isLive:(BOOL)live
                      keepGUISize:(BOOL)keepGUISize
                     keepOnScreen:(BOOL)onScreen
{
    ASLogDebug(@"setTextDimensionsWithRows:%d columns:%d isLive:%d "
            "keepGUISize:%d "
            "keepOnScreen:%d", rows, cols, live, keepGUISize, onScreen);

    // NOTE: The only place where the (rows,columns) of the vim view are
    // modified is here and when entering/leaving full-screen.  Setting these
    // values have no immediate effect, the actual resizing of the view is done
    // in processInputQueueDidFinish.
    //
    // The 'live' flag indicates that this resize originated from a live
    // resize; it may very well happen that the view is no longer in live
    // resize when this message is received.  We refrain from changing the view
    // size when this flag is set, otherwise the window might jitter when the
    // user drags to resize the window.

    [vimView setDesiredRows:rows columns:cols];

    vimView.pendingLiveResize = NO;
    if (blockRenderUntilResize) {
        blockRenderUntilResize = NO;
        blockedRenderTextViewFrame = NSZeroRect;
        [vimView.textView setDrawRectOffset:NSZeroSize];
    }
    if (vimView.pendingLiveResizeQueued) {
        // There was already a new size queued while Vim was still processing
        // the last one. We need to immediately request another resize now that
        // Vim was done with the last message.
        //
        // This could happen if we are in the middle of rapid resize (e.g.
        // double-clicking on the border/corner of window), as we would fire
        // off a lot of LiveResizeMsgID messages where some will be
        // intentionally omitted to avoid swamping IPC as we rate limit it to
        // only one outstanding resize message at a time
        // inframeSizeMayHaveChanged:.
        vimView.pendingLiveResizeQueued = NO;
        [self resizeVimView];
    }

    if (setupDone && !live && !keepGUISize) {
        [self resizeVimViewAndWindow];
        keepOnScreen = onScreen;
    }

    // Autosave rows and columns.
    if (windowAutosaveKey && !fullScreenEnabled
            && rows > MMMinRows && cols > MMMinColumns) {
        // HACK! If tabline is visible then window will look about one line
        // higher than it actually is so increment rows by one before
        // autosaving dimension so that the approximate total window height is
        // autosaved.  This is particularly important when window is maximized
        // vertically; if we don't add a row here a new window will appear to
        // not be tall enough when the first window is showing the tabline.
        // A negative side-effect of this is that the window will redraw on
        // startup if the window is too tall to fit on screen (which happens
        // for example if 'showtabline=2').
        // TODO: Store window pixel dimensions instead of rows/columns?
        int autosaveRows = rows;
        if (![[vimView tabline] isHidden])
            ++autosaveRows;

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setInteger:autosaveRows forKey:MMAutosaveRowsKey];
        [ud setInteger:cols forKey:MMAutosaveColumnsKey];
        [ud synchronize];
    }
}

/// Resize the Vim view to its desired size based on number of rows/cols.
/// Ignores the window size and force the window to resize along with it.
- (void)resizeVimViewAndWindow
{
    if (setupDone)
    {
        shouldResizeVimView = YES;
        if (!vimController.isHandlingInputQueue)
            [self processInputQueueDidFinish];
    }
}

/// Resize the Vim view to match the GUI window size. This makes sure the GUI
/// doesn't change its size and fit everything within it to match. If the text
/// view ends up changing size, will send a message to Vim to resize itself.
- (void)resizeVimView
{
    if (setupDone)
    {
        shouldResizeVimView = YES;
        shouldKeepGUISize = YES;
        if (!vimController.isHandlingInputQueue)
            [self processInputQueueDidFinish];
    }
}

/// Resize the Vim view to match GUI window size, but also block any text
/// rendering from happening while we wait for Vim to be resized. This is used
/// to avoid any flickering as the current rendered texts are going to be
/// invalidated very soon as Vim will be resized and issue new draw commands.
///
/// This happens when say we have guioptions+=k and the user changes the font
/// or shows the tab bar.
- (void)resizeVimViewBlockRender
{
    if (setupDone)
    {
        shouldResizeVimView = YES;
        shouldKeepGUISize = YES;
        blockRenderUntilResize = YES;
        blockedRenderTextViewFrame = [self.window convertRectToScreen:
                                      [vimView convertRect:vimView.textView.frame
                                                    toView:nil]];
        if (!vimController.isHandlingInputQueue)
            [self processInputQueueDidFinish];
    }
}

- (BOOL)isRenderBlocked
{
    return blockRenderUntilResize;
}

- (void)zoomWithRows:(int)rows columns:(int)cols state:(int)state
{
    [self setTextDimensionsWithRows:rows
                            columns:cols
                             isLive:NO
                        keepGUISize:NO
                       keepOnScreen:YES];

    // NOTE: If state==0 then the window should be put in the non-zoomed
    // "user state".  That is, move the window back to the last stored
    // position.  If the window is in the zoomed state, the call to change the
    // dimensions above will also reposition the window to ensure it fits on
    // the screen.  However, since resizing of the window is delayed we also
    // delay repositioning so that both happen at the same time (this avoid
    // situations where the window woud appear to "jump").
    if (!state && !NSEqualPoints(NSZeroPoint, userTopLeft))
        shouldRestoreUserTopLeft = YES;
}

- (void)setTitle:(NSString *)title
{
    // Save the original title, if we haven't already.
    [title retain]; // retain the title first before release lastSetTitle, since you can call setTitle on lastSetTitle itself.
    [lastSetTitle release];
    lastSetTitle = title;
    
    // While in live resize the window title displays the dimensions of the
    // window so don't clobber this with the new title. We have already set
    // lastSetTitle above so once live resize is done we will set it back.
    if ([vimView inLiveResize]) {
        return;
    }

    if (!title)
        return;

    [decoratedWindow setTitle:title];
    if (fullScreenWindow) {
        [fullScreenWindow setTitle:title];

        // NOTE: Cocoa does not update the "Window" menu for borderless windows
        // so we have to do it manually.
        [NSApp changeWindowsItem:fullScreenWindow title:title filename:NO];
    }
}

/// Set the currently edited document's file path, passed in from Vim. Buffers with
/// no file paths will be passed in as empty strings.
- (void)setDocumentFilename:(NSString *)filename
{
    if (!filename)
        return;

    // Ensure file really exists or the path to the proxy icon will look weird.
    // If the file does not exists, don't show a proxy icon.
    if (![[NSFileManager defaultManager] fileExistsAtPath:filename])
        filename = @"";

    [filename retain];
    [documentFilename release];
    documentFilename = filename;

    [self updateDocumentFilename];
}

- (void)updateDocumentFilename
{
    if (documentFilename == nil)
        return;
    const bool showDocumentIcon = [[NSUserDefaults standardUserDefaults] boolForKey:MMTitlebarShowsDocumentIconKey];
    NSString *filename = showDocumentIcon ? documentFilename : @"";
    [decoratedWindow setRepresentedFilename:filename];
    [fullScreenWindow setRepresentedFilename:filename];

}

- (void)setToolbar:(NSToolbar *)theToolbar
{
    if (theToolbar != toolbar) {
        [toolbar release];
        toolbar = [theToolbar retain];
    }

    // NOTE: Toolbar must be set here or it won't work to show it later.
    [decoratedWindow setToolbar:toolbar];

    // HACK! Redirect the pill button so that we can ask Vim to hide the
    // toolbar.
    NSButton *pillButton = [decoratedWindow
            standardWindowButton:NSWindowToolbarButton];
    if (pillButton) {
        [pillButton setAction:@selector(toggleToolbar:)];
        [pillButton setTarget:self];
    }
}

- (void)createScrollbarWithIdentifier:(int32_t)ident type:(int)type
{
    [vimView createScrollbarWithIdentifier:ident type:type];
}

- (BOOL)destroyScrollbarWithIdentifier:(int32_t)ident
{
    BOOL scrollbarHidden = [vimView destroyScrollbarWithIdentifier:ident];   
    return scrollbarHidden;
}

- (BOOL)showScrollbarWithIdentifier:(int32_t)ident state:(BOOL)visible
{
    BOOL scrollbarToggled = [vimView showScrollbarWithIdentifier:ident
                                                           state:visible];
    return scrollbarToggled;
}

- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(int32_t)ident
{
    [vimView setScrollbarPosition:pos length:len identifier:ident];
}

- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(int32_t)ident
{
    [vimView setScrollbarThumbValue:val proportion:prop identifier:ident];
}

- (void)setBackgroundOption:(int)dark
{
    backgroundDark = dark;
    if ([[NSUserDefaults standardUserDefaults]
         integerForKey:MMAppearanceModeSelectionKey] == MMAppearanceModeSelectionBackgroundOption)
    {
        [self refreshApperanceMode];
    }
}

- (void)refreshApperanceMode
{
    // This function calculates what apperance mode (light vs dark mode and
    // titlebar settings) to use for this window, depending on what the user
    // has selected as a preference.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    
    // Transparent title bar setting
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_10
    if (AVAILABLE_MAC_OS(10, 10)) {
        decoratedWindow.titlebarAppearsTransparent = [ud boolForKey:MMTitlebarAppearsTransparentKey];
    }
#endif
    
    // No title bar setting
    if ([ud boolForKey:MMNoTitleBarWindowKey]) {
        [decoratedWindow setStyleMask:([decoratedWindow styleMask] & ~NSWindowStyleMaskTitled)];
    } else {
        [decoratedWindow setStyleMask:([decoratedWindow styleMask] | NSWindowStyleMaskTitled)];
    }

    // Whether to hide shadows or not
    if ([ud boolForKey:MMNoWindowShadowKey]) {
        [decoratedWindow setHasShadow:NO];
    } else {
        [decoratedWindow setHasShadow:YES];
    }

    // Title may have been lost if we hid the title-bar. Reset it.
    [self setTitle:lastSetTitle];
    [self updateDocumentFilename];

    // Dark mode only works on 10.14+ because that's when dark mode was
    // introduced.
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
    if (@available(macos 10.14, *)) {
        NSAppearance* desiredAppearance;
        switch ([ud integerForKey:MMAppearanceModeSelectionKey])
        {
            case MMAppearanceModeSelectionLight:
            {
                desiredAppearance = [NSAppearance appearanceNamed: NSAppearanceNameAqua];
                break;
            }
            case MMAppearanceModeSelectionDark:
            {
                desiredAppearance = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];
                break;
            }
            case MMAppearanceModeSelectionBackgroundOption:
            {
                if (backgroundDark) {
                    desiredAppearance = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];
                } else {
                    desiredAppearance = [NSAppearance appearanceNamed: NSAppearanceNameAqua];
                }
                break;
            }
            case MMAppearanceModeSelectionAuto:
            default:
            {
                // Use the system appearance. This will also auto-switch when OS changes mode.
                desiredAppearance = nil;
                break;
            }
        }
        
        decoratedWindow.appearance = desiredAppearance;
        fullScreenWindow.appearance = desiredAppearance;
    }
#endif
}

- (void)setTablineColorsTabBg:(NSColor *)tabBg tabFg:(NSColor *)tabFg
                       fillBg:(NSColor *)fillBg fillFg:(NSColor *)fillFg
                        selBg:(NSColor *)selBg selFg:(NSColor *)selFg
{
    [vimView setTablineColorsTabBg:tabBg tabFg:tabFg fillBg:fillBg fillFg:fillFg selBg:selBg selFg:selFg];

    if([[NSUserDefaults standardUserDefaults] boolForKey:MMWindowUseTabBackgroundColorKey]) {
        if (!vimView.tabline.hidden) {
            [self setWindowColorToTablineColor];
        }
    }
}

- (void)setWindowColorToTablineColor
{
    NSColor *defaultBg = vimView.textView.defaultBackgroundColor;
    NSColor *tablineColor = vimView.tabline.tablineFillBgColor;
    if (defaultBg.alphaComponent == 1.0) {
        [self setWindowBackgroundColor:tablineColor];
    } else {
        // Make sure 'transparency' Vim setting is preserved
        NSColor *colorWithAlpha = [tablineColor colorWithAlphaComponent:defaultBg.alphaComponent];
        [self setWindowBackgroundColor:colorWithAlpha];
    }
}

- (void)refreshTabProperties
{
    [vimView refreshTabProperties];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if([ud boolForKey:MMWindowUseTabBackgroundColorKey] && !vimView.tabline.hidden) {
        [self setWindowColorToTablineColor];
    } else {
        [self setWindowBackgroundColor:vimView.textView.defaultBackgroundColor];
    }
}

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore
{
    [vimView setDefaultColorsBackground:back foreground:fore];
    if([[NSUserDefaults standardUserDefaults] boolForKey:MMWindowUseTabBackgroundColorKey] &&
       !vimView.tabline.hidden)
    {
        [self setWindowColorToTablineColor];
    }
    else {
        [self setWindowBackgroundColor:back];
    }
}

- (void)setWindowBackgroundColor:(NSColor *)back
{
    // NOTE: This is called when the transparency changes so set the opacity
    // flag on the window here (should be faster if the window is opaque).
    const BOOL isOpaque = [back alphaComponent] == 1.0f;
    [decoratedWindow setOpaque:isOpaque];
    if (fullScreenWindow)
        [fullScreenWindow setOpaque:isOpaque];

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (@available(macos 10.14, *)) {
        // We usually don't really need to change the background color of the
        // window, but in 10.14+ we switched to using layer-backed drawing.
        // That's fine except when we set 'transparency' to non-zero. The alpha
        // is set on the text view, but it won't work if drawn on top of a solid
        // window, so we need to set a transparency color here to make the
        // transparency show through.
        if ([back alphaComponent] == 1) {
            // The window's background color affects the title bar tint and
            // if we are using a transparent title bar this color will show
            // up as well.
            // (Note that this won't play well in <=10.12 since we are using
            // the deprecated NSWindowStyleMaskTexturedBackground which makes
            // the titlebars transparent in those. Consider not using textured
            // background.)
            [decoratedWindow setBackgroundColor:back];

            // Note: We leave the full screen window's background color alone
            // because it is affected by 'fuoptions' instead. We just change the
            // alpha back to 1 in case it was changed previously because transparency
            // was set.
            if (fullScreenWindow) {
                [fullScreenWindow setBackgroundColor:
                 [fullScreenWindow.backgroundColor colorWithAlphaComponent:1]];
            }
        } else {
            // HACK! We really want a transparent background color to avoid
            // double blending the transparency, but setting alpha=0 leads to
            // the window border disappearing and also drag-to-resize becomes a
            // lot slower. So hack around it by making it virtually transparent.
            [decoratedWindow setBackgroundColor:[back colorWithAlphaComponent:0.001]];
            if (fullScreenWindow) {
                [fullScreenWindow setBackgroundColor:
                 [fullScreenWindow.backgroundColor colorWithAlphaComponent:0.001]];
            }
        }
    }
    else
#endif
    {
        // 10.13 or below. As noted above, the window flag
        // NSWindowStyleMaskTexturedBackground doesn't play well with window color,
        // but if we are toggling the titlebar transparent option, we need to set
        // the window background color in order the title bar to be tinted correctly.
        if ([[NSUserDefaults standardUserDefaults]
                boolForKey:MMTitlebarAppearsTransparentKey]) {
            if ([back alphaComponent] != 0) {
                [decoratedWindow setBackgroundColor:back];
            } else {
                // See above HACK for more details. Basically we cannot set a
                // color with 0 alpha or the window manager will give it a
                // different treatment.
                NSColor *clearColor = [back colorWithAlphaComponent:0.001];
                [decoratedWindow setBackgroundColor:clearColor];
            }
        }
    }
}

- (void)setFont:(NSFont *)font
{
    const NSWindow* mainWindow = [NSApp mainWindow];
    if (mainWindow && (mainWindow == decoratedWindow || mainWindow == fullScreenWindow)) {
        // Update the shared font manager with the new font, but only if this is the main window,
        // as the font manager is shared among all the windows.
        [[NSFontManager sharedFontManager] setSelectedFont:font isMultiple:NO];
    }

    [[vimView textView] setFont:font];
    [self updateResizeConstraints:NO];
}

- (void)setWideFont:(NSFont *)font
{
    [[vimView textView] setWideFont:font];
}

- (void)refreshFonts
{
    [[vimView textView] refreshFonts];
}

- (void)processInputQueueDidFinish
{
    // NOTE: Resizing is delayed until after all commands have been processed
    // since it often happens that more than one command will cause a resize.
    // If we were to immediately resize then the vim view size would jitter
    // (e.g.  hiding/showing scrollbars often happens several time in one
    // update).
    // Also delay toggling the toolbar until after scrollbars otherwise
    // problems arise when showing toolbar and scrollbar at the same time, i.e.
    // on "set go+=rT".

    // Update toolbar before resizing, since showing the toolbar may require
    // the view size to become smaller.
    if (updateToolbarFlag != 0)
        [self updateToolbar];

    const int oldTextViewRows = vimView.textView.pendingMaxRows;
    const int oldTextViewCols = vimView.textView.pendingMaxColumns;
    BOOL vimViewSizeChanged = NO;

    // NOTE: If the window has not been presented then we must avoid resizing
    // the views since it will cause them to be constrained to the screen which
    // has not yet been set!
    if (windowPresented && shouldResizeVimView) {
        shouldResizeVimView = NO;

        NSSize originalSize = [vimView frame].size;
        int rows = 0, cols = 0;

        // Setting 'guioptions+=k' will make shouldKeepGUISize true, which
        // means avoid resizing the window. Instead, resize the view instead
        // to keep the GUI window's size consistent.
        bool avoidWindowResize = shouldKeepGUISize || fullScreenEnabled;

        if (!avoidWindowResize) {
            NSSize contentSize = [vimView constrainRows:&rows columns:&cols
                                                 toSize:
                                  fullScreenWindow ? [fullScreenWindow frame].size :
                                  fullScreenEnabled ? desiredWindowSize :
                                  [self constrainContentSizeToScreenSize:[vimView desiredSize]]];

            [vimView setFrameSize:contentSize];

            [self resizeWindowToFitContentSize:contentSize
                                  keepOnScreen:keepOnScreen];
        }
        else {
            NSSize frameSize;
            if (fullScreenWindow) {
                // Non-native full screen mode.
                NSRect desiredFrame = [fullScreenWindow getDesiredFrame];
                frameSize = desiredFrame.size;
                [vimView setFrameOrigin:desiredFrame.origin]; // This will get set back to normal in MMFullScreenWindow::leaveFullScreen.
            } else if (fullScreenEnabled) {
                // Native full screen mode.
                frameSize = desiredWindowSize;
            } else {
                frameSize = originalSize;
            }
            [vimView setFrameSizeKeepGUISize:frameSize];
        }

        keepOnScreen = NO;
        shouldKeepGUISize = NO;

        vimViewSizeChanged = (vimView.textView.pendingMaxColumns != oldTextViewCols || vimView.textView.pendingMaxRows != oldTextViewRows);
    }

    if (blockRenderUntilResize) {
        if (vimViewSizeChanged) {
            const NSRect newTextViewFrame = [self.window convertRectToScreen:[vimView convertRect:vimView.textView.frame toView:nil]];

            // We are currently blocking all rendering to prevent flicker. If
            // the view frame moved (this happens if say the tab bar was shown
            // or hidden) the user will see a temporary flicker as the text
            // view was moved before Vim has updated us with new draw calls
            // to match the new size. To alleviate this, we temporarily apply
            // a drawing offset in the text view to counter the offset. To the
            // user it would appear that the text view hasn't moved at all.
            [vimView.textView setDrawRectOffset:
             NSMakeSize(NSMinX(blockedRenderTextViewFrame) - NSMinX(newTextViewFrame),
                        NSMaxY(blockedRenderTextViewFrame) - NSMaxY(newTextViewFrame))];
        } else {
            // We were blocking all rendering until Vim has been resized. However
            // in situations where we turned out to not need to resize Vim to
            // begin with, we need to remedy the situation as we dropped some
            // draw commands before. We simply ask Vim to redraw itself for
            // simplicity instead of caching all the draw commands for this.
            // This could happen if we changed guifont (which makes Vim think
            // we need to resize) but turned out we set it to the same font so
            // the grid size is the same and no need to resize.
            blockRenderUntilResize = NO;
            blockedRenderTextViewFrame = NSZeroRect;
            [vimView.textView setDrawRectOffset:NSZeroSize];

            [vimController sendMessage:RedrawMsgID data:nil];
        }
    }

    // Tell Vim view to update its scrollbars which is done once per update.
    // Do it last so whatever resizing we have done above will take effect
    // immediate too instead of waiting till next frame.
    [vimView finishPlaceScrollbars];

    // Work around a bug which affects macOS 10.14 and older.
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
    if (@available(macos 10.15, *)) {
    } else
#endif
    {
        // Ensure that the app waits until the next frame to commit the current
        // CATransaction. Without this, layer-backed views display as soon as
        // the thread returns to the event loop, potentially drawing *many*
        // times for a single screen update. The app correctly waits to draw
        // when a window needs display, so mark the window as needing display.
        self.window.viewsNeedDisplay = YES;
    }
}

- (void)showTabline:(BOOL)on
{
    [vimView showTabline:on];
    [self updateTablineSeparator];

    if([[NSUserDefaults standardUserDefaults] boolForKey:MMWindowUseTabBackgroundColorKey]) {
        if (on) {
            [self setWindowColorToTablineColor];
        } else {
            [self setWindowBackgroundColor:vimView.textView.defaultBackgroundColor];
        }
    }
}

- (void)showToolbar:(BOOL)on size:(int)size mode:(int)mode
{
    if (!toolbar) return;

    [toolbar setSizeMode:size];
    [toolbar setDisplayMode:mode];

    // Positive flag shows toolbar, negative hides it.
    updateToolbarFlag = on ? 1 : -1;

    // NOTE: If the window is not visible we must toggle the toolbar
    // immediately, otherwise "set go-=T" in .gvimrc will lead to the toolbar
    // showing its hide animation every time a new window is opened.  (See
    // processInputQueueDidFinish for the reason why we need to delay toggling
    // the toolbar when the window is visible.)
    //
    // Also, the delayed updateToolbar will have the correct shouldKeepGUISize
    // set when it's called, which is important for that function to respect
    // guioptions 'k'.
    if (![decoratedWindow isVisible])
        [self updateToolbar];
}

- (void)setMouseShape:(int)shape
{
    [[vimView textView] setMouseShape:shape];
}

- (void)adjustLinespace:(int)linespace
{
    if (vimView && [vimView textView]) {
        [[vimView textView] setLinespace:(float)linespace];
    }
}

- (void)adjustColumnspace:(int)columnspace
{
    if (vimView && [vimView textView]) {
        [[vimView textView] setColumnspace:(float)columnspace];
    }
}

- (void)liveResizeWillStart
{
    if (!setupDone) return;

    // NOTE: During live resize Cocoa goes into "event tracking mode".  We have
    // to add the backend connection to this mode in order for resize messages
    // from Vim to reach MacVim.  We do not wish to always listen to requests
    // in event tracking mode since then MacVim could receive DO messages at
    // unexpected times (e.g. when a key equivalent is pressed and the menu bar
    // momentarily lights up).
    id proxy = [vimController backendProxy];
    NSConnection *connection = [(NSDistantObject*)proxy connectionForProxy];
    [connection addRequestMode:NSEventTrackingRunLoopMode];
}

- (void)liveResizeDidEnd
{
    if (!setupDone) return;

    // See comment above regarding event tracking mode.
    id proxy = [vimController backendProxy];
    NSConnection *connection = [(NSDistantObject*)proxy connectionForProxy];
    [connection removeRequestMode:NSEventTrackingRunLoopMode];

    // If we saved the original title while resizing, restore it.
    if (lastSetTitle != nil) {
        [decoratedWindow setTitle:lastSetTitle];
    }

    if (vimView.pendingLiveResizeQueued) {
        // Similar to setTextDimensionsWithRows:, if there's still outstanding
        // resize message queued, we just immediately flush it here to make
        // sure Vim will get the most up-to-date size here when we are done
        // with live resizing to make sure we don't havae any stale sizes due
        // to rate limiting of IPC messages during live resizing..
        vimView.pendingLiveResizeQueued = NO;
        [self resizeVimView];
    }
}

- (void)setBlurRadius:(int)radius
{
    blurRadius = radius;
    if (windowPresented) { 
        [decoratedWindow setBlurRadius:radius];
        if (fullScreenWindow) {
            [MMWindow setBlurRadius:radius onWindow:fullScreenWindow];
        }
    }
}

- (void)enterFullScreen:(int)fuoptions backgroundColor:(NSColor *)back
{
    if (fullScreenEnabled) return;

    BOOL useNativeFullScreen = [[NSUserDefaults standardUserDefaults]
                                            boolForKey:MMNativeFullScreenKey];
    // Make sure user is not trying to use native full-screen on systems that
    // do not support it.
    if (![NSWindow instancesRespondToSelector:@selector(toggleFullScreen:)])
        useNativeFullScreen = NO;

    fullScreenOptions = fuoptions;
    if (useNativeFullScreen) {
        // Enter native full-screen mode.
        if (windowPresented) {
            [self enterNativeFullScreen];
        } else {
            delayEnterFullScreen = YES;
        }
    } else {
        // Enter custom full-screen mode.
        ASLogInfo(@"Enter custom full-screen");

        NSColor *fullscreenBg = back;

        // Copy option: 'transparency'
        //   See setDefaultColorsBackground: for why set a transparent
        //   background color, and why 0.001 instead of 0.
        if ([fullscreenBg alphaComponent] != 1) {
            fullscreenBg = [fullscreenBg colorWithAlphaComponent:0.001];
        }

        // fullScreenWindow could be non-nil here if this is called multiple
        // times during startup.
        [fullScreenWindow release];

        fullScreenWindow = [[MMFullScreenWindow alloc]
            initWithWindow:decoratedWindow view:vimView backgroundColor:fullscreenBg];
        [fullScreenWindow setOptions:fuoptions];
        [fullScreenWindow setRepresentedFilename:
            [decoratedWindow representedFilename]];

        // NOTE: Do not enter full-screen until the window has been presented
        // since we don't actually know which screen to use before then.  (The
        // custom full-screen can appear on any screen, as opposed to native
        // full-screen which always uses the main screen.)
        if (windowPresented) {
            const BOOL shouldPreventFlicker = (fuoptions & FUOPT_MAXVERT) && (fuoptions & FUOPT_MAXHORZ);
            if (shouldPreventFlicker) {
                // Prevent visual flickering by temporarily blocking new render
                // until Vim has updated/resized itself.
                // We don't do the same when exiting full screen because when
                // going in this direction the flickering is less noticeable
                // and it looks odd when the user sees a clamped view.
                // Also, don't do this if maxvert/maxhorz not set because it
                // looks quite off in that situation as Vim is supposed to move
                // visually.
                blockRenderUntilResize = YES;
                blockedRenderTextViewFrame = [decoratedWindow convertRectToScreen:
                                              [vimView convertRect:vimView.textView.frame
                                                            toView:nil]];
            }

            [fullScreenWindow enterFullScreen];
            fullScreenEnabled = YES;

            // Copy option: 'blurradius'
            //   Do this here instead of in full screen window since this
            //   involves calling private APIs and we want to limit where we
            //   do that.
            if (blurRadius != 0)
                [MMWindow setBlurRadius:blurRadius onWindow:fullScreenWindow];

            shouldResizeVimView = YES;
        }
    }
}

- (void)leaveFullScreen
{
    if (!fullScreenEnabled) return;

    ASLogInfo(@"Exit full-screen");

    fullScreenEnabled = NO;
    if (fullScreenWindow) {
        // Using custom full-screen
        [fullScreenWindow leaveFullScreen];
        [fullScreenWindow release];
        fullScreenWindow = nil;

        // View is always at (0,0) except in full screen where it gets set to
        // [fullScreenWindow getDesiredFrame].
        [self.vimView setFrameOrigin:NSZeroPoint];

        // Simply resize Vim view to fit within the original window size. Note
        // that this behavior is similar to guioption-k, even if it's not set
        // in Vim.
        [self.vimView setFrameSizeKeepGUISize:[self contentSize]];
    } else {
        // Using native full-screen
        // NOTE: fullScreenEnabled is used to detect if we enter full-screen
        // programatically and so must be set before calling
        // realToggleFullScreen:.
        NSParameterAssert(fullScreenEnabled == NO);
        [decoratedWindow realToggleFullScreen:self];
    }
}

/// Called when the window is in non-native full-screen mode and the user has
/// updated the background color.
- (void)setFullScreenBackgroundColor:(NSColor *)back
{
    if (fullScreenWindow)
        // See setDefaultColorsBackground: for why set a transparent
        // background color, and why 0.001 instead of 0.
        if ([back alphaComponent] != 1) {
            back = [back colorWithAlphaComponent:0.001];
        }

        [fullScreenWindow setBackgroundColor:back];
}

- (void)invFullScreen:(id)sender
{
    [vimController addVimInput:@"<C-\\><C-N>:set invfu<CR>"];
}

- (void)setBufferModified:(BOOL)mod
{
    // NOTE: We only set the document edited flag on the decorated window since
    // the custom full-screen window has no close button anyway.  (It also
    // saves us from keeping track of the flag in two different places.)
    [decoratedWindow setDocumentEdited:mod];
}

- (void)setTopLeft:(NSPoint)pt
{
    if (setupDone) {
        [decoratedWindow setFrameTopLeftPoint:pt];
    } else {
        // Window has not been "opened" yet (see openWindow:) but remember this
        // value to be used when the window opens.
        defaultTopLeft = pt;
    }
}

- (BOOL)getDefaultTopLeft:(NSPoint*)pt
{
    // A default top left point may be set in .[g]vimrc with the :winpos
    // command.  (If this has not been done the top left point will be the zero
    // point.)
    if (pt && !NSEqualPoints(defaultTopLeft, NSZeroPoint)) {
        *pt = defaultTopLeft;
        return YES;
    }

    return NO;
}


- (IBAction)addNewTab:(id)sender
{
    [vimView addNewTab:sender];
}

- (IBAction)toggleToolbar:(id)sender
{
    [vimController sendMessage:ToggleToolbarMsgID data:nil];
}

- (IBAction)performClose:(id)sender
{
    // NOTE: With the introduction of :macmenu it is possible to bind
    // File.Close to ":conf q" but at the same time have it send off the
    // performClose: action.  For this reason we no longer need the CloseMsgID
    // message.  However, we still need File.Close to send performClose:
    // otherwise Cmd-w will not work on dialogs.
    [self vimMenuItemAction:sender];
}

- (IBAction)findNext:(id)sender
{
    [self doFindNext:YES];
}

- (IBAction)findPrevious:(id)sender
{
    [self doFindNext:NO];
}

- (IBAction)useSelectionForFind:(id)sender
{
    [vimController sendMessage:UseSelectionForFindMsgID data:nil];
}

- (IBAction)vimMenuItemAction:(id)sender
{
    if (![sender isKindOfClass:[NSMenuItem class]]) return;

    // TODO: Make into category on NSMenuItem which returns descriptor.
    NSMenuItem *item = (NSMenuItem*)sender;
    NSMutableArray *desc = [NSMutableArray arrayWithObject:[item title]];

    NSMenu *menu = [item menu];
    while (menu) {
        [desc insertObject:[menu title] atIndex:0];
        menu = [menu supermenu];
    }

    // The "MainMenu" item is part of the Cocoa menu and should not be part of
    // the descriptor.
    if ([[desc objectAtIndex:0] isEqual:@"MainMenu"])
        [desc removeObjectAtIndex:0];

    NSDictionary *attrs = [NSDictionary dictionaryWithObject:desc
                                                      forKey:@"descriptor"];
    [vimController sendMessage:ExecuteMenuMsgID data:[attrs dictionaryAsData]];
}

- (IBAction)vimToolbarItemAction:(id)sender
{
    NSArray *desc = [NSArray arrayWithObjects:@"ToolBar", [sender label], nil];
    NSDictionary *attrs = [NSDictionary dictionaryWithObject:desc
                                                      forKey:@"descriptor"];
    [vimController sendMessage:ExecuteMenuMsgID data:[attrs dictionaryAsData]];
}

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
- (IBAction)vimTouchbarItemAction:(id)sender
{
    MMTouchBarButton *button = (MMTouchBarButton*)sender;
    NSArray *desc = [button desc];
    NSDictionary *attrs = [NSDictionary dictionaryWithObject:desc
                                                      forKey:@"descriptor"];
    [vimController sendMessage:ExecuteMenuMsgID data:[attrs dictionaryAsData]];
}
#endif

- (IBAction)fontSizeUp:(id)sender
{
    // This creates a new font and triggers text view's changeFont: callback
    [[NSFontManager sharedFontManager] modifyFont:
            [NSNumber numberWithInt:NSSizeUpFontAction]];
}

- (IBAction)fontSizeDown:(id)sender
{
    // This creates a new font and triggers text view's changeFont: callback
    [[NSFontManager sharedFontManager] modifyFont:
            [NSNumber numberWithInt:NSSizeDownFontAction]];
}

- (IBAction)findAndReplace:(id)sender
{
    NSInteger tag = [sender tag];
    MMFindReplaceController *fr = [MMFindReplaceController sharedInstance];
    int flags = 0;

    // NOTE: The 'flags' values must match the FRD_ defines in gui.h (except
    // for 0x100 which we use to indicate a backward search).
    switch (tag) {
        case 1: flags = 0x100; break;
        case 2: flags = 3; break;
        case 3: flags = 4; break;
    }

    if ([fr matchWord])
        flags |= 0x08;
    if (![fr ignoreCase])
        flags |= 0x10;

    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
            [fr findString],                @"find",
            [fr replaceString],             @"replace",
            [NSNumber numberWithInt:flags], @"flags",
            nil];

    [vimController sendMessage:FindReplaceMsgID data:[args dictionaryAsData]];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    // This class is a responsder class and this should get called when we have
    // a specific action that we implement exposed as a menu. As such just return
    // [item tag] and no need to worry about macOS-injected menus.
    return [item tag];
}

// -- NSWindow delegate ------------------------------------------------------

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    [[MMAppController sharedInstance] setMainMenu:[vimController mainMenu]];

    if ([vimView textView]) {
        // Update the shared font manager to always be set to the font of the main window.
        NSFontManager *fm = [NSFontManager sharedFontManager];
        [fm setSelectedFont:[[vimView textView] font] isMultiple:NO];
    }
}

- (void)windowDidBecomeKey:(NSNotificationCenter *)notification
{
    [vimController sendMessage:GotFocusMsgID data:nil];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    [vimController sendMessage:LostFocusMsgID data:nil];
}

- (BOOL)windowShouldClose:(id)sender
{
    // Don't close the window now; Instead let Vim decide whether to close the
    // window or not.
    [vimController sendMessage:VimShouldCloseMsgID data:nil];
    return NO;
}

- (void)windowDidMove:(NSNotification *)notification
{
    if (!setupDone)
        return;

    if (fullScreenEnabled) {
        // NOTE: The full-screen is not supposed to be able to be moved.  If we
        // do get here while in full-screen something unexpected happened (e.g.
        // the full-screen window was on an external display that got
        // unplugged).
        return;
    }

    NSRect frame = [decoratedWindow frame];
    NSPoint topLeft = { frame.origin.x, NSMaxY(frame) };
    if (windowAutosaveKey) {
        NSString *topLeftString = NSStringFromPoint(topLeft);

        [[NSUserDefaults standardUserDefaults]
            setObject:topLeftString forKey:windowAutosaveKey];
    }

    // NOTE: This method is called when the user drags the window, but not when
    // the top left point changes programmatically.
    // NOTE 2: Vim counts Y-coordinates from the top of the screen.
    int pos[2] = {
            (int)topLeft.x,
            (int)(NSMaxY([[decoratedWindow screen] frame]) - topLeft.y) };
    NSData *data = [NSData dataWithBytes:pos length:2*sizeof(int)];
    [vimController sendMessage:SetWindowPositionMsgID data:data];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize {
    desiredWindowSize = frameSize;
    return frameSize;
}

- (void)windowDidResize:(id)sender
{
    if (resizingDueToMove) {
        resizingDueToMove = NO;
        return;
    }

    if (!setupDone)
        return;

    // NOTE: Since we have no control over when the window may resize (Cocoa
    // may resize automatically) we simply set the view to fill the entire
    // window.  The vim view takes care of notifying Vim if the number of
    // (rows,columns) changed.
    // Calling setFrameSizeKeepGUISize: instead of setFrameSize: prevents a
    // degenerate case where frameSizeMayHaveChanged: ends up resizing the window
    // *again* causing windowDidResize: to be called.
    if (fullScreenEnabled && fullScreenWindow != nil) {
        // Non-native full screen mode is more complicated and needs to
        // re-layout the Vim view to properly account for the menu bar / notch,
        // and misc fuopt configuration.
        // This code is similar to what's done in processInputQueueDidFinish.
        NSRect desiredFrame = [fullScreenWindow getDesiredFrame];
        [vimView setFrameOrigin:desiredFrame.origin];
        [vimView setFrameSizeKeepGUISize:desiredFrame.size];
    }
    else {
        [vimView setFrameSizeKeepGUISize:[self contentSize]];
    }
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification
{
    ASLogDebug(@"");
    [vimController sendMessage:RedrawMsgID data:nil];
}

// This is not an NSWindow delegate method, our custom MMWindow class calls it
// instead of the usual windowWillUseStandardFrame:defaultFrame:.
- (IBAction)zoom:(id)sender
{
    NSScreen *screen = [decoratedWindow screen];
    if (!screen) {
        ASLogNotice(@"Window not on screen, zoom to main screen");
        screen = [NSScreen mainScreen];
        if (!screen) {
            ASLogNotice(@"No main screen, abort zoom");
            return;
        }
    }

    // Decide whether too zoom horizontally or not (always zoom vertically).
    NSEvent *event = [NSApp currentEvent];
    BOOL cmdLeftClick = [event type] == NSEventTypeLeftMouseUp &&
                        [event modifierFlags] & NSEventModifierFlagCommand;
    BOOL zoomBoth = [[NSUserDefaults standardUserDefaults]
                                                    boolForKey:MMZoomBothKey];
    zoomBoth = (zoomBoth && !cmdLeftClick) || (!zoomBoth && cmdLeftClick);

    // Figure out how many rows/columns can fit while zoomed.
    int rowsZoomed, colsZoomed;
    NSRect maxFrame = [screen visibleFrame];
    NSRect contentRect = [decoratedWindow contentRectForFrameRect:maxFrame];
    [vimView constrainRows:&rowsZoomed
                   columns:&colsZoomed
                    toSize:contentRect.size];

    int curRows, curCols;
    [[vimView textView] getMaxRows:&curRows columns:&curCols];

    int rows, cols;
    BOOL isZoomed = zoomBoth ? curRows >= rowsZoomed && curCols >= colsZoomed
                             : curRows >= rowsZoomed;
    if (isZoomed) {
        rows = userRows > 0 ? userRows : curRows;
        cols = userCols > 0 ? userCols : curCols;
    } else {
        rows = rowsZoomed;
        cols = zoomBoth ? colsZoomed : curCols;

        if (curRows+2 < rows || curCols+2 < cols) {
            // The window is being zoomed so save the current "user state".
            // Note that if the window does not enlarge by a 'significant'
            // number of rows/columns then we don't save the current state.
            // This is done to take into account toolbar/scrollbars
            // showing/hiding.
            userRows = curRows;
            userCols = curCols;
            NSRect frame = [decoratedWindow frame];
            userTopLeft = NSMakePoint(frame.origin.x, NSMaxY(frame));
        }
    }

    // NOTE: Instead of resizing the window immediately we send a zoom message
    // to the backend so that it gets a chance to resize before the window
    // does.  This avoids problems with the window flickering when zooming.
    int info[3] = { rows, cols, !isZoomed };
    NSData *data = [NSData dataWithBytes:info length:3*sizeof(int)];
    [vimController sendMessage:ZoomMsgID data:data];
}

/// Pin the window to the left of the screen.
///
/// @note We expose this as a method instead of just having Actions.plist
/// expose NSWindow's private API `_zoomLeft` because it's a little nicer this
/// way instead of having to confuse the user with the underscore, and also so
/// that we can block this while full screen is active.
- (IBAction)zoomLeft:(id)sender
{
    if (fullScreenEnabled)
        return;

    // macOS (as of 13.0) doesn't currently have an API to do "zoom left/right"
    // aka Aero Snap in Windows, even though macOS 10.15 added UI to do so if
    // you hover over the full screen button with Option key pressed. Because
    // of that, we have to cheat a little bit and use private APIs
    // (_zoomLeft/_zoomRight) which seems to work just fine. We also
    // future-proof by detecting if this API gets graduated to public API
    // (without the "_") and call that if that exists.
    if ([decoratedWindow respondsToSelector:@selector(zoomLeft:)]) {
        [decoratedWindow performSelector:@selector(zoomLeft:) withObject:sender];
    } else if ([decoratedWindow respondsToSelector:@selector(_zoomLeft:)]) {
        [decoratedWindow performSelector:@selector(_zoomLeft:) withObject:sender];
    }
}

/// Pin the window to the right of the screen. See zoomLeft: for comments.
- (IBAction)zoomRight:(id)sender
{
    if (fullScreenEnabled)
        return;

    if ([decoratedWindow respondsToSelector:@selector(zoomRight:)]) {
        [decoratedWindow performSelector:@selector(zoomRight:) withObject:sender];
    } else if ([decoratedWindow respondsToSelector:@selector(_zoomRight:)]) {
        [decoratedWindow performSelector:@selector(_zoomRight:) withObject:sender];
    }
}

/// Make this window join all app sets
- (IBAction)joinAllStageManagerSets:(id)sender
{
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_13_0
    if (@available(macos 13.0, *)) {
        NSWindowCollectionBehavior wcb = decoratedWindow.collectionBehavior;
        wcb &= ~(NSWindowCollectionBehaviorPrimary);
        wcb &= ~(NSWindowCollectionBehaviorAuxiliary);
        wcb |= NSWindowCollectionBehaviorCanJoinAllApplications;
        [decoratedWindow setCollectionBehavior:wcb];

        if (fullScreenWindow) { // non-native full screen has a separate window
            NSWindowCollectionBehavior wcb = fullScreenWindow.collectionBehavior;
            wcb &= ~(NSWindowCollectionBehaviorPrimary);
            wcb &= ~(NSWindowCollectionBehaviorAuxiliary);
            wcb |= NSWindowCollectionBehaviorCanJoinAllApplications;
            [fullScreenWindow setCollectionBehavior:wcb];
        }
    }
#endif
}

/// Make this window only show up in its own set. This is the default, so calling
/// this is only necessary if joinAllStageManagerSets: was previousaly called.
- (IBAction)unjoinAllStageManagerSets:(id)sender
{
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_13_0
    if (@available(macos 13.0, *)) {
        NSWindowCollectionBehavior wcb = decoratedWindow.collectionBehavior;
        wcb &= ~(NSWindowCollectionBehaviorCanJoinAllApplications);
        wcb &= ~(NSWindowCollectionBehaviorAuxiliary);
        wcb |= NSWindowCollectionBehaviorPrimary;
        [decoratedWindow setCollectionBehavior:wcb];

        if (fullScreenWindow) { // non-native full screen has a separate window
            NSWindowCollectionBehavior wcb = fullScreenWindow.collectionBehavior;
            wcb &= ~(NSWindowCollectionBehaviorCanJoinAllApplications);
            wcb &= ~(NSWindowCollectionBehaviorAuxiliary);
            wcb |= NSWindowCollectionBehaviorPrimary;
            [fullScreenWindow setCollectionBehavior:wcb];
        }
    }
#endif
}

// -- Services menu delegate -------------------------------------------------

- (id)validRequestorForSendType:(NSString *)sendType
                     returnType:(NSString *)returnType
{
    const BOOL sendOk = (([sendType isEqual:NSPasteboardTypeString] && [self.vimController hasSelectedText])
                         || [sendType length] == 0);
    const BOOL returnOk = ([returnType isEqual:NSPasteboardTypeString] || [returnType length] == 0);
    if (sendOk && returnOk)
    {
        return self;
    }
    return [super validRequestorForSendType:sendType returnType:returnType];
}

/// Called by OS when it tries to show a "Services" menu. We ask Vim for the
/// currently selected text and write that to the provided pasteboard.
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
                             types:(NSArray *)types
{
    // We don't check whether types == NSPasteboardTypeString because for some
    // reason macOS likes to send NSStringPboardType instead even that's deprecated.
    // We should really be fine here since we already checked the types in
    // validRequestsForSendType: above.
    (void)types;

    NSString *string = [vimController selectedText];
    if (string != nil) {
        NSArray *types = [NSArray arrayWithObject:NSPasteboardTypeString];
        [pboard declareTypes:types owner:nil];
        return [pboard setString:string forType:NSPasteboardTypeString];
    }
    return NO;
}

/// Called by the OS when it tries to update the selection. This could happen
/// if you selected "Convert text to full width" in the Services menu, for example.
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard
{
    // Replace the current selection with the text on the pasteboard.
    NSArray *types = [pboard types];
    if ([types containsObject:NSPasteboardTypeString]) {
        NSString *input = [pboard stringForType:NSPasteboardTypeString];
        [vimController replaceSelectedText:input];
        return YES;
    }

    return NO;
}


// -- Full-screen delegate ---------------------------------------------------

- (NSApplicationPresentationOptions)window:(NSWindow *)window
    willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)opt
{
    return opt | NSApplicationPresentationAutoHideToolbar;
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    // Store window frame and use it when exiting full-screen.
    preFullScreenFrame = [decoratedWindow frame];

    // The separator should never be visible in fullscreen or split-screen.
    [decoratedWindow hideTablineSeparator:YES];

    // ASSUMPTION: fullScreenEnabled always reflects the state of Vim's 'fu'.
    if (!fullScreenEnabled) {
        ASLogDebug(@"Full-screen out of sync, tell Vim to set 'fu'");
        // NOTE: If we get here it means that Cocoa has somehow entered
        // full-screen without us getting to set the 'fu' option first, so Vim
        // and the GUI are out of sync.  The following code (eventually) gets
        // them back into sync.  A problem is that the full-screen options have
        // not been set, so we have to cache that state and grab it here.
        fullScreenOptions = [[vimController objectForVimStateKey:
                                            @"fullScreenOptions"] intValue];
        fullScreenEnabled = YES;
        [self invFullScreen:self];
    }
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    // Sometimes full screen will de-focus the text view. This seems to happen
    // when titlebar is configured as hidden. Simply re-assert it to make sure
    // text is still focused.
    [decoratedWindow makeFirstResponder:[vimView textView]];

    if (!fullScreenEnabled) {
        // In case for some odd sequence of events (e.g. getting a
        // windowDidFailToEnterFullScreen, then this call), if we have
        // mismatched state, just reset it back to the correct one.
        fullScreenEnabled = YES;
        [vimController addVimInput:@"<C-\\><C-N>:set fu<CR>"];
    }
}

- (void)windowDidFailToEnterFullScreen:(NSWindow *)window
{
    ASLogNotice(@"Failed to ENTER full-screen, restoring window frame...");

    fullScreenEnabled = NO;
    [window setFrame:preFullScreenFrame display:YES];

    // Sometimes full screen will de-focus the text view. This seems to happen
    // when titlebar is configured as hidden. Simply re-assert it to make sure
    // text is still focused.
    [decoratedWindow makeFirstResponder:[vimView textView]];

    // Vim needs to be told that it's no longer in full screen. Because we
    // already set fullScreenEnabled=NO, this won't do anything other than
    // updating Vim's state.
    [vimController addVimInput:@"<C-\\><C-N>:set nofu<CR>"];
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{
    // ASSUMPTION: fullScreenEnabled always reflects the state of Vim's 'fu'.
    if (fullScreenEnabled) {
        ASLogDebug(@"Full-screen out of sync, tell Vim to clear 'fu'");
        // NOTE: If we get here it means that Cocoa has somehow exited
        // full-screen without us getting to clear the 'fu' option first, so
        // Vim and the GUI are out of sync.  The following code (eventually)
        // gets them back into sync.
        fullScreenEnabled = NO;
        [self invFullScreen:self];
    }

    // If we are using a resize increment (i.e. smooth resize is off), macOS
    // has a quirk/bug that will use the increment to determine the final size
    // of the original window as fixed increment from the full screen window,
    // which could annoyingly not be the original size. This could lead to
    // enter full screen -> exit full screen leading to the window having
    // different size. Because of that, just set increment to 1,1 here to
    // alleviate the issue.
    [decoratedWindow setContentResizeIncrements:NSMakeSize(1, 1)];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    // We set the resize increment to 1,1 above just to sure window size was
    // restored properly. We want to set it back to the correct value, which
    // would not be 1,1 if we are not using smooth resize.
    [self updateResizeConstraints:NO];

    [self updateTablineSeparator];

    // Sometimes full screen will de-focus the text view. This seems to happen
    // when titlebar is configured as hidden. Simply re-assert it to make sure
    // text is still focused.
    [decoratedWindow makeFirstResponder:[vimView textView]];

    if (fullScreenEnabled) {
        // Sometimes macOS will first send a windowDidFailToExitFullScreen
        // notification (e.g. if user is in the middle of switching spaces)
        // before actually sending windowDidExitFullScreen. Just to be safe, if
        // we are actually confused here, simply reset the state back.
        fullScreenEnabled = NO;
        [vimController addVimInput:@"<C-\\><C-N>:set nofu<CR>"];
    }
}

- (void)windowDidFailToExitFullScreen:(NSWindow *)window
{
    ASLogNotice(@"Failed to EXIT full-screen, maximizing window...");

    fullScreenEnabled = YES;

    // Sometimes full screen will de-focus the text view. This seems to happen
    // when titlebar is configured as hidden. Simply re-assert it to make sure
    // text is still focused.
    [decoratedWindow makeFirstResponder:[vimView textView]];

    // Vim needs to be told that it's still in full screen. Because we already
    // set fullScreenEnabled=YES, this won't do anything other than updating
    // Vim's state.
    [vimController addVimInput:@"<C-\\><C-N>:set fu<CR>"];
}

- (void)runAfterWindowPresentedUsingBlock:(void (^)(void))block
{
    if (windowPresented) { // no need to defer block, just run it now
        block();
        return;
    }

    // run block later
    if (afterWindowPresentedQueue == nil)
        afterWindowPresentedQueue = [[NSMutableArray alloc] init];
    [afterWindowPresentedQueue addObject:[block copy]];
}

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
- (NSTouchBar *)makeTouchBar
{
    return [vimController makeTouchBar];
}
#endif

/// This will update the window's resizing constraints to either be smooth or rounded to whole cells.
///
/// @param resizeWindow If specified, will also resize the window itself down to match the Vim view's desired size.
- (void)updateResizeConstraints:(BOOL)resizeWindow
{
    if (!setupDone) return;

    // If smooth resizing is not set, set the resize increments to exactly
    // match the font size; this way the window will always hold an integer
    // number of (rows,columns). Otherwise, just allow arbitrary resizing.
    const BOOL smoothResize = [[NSUserDefaults standardUserDefaults] boolForKey:MMSmoothResizeKey];
    const NSSize desiredResizeConstraints = smoothResize ?
                                                NSMakeSize(1, 1) :
                                                [[vimView textView] cellSize];
    [decoratedWindow setContentResizeIncrements:desiredResizeConstraints];

    const NSSize minSize = [vimView minSize];
    [decoratedWindow setContentMinSize:minSize];

    if (resizeWindow) {
        if (!smoothResize) {
            // We only want to resize the window down to match the Vim size if not using smooth resizing.
            // This resizing is going to re-snap the Window size to multiples of grid size. Otherwise
            // the resize constraint is always going to be at an offset to the desired size.
            [self resizeVimViewAndWindow];
        }
    }
}

@end // MMWindowController



@implementation MMWindowController (Private)

- (NSSize)contentSize
{
    // NOTE: Never query the content view directly for its size since it may
    // not return the same size as contentRectForFrameRect: (e.g. when in
    // windowed mode and the tabline separator is visible)!
    NSWindow *win = [self window];
    return [win contentRectForFrameRect:[win frame]].size;
}

- (void)resizeWindowToFitContentSize:(NSSize)contentSize
                        keepOnScreen:(BOOL)onScreen
{
    NSRect frame = [decoratedWindow frame];
    NSRect contentRect = [decoratedWindow contentRectForFrameRect:frame];

    // Keep top-left corner of the window fixed when resizing.
    contentRect.origin.y -= contentSize.height - contentRect.size.height;
    contentRect.size = contentSize;

    NSRect newFrame = [decoratedWindow frameRectForContentRect:contentRect];

    if (shouldRestoreUserTopLeft) {
        // Restore user top left window position (which is saved when zooming).
        CGFloat dy = userTopLeft.y - NSMaxY(newFrame);
        newFrame.origin.x = userTopLeft.x;
        newFrame.origin.y += dy;
        shouldRestoreUserTopLeft = NO;
    }

    NSScreen *screen = [decoratedWindow screen];
    if (onScreen && screen) {
        // Ensure that the window fits inside the visible part of the screen.
        // If there are more than one screen the window will be moved to fit
        // entirely in the screen that most of it occupies.
        NSRect maxFrame = fullScreenEnabled ? [screen frame]
                                            : [screen visibleFrame];
        maxFrame = [self constrainFrame:maxFrame];

        if (newFrame.size.width > maxFrame.size.width) {
            newFrame.size.width = maxFrame.size.width;
            newFrame.origin.x = maxFrame.origin.x;
        }
        if (newFrame.size.height > maxFrame.size.height) {
            newFrame.size.height = maxFrame.size.height;
            newFrame.origin.y = maxFrame.origin.y;
        }

        if (newFrame.origin.y < maxFrame.origin.y)
            newFrame.origin.y = maxFrame.origin.y;
        if (NSMaxY(newFrame) > NSMaxY(maxFrame))
            newFrame.origin.y = NSMaxY(maxFrame) - newFrame.size.height;
        if (newFrame.origin.x < maxFrame.origin.x)
            newFrame.origin.x = maxFrame.origin.x;
        if (NSMaxX(newFrame) > NSMaxX(maxFrame))
            newFrame.origin.x = NSMaxX(maxFrame) - newFrame.size.width;
    }

    if (fullScreenEnabled && screen) {
        // Keep window centered when in native full-screen.
        NSRect screenFrame = [screen frame];
        newFrame.origin.y = screenFrame.origin.y +
            round(0.5*(screenFrame.size.height - newFrame.size.height));
        newFrame.origin.x = screenFrame.origin.x +
            round(0.5*(screenFrame.size.width - newFrame.size.width));
    }

    ASLogDebug(@"Set window frame: %@", NSStringFromRect(newFrame));
    [decoratedWindow setFrame:newFrame display:YES];

    NSPoint oldTopLeft = { frame.origin.x, NSMaxY(frame) };
    NSPoint newTopLeft = { newFrame.origin.x, NSMaxY(newFrame) };
    if (!NSEqualPoints(oldTopLeft, newTopLeft)) {
        // NOTE: The window top left position may change due to the window
        // being moved e.g. when the tabline is shown so we must tell Vim what
        // the new window position is here.
        // NOTE 2: Vim measures Y-coordinates from top of screen.
        int pos[2] = {
            (int)newTopLeft.x,
            (int)(NSMaxY([[decoratedWindow screen] frame]) - newTopLeft.y) };
        NSData *data = [NSData dataWithBytes:pos length:2*sizeof(int)];
        [vimController sendMessage:SetWindowPositionMsgID data:data];
    }
}

- (NSSize)constrainContentSizeToScreenSize:(NSSize)contentSize
{
    NSWindow *win = [self window];
    if (![win screen])
        return contentSize;

    // NOTE: This may be called in both windowed and full-screen mode.  The
    // "visibleFrame" method does not overlap menu and dock so should not be
    // used in full-screen.
    NSRect screenRect = fullScreenEnabled ? [[win screen] frame]
                                          : [[win screen] visibleFrame];
    NSRect rect = [win contentRectForFrameRect:screenRect];

    if (contentSize.height > rect.size.height)
        contentSize.height = rect.size.height;
    if (contentSize.width > rect.size.width)
        contentSize.width = rect.size.width;

    return contentSize;
}

- (NSRect)constrainFrame:(NSRect)frame
{
    // Constrain the given (window) frame so that it fits an even number of
    // rows and columns.
    NSRect contentRect = [decoratedWindow contentRectForFrameRect:frame];
    NSSize constrainedSize = [vimView constrainRows:NULL
                                            columns:NULL
                                             toSize:contentRect.size];

    contentRect.origin.y += contentRect.size.height - constrainedSize.height;
    contentRect.size = constrainedSize;

    return [decoratedWindow frameRectForContentRect:contentRect];
}

- (void)updateTablineSeparator
{
    BOOL tablineVisible  = ![[vimView tabline] isHidden];
    BOOL toolbarHidden  = [decoratedWindow toolbar] == nil;
    BOOL hideSeparator  = NO;

    // See initWithVimController: for textured background deprecation notes.
    BOOL windowTextured = NO;
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_VERSION_11_0
    if (AVAILABLE_MAC_OS(11, 0)) {
    } else {
        windowTextured = ([decoratedWindow styleMask] &
                          NSWindowStyleMaskTexturedBackground) != 0;
    }
#endif

    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_10) {
        // The tabline separator is mostly an old feature and not necessary
        // modern macOS versions.
        hideSeparator = YES;
    } else {
        if (fullScreenEnabled || tablineVisible)
            hideSeparator = YES;
        else
            hideSeparator = toolbarHidden && !windowTextured;
    }

    [self hideTablineSeparator:hideSeparator];
}

- (void)hideTablineSeparator:(BOOL)hide
{
    // The full-screen window has no tabline separator so we operate on
    // decoratedWindow instead of [self window].
    if ([decoratedWindow hideTablineSeparator:hide]) {
        // The tabline separator was toggled so the content view must change
        // size.
        [self updateResizeConstraints:NO];
    }
}

- (void)doFindNext:(BOOL)next
{
    NSString *query = nil;

#if 0
    // Use current query if the search field is selected.
    id searchField = [[self searchFieldItem] view];
    if (searchField && [[searchField stringValue] length] > 0 &&
            [decoratedWindow firstResponder] == [searchField currentEditor])
        query = [searchField stringValue];
#endif

    if (!query) {
        // Use find pasteboard for next query.
        NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
        NSArray *supportedTypes = [NSArray arrayWithObjects:VimFindPboardType,
                                   NSPasteboardTypeString, nil];
        NSString *bestType = [pb availableTypeFromArray:supportedTypes];

        // See gui_macvim_add_to_find_pboard() for an explanation of these
        // types.
        if ([bestType isEqual:VimFindPboardType]) {
            query = [pb stringForType:VimFindPboardType];
        } else {
            query = [pb stringForType:NSPasteboardTypeString];
        }
    }

    NSString *input = nil;
    if (query) {
        // NOTE: The '/' register holds the last search string.  By setting it
        // (using the '@/' syntax) we fool Vim into thinking that it has
        // already searched for that string and then we can simply use 'n' or
        // 'N' to find the next/previous match.
        input = [NSString stringWithFormat:@"<C-\\><C-N>:let @/='%@'<CR>%c",
                query, next ? 'n' : 'N'];
    } else {
        input = next ? @"<C-\\><C-N>n" : @"<C-\\><C-N>N"; 
    }

    [vimController addVimInput:input];
}

- (void)updateToolbar
{
    if (nil == toolbar || 0 == updateToolbarFlag) return;

    // Positive flag shows toolbar, negative hides it.
    BOOL on = updateToolbarFlag > 0 ? YES : NO;

    NSRect origWindowFrame = [decoratedWindow frame];
    BOOL origHasToolbar = decoratedWindow.toolbar != nil;

    [decoratedWindow setToolbar:(on ? toolbar : nil)];

    if (shouldKeepGUISize && !fullScreenEnabled && origHasToolbar != on) {
        // "shouldKeepGUISize" means guioptions has 'k' in it, indicating that user doesn't
        // want the window to resize itself. In non-fullscreen when we call setToolbar:
        // Cocoa automatically resizes the window so we need to un-resize it back to
        // original.

        NSRect newWindowFrame = [decoratedWindow frame];
        if (newWindowFrame.size.height == origWindowFrame.size.height) {
            // This is an odd case here, where the window has not changed size at all.
            // The addition/removal of toolbar should have changed its size. This means that
            // there isn't enough space to grow the window on the screen. Usually we rely
            // on windowDidResize: to call setFrameSizeKeepGUISize for us but now we have
            // to do it manually in this special case.
            [vimView setFrameSizeKeepGUISize:[self contentSize]];
        }
        else {
            [decoratedWindow setFrame:origWindowFrame display:YES];
        }
    }

    [self updateTablineSeparator];

    updateToolbarFlag = 0;
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification
{
    if (fullScreenWindow) {
        [fullScreenWindow applicationDidChangeScreenParameters:notification];
    }
}

- (void)enterNativeFullScreen
{
    if (fullScreenEnabled)
        return;

    ASLogInfo(@"Enter native full-screen");

    fullScreenEnabled = YES;

    // NOTE: fullScreenEnabled is used to detect if we enter full-screen
    // programatically and so must be set before calling realToggleFullScreen:.
    NSParameterAssert(fullScreenEnabled == YES);
    [decoratedWindow realToggleFullScreen:self];
}

- (void)processAfterWindowPresentedQueue
{
    for (void (^block)(void) in afterWindowPresentedQueue)
        block();

    [afterWindowPresentedQueue release]; afterWindowPresentedQueue = nil;
}

@end // MMWindowController (Private)

