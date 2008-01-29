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
 * Resizing in full-screen mode:
 *
 * The window never resizes since it fills the screen, however the vim view may
 * change size, e.g. when the user types ":set lines=60", or when a scrollbar
 * is toggled.
 *
 * It is ensured that the vim view never becomes larger than the screen size
 * and that it always stays in the center of the screen.
 *  
 */

#import "MMWindowController.h"
#import "MMAppController.h"
#import "MMAtsuiTextView.h"
#import "MMFullscreenWindow.h"
#import "MMTextView.h"
#import "MMTypesetter.h"
#import "MMVimController.h"
#import "MMVimView.h"
#import "MMWindow.h"
#import "MacVim.h"

#import <PSMTabBarControl.h>



@interface MMWindowController (Private)
- (NSSize)contentSize;
- (void)resizeWindowToFitContentSize:(NSSize)contentSize;
- (NSSize)constrainContentSizeToScreenSize:(NSSize)contentSize;
- (void)updateResizeConstraints;
- (NSTabViewItem *)addNewTabViewItem;
- (IBAction)vimMenuItemAction:(id)sender;
- (BOOL)askBackendForStarRegister:(NSPasteboard *)pb;
- (void)hideTablineSeparator:(BOOL)hide;
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

#ifndef CGFLOAT_DEFINED
    // On Leopard, CGFloat is float on 32bit and double on 64bit. On Tiger,
    // we can't use this anyways, so it's just here to keep the compiler happy.
    // However, when we're compiling for Tiger and running on Leopard, we
    // might need the correct typedef, so this piece is copied from ATSTypes.h
# ifdef __LP64__
    typedef double CGFloat;
# else
    typedef float CGFloat;
# endif
#endif
- (void)setAutorecalculatesContentBorderThickness:(BOOL)b forEdge:(NSRectEdge)e;
- (void)setContentBorderThickness:(CGFloat)b forEdge:(NSRectEdge)e;
@end




@implementation MMWindowController

- (id)initWithVimController:(MMVimController *)controller
{
#ifndef NSAppKitVersionNumber10_4  // needed for non-10.5 sdk
# define NSAppKitVersionNumber10_4 824
#endif
    unsigned styleMask = NSTitledWindowMask | NSClosableWindowMask
            | NSMiniaturizableWindowMask | NSResizableWindowMask
            | NSUnifiedTitleAndToolbarWindowMask;

    // Use textured background on Leopard or later (skip the 'if' on Tiger for
    // polished metal window).
    if ([[NSUserDefaults standardUserDefaults] boolForKey:MMTexturedWindowKey]
            || (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_4))
        styleMask |= NSTexturedBackgroundWindowMask;

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
    
    if ([win styleMask] & NSTexturedBackgroundWindowMask) {
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

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);

    [decoratedWindow release];  decoratedWindow = nil;
    [windowAutosaveKey release];  windowAutosaveKey = nil;
    [vimView release];  vimView = nil;

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
    //NSLog(@"%@ %s", [self className], _cmd);

    if (fullscreenEnabled) {
        // If we are closed while still in fullscreen, end fullscreen mode,
        // release ourselves (because this won't happen in MMWindowController)
        // and perform close operation on the original window.
        [self leaveFullscreen];
    }

    setupDone = NO;
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
    [[NSApp delegate] windowControllerWillOpen:self];

    [self addNewTabViewItem];

    setupDone = YES;

    [self updateResizeConstraints];
    [self resizeWindowToFitContentSize:[vimView desiredSize]];
    [[self window] makeKeyAndOrderFront:self];
}

- (void)updateTabsWithData:(NSData *)data
{
    [vimView updateTabsWithData:data];
}

- (void)selectTabWithIndex:(int)idx
{
    [vimView selectTabWithIndex:idx];
}

- (void)setTextDimensionsWithRows:(int)rows columns:(int)cols live:(BOOL)live
{
    //NSLog(@"setTextDimensionsWithRows:%d columns:%d live:%s", rows, cols,
    //        live ? "YES" : "NO");

    // NOTE: This is the only place where the (rows,columns) of the vim view
    // are modified.  Setting these values have no immediate effect, the actual
    // resizing of the view is done in processCommandQueueDidFinish.
    //
    // The 'live' flag indicates that this resize originated from a live
    // resize; it may very well happen that the view is no longer in live
    // resize when this message is received.  We refrain from changing the view
    // size when this flag is set, otherwise the window might jitter when the
    // user drags to resize the window.

    [vimView setDesiredRows:rows columns:cols];

    if (setupDone && !live)
        shouldResizeVimView = YES;
}

- (void)setTitle:(NSString *)title
{
    if (title) {
        [decoratedWindow setTitle:title];
        [fullscreenWindow setTitle:title];
    }
}

- (void)setToolbar:(NSToolbar *)toolbar
{
    // The full-screen window has no toolbar.
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

- (void)createScrollbarWithIdentifier:(long)ident type:(int)type
{
    [vimView createScrollbarWithIdentifier:ident type:type];
}

- (BOOL)destroyScrollbarWithIdentifier:(long)ident
{
    BOOL scrollbarHidden = [vimView destroyScrollbarWithIdentifier:ident];   
    shouldResizeVimView = shouldResizeVimView || scrollbarHidden;

    return scrollbarHidden;
}

- (BOOL)showScrollbarWithIdentifier:(long)ident state:(BOOL)visible
{
    BOOL scrollbarToggled = [vimView showScrollbarWithIdentifier:ident
                                                           state:visible];
    shouldResizeVimView = shouldResizeVimView || scrollbarToggled;

    return scrollbarToggled;
}

- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident
{
    [vimView setScrollbarPosition:pos length:len identifier:ident];
}

- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(long)ident
{
    [vimView setScrollbarThumbValue:val proportion:prop identifier:ident];
}

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore
{
    // NOTE: This is called when the transparency changes so set the opacity
    // flag on the window here (should be faster if the window is opaque).
    BOOL isOpaque = [back alphaComponent] == 1.0f;
    [[self window] setOpaque:isOpaque];

    [vimView setDefaultColorsBackground:back foreground:fore];
}

- (void)setFont:(NSFont *)font
{
    [[NSFontManager sharedFontManager] setSelectedFont:font isMultiple:NO];
    [[vimView textView] setFont:font];
    [self updateResizeConstraints];
}

- (void)setWideFont:(NSFont *)font
{
    [[vimView textView] setWideFont:font];
}

- (void)processCommandQueueDidFinish
{
    // NOTE: Resizing is delayed until after all commands have been processed
    // since it often happens that more than one command will cause a resize.
    // If we were to immediately resize then the vim view size would jitter
    // (e.g.  hiding/showing scrollbars often happens several time in one
    // update).

    if (shouldResizeVimView) {
        shouldResizeVimView = NO;

        NSSize contentSize = [vimView desiredSize];
        contentSize = [self constrainContentSizeToScreenSize:contentSize];
        contentSize = [vimView constrainRows:NULL columns:NULL
                                      toSize:contentSize];
        [vimView setFrameSize:contentSize];

        if (fullscreenEnabled) {
            [[fullscreenWindow contentView] setNeedsDisplay:YES];
            [fullscreenWindow centerView];
        } else {
            [self resizeWindowToFitContentSize:contentSize];
        }
    }
}

- (void)popupMenu:(NSMenu *)menu atRow:(int)row column:(int)col
{
    if (!setupDone) return;

    NSEvent *event;
    if (row >= 0 && col >= 0) {
        // TODO: Let textView convert (row,col) to NSPoint.
        NSSize cellSize = [[vimView textView] cellSize];
        NSPoint pt = { (col+1)*cellSize.width, (row+1)*cellSize.height };
        pt = [[vimView textView] convertPoint:pt toView:nil];

        event = [NSEvent mouseEventWithType:NSRightMouseDown
                                   location:pt
                              modifierFlags:0
                                  timestamp:0
                               windowNumber:[[self window] windowNumber]
                                    context:nil
                                eventNumber:0
                                 clickCount:0
                                   pressure:1.0];
    } else {
        event = [[vimView textView] lastMouseDownEvent];
    }

    [NSMenu popUpContextMenu:menu withEvent:event forView:[vimView textView]];
}

- (void)showTabBar:(BOOL)on
{
    [[vimView tabBarControl] setHidden:!on];

    // Showing the tabline may result in the tabline separator being hidden or
    // shown; this does not apply to full-screen mode.
    if (!on) {
        NSToolbar *toolbar = [decoratedWindow toolbar]; 
        if (([decoratedWindow styleMask] & NSTexturedBackgroundWindowMask)
                == 0) {
            [self hideTablineSeparator:![toolbar isVisible]];
        } else {
            [self hideTablineSeparator:NO];
        }
    } else {
        if (([decoratedWindow styleMask] & NSTexturedBackgroundWindowMask)
                == 0) {
            [self hideTablineSeparator:on];
        } else {
            [self hideTablineSeparator:YES];
        }
    }
}

- (void)showToolbar:(BOOL)on size:(int)size mode:(int)mode
{
    NSToolbar *toolbar = [decoratedWindow toolbar];
    if (!toolbar) return;

    [toolbar setSizeMode:size];
    [toolbar setDisplayMode:mode];
    [toolbar setVisible:on];

    if (([decoratedWindow styleMask] & NSTexturedBackgroundWindowMask) == 0) {
        if (!on) {
            [self hideTablineSeparator:YES];
        } else {
            [self hideTablineSeparator:![[vimView tabBarControl] isHidden]];
        }
    } else {
        // Textured windows don't have a line below there title bar, so we
        // need the separator in this case as well. In fact, the only case
        // where we don't need the separator is when the tab bar control
        // is visible (because it brings its own separator).
        [self hideTablineSeparator:![[vimView tabBarControl] isHidden]];
    }
}

- (void)setMouseShape:(int)shape
{
    // This switch should match mshape_names[] in misc2.c.
    //
    // TODO: Add missing cursor shapes.
    switch (shape) {
        case 2: [[NSCursor IBeamCursor] set]; break;
        case 3: case 4: [[NSCursor resizeUpDownCursor] set]; break;
        case 5: case 6: [[NSCursor resizeLeftRightCursor] set]; break;
        case 9: [[NSCursor crosshairCursor] set]; break;
        case 10: [[NSCursor pointingHandCursor] set]; break;
        case 11: [[NSCursor openHandCursor] set]; break;
        default:
            [[NSCursor arrowCursor] set]; break;
    }

    // Shape 1 indicates that the mouse cursor should be hidden.
    if (1 == shape)
        [NSCursor setHiddenUntilMouseMoves:YES];
}

- (void)adjustLinespace:(int)linespace
{
    if (vimView && [vimView textView]) {
        [[vimView textView] setLinespace:(float)linespace];
        shouldResizeVimView = YES;
    }
}

- (void)liveResizeWillStart
{
    // Save the original title, if we haven't already.
    if (lastSetTitle == nil) {
        lastSetTitle = [[decoratedWindow title] retain];
    }
}

- (void)liveResizeDidEnd
{
    if (!setupDone) return;

    // NOTE: During live resize messages from MacVim to Vim are often dropped
    // (because too many messages are sent at once).  This may lead to
    // inconsistent states between Vim and MacVim; to avoid this we send a
    // synchronous resize message to Vim now (this is not fool-proof, but it
    // does seem to work quite well).

    int constrained[2];
    NSSize textViewSize = [[vimView textView] frame].size;
    [[vimView textView] constrainRows:&constrained[0] columns:&constrained[1]
                               toSize:textViewSize];

    //NSLog(@"End of live resize, notify Vim that text dimensions are %dx%d",
    //       constrained[1], constrained[0]);

    NSData *data = [NSData dataWithBytes:constrained length:2*sizeof(int)];
    BOOL sendOk = [vimController sendMessageNow:SetTextDimensionsMsgID
                                           data:data
                                        timeout:.5];

    if (!sendOk) {
        // Sending of synchronous message failed.  Force the window size to
        // match the last dimensions received from Vim, otherwise we end up
        // with inconsistent states.
        [self resizeWindowToFitContentSize:[vimView desiredSize]];
    }

    // If we saved the original title while resizing, restore it.
    if (lastSetTitle != nil) {
        [decoratedWindow setTitle:lastSetTitle];
        [lastSetTitle release];
        lastSetTitle = nil;
    }
}

- (void)enterFullscreen
{
    if (fullscreenEnabled) return;

    fullscreenWindow = [[MMFullscreenWindow alloc]
            initWithWindow:decoratedWindow view:vimView];
    [fullscreenWindow enterFullscreen];    
    [fullscreenWindow setDelegate:self];
    fullscreenEnabled = YES;

    // The resize handle disappears so the vim view needs to update the
    // scrollbars.
    shouldResizeVimView = YES;
}

- (void)leaveFullscreen
{
    if (!fullscreenEnabled) return;

    fullscreenEnabled = NO;
    [fullscreenWindow leaveFullscreen];    
    [fullscreenWindow release];
    fullscreenWindow = nil;

    // The vim view may be too large to fit the screen, so update it.
    shouldResizeVimView = YES;
}

- (void)setBuffersModified:(BOOL)mod
{
    // NOTE: We only set the document edited flag on the decorated window since
    // the full-screen window has no close button anyway.  (It also saves us
    // from keeping track of the flag in two different places.)
    [decoratedWindow setDocumentEdited:mod];
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
    // NOTE: File->Close is bound to this action message instead binding it
    // directly to the below vim input so that File->Close also works for
    // auxiliary windows such as the About dialog.  (If we were to bind the
    // below, then <D-w> will not close e.g. the About dialog.)
    [vimController addVimInput:@"<C-\\><C-N>:conf q<CR>"];
}


// -- NSWindow delegate ------------------------------------------------------

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    [vimController updateMainMenu];
    [vimController sendMessage:GotFocusMsgID data:nil];

    if ([vimView textView]) {
        NSFontManager *fm = [NSFontManager sharedFontManager];
        [fm setSelectedFont:[[vimView textView] font] isMultiple:NO];
    }
}

- (void)windowDidResignMain:(NSNotification *)notification
{
    [vimController sendMessage:LostFocusMsgID data:nil];

    if ([vimView textView])
        [[vimView textView] hideMarkedTextField];
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
    if (setupDone && windowAutosaveKey) {
        NSRect frame = [decoratedWindow frame];
        NSPoint topLeft = { frame.origin.x, NSMaxY(frame) };
        NSString *topLeftString = NSStringFromPoint(topLeft);

        [[NSUserDefaults standardUserDefaults]
            setObject:topLeftString forKey:windowAutosaveKey];
    }
}

- (void)windowDidResize:(id)sender
{
    if (!setupDone || fullscreenEnabled) return;

    // NOTE: Since we have no control over when the window may resize (Cocoa
    // may resize automatically) we simply set the view to fill the entire
    // window.  The vim view takes care of notifying Vim if the number of
    // (rows,columns) changed.
    [vimView setFrameSize:[self contentSize]];
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)win
                        defaultFrame:(NSRect)frame
{
    // Keep old width and horizontal position unless user clicked while the
    // Command key is held down.
    NSEvent *event = [NSApp currentEvent];
    if (!([event type] == NSLeftMouseUp
            && [event modifierFlags] & NSCommandKeyMask)) {
        NSRect currentFrame = [win frame];
        frame.size.width = currentFrame.size.width;
        frame.origin.x = currentFrame.origin.x;
    }

    return frame;
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
{
    NSRect frame = [decoratedWindow frame];
    NSRect contentRect = [decoratedWindow contentRectForFrameRect:frame];

    // Keep top-left corner of the window fixed when resizing.
    contentRect.origin.y -= contentSize.height - contentRect.size.height;
    contentRect.size = contentSize;

    frame = [decoratedWindow frameRectForContentRect:contentRect];
    [decoratedWindow setFrame:frame display:YES];
}

- (NSSize)constrainContentSizeToScreenSize:(NSSize)contentSize
{
    NSWindow *win = [self window];
    NSRect rect = [win contentRectForFrameRect:[[win screen] visibleFrame]];

    if (contentSize.height > rect.size.height)
        contentSize.height = rect.size.height;
    if (contentSize.width > rect.size.width)
        contentSize.width = rect.size.width;

    return contentSize;
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

- (IBAction)vimMenuItemAction:(id)sender
{
    int tag = [sender tag];

    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&tag length:sizeof(int)];

    [vimController sendMessage:ExecuteMenuMsgID data:data];
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
        @catch (NSException *e) {
            NSLog(@"WARNING: Caught exception in %s: \"%@\"", _cmd, e);
        }
    }

    return reply;
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

@end // MMWindowController (Private)
