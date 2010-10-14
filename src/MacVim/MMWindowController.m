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

#import "MMAppController.h"
#import "MMAtsuiTextView.h"
#import "MMFindReplaceController.h"
#import "MMFullscreenWindow.h"
#import "MMTextView.h"
#import "MMTypesetter.h"
#import "MMVimController.h"
#import "MMVimView.h"
#import "MMWindow.h"
#import "MMWindowController.h"
#import "Miscellaneous.h"
#import <PSMTabBarControl/PSMTabBarControl.h>



@interface MMWindowController (Private)
- (NSSize)contentSize;
- (void)resizeWindowToFitContentSize:(NSSize)contentSize
                        keepOnScreen:(BOOL)onScreen;
- (NSSize)constrainContentSizeToScreenSize:(NSSize)contentSize;
- (NSRect)constrainFrame:(NSRect)frame;
- (void)updateResizeConstraints;
- (NSTabViewItem *)addNewTabViewItem;
- (BOOL)askBackendForStarRegister:(NSPasteboard *)pb;
- (void)hideTablineSeparator:(BOOL)hide;
- (void)doFindNext:(BOOL)next;
- (void)updateToolbar;
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
    ASLogDebug(@"");

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
    ASLogDebug(@"%@ %s", [self className], _cmd);

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
    // Indicates that the window is ready to be displayed, but do not display
    // (or place) it yet -- that is done in showWindow.

    [self addNewTabViewItem];

    setupDone = YES;

    [self updateResizeConstraints];
    [self resizeWindowToFitContentSize:[vimView desiredSize]
                          keepOnScreen:YES];
}

- (BOOL)presentWindow:(id)unused
{
    // Actually show the window on screen.  However, if openWindow hasn't
    // already been called nothing will happen (the window will be displayed
    // later).
    if (!setupDone) return NO;

    [[MMAppController sharedInstance] windowControllerWillOpen:self];
    [[self window] makeKeyAndOrderFront:self];

    if (fullscreenWindow) {
        // Delayed entering of full screen happens here (a ":set fu" in a
        // GUIEnter auto command could cause this).
        [fullscreenWindow enterFullscreen];
        fullscreenEnabled = YES;
    }

    return YES;
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
    //ASLogDebug(@"setTextDimensionsWithRows:%d columns:%d isLive:%d "
    //        "keepOnScreen:%d", rows, cols, live, onScreen);

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

    if (windowAutosaveKey) {
        // Autosave rows and columns (only done for window which also autosaves
        // window position).
        id tv = [vimView textView];
        int rows = [tv maxRows];
        int cols = [tv maxColumns];
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setInteger:rows forKey:MMAutosaveRowsKey];
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
    if (title)
        [decoratedWindow setTitle:title];
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
    [fullscreenWindow setRepresentedFilename:filename];
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

- (void)createScrollbarWithIdentifier:(int32_t)ident type:(int)type
{
    [vimView createScrollbarWithIdentifier:ident type:type];
}

- (BOOL)destroyScrollbarWithIdentifier:(int32_t)ident
{
    BOOL scrollbarHidden = [vimView destroyScrollbarWithIdentifier:ident];   
    shouldResizeVimView = shouldResizeVimView || scrollbarHidden;

    return scrollbarHidden;
}

- (BOOL)showScrollbarWithIdentifier:(int32_t)ident state:(BOOL)visible
{
    BOOL scrollbarToggled = [vimView showScrollbarWithIdentifier:ident
                                                           state:visible];
    shouldResizeVimView = shouldResizeVimView || scrollbarToggled;

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
    if (fullscreenEnabled)
        [fullscreenWindow setOpaque:isOpaque];

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

    if (shouldResizeVimView) {
        shouldResizeVimView = NO;

        NSSize originalSize = [vimView frame].size;
        NSSize contentSize = [vimView desiredSize];
        contentSize = [self constrainContentSizeToScreenSize:contentSize];
        contentSize = [vimView constrainRows:NULL columns:NULL
                                      toSize:contentSize];
        [vimView setFrameSize:contentSize];

        if (fullscreenEnabled) {
            // NOTE! Don't mark the fullscreen content view as needing an
            // update unless absolutely necessary since when it is updated the
            // entire screen is cleared.  This may cause some parts of the Vim
            // view to be cleared but not redrawn since Vim does not realize
            // that we've erased part of the view.
            if (!NSEqualSizes(originalSize, contentSize)) {
                [[fullscreenWindow contentView] setNeedsDisplay:YES];
                [fullscreenWindow centerView];
            }
        } else {
            [self resizeWindowToFitContentSize:contentSize
                                  keepOnScreen:keepOnScreen];
        }

        keepOnScreen = NO;
    }
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
        shouldResizeVimView = YES;
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

    // NOTE: During live resize messages from MacVim to Vim are often dropped
    // (because too many messages are sent at once).  This may lead to
    // inconsistent states between Vim and MacVim; to avoid this we send a
    // synchronous resize message to Vim now (this is not fool-proof, but it
    // does seem to work quite well).
    // Do NOT send a SetTextDimensionsMsgID message (as opposed to
    // LiveResizeMsgID) since then the view is constrained to not be larger
    // than the screen the window mostly occupies; this makes it impossible to
    // resize the window across multiple screens.

    int constrained[2];
    NSSize textViewSize = [[vimView textView] frame].size;
    [[vimView textView] constrainRows:&constrained[0] columns:&constrained[1]
                               toSize:textViewSize];

    ASLogDebug(@"End of live resize, notify Vim that text dimensions are %dx%d",
               constrained[1], constrained[0]);

    NSData *data = [NSData dataWithBytes:constrained length:2*sizeof(int)];
    BOOL sendOk = [vimController sendMessageNow:LiveResizeMsgID
                                           data:data
                                        timeout:.5];

    if (!sendOk) {
        // Sending of synchronous message failed.  Force the window size to
        // match the last dimensions received from Vim, otherwise we end up
        // with inconsistent states.
        [self resizeWindowToFitContentSize:[vimView desiredSize]
                              keepOnScreen:NO];
    }

    // If we saved the original title while resizing, restore it.
    if (lastSetTitle != nil) {
        [decoratedWindow setTitle:lastSetTitle];
        [lastSetTitle release];
        lastSetTitle = nil;
    }
}

- (void)enterFullscreen:(int)fuoptions backgroundColor:(NSColor *)back
{
    if (fullscreenEnabled) return;

    // fullscreenWindow could be nil here if this is called multiple times
    // during startup.
    [fullscreenWindow release];

    fullscreenWindow = [[MMFullscreenWindow alloc]
            initWithWindow:decoratedWindow view:vimView backgroundColor:back];
    [fullscreenWindow setOptions:fuoptions];
    [fullscreenWindow setRepresentedFilename:
                                        [decoratedWindow representedFilename]];

    // If the window is not visible then delay entering full screen until the
    // window is presented.
    if ([decoratedWindow isVisible]) {
        [fullscreenWindow enterFullscreen];
        fullscreenEnabled = YES;

        // The resize handle disappears so the vim view needs to update the
        // scrollbars.
        shouldResizeVimView = YES;
    } else {
        ASLogDebug(@"Delay enter full screen");
    }
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

- (void)setFullscreenBackgroundColor:(NSColor *)back
{
    if (fullscreenWindow)
        [fullscreenWindow setBackgroundColor:back];
}

- (void)setBuffersModified:(BOOL)mod
{
    // NOTE: We only set the document edited flag on the decorated window since
    // the full-screen window has no close button anyway.  (It also saves us
    // from keeping track of the flag in two different places.)
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
    [vimController sendMessage:GotFocusMsgID data:nil];

    if ([vimView textView]) {
        NSFontManager *fm = [NSFontManager sharedFontManager];
        [fm setSelectedFont:[[vimView textView] font] isMultiple:NO];
    }
}

- (void)windowDidResignMain:(NSNotification *)notification
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

    if (fullscreenEnabled) {
        // HACK! The full-screen is not supposed to be able to be moved.  If we
        // do get here while in full-screen something unexpected happened (e.g.
        // the full-screen window was on an external display that got
        // unplugged) and we handle this situation by leaving full-screen.
        [self leaveFullscreen];
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
    int pos[2] = { (int)topLeft.x, (int)topLeft.y };
    NSData *data = [NSData dataWithBytes:pos length:2*sizeof(int)];
    [vimController sendMessage:SetWindowPositionMsgID data:data];
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
    BOOL cmdLeftClick = [event type] == NSLeftMouseUp &&
                        [event modifierFlags] & NSCommandKeyMask;
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

    if (onScreen && [decoratedWindow screen]) {
        // Ensure that the window fits inside the visible part of the screen.
        // If there are more than one screen the window will be moved to fit
        // entirely in the screen that most of it occupies.
        // NOTE: Not called in full-screen mode so use "visibleFrame' instead
        // of "frame".
        NSRect maxFrame = [[decoratedWindow screen] visibleFrame];
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

    [decoratedWindow setFrame:newFrame display:YES];

    NSPoint oldTopLeft = { frame.origin.x, NSMaxY(frame) };
    NSPoint newTopLeft = { newFrame.origin.x, NSMaxY(newFrame) };
    if (!NSEqualPoints(oldTopLeft, newTopLeft)) {
        // NOTE: The window top left position may change due to the window
        // being moved e.g. when the tabline is shown so we must tell Vim what
        // the new window position is here.
        int pos[2] = { (int)newTopLeft.x, (int)newTopLeft.y };
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
    NSRect screenRect = fullscreenEnabled ? [[win screen] frame]
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
        if ([bestType isEqual:VimFindPboardType])
            query = [pb stringForType:VimFindPboardType];
        else
            query = [pb stringForType:NSStringPboardType];
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
    NSToolbar *toolbar = [decoratedWindow toolbar];
    if (nil == toolbar || 0 == updateToolbarFlag) return;

    // Positive flag shows toolbar, negative hides it.
    BOOL on = updateToolbarFlag > 0 ? YES : NO;
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

    updateToolbarFlag = 0;
}

@end // MMWindowController (Private)
