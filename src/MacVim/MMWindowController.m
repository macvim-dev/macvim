/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMWindowController.h"
#import <PSMTabBarControl.h>
#import "MMTextView.h"
#import "MMTextStorage.h"
#import "MMVimController.h"
#import "MacVim.h"
#import "MMAppController.h"
#import "MMTypesetter.h"
#import "MMFullscreenWindow.h"
#import "MMVimView.h"



@interface MMWindowController (Private)
- (NSSize)contentSize;
- (NSRect)contentRectForFrameRect:(NSRect)frame;
- (NSRect)frameRectForContentRect:(NSRect)contentRect;
- (void)resizeWindowToFit:(id)sender;
- (NSRect)fitWindowToFrame:(NSRect)frame;
- (void)updateResizeIncrements;
- (NSTabViewItem *)addNewTabViewItem;
- (IBAction)vimMenuItemAction:(id)sender;
- (BOOL)askBackendForStarRegister:(NSPasteboard *)pb;
- (void)checkWindowNeedsResizing;
- (NSSize)resizeVimViewToFitSize:(NSSize)size;
@end



#if 0
NSString *buildMenuItemDescriptor(NSMenu *menu, NSString *tail)
{
    return menu ? buildMenuItemDescriptor([menu supermenu], [[menu title]
                    stringByAppendingString:tail])
                : tail;
}

NSMutableArray *buildMenuAddress(NSMenu *menu)
{
    NSMutableArray *addr;
    if (menu) {
        addr = buildMenuAddress([menu supermenu]);
        [addr addObject:[menu title]];
    } else {
        addr = [NSMutableArray array];
    }

    return addr;
}
#endif

// Note: This hack allows us to set content shadowing separately from
// the window shadow.  This is apparently what webkit and terminal do.
@interface NSWindow (NSWindowPrivate) // new Tiger private method
- (void)_setContentHasShadow:(BOOL)shadow;
@end


@implementation MMWindowController

- (id)initWithVimController:(MMVimController *)controller
{
    if ((self = [super initWithWindowNibName:@"EmptyWindow"])) {
        vimController = controller;

        // Window cascading is handled by MMAppController.
        [self setShouldCascadeWindows:NO];

        NSWindow *win = [self window];
        NSView *contentView = [win contentView];
        vimView = [[MMVimView alloc] initWithFrame:[contentView frame]
                                     vimController:vimController];
        [contentView addSubview:vimView];
        // [vimView translateOriginToPoint:
        //     NSMakePoint([contentView frame].size.width, 0)];
        // [vimView rotateByAngle:45.f];

        // Create the tabline separator (which may be visible when the tabline
        // is hidden).
        NSRect tabSepRect = [contentView frame];
        tabSepRect.origin.y = NSMaxY(tabSepRect)-1;
        tabSepRect.size.height = 1;
        tablineSeparator = [[NSBox alloc] initWithFrame:tabSepRect];
        
        [tablineSeparator setBoxType:NSBoxSeparator];
        [tablineSeparator setHidden:NO];
        [tablineSeparator setAutoresizingMask:NSViewWidthSizable
            | NSViewMinYMargin];

        [contentView setAutoresizesSubviews:YES];
        [contentView addSubview:tablineSeparator];

        [win setDelegate:self];
        [win setInitialFirstResponder:[vimView textView]];
	
        // Make us safe on pre-tiger OSX
        if ([win respondsToSelector:@selector(_setContentHasShadow:)])
            [win _setContentHasShadow:NO];
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);

    [tablineSeparator release];  tablineSeparator = nil;
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

- (MMTextView *)textView
{
    return [vimView textView];
}

- (MMTextStorage *)textStorage
{
    return [vimView textStorage];
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

    if (fullscreenWindow != nil) {
        // if we are closed while still in fullscreen, end fullscreen mode,
        // release ourselves (because this won't happen in MMWindowController)
        // and perform close operation on the original window
        [self leaveFullscreen];
    }


    setupDone = NO;
    vimController = nil;

    [tablineSeparator removeFromSuperviewWithoutNeedingDisplay];
    [vimView removeFromSuperviewWithoutNeedingDisplay];
    [vimView cleanup];  // TODO: is this necessary?

    [[self window] orderOut:self];
}

- (void)openWindow
{
    [[NSApp delegate] windowControllerWillOpen:self];

    [self addNewTabViewItem];

    setupDone = YES;

    [self updateResizeIncrements];
    [self resizeWindowToFit:self];
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

- (void)setTextDimensionsWithRows:(int)rows columns:(int)cols
{
    //NSLog(@"setTextDimensionsWithRows:%d columns:%d", rows, cols);

    [vimView setActualRows:rows columns:cols];

    if (setupDone && ![vimView inLiveResize])
        shouldUpdateWindowSize = YES;
}

- (void)createScrollbarWithIdentifier:(long)ident type:(int)type
{
    [vimView createScrollbarWithIdentifier:ident type:type];
}

- (void)destroyScrollbarWithIdentifier:(long)ident
{
    [vimView destroyScrollbarWithIdentifier:ident];   
    [self checkWindowNeedsResizing];
}

- (void)showScrollbarWithIdentifier:(long)ident state:(BOOL)visible
{
    [vimView showScrollbarWithIdentifier:ident state:visible];
    [self checkWindowNeedsResizing];
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
    [[vimView textStorage] setFont:font];
    [self updateResizeIncrements];
}

- (void)processCommandQueueDidFinish
{
    // XXX: If not in live resize and vimview's desired size differs from actual
    // size, resize ourselves
    if (shouldUpdateWindowSize) {
        shouldUpdateWindowSize = NO;
        [vimView setShouldUpdateWindowSize:NO];
        [self resizeWindowToFit:self];
    }
}

- (void)popupMenu:(NSMenu *)menu atRow:(int)row column:(int)col
{
    if (!setupDone) return;

    NSEvent *event;
    if (row >= 0 && col >= 0) {
        NSSize cellSize = [[vimView textStorage] cellSize];
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

    if (!on) {
        NSToolbar *toolbar = [[self window] toolbar]; 
        [tablineSeparator setHidden:![toolbar isVisible]];
    } else {
        [tablineSeparator setHidden:on];
    }

    //if (setupDone)
    //    shouldUpdateWindowSize = YES;
}

- (void)showToolbar:(BOOL)on size:(int)size mode:(int)mode
{
    NSToolbar *toolbar = [[self window] toolbar];
    if (!toolbar) return;

    [toolbar setSizeMode:size];
    [toolbar setDisplayMode:mode];
    [toolbar setVisible:on];

    if (!on) {
        [tablineSeparator setHidden:YES];
    } else {
        [tablineSeparator setHidden:![[vimView tabBarControl] isHidden]];
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
    if (vimView && [vimView textStorage]) {
        [[vimView textStorage] setLinespace:(float)linespace];
        shouldUpdateWindowSize = YES;
    }
}

- (void)liveResizeWillStart
{
    // Save the original title, if we haven't already.
    if (lastSetTitle == nil) {
        lastSetTitle = [[[self window] title] retain];
    }
}

- (void)liveResizeDidEnd
{
    if (!setupDone) return;

    // At the end of an resize, check if vim view size and number of
    // columns / rows agree (the first is set while resizing, the second by
    // messages sent from vim). If not, send a synchronous (!) message to vim
    // to set columns / rows to the value belonging to the view size. If the
    // message couldn't be sent, change the view size to fit columns / rows.

    // NOTE!  It is assumed that the window has been resized so that it will
    // exactly fit the text storage (possibly after resizing it).  If this is
    // not the case the display might be messed up.
    BOOL resizeFailed = NO;
    NSSize contentSize = [self contentSize];

    int desiredSize[2];
    [vimView getDesiredRows:&desiredSize[0] columns:&desiredSize[1]
                    forSize:contentSize];

    int rows, columns;
    [vimView getActualRows:&rows columns:&columns];

    if (desiredSize[0] != rows || desiredSize[1] != columns) {

        NSData *data = [NSData dataWithBytes:desiredSize length:2*sizeof(int)];

        // NOTE:  Since we're at the end of a live resize we want to make sure
        // that the SetTextDimensionsMsgID message reaches Vim, else Vim and
        // MacVim will have inconsistent states (i.e. the text view will be too
        // large or too small for the window size).  Thus, add a timeout (this
        // may have to be tweaked) and take note if the message was sent or
        // not.
        resizeFailed = ![vimController sendMessageNow:SetTextDimensionsMsgID
                                                 data:data
                                              timeout:.5];
    }

    if (resizeFailed) {
        // Force the window size to match the text view size otherwise Vim and
        // MacVim will have inconsistent states.
        [self resizeWindowToFit:self];
    }

    // If we saved the original title while resizing, restore it.
    if (lastSetTitle != nil) {
        [[self window] setTitle:lastSetTitle];
        [lastSetTitle release];
        lastSetTitle = nil;
    }
}

- (void)placeViews
{
    if (!setupDone) return;

    NSRect vimViewRect;
    vimViewRect.origin = NSMakePoint(0, 0);
    vimViewRect.size = [vimView getDesiredRows:NULL columns:NULL
                                       forSize:[self contentSize]];

     // HACK! If the window does resize, then windowDidResize is called which in
     // turn calls placeViews.  In case the computed new size of the window is
     // no different from the current size, then we need to call placeViews
     // manually.
     if (NSEqualRects(vimViewRect, [vimView frame])) {
         [vimView placeViews];
     } else {
         [vimView setFrame:vimViewRect];
     }
}

- (void)enterFullscreen
{
    fullscreenWindow = [[MMFullscreenWindow alloc] initWithWindow:[self window]
                                                             view:vimView];
    [fullscreenWindow enterFullscreen];    
      
    [fullscreenWindow setDelegate:self];
}

- (void)leaveFullscreen
{
    [fullscreenWindow leaveFullscreen];    
    [fullscreenWindow release];
    fullscreenWindow = nil;
}


- (IBAction)addNewTab:(id)sender
{
    [vimView addNewTab:sender];
}

- (IBAction)toggleToolbar:(id)sender
{
    [vimController sendMessage:ToggleToolbarMsgID data:nil];
}



// -- NSWindow delegate ------------------------------------------------------

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    [vimController sendMessage:GotFocusMsgID data:nil];

    if ([vimView textStorage]) {
        NSFontManager *fontManager = [NSFontManager sharedFontManager];
        [fontManager setSelectedFont:[[vimView textStorage] font]
                          isMultiple:NO];
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
    [vimController sendMessage:VimShouldCloseMsgID data:nil];
    return NO;
}

- (void)windowDidMove:(NSNotification *)notification
{
    if (setupDone && windowAutosaveKey) {
        NSRect frame = [[self window] frame];
        NSPoint topLeft = { frame.origin.x, NSMaxY(frame) };
        NSString *topLeftString = NSStringFromPoint(topLeft);

        [[NSUserDefaults standardUserDefaults]
            setObject:topLeftString forKey:windowAutosaveKey];
    }
}

- (void)windowDidResize:(id)sender
{
    if (!setupDone) return;

    // Live resizing works as follows:
    // VimView's size is changed immediatly, and a resize message to the
    // remote vim instance is sent. The remote vim instance sends a
    // "vim content size changed" right back, but in live resize mode this
    // doesn't change the VimView (because we assume that it already has the
    // correct size because we set the resize increments correctly). Afterward,
    // the remote vim view sends a batch draw for the text visible in the
    // resized text area.

    NSSize contentSize = [self contentSize];
    [self resizeVimViewToFitSize:contentSize];

    NSRect frame;
    frame.origin = NSMakePoint(0, 0);
    frame.size = contentSize;
    [vimView setFrame:frame];
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)win
                        defaultFrame:(NSRect)frame
{
    // HACK!  For some reason 'frame' is not always constrained to fit on the
    // screen (e.g. it may overlap the menu bar), so first constrain it to the
    // screen; otherwise the new frame we compute may be too large and this
    // will mess up the display after the window resizes.
    frame = [win constrainFrameRect:frame toScreen:[win screen]];

    // HACK!  If the top of 'frame' is lower than the current window frame,
    // increase 'frame' so that their tops align.  Really, 'frame' should
    // already have its top at least as high as the current window frame, but
    // for some reason this is not always the case.
    // (See resizeWindowToFit: for a similar hack.)
    NSRect cur = [win frame];
    if (NSMaxY(cur) > NSMaxY(frame)) {
        frame.size.height = cur.origin.y - frame.origin.y + cur.size.height;
    }

    frame = [self fitWindowToFrame:frame];

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

- (NSRect)contentRectForFrameRect:(NSRect)frame
{
    NSRect result = [[self window] contentRectForFrameRect:frame];
    if (![tablineSeparator isHidden])
        --result.size.height;
    return result;
}

- (NSRect)frameRectForContentRect:(NSRect)contentRect
{
    if (![tablineSeparator isHidden])
        ++contentRect.size.height;
    return [[self window] frameRectForContentRect:contentRect];
}

- (NSSize)contentSize
{
    return [self contentRectForFrameRect:[[self window] frame]].size;
}

- (void)resizeWindowToFit:(id)sender
{
    // Makes the window large enough to contain the vim view, called after the
    // vim view's size was changed. If the window had to become to big, the
    // vim view is made smaller.

    // NOTE: Be very careful when you call this method!  Do not call while
    // processing command queue, instead set 'shouldUpdateWindowSize' to YES.
    // The only other place it is currently called is when live resize ends.
    // This is done to ensure that the text view and window sizes match up
    // (they may become out of sync if a SetTextDimensionsMsgID message to the
    // backend is dropped).

    if (!setupDone) return;

    // Get size of text view, adapt window size to it
    NSWindow *win = [self window];
    NSRect frame = [win frame];
    NSRect contentRect = [self contentRectForFrameRect:frame];
    NSSize newSize = [vimView desiredSizeForActualRowsAndColumns];

    // Keep top-left corner of the window fixed when resizing.
    contentRect.origin.y -= newSize.height - contentRect.size.height;
    contentRect.size = newSize;

    frame = [self frameRectForContentRect:contentRect];
    NSRect maxFrame = [win constrainFrameRect:frame toScreen:[win screen]];

    // HACK!  Assuming the window frame cannot already be placed too high,
    // adjust 'maxFrame' so that it at least as high up as the current frame.
    // The reason for doing this is that constrainFrameRect:toScreen: does not
    // always seem to utilize as much area as possible.
    if (NSMaxY(frame) > NSMaxY(maxFrame)) {
        maxFrame.size.height = frame.origin.y - maxFrame.origin.y
                + frame.size.height;
    }

    if (!NSEqualRects(maxFrame, frame)) {
        // The new window frame is too big to fit on the screen, so fit the
        // text storage to the biggest frame which will fit on the screen.
        //NSLog(@"Proposed window frame does not fit on the screen!");
        frame = [self fitWindowToFrame:maxFrame];
        [self resizeVimViewToFitSize:[self contentRectForFrameRect:frame].size];
    }

    // NSLog(@"%s %@", _cmd, NSStringFromRect(frame));

    // HACK! If the window does resize, then windowDidResize is called which in
    // turn calls placeViews.  In case the computed new size of the window is
    // no different from the current size, then we need to call placeViews
    // manually.
    if (NSEqualRects(frame, [win frame])) {
        [self placeViews];
    } else {
        [win setFrame:frame display:YES];
    }
}

- (NSRect)fitWindowToFrame:(NSRect)frame
{
    if (!setupDone) return frame;

    NSRect contentRect = [self contentRectForFrameRect:frame];
    NSSize size = [vimView getDesiredRows:NULL columns:NULL
                                  forSize:contentRect.size];

    // Keep top-left corner of 'frame' fixed.
    contentRect.origin.y -= size.height - contentRect.size.height;
    contentRect.size = size;

    return [self frameRectForContentRect:contentRect];
}

- (void)updateResizeIncrements
{
    if (!setupDone) return;

    NSSize size = [[vimView textStorage] cellSize];
    [[self window] setContentResizeIncrements:size];
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

- (void)checkWindowNeedsResizing
{
    shouldUpdateWindowSize =
        shouldUpdateWindowSize || [vimView shouldUpdateWindowSize];
}

- (NSSize)resizeVimViewToFitSize:(NSSize)size
{
    // If our optimal (rows,cols) do not match our current (rows,cols), resize
    // ourselves and tell the Vim process to sync up.
    int desired[2];
    NSSize newSize = [vimView getDesiredRows:&desired[0] columns:&desired[1]
                              forSize:size];

    int rows, columns;
    [vimView getActualRows:&rows columns:&columns];

    if (desired[0] != rows || desired[1] != columns) {
        // NSLog(@"Notify Vim that text storage dimensions changed from %dx%d "
        //       @"to %dx%d", columns, rows, desired[0], desired[1]);
        NSData *data = [NSData dataWithBytes:desired length:2*sizeof(int)];

        [vimController sendMessage:SetTextDimensionsMsgID data:data];

        // We only want to set the window title if this resize came from
        // a live-resize, not (for example) setting 'columns' or 'lines'.
        if ([[self textView] inLiveResize]) {
            [[self window] setTitle:[NSString stringWithFormat:@"%dx%d",
                    desired[1], desired[0]]];
        }
    }

    return newSize;
}


@end // MMWindowController (Private)
