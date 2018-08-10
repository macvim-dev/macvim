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
#import <PSMTabBarControl/PSMTabBarControl.h>


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
- (void)updateResizeConstraints;
- (NSTabViewItem *)addNewTabViewItem;
- (BOOL)askBackendForStarRegister:(NSPasteboard *)pb;
- (void)updateTablineSeparator;
- (void)hideTablineSeparator:(BOOL)hide;
- (void)doFindNext:(BOOL)next;
- (void)updateToolbar;
- (BOOL)maximizeWindow:(int)options;
- (void)applicationDidChangeScreenParameters:(NSNotification *)notification;
- (void)enterNativeFullScreen;
- (void)processAfterWindowPresentedQueue;
+ (NSString *)tabBarStyleForUnified;
+ (NSString *)tabBarStyleForMetal;
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
    unsigned styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
            | NSWindowStyleMaskUnifiedTitleAndToolbar
            | NSWindowStyleMaskTexturedBackground;

    if ([[NSUserDefaults standardUserDefaults]
            boolForKey:MMNoTitleBarWindowKey]) {
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

    // Window cascading is handled by MMAppController.
    [self setShouldCascadeWindows:NO];

    // NOTE: Autoresizing is enabled for the content view, but only used
    // for the tabline separator.  The vim view must be resized manually
    // because of full-screen considerations, and because its size depends
    // on whether the tabline separator is visible or not.
    NSView *contentView = [win contentView];
    [contentView setAutoresizesSubviews:YES];

    vimView = [[MMVimView alloc] initWithFrame:[contentView frame]
                                 vimController:vimController];
    [vimView setAutoresizingMask:NSViewNotSizable];
    [contentView addSubview:vimView];

    [win setDelegate:self];
    [win setInitialFirstResponder:[vimView textView]];
    
    if ([win styleMask] & NSWindowStyleMaskTexturedBackground) {
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

#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)
    // Building on Mac OS X 10.7 or greater.

    // This puts the full-screen button in the top right of each window
    if ([win respondsToSelector:@selector(setCollectionBehavior:)])
        [win setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];

    // This makes windows animate when opened
    if ([win respondsToSelector:@selector(setAnimationBehavior:)])
        [win setAnimationBehavior:NSWindowAnimationBehaviorDocumentWindow];
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
    [windowAutosaveKey release];  windowAutosaveKey = nil;
    [vimView release];  vimView = nil;
    [toolbar release];  toolbar = nil;
    // in case processAfterWindowPresentedQueue wasn't called
    [afterWindowPresentedQueue release];  afterWindowPresentedQueue = nil;

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

    if (fullScreenEnabled) {
        // If we are closed while still in full-screen, end full-screen mode,
        // release ourselves (because this won't happen in MMWindowController)
        // and perform close operation on the original window.
        [self leaveFullScreen];
    }

    vimController = nil;

    [vimView removeFromSuperviewWithoutNeedingDisplay];
    [vimView cleanup];

    // It is feasible (though unlikely) that the user quits before the window
    // controller is released, make sure the edit flag is cleared so no warning
    // dialog is displayed.
    [decoratedWindow setDocumentEdited:NO];

    [[self window] orderOut:self];
}

- (void)openWindow
{
    // Indicates that the window is ready to be displayed, but do not display
    // (or place) it yet -- that is done in showWindow.
    //
    // TODO: Remove this method?  Everything can probably be done in
    // presentWindow: but must carefully check dependencies on 'setupDone'
    // flag.

    [self addNewTabViewItem];

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
    [self updateResizeConstraints];
    [self resizeWindowToFitContentSize:[vimView desiredSize]
                          keepOnScreen:YES];


    [decoratedWindow makeKeyAndOrderFront:self];

    // HACK! Calling makeKeyAndOrderFront: may cause Cocoa to force the window
    // into native full-screen mode (this happens e.g. if a new window is
    // opened when MacVim is already in full-screen).  In this case we don't
    // want the decorated window to pop up before the animation into
    // full-screen, so set its alpha to 0.
    if (fullScreenEnabled && !fullScreenWindow)
        [decoratedWindow setAlphaValue:0];

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
    } else if (delayEnterFullScreen) {
        // Set alpha to zero so that the decorated window doesn't pop up
        // before we enter full-screen.
        [decoratedWindow setAlphaValue:0];
        [self enterNativeFullScreen];
    }

    return YES;
}

- (void)moveWindowAcrossScreens:(NSPoint)topLeft
{
    // HACK! This method moves a window to a new origin and to a different
    // screen. This is primarily useful to avoid a scenario where such a move
    // will trigger a resize, even though the frame didn't actually change size.
    // This method should not be called unless the new origin is definitely on
    // a different screen, otherwise the next legitimate resize message will
    // be skipped.
    resizingDueToMove = YES;
    [[self window] setFrameTopLeftPoint:topLeft];
}

- (void)updateTabsWithData:(NSData *)data
{
    [vimView updateTabsWithData:data];
}

- (void)selectTabWithIndex:(int)idx
{
    [vimView selectTabWithIndex:idx];
}

- (void)setTextDimensionsWithRows:(int)rows columns:(int)cols isLive:(BOOL)live
                     keepOnScreen:(BOOL)onScreen
{
    ASLogDebug(@"setTextDimensionsWithRows:%d columns:%d isLive:%d "
            "keepOnScreen:%d", rows, cols, live, onScreen);

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

    if (setupDone && !live) {
        shouldResizeVimView = YES;
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
        if (![[vimView tabBarControl] isHidden])
            ++autosaveRows;

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setInteger:autosaveRows forKey:MMAutosaveRowsKey];
        [ud setInteger:cols forKey:MMAutosaveColumnsKey];
        [ud synchronize];
    }
}

- (void)zoomWithRows:(int)rows columns:(int)cols state:(int)state
{
    [self setTextDimensionsWithRows:rows
                            columns:cols
                             isLive:NO
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

- (void)setDocumentFilename:(NSString *)filename
{
    if (!filename)
        return;

    // Ensure file really exists or the path to the proxy icon will look weird.
    // If the file does not exists, don't show a proxy icon.
    if (![[NSFileManager defaultManager] fileExistsAtPath:filename])
        filename = @"";

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
    shouldResizeVimView = shouldResizeVimView || scrollbarHidden;
    shouldMaximizeWindow = shouldMaximizeWindow || scrollbarHidden;

    return scrollbarHidden;
}

- (BOOL)showScrollbarWithIdentifier:(int32_t)ident state:(BOOL)visible
{
    BOOL scrollbarToggled = [vimView showScrollbarWithIdentifier:ident
                                                           state:visible];
    shouldResizeVimView = shouldResizeVimView || scrollbarToggled;
    shouldMaximizeWindow = shouldMaximizeWindow || scrollbarToggled;

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

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore
{
    // NOTE: This is called when the transparency changes so set the opacity
    // flag on the window here (should be faster if the window is opaque).
    BOOL isOpaque = [back alphaComponent] == 1.0f;
    [decoratedWindow setOpaque:isOpaque];
    if (fullScreenWindow)
        [fullScreenWindow setOpaque:isOpaque];

    [vimView setDefaultColorsBackground:back foreground:fore];
}

- (void)setFont:(NSFont *)font
{
    [[NSFontManager sharedFontManager] setSelectedFont:font isMultiple:NO];
    [[vimView textView] setFont:font];
    [self updateResizeConstraints];
    shouldMaximizeWindow = YES;
}

- (void)setWideFont:(NSFont *)font
{
    [[vimView textView] setWideFont:font];
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

    // NOTE: If the window has not been presented then we must avoid resizing
    // the views since it will cause them to be constrained to the screen which
    // has not yet been set!
    if (windowPresented && shouldResizeVimView) {
        shouldResizeVimView = NO;

        // Make sure full-screen window stays maximized (e.g. when scrollbar or
        // tabline is hidden) according to 'fuopt'.

        BOOL didMaximize = NO;
        if (shouldMaximizeWindow && fullScreenEnabled &&
                (fullScreenOptions & (FUOPT_MAXVERT|FUOPT_MAXHORZ)) != 0)
            didMaximize = [self maximizeWindow:fullScreenOptions];

        shouldMaximizeWindow = NO;

        // Resize Vim view and window, but don't do this now if the window was
        // just reszied because this would make the window "jump" unpleasantly.
        // Instead wait for Vim to respond to the resize message and do the
        // resizing then.
        // TODO: What if the resize message fails to make it back?
        if (!didMaximize) {
            NSSize originalSize = [vimView frame].size;
            int rows = 0, cols = 0;
            NSSize contentSize = [vimView constrainRows:&rows columns:&cols
                                                 toSize:
                                  fullScreenWindow ? [fullScreenWindow frame].size :
                                  fullScreenEnabled ? desiredWindowSize :
                                  [self constrainContentSizeToScreenSize:[vimView desiredSize]]];
            [vimView setFrameSize:contentSize];

            if (fullScreenWindow) {
                // NOTE! Don't mark the full-screen content view as needing an
                // update unless absolutely necessary since when it is updated
                // the entire screen is cleared.  This may cause some parts of
                // the Vim view to be cleared but not redrawn since Vim does
                // not realize that we've erased part of the view.
                if (!NSEqualSizes(originalSize, contentSize)) {
                    [[fullScreenWindow contentView] setNeedsDisplay:YES];
                    [fullScreenWindow centerView];
                }
            } else {
                [self resizeWindowToFitContentSize:contentSize
                                      keepOnScreen:keepOnScreen];
            }
        }

        keepOnScreen = NO;
    }
}

- (void)showTabBar:(BOOL)on
{
    [[vimView tabBarControl] setHidden:!on];
    [self updateTablineSeparator];
    shouldMaximizeWindow = YES;
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
        shouldMaximizeWindow = shouldResizeVimView = YES;
    }
}

- (void)adjustColumnspace:(int)columnspace
{
    if (vimView && [vimView textView]) {
        [[vimView textView] setColumnspace:(float)columnspace];
        shouldMaximizeWindow = shouldResizeVimView = YES;
    }
}

- (void)liveResizeWillStart
{
    if (!setupDone) return;

    // Save the original title, if we haven't already.
    if (lastSetTitle == nil) {
        lastSetTitle = [[decoratedWindow title] retain];
    }

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
        [lastSetTitle release];
        lastSetTitle = nil;
    }
}

- (void)setBlurRadius:(int)radius
{
    blurRadius = radius;
    if (windowPresented) { 
        [decoratedWindow setBlurRadius:radius];
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
        // Enter native full-screen mode.  Only supported on Mac OS X 10.7+.
        if (windowPresented) {
            [self enterNativeFullScreen];
        } else {
            delayEnterFullScreen = YES;
        }
    } else {
        // Enter custom full-screen mode.  Always supported.
        ASLogInfo(@"Enter custom full-screen");

        // fullScreenWindow could be non-nil here if this is called multiple
        // times during startup.
        [fullScreenWindow release];

        fullScreenWindow = [[MMFullScreenWindow alloc]
            initWithWindow:decoratedWindow view:vimView backgroundColor:back];
        [fullScreenWindow setOptions:fuoptions];
        [fullScreenWindow setRepresentedFilename:
            [decoratedWindow representedFilename]];

        // NOTE: Do not enter full-screen until the window has been presented
        // since we don't actually know which screen to use before then.  (The
        // custom full-screen can appear on any screen, as opposed to native
        // full-screen which always uses the main screen.)
        if (windowPresented) {
            [fullScreenWindow enterFullScreen];
            fullScreenEnabled = YES;

            // The resize handle disappears so the vim view needs to update the
            // scrollbars.
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

        // The vim view may be too large to fit the screen, so update it.
        shouldResizeVimView = YES;
    } else {
        // Using native full-screen
        // NOTE: fullScreenEnabled is used to detect if we enter full-screen
        // programatically and so must be set before calling
        // realToggleFullScreen:.
        NSParameterAssert(fullScreenEnabled == NO);
        [decoratedWindow realToggleFullScreen:self];
    }
}

- (void)setFullScreenBackgroundColor:(NSColor *)back
{
    if (fullScreenWindow)
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
    NSArray *desc = [NSArray arrayWithObjects:@"TouchBar", [sender title], nil];
    NSDictionary *attrs = [NSDictionary dictionaryWithObject:desc
                                                      forKey:@"descriptor"];
    [vimController sendMessage:ExecuteMenuMsgID data:[attrs dictionaryAsData]];
}
#endif

- (IBAction)fontSizeUp:(id)sender
{
    [[NSFontManager sharedFontManager] modifyFont:
            [NSNumber numberWithInt:NSSizeUpFontAction]];
}

- (IBAction)fontSizeDown:(id)sender
{
    [[NSFontManager sharedFontManager] modifyFont:
            [NSNumber numberWithInt:NSSizeDownFontAction]];
}

- (IBAction)findAndReplace:(id)sender
{
    int tag = [sender tag];
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
    if ([item action] == @selector(vimMenuItemAction:)
            || [item action] == @selector(performClose:))
        return [item tag];

    return YES;
}

// -- NSWindow delegate ------------------------------------------------------

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    [[MMAppController sharedInstance] setMainMenu:[vimController mainMenu]];

    if ([vimView textView]) {
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

    // NOTE: We need to update the window frame size for Split View even though
    // in full-screen on El Capitan or later.
    if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_10_Max
            && fullScreenEnabled)
        return;

    // NOTE: Since we have no control over when the window may resize (Cocoa
    // may resize automatically) we simply set the view to fill the entire
    // window.  The vim view takes care of notifying Vim if the number of
    // (rows,columns) changed.
    [vimView setFrameSize:[self contentSize]];
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification
{
    [vimController sendMessage:BackingPropertiesChangedMsgID data:nil];
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



// -- Services menu delegate -------------------------------------------------

- (id)validRequestorForSendType:(NSString *)sendType
                     returnType:(NSString *)returnType
{
    if ([sendType isEqual:NSStringPboardType]
            && [self askBackendForStarRegister:nil])
        return self;

    return [super validRequestorForSendType:sendType returnType:returnType];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
                             types:(NSArray *)types
{
    if (![types containsObject:NSStringPboardType])
        return NO;

    return [self askBackendForStarRegister:pboard];
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard
{
    // Replace the current selection with the text on the pasteboard.
    NSArray *types = [pboard types];
    if ([types containsObject:NSStringPboardType]) {
        NSString *input = [NSString stringWithFormat:@"s%@",
                 [pboard stringForType:NSStringPboardType]];
        [vimController addVimInput:input];
        return YES;
    }

    return NO;
}


#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)

// -- Full-screen delegate ---------------------------------------------------

- (NSApplicationPresentationOptions)window:(NSWindow *)window
    willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)opt
{
    return opt | NSApplicationPresentationAutoHideToolbar;
}

- (NSArray *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObject:decoratedWindow];
}

- (void)window:(NSWindow *)window
    startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
    // Fade out window, remove title bar and maximize, then fade back in.
    // (There is a small delay before window is maximized but usually this is
    // not noticeable on a relatively modern Mac.)

    // Fade out
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:0.5*duration];
        [[window animator] setAlphaValue:0];
    } completionHandler:^{
        [window setStyleMask:([window styleMask] | NSWindowStyleMaskFullScreen)];
        NSString *tabBarStyle = [[self class] tabBarStyleForUnified];
        [[vimView tabBarControl] setStyleNamed:tabBarStyle];
        [self updateTablineSeparator];

        // Stay dark for some time to wait for things to sync, then do the full screen operation
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:0.5*duration];
            [[window animator] setAlphaValue:0];
        } completionHandler:^{
            [self maximizeWindow:fullScreenOptions];
            
            // Fade in
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                [context setDuration:0.5*duration];
                [[window animator] setAlphaValue:1];
            } completionHandler:^{
                // Do nothing
            }];
        }];
    }];
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
    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_10_Max) {
        // NOTE: On El Capitan, we need to redraw the view when entering
        // full-screen using :fullscreen option (including Ctrl-Cmd-f).
        [vimController sendMessage:BackingPropertiesChangedMsgID data:nil];
    }
}

- (void)windowDidFailToEnterFullScreen:(NSWindow *)window
{
    // NOTE: This message can be called without
    // window:startCustomAnimationToEnterFullScreenWithDuration: ever having
    // been called so any state to store before entering full-screen must be
    // stored in windowWillEnterFullScreen: which always gets called.
    ASLogNotice(@"Failed to ENTER full-screen, restoring window frame...");

    fullScreenEnabled = NO;
    [window setAlphaValue:1];
    [window setStyleMask:([window styleMask] & ~NSWindowStyleMaskFullScreen)];
    NSString *tabBarStyle = [[self class] tabBarStyleForMetal];
    [[vimView tabBarControl] setStyleNamed:tabBarStyle];
    [self updateTablineSeparator];
    [window setFrame:preFullScreenFrame display:YES];
}

- (NSArray *)customWindowsToExitFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObject:decoratedWindow];
}

- (void)window:(NSWindow *)window
    startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
    if (!setupDone) {
        // HACK! The window has closed but Cocoa still brings it back to life
        // and shows a grey box the size of the window unless we explicitly
        // hide it by setting its alpha to 0 here.
        [window setAlphaValue:0];
        return;
    }

    // Fade out window, add back title bar and restore window frame, then fade
    // back in.  (There is a small delay before window contents is drawn after
    // the window frame is set but usually this is not noticeable on a
    // relatively modern Mac.)
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:0.5*duration];
        [[window animator] setAlphaValue:0];
    } completionHandler:^{
        [window setStyleMask:([window styleMask] & ~NSWindowStyleMaskFullScreen)];
        NSString *tabBarStyle = [[self class] tabBarStyleForMetal];
        [[vimView tabBarControl] setStyleNamed:tabBarStyle];
        [self updateTablineSeparator];
        [window setFrame:preFullScreenFrame display:YES];

        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:0.5*duration];
            [[window animator] setAlphaValue:1];
        } completionHandler:^{
            // Do nothing
        }];
    }];
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
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_10_Max) {
        // NOTE: On El Capitan, we need to redraw the view when leaving
        // full-screen by moving the window out from Split View.
        [vimController sendMessage:BackingPropertiesChangedMsgID data:nil];
    }
  
    [self updateTablineSeparator];
}

- (void)windowDidFailToExitFullScreen:(NSWindow *)window
{
    // TODO: Is this the correct way to deal with this message?  Are we still
    // in full-screen at this point?
    ASLogNotice(@"Failed to EXIT full-screen, maximizing window...");

    fullScreenEnabled = YES;
    [window setAlphaValue:1];
    [window setStyleMask:([window styleMask] | NSWindowStyleMaskFullScreen)];
    NSString *tabBarStyle = [[self class] tabBarStyleForUnified];
    [[vimView tabBarControl] setStyleNamed:tabBarStyle];
    [self updateTablineSeparator];
    [self maximizeWindow:fullScreenOptions];
}

#endif // (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)

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

- (void)updateResizeConstraints
{
    if (!setupDone) return;

    // Set the resize increments to exactly match the font size; this way the
    // window will always hold an integer number of (rows,columns).
    NSSize cellSize = [[vimView textView] cellSize];
    [decoratedWindow setContentResizeIncrements:cellSize];

    NSSize minSize = [vimView minSize];
    [decoratedWindow setContentMinSize:minSize];
}

- (NSTabViewItem *)addNewTabViewItem
{
    return [vimView addNewTabViewItem];
}

- (BOOL)askBackendForStarRegister:(NSPasteboard *)pb
{ 
    // TODO: Can this be done with evaluateExpression: instead?
    BOOL reply = NO;
    id backendProxy = [vimController backendProxy];

    if (backendProxy) {
        @try {
            reply = [backendProxy starRegisterToPasteboard:pb];
        }
        @catch (NSException *ex) {
            ASLogDebug(@"starRegisterToPasteboard: failed: pid=%d reason=%@",
                    [vimController pid], ex);
        }
    }

    return reply;
}

- (void)updateTablineSeparator
{
    BOOL tabBarVisible  = ![[vimView tabBarControl] isHidden];
    BOOL toolbarHidden  = [decoratedWindow toolbar] == nil;
    BOOL windowTextured = ([decoratedWindow styleMask] &
                            NSWindowStyleMaskTexturedBackground) != 0;
    BOOL hideSeparator  = NO;

    if (fullScreenEnabled || tabBarVisible)
        hideSeparator = YES;
    else
        hideSeparator = toolbarHidden && !windowTextured;

    [self hideTablineSeparator:hideSeparator];
}

- (void)hideTablineSeparator:(BOOL)hide
{
    // The full-screen window has no tabline separator so we operate on
    // decoratedWindow instead of [self window].
    if ([decoratedWindow hideTablineSeparator:hide]) {
        // The tabline separator was toggled so the content view must change
        // size.
        [self updateResizeConstraints];
        shouldResizeVimView = YES;
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
        NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSFindPboard];
        NSArray *supportedTypes = [NSArray arrayWithObjects:VimFindPboardType,
                NSStringPboardType, nil];
        NSString *bestType = [pb availableTypeFromArray:supportedTypes];

        // See gui_macvim_add_to_find_pboard() for an explanation of these
        // types.
        if ([bestType isEqual:VimFindPboardType]) {
            query = [pb stringForType:VimFindPboardType];
        } else {
            BOOL shareFindPboard = [[NSUserDefaults standardUserDefaults]
                                                boolForKey:MMShareFindPboardKey];
            if (shareFindPboard)
                query = [pb stringForType:NSStringPboardType];
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
    [decoratedWindow setToolbar:(on ? toolbar : nil)];
    [self updateTablineSeparator];

    updateToolbarFlag = 0;
}

- (BOOL)maximizeWindow:(int)options
{
    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_10_Max) {
        // NOTE: Prevent to resize the window in Split View on El Capitan or
        // later.
        return NO;
    }

    int currRows, currColumns;
    [[vimView textView] getMaxRows:&currRows columns:&currColumns];

    // NOTE: Do not use [NSScreen visibleFrame] when determining the screen
    // size since it compensates for menu and dock.
    int maxRows, maxColumns;
    NSScreen *screen = [decoratedWindow screen];
    if (!screen) {
        ASLogNotice(@"Window not on screen, using main screen");
        screen = [NSScreen mainScreen];
    }
    NSSize size = [screen frame].size;
    [vimView constrainRows:&maxRows columns:&maxColumns toSize:size];

    ASLogDebug(@"Window dimensions max: %dx%d  current: %dx%d",
            maxRows, maxColumns, currRows, currColumns);

    // Compute current fu size
    int fuRows = currRows, fuColumns = currColumns;
    if (options & FUOPT_MAXVERT)
        fuRows = maxRows;
    if (options & FUOPT_MAXHORZ)
        fuColumns = maxColumns;

    // If necessary, resize vim to target fu size
    if (currRows != fuRows || currColumns != fuColumns) {
        // The size sent here is queued and sent to vim when it's in
        // event processing mode again. Make sure to only send the values we
        // care about, as they override any changes that were made to 'lines'
        // and 'columns' after 'fu' was set but before the event loop is run.
        NSData *data = nil;
        int msgid = 0;
        if (currRows != fuRows && currColumns != fuColumns) {
            int newSize[2] = { fuRows, fuColumns };
            data = [NSData dataWithBytes:newSize length:2*sizeof(int)];
            msgid = SetTextDimensionsMsgID;
        } else if (currRows != fuRows) {
            data = [NSData dataWithBytes:&fuRows length:sizeof(int)];
            msgid = SetTextRowsMsgID;
        } else if (currColumns != fuColumns) {
            data = [NSData dataWithBytes:&fuColumns length:sizeof(int)];
            msgid = SetTextColumnsMsgID;
        }
        NSParameterAssert(data != nil && msgid != 0);

        ASLogDebug(@"%s: %dx%d", MessageStrings[msgid], fuRows, fuColumns);
        MMVimController *vc = [self vimController];
        [vc sendMessage:msgid data:data];
        [[vimView textView] setMaxRows:fuRows columns:fuColumns];

        // Indicate that window was resized
        return YES;
    }

    // Indicate that window was not resized
    return NO;
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification
{
    if (fullScreenWindow) {
        [fullScreenWindow applicationDidChangeScreenParameters:notification];
    } else if (fullScreenEnabled) {
        ASLogDebug(@"Re-maximizing full-screen window...");
        [self maximizeWindow:fullScreenOptions];
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

+ (NSString *)tabBarStyleForUnified
{
    return shouldUseYosemiteTabBarStyle() ? @"Yosemite" : @"Unified";
}

+ (NSString *)tabBarStyleForMetal
{
    return shouldUseYosemiteTabBarStyle() ? @"Yosemite" : @"Metal";
}

@end // MMWindowController (Private)

