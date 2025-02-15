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
 * MMVimView
 *
 * A view class with a tabline, scrollbars, and a text view.  The tabline may
 * appear at the top of the view in which case it fills up the view from left
 * to right edge.  Any number of scrollbars may appear adjacent to all other
 * edges of the view (there may be more than one scrollbar per edge and
 * scrollbars may also be placed on the left edge of the view).  The rest of
 * the view is filled by the text view.
 */

#import "Miscellaneous.h"
#import "MMCoreTextView.h"
#import "MMTextView.h"
#import "MMVimController.h"
#import "MMVimView.h"
#import "MMWindowController.h"
#import "MMTabline.h"



// Scroller type; these must match SBAR_* in gui.h
enum {
    MMScrollerTypeLeft = 0,
    MMScrollerTypeRight,
    MMScrollerTypeBottom
};

typedef enum: NSInteger {
    MMTabColorTypeTabBg = 0,
    MMTabColorTypeTabFg,
    MMTabColorTypeSelBg,
    MMTabColorTypeSelFg,
    MMTabColorTypeFillBg,
    MMTabColorTypeFillFg,
    MMTabColorTypeCount
} MMTabColorType;


// TODO:  Move!
@interface MMScroller : NSScroller {
    int32_t identifier;
    int type;
    NSRange range;
}
- (id)initWithIdentifier:(int32_t)ident type:(int)type;
- (int32_t)scrollerId;
- (int)type;
- (NSRange)range;
- (void)setRange:(NSRange)newRange;
@end


@interface MMVimView (Private) <MMTablineDelegate>
- (BOOL)bottomScrollbarVisible;
- (BOOL)leftScrollbarVisible;
- (BOOL)rightScrollbarVisible;
- (void)placeScrollbars;
- (MMScroller *)scrollbarForIdentifier:(int32_t)ident index:(unsigned *)idx;
- (NSSize)vimViewSizeForTextViewSize:(NSSize)textViewSize;
- (NSRect)textViewRectForVimViewSize:(NSSize)contentSize;
- (void)frameSizeMayHaveChanged:(BOOL)keepGUISize;
@end


// This is an informal protocol implemented by MMWindowController (maybe it
// shold be a formal protocol, but ...).
@interface NSWindowController (MMVimViewDelegate)
- (void)liveResizeWillStart;
- (void)liveResizeDidEnd;
@end



@implementation MMVimView
{
    NSColor *tabColors[MMTabColorTypeCount];
}

- (MMVimView *)initWithFrame:(NSRect)frame
               vimController:(MMVimController *)controller
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    vimController = controller;
    scrollbars = [[NSMutableArray alloc] init];

    // Only the tabline is autoresized, all other subview placement is done in
    // frameSizeMayHaveChanged.
    [self setAutoresizesSubviews:YES];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger renderer = [ud integerForKey:MMRendererKey];
    ASLogInfo(@"Use renderer=%ld", renderer);

    if (MMRendererCoreText == renderer) {
        // HACK! 'textView' has type MMTextView, but MMCoreTextView is not
        // derived from MMTextView.
        textView = (MMTextView *)[[MMCoreTextView alloc] initWithFrame:frame];
    } else {
        // Use Cocoa text system for text rendering.
        textView = [[MMTextView alloc] initWithFrame:frame];
    }

    // Allow control of text view inset via MMTextInset* user defaults.
    [textView setTextContainerInset:NSMakeSize(
        [ud integerForKey:MMTextInsetLeftKey],
        [ud integerForKey:MMTextInsetTopKey])];

    [textView setAutoresizingMask:NSViewNotSizable];
    [self addSubview:textView];
    
    // Create the tabline which is responsible for drawing the tabline and tabs.
    NSRect tablineFrame = {{0, frame.size.height - MMTablineHeight}, {frame.size.width, MMTablineHeight}};
    tabline = [[MMTabline alloc] initWithFrame:tablineFrame];
    tabline.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    tabline.delegate = self;
    tabline.hidden = YES;
    tabline.showsAddTabButton = [ud boolForKey:MMShowAddTabButtonKey];
    tabline.showsTabScrollButtons = [ud boolForKey:MMShowTabScrollButtonsKey];
    tabline.useAnimation = ![ud boolForKey:MMDisableTablineAnimationKey];
    tabline.optimumTabWidth = [ud integerForKey:MMTabOptimumWidthKey];
    tabline.minimumTabWidth = [ud integerForKey:MMTabMinWidthKey];
    tabline.addTabButton.target = self;
    tabline.addTabButton.action = @selector(addNewTab:);
    [tabline registerForDraggedTypes:@[getPasteboardFilenamesType()]];
    [self addSubview:tabline];
    
    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [tabline release];
    [scrollbars release];  scrollbars = nil;

    for (NSUInteger i = 0; i < MMTabColorTypeCount; i++)
        [tabColors[i] release];

    // HACK! The text storage is the principal owner of the text system, but we
    // keep only a reference to the text view, so release the text storage
    // first (unless we are using the CoreText renderer).
    if ([textView isKindOfClass:[MMTextView class]])
        [[textView textStorage] release];

    [textView release];  textView = nil;

    [super dealloc];
}

- (BOOL)isOpaque
{
    return textView.defaultBackgroundColor.alphaComponent == 1;
}

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
// The core logic should not be reachable in 10.7 or above and is deprecated code.
// See documentation for showsResizeIndicator and placeScrollbars: comments.
// As such, just ifdef out the whole thing as we no longer support 10.7.
- (void)drawRect:(NSRect)rect
{
    // On Leopard, we want to have a textured window background for nice
    // looking tabs. However, the textured window background looks really
    // weird behind the window resize throbber, so emulate the look of an
    // NSScrollView in the bottom right corner.
    if (![[self window] showsResizeIndicator]
            || !([[self window] styleMask] & NSWindowStyleMaskTexturedBackground))
        return;
    
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
    int sw = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy];
#else
    int sw = [NSScroller scrollerWidth];
#endif

    // add .5 to the pixel locations to put the lines on a pixel boundary.
    // the top and right edges of the rect will be outside of the bounds rect
    // and clipped away.
    NSRect sizerRect = NSMakeRect([self bounds].size.width - sw + .5, -.5,
            sw, sw);
    //NSBezierPath* path = [NSBezierPath bezierPath];
    NSBezierPath* path = [NSBezierPath bezierPathWithRect:sizerRect];

    // On Tiger, we have color #E8E8E8 behind the resize throbber
    // (which is windowBackgroundColor on untextured windows or controlColor in
    // general). Terminal.app on Leopard has #FFFFFF background and #D9D9D9 as
    // stroke. The colors below are #FFFFFF and #D4D4D4, which is close enough
    // for me.
    [[NSColor controlBackgroundColor] set];
    [path fill];

    [[NSColor secondarySelectedControlColor] set];
    [path stroke];

    if ([self leftScrollbarVisible]) {
        // If the left scrollbar is visible there is an empty square under it.
        // Fill it in just like on the right hand corner.  The half pixel
        // offset ensures the outline goes on the top and right side of the
        // square; the left and bottom parts of the outline are clipped.
        sizerRect = NSMakeRect(-.5,-.5,sw,sw);
        path = [NSBezierPath bezierPathWithRect:sizerRect];
        [[NSColor controlBackgroundColor] set];
        [path fill];
        [[NSColor secondarySelectedControlColor] set];
        [path stroke];
    }
}
#endif

- (MMTextView *)textView
{
    return textView;
}

- (MMTabline *)tabline
{
    return tabline;
}

- (void)cleanup
{
    vimController = nil;
    
    [[self window] setDelegate:nil];

    [tabline removeFromSuperviewWithoutNeedingDisplay];
    [textView removeFromSuperviewWithoutNeedingDisplay];

    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *sb = [scrollbars objectAtIndex:i];
        [sb removeFromSuperviewWithoutNeedingDisplay];
    }
}

- (NSSize)desiredSize
{
    return [self vimViewSizeForTextViewSize:[textView desiredSize]];
}

- (NSSize)minSize
{
    return [self vimViewSizeForTextViewSize:[textView minSize]];
}

- (NSSize)constrainRows:(int *)r columns:(int *)c toSize:(NSSize)size
{
    NSSize textViewSize = [self textViewRectForVimViewSize:size].size;
    textViewSize = [textView constrainRows:r columns:c toSize:textViewSize];
    return [self vimViewSizeForTextViewSize:textViewSize];
}

- (void)setDesiredRows:(int)r columns:(int)c
{
    [textView setMaxRows:r columns:c];
}

- (IBAction)addNewTab:(id)sender
{
    // Callback from the "Create a new tab button". We override this so we can
    // send a message to Vim first and let it handle it before replying back.
    [vimController sendMessage:AddNewTabMsgID data:nil];
}

- (IBAction)scrollToCurrentTab:(id)sender
{
    [tabline scrollTabToVisibleAtIndex:tabline.selectedTabIndex];
}

- (IBAction)scrollBackwardOneTab:(id)sender
{
    [tabline scrollBackwardOneTab];
}

- (IBAction)scrollForwardOneTab:(id)sender
{
    [tabline scrollForwardOneTab];
}

- (void)showTabline:(BOOL)on
{
    [tabline setHidden:!on];
    if (!on) {
        // When the tab is not shown we don't get tab updates from Vim. We just
        // close all of them as otherwise we will be holding onto stale states.
        [tabline closeAllTabs];
    }
}

/// Callback from Vim to update the tabline with new tab data
- (void)updateTabsWithData:(NSData *)data
{
    const void *p = [data bytes];
    const void * const end = p + [data length];

    // 1. Current tab is first in the message.
    int curtabIdx = *((int*)p);  p += sizeof(int);

    // 2. Read all the tab IDs (which uniquely identify each tab), and count
    //    the number of Vim tabs in the process of doing so.
    int numTabs = 0;
    BOOL pendingCloseTabClosed = (pendingCloseTabID != 0);
    const intptr_t * const tabIDs = p;
    while (p < end) {
        intptr_t tabID = *((intptr_t*)p); p += sizeof(intptr_t);
        if (tabID == 0) // null-terminated
            break;
        if (pendingCloseTabID != 0 && (NSInteger)tabID == pendingCloseTabID) {
            // Vim hasn't gotten around to handling the tab close message yet,
            // just wait until it has done so.
            pendingCloseTabClosed = NO;
        }
        numTabs += 1;
    }

    BOOL delayTabResize = NO;
    if (pendingCloseTabClosed) {
        // When the user has pressed a tab close button, only animate tab
        // positions, not the widths. This allows the next tab's close button
        // to line up with the last, allowing the user to close multiple tabs
        // quickly.
        delayTabResize = YES;
        pendingCloseTabID = 0;
    }

    // Ask the tabline to update all the tabs based on the tab IDs
    static_assert(sizeof(NSInteger) == sizeof(intptr_t),
                  "Tab tag size mismatch between Vim and MacVim");
    [tabline updateTabsByTags:(NSInteger*)tabIDs
                          len:numTabs
               delayTabResize:delayTabResize];

    // 3. Read all the tab labels/tooltips and assign to each tab
    NSInteger tabIdx = 0;
    while (p < end && tabIdx < tabline.numberOfTabs) {
        MMTab *tv = [tabline tabAtIndex:tabIdx];
        for (unsigned i = 0; i < MMTabInfoCount; ++i) {
            size_t length = *((size_t*)p);  p += sizeof(size_t);
            if (length <= 0)
                continue;
            NSString *val = [[NSString alloc]
                    initWithBytes:(void*)p length:length
                         encoding:NSUTF8StringEncoding];
            p += length;
            if (i == MMTabLabel) {
                tv.title = val;
            } else if (i == MMTabToolTip) {
                tv.toolTip = val;
            }
            [val release];
        }
        tabIdx += 1;
    }

    // Finally, select the currently selected tab
    if (curtabIdx < 0 || curtabIdx >= tabline.numberOfTabs) {
        ASLogWarn(@"No tab with index %d exists.", curtabIdx);
        return;
    }
    if (curtabIdx != tabline.selectedTabIndex) {
        [tabline selectTabAtIndex:curtabIdx];
        [tabline scrollTabToVisibleAtIndex:curtabIdx];
    }
}

- (void)refreshTabProperties
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    tabline.showsTabScrollButtons = [ud boolForKey:MMShowTabScrollButtonsKey];
    [self updateTablineColors:MMTabColorsModeCount];
}

- (void)createScrollbarWithIdentifier:(int32_t)ident type:(int)type
{
    MMScroller *scroller = [[MMScroller alloc] initWithIdentifier:ident
                                                             type:type];
    [scroller setTarget:self];
    [scroller setAction:@selector(scroll:)];

    [self addSubview:scroller];
    [scrollbars addObject:scroller];
    [scroller release];
    
    self.pendingPlaceScrollbars = YES;
}

- (BOOL)destroyScrollbarWithIdentifier:(int32_t)ident
{
    unsigned idx = 0;
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:&idx];
    if (!scroller) return NO;

    [scroller removeFromSuperview];
    [scrollbars removeObjectAtIndex:idx];
    
    self.pendingPlaceScrollbars = YES;

    // If a visible scroller was removed then the vim view must resize.  This
    // is handled by the window controller (the vim view never resizes itself).
    return ![scroller isHidden];
}

- (BOOL)showScrollbarWithIdentifier:(int32_t)ident state:(BOOL)visible
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    if (!scroller) return NO;

    BOOL wasVisible = ![scroller isHidden];
    [scroller setHidden:!visible];
    
    self.pendingPlaceScrollbars = YES;

    // If a scroller was hidden or shown then the vim view must resize.  This
    // is handled by the window controller (the vim view never resizes itself).
    return wasVisible != visible;
}

- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(int32_t)ident
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    [scroller setDoubleValue:val];
    [scroller setKnobProportion:prop];
    [scroller setEnabled:prop != 1.f];
}


- (void)scroll:(id)sender
{
    NSMutableData *data = [NSMutableData data];
    int32_t ident = [(MMScroller*)sender scrollerId];
    unsigned hitPart = (unsigned)[sender hitPart];
    float value = [sender floatValue];

    [data appendBytes:&ident length:sizeof(int32_t)];
    [data appendBytes:&hitPart length:sizeof(unsigned)];
    [data appendBytes:&value length:sizeof(float)];

    [vimController sendMessage:ScrollbarEventMsgID data:data];
}

- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(int32_t)ident
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    NSRange range = NSMakeRange(pos, len);
    if (!NSEqualRanges(range, [scroller range])) {
        [scroller setRange:range];
        // This could be sent because a text window was created or closed, so
        // we might need to update which scrollbars are visible.
    }
    self.pendingPlaceScrollbars = YES;
}

- (void)finishPlaceScrollbars
{
    if (self.pendingPlaceScrollbars) {
        self.pendingPlaceScrollbars = NO;
        [self placeScrollbars];
    }
}

- (void)updateTablineColors:(MMTabColorsMode)mode
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    MMTabColorsMode tabColorsMode = [ud integerForKey:MMTabColorsModeKey];
    if (tabColorsMode >= MMTabColorsModeCount || tabColorsMode < 0) {
        // Catch-all for invalid values, which could be useful if we add new
        // modes and a user goes back and uses an old version of MacVim.
        tabColorsMode = MMTabColorsModeAutomatic;
    }
    if (mode != MMTabColorsModeCount && mode != tabColorsMode) {
        // Early out to avoid unnecessary updates if this is not relevant.
        return;
    }
    if (tabColorsMode == MMTabColorsModeDefaultColors) {
        [tabline setColorsTabBg:nil
                          tabFg:nil
                          selBg:nil
                          selFg:nil
                         fillBg:nil
                         fillFg:nil];
    } else if (tabColorsMode == MMTabColorsModeVimColorscheme) {
        [tabline setColorsTabBg:tabColors[MMTabColorTypeTabBg]
                          tabFg:tabColors[MMTabColorTypeTabFg]
                          selBg:tabColors[MMTabColorTypeSelBg]
                          selFg:tabColors[MMTabColorTypeSelFg]
                         fillBg:tabColors[MMTabColorTypeFillBg]
                         fillFg:tabColors[MMTabColorTypeFillFg]];
    } else {
        // tabColorsMode == MMTabColorsModeAutomatic
        NSColor *back = [[self textView] defaultBackgroundColor];
        NSColor *fore = [[self textView] defaultForegroundColor];
        [tabline setAutoColorsSelBg:back fg:fore];
    }

}

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore
{
    [textView setDefaultColorsBackground:back foreground:fore];
    [self updateTablineColors:MMTabColorsModeAutomatic];

    CALayer *backedLayer = [self layer];
    if (backedLayer) {
        // This only happens in 10.14+, where everything is layer-backed by
        // default. Since textView draws itself as a separate layer, we don't
        // want this layer to draw anything. This is especially important with
        // 'transparency' where there's alpha blending and we don't want this
        // layer to be in the way and double-blending things.
        [backedLayer setBackgroundColor:CGColorGetConstantColor(kCGColorClear)];
    }

    for (NSUInteger i = 0, count = [scrollbars count]; i < count; ++i) {
        MMScroller *sb = [scrollbars objectAtIndex:i];
        [sb setNeedsDisplay:YES];
    }
    [self setNeedsDisplay:YES];
}

- (void)setTablineColorsTabBg:(NSColor *)tabBg tabFg:(NSColor *)tabFg
                       fillBg:(NSColor *)fillBg fillFg:(NSColor *)fillFg
                        selBg:(NSColor *)selBg selFg:(NSColor *)selFg
{
    for (NSUInteger i = 0; i < MMTabColorTypeCount; i++)
        [tabColors[i] release];
    tabColors[MMTabColorTypeTabBg] = [tabBg retain];
    tabColors[MMTabColorTypeTabFg] = [tabFg retain];
    tabColors[MMTabColorTypeSelBg] = [selBg retain];
    tabColors[MMTabColorTypeSelFg] = [selFg retain];
    tabColors[MMTabColorTypeFillBg] = [fillBg retain];
    tabColors[MMTabColorTypeFillFg] = [fillFg retain];
    [self updateTablineColors:MMTabColorsModeVimColorscheme];
}


// -- MMTablineDelegate ----------------------------------------------


- (BOOL)tabline:(MMTabline *)tabline shouldSelectTabAtIndex:(NSUInteger)index
{
    // Propagate the selection message to Vim.
    if (NSNotFound != index) {
        int i = (int)index;
        NSData *data = [NSData dataWithBytes:&i length:sizeof(int)];
        [vimController sendMessage:SelectTabMsgID data:data];
    }
    // Let Vim decide whether to select the tab or not.
    return NO;
}

- (BOOL)tabline:(MMTabline *)tabline shouldCloseTabAtIndex:(NSUInteger)index
{
    if (index >= 0 && index < tabline.numberOfTabs - 1) {
        // If the user is closing any tab other than the last one, we remember
        // the state so later on we don't resize the tabs in the layout
        // animation to preserve the stability of tab positions to allow for
        // quickly closing multiple tabs. This is similar to how macOS tabs
        // work.
        pendingCloseTabID = [tabline tabAtIndex:index].tag;
    }
    // Propagate the close message to Vim
    int i = (int)index;
    NSData *data = [NSData dataWithBytes:&i length:sizeof(int)];
    [vimController sendMessage:CloseTabMsgID data:data];

    // Let Vim decide whether to close the tab or not.
    return NO;
}

- (void)tabline:(MMTabline *)tabline didDragTab:(MMTab *)tab toIndex:(NSUInteger)index
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&index length:sizeof(int)];
    [vimController sendMessage:DraggedTabMsgID data:data];
}

- (NSDragOperation)tabline:(MMTabline *)tabline draggingEntered:(id <NSDraggingInfo>)dragInfo forTabAtIndex:(NSUInteger)index
{
    return [dragInfo.draggingPasteboard.types containsObject:getPasteboardFilenamesType()]
            ? NSDragOperationCopy
            : NSDragOperationNone;
}

- (BOOL)tabline:(MMTabline *)tabline performDragOperation:(id <NSDraggingInfo>)dragInfo forTabAtIndex:(NSUInteger)index
{
    NSPasteboard *pb = dragInfo.draggingPasteboard;
    NSArray<NSString*>* filenames = extractPasteboardFilenames(pb);
    if (filenames == nil || filenames.count == 0)
        return NO;

    if (index != NSNotFound) {
        // If dropping on a specific tab, only open one file
        [vimController file:[filenames objectAtIndex:0] draggedToTabAtIndex:index];
    } else {
        // Files were dropped on empty part of tab bar; open them all
        [vimController filesDraggedToTabline:filenames];
    }
    return YES;
}


// -- NSView customization ---------------------------------------------------


- (void)viewWillStartLiveResize
{
    id windowController = [[self window] windowController];
    [windowController liveResizeWillStart];

    [super viewWillStartLiveResize];
}

- (void)viewDidEndLiveResize
{
    id windowController = [[self window] windowController];
    [windowController liveResizeDidEnd];

    [super viewDidEndLiveResize];
}

- (void)setFrameSize:(NSSize)size
{
    // NOTE: Instead of only acting when a frame was resized, we do some
    // updating each time a frame may be resized.  (At the moment, if we only
    // respond to actual frame changes then typing ":set lines=1000" twice in a
    // row will result in the vim view holding more rows than the can fit
    // inside the window.)
    [super setFrameSize:size];
    [self frameSizeMayHaveChanged:NO];
}

- (void)setFrameSizeKeepGUISize:(NSSize)size
{
    // NOTE: Instead of only acting when a frame was resized, we do some
    // updating each time a frame may be resized.  (At the moment, if we only
    // respond to actual frame changes then typing ":set lines=1000" twice in a
    // row will result in the vim view holding more rows than the can fit
    // inside the window.)
    [super setFrameSize:size];
    [self frameSizeMayHaveChanged:YES];
}

- (void)setFrame:(NSRect)frame
{
    // See comment in setFrameSize: above.
    [super setFrame:frame];
    [self frameSizeMayHaveChanged:NO];
}

- (void)viewDidChangeEffectiveAppearance
{
    [vimController appearanceChanged:getCurrentAppearance(self.effectiveAppearance)];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud integerForKey:MMTabColorsModeKey] == MMTabColorsModeDefaultColors &&
        [ud boolForKey:MMWindowUseTabBackgroundColorKey])
    {
        // Tab line default colors depends on system light/dark modes. We will
        // need to notify the window as well if it is set up to use the tab bar
        // colors. We need to schedule this for later because the tabline's
        // effectAppearance gets changed *after* this method is called, so we
        // need to delay the refresh or we would get stale data.
        MMWindowController *winController = [vimController windowController];
        [winController performSelectorOnMainThread:@selector(refreshTabProperties) withObject:nil waitUntilDone:NO];
    }
}
@end // MMVimView




@implementation MMVimView (Private)

- (BOOL)bottomScrollbarVisible
{
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeBottom && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (BOOL)leftScrollbarVisible
{
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeLeft && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (BOOL)rightScrollbarVisible
{
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeRight && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (void)placeScrollbars
{
    NSRect textViewFrame = [textView frame];
    BOOL leftSbVisible = NO;
    BOOL rightSbVisible = NO;
    BOOL botSbVisible = NO;

    // HACK!  Find the lowest left&right vertical scrollbars This hack
    // continues further down.
    NSUInteger lowestLeftSbIdx = (NSUInteger)-1;
    NSUInteger lowestRightSbIdx = (NSUInteger)-1;
    NSUInteger rowMaxLeft = 0, rowMaxRight = 0;
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if (![scroller isHidden]) {
            NSRange range = [scroller range];
            if ([scroller type] == MMScrollerTypeLeft
                    && range.location >= rowMaxLeft) {
                rowMaxLeft = range.location;
                lowestLeftSbIdx = i;
                leftSbVisible = YES;
            } else if ([scroller type] == MMScrollerTypeRight
                    && range.location >= rowMaxRight) {
                rowMaxRight = range.location;
                lowestRightSbIdx = i;
                rightSbVisible = YES;
            } else if ([scroller type] == MMScrollerTypeBottom) {
                botSbVisible = YES;
            }
        }
    }

    // Place the scrollbars.
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller isHidden])
            continue;

        NSRect rect;
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
        CGFloat scrollerWidth = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy];
#else
        CGFloat scrollerWidth = [NSScroller scrollerWidth];
#endif
        if ([scroller type] == MMScrollerTypeBottom) {
            rect = [textView rectForColumnsInRange:[scroller range]];
            rect.size.height = scrollerWidth;
            if (leftSbVisible)
                rect.origin.x += scrollerWidth;

            // HACK!  Make sure the horizontal scrollbar covers the text view
            // all the way to the right, otherwise it looks ugly when the user
            // drags the window to resize.
            float w = NSMaxX(textViewFrame) - NSMaxX(rect);
            if (w > 0)
                rect.size.width += w;

            // Make sure scrollbar rect is bounded by the text view frame.
            // Also leave some room for the resize indicator on the right in
            // case there is no right scrollbar.
            if (rect.origin.x < textViewFrame.origin.x)
                rect.origin.x = textViewFrame.origin.x;
            else if (rect.origin.x > NSMaxX(textViewFrame))
                rect.origin.x = NSMaxX(textViewFrame);
            if (NSMaxX(rect) > NSMaxX(textViewFrame))
                rect.size.width -= NSMaxX(rect) - NSMaxX(textViewFrame);
            if (!rightSbVisible)
                rect.size.width -= scrollerWidth;
            if (rect.size.width < 0)
                rect.size.width = 0;
        } else {
            rect = [textView rectForRowsInRange:[scroller range]];
            // Adjust for the fact that text layout is flipped.
            rect.origin.y = NSMaxY(textViewFrame) - rect.origin.y
                    - rect.size.height;
            rect.size.width = scrollerWidth;
            if ([scroller type] == MMScrollerTypeRight)
                rect.origin.x = NSMaxX(textViewFrame);

            // HACK!  Make sure the lowest vertical scrollbar covers the text
            // view all the way to the bottom.  This is done because Vim only
            // makes the scrollbar cover the (vim-)window it is associated with
            // and this means there is always an empty gap in the scrollbar
            // region next to the command line.
            // TODO!  Find a nicer way to do this.
            if (i == lowestLeftSbIdx || i == lowestRightSbIdx) {
                float h = rect.origin.y + rect.size.height
                          - textViewFrame.origin.y;
                if (rect.size.height < h) {
                    rect.origin.y = textViewFrame.origin.y;
                    rect.size.height = h;
                }
            }

            // Vertical scrollers must not cover the resize box in the
            // bottom-right corner of the window.
            if ([[self window] showsResizeIndicator]  // Note: This is deprecated as of 10.7, see below comment.
                && rect.origin.y < scrollerWidth) {
                rect.size.height -= scrollerWidth - rect.origin.y;
                rect.origin.y = scrollerWidth;
            }

            // Make sure scrollbar rect is bounded by the text view frame.
            if (rect.origin.y < textViewFrame.origin.y) {
                rect.size.height -= textViewFrame.origin.y - rect.origin.y;
                rect.origin.y = textViewFrame.origin.y;
            } else if (rect.origin.y > NSMaxY(textViewFrame))
                rect.origin.y = NSMaxY(textViewFrame);
            if (NSMaxY(rect) > NSMaxY(textViewFrame))
                rect.size.height -= NSMaxY(rect) - NSMaxY(textViewFrame);
            if (rect.size.height < 0)
                rect.size.height = 0;
        }

        NSRect oldRect = [scroller frame];
        if (!NSEqualRects(oldRect, rect)) {
            [scroller setFrame:rect];
            // Clear behind the old scroller frame, or parts of the old
            // scroller might still be visible after setFrame:.
            [[[self window] contentView] setNeedsDisplayInRect:oldRect];
            [scroller setNeedsDisplay:YES];
        }
    }

    if (NSAppKitVersionNumber < NSAppKitVersionNumber10_7) {
        // HACK: If there is no bottom or right scrollbar the resize indicator will
        // cover the bottom-right corner of the text view so tell NSWindow not to
        // draw it in this situation.
        //
        // Note: This API is ignored from 10.7 onward and is now deprecated. This
        // should be removed if we want to drop support for 10.6.
        [[self window] setShowsResizeIndicator:(rightSbVisible||botSbVisible)];
    }
}

- (MMScroller *)scrollbarForIdentifier:(int32_t)ident index:(unsigned *)idx
{
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller scrollerId] == ident) {
            if (idx) *idx = (unsigned)i;
            return scroller;
        }
    }

    return nil;
}

- (NSSize)vimViewSizeForTextViewSize:(NSSize)textViewSize
{
    NSSize size = textViewSize;
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
    CGFloat scrollerWidth = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy];
#else
    CGFloat scrollerWidth = [NSScroller scrollerWidth];
#endif

    if (!tabline.isHidden)
        size.height += NSHeight(tabline.frame);

    if ([self bottomScrollbarVisible])
        size.height += scrollerWidth;
    if ([self leftScrollbarVisible])
        size.width += scrollerWidth;
    if ([self rightScrollbarVisible])
        size.width += scrollerWidth;

    return size;
}

- (NSRect)textViewRectForVimViewSize:(NSSize)contentSize
{
    NSRect rect = { {0, 0}, {contentSize.width, contentSize.height} };
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
    CGFloat scrollerWidth = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy];
#else
    CGFloat scrollerWidth = [NSScroller scrollerWidth];
#endif

    if (!tabline.isHidden)
        rect.size.height -= NSHeight(tabline.frame);

    if ([self bottomScrollbarVisible]) {
        rect.size.height -= scrollerWidth;
        rect.origin.y += scrollerWidth;
    }
    if ([self leftScrollbarVisible]) {
        rect.size.width -= scrollerWidth;
        rect.origin.x += scrollerWidth;
    }
    if ([self rightScrollbarVisible])
        rect.size.width -= scrollerWidth;

    return rect;
}

- (void)frameSizeMayHaveChanged:(BOOL)keepGUISize
{
    // NOTE: Whenever a call is made that may have changed the frame size we
    // take the opportunity to make sure all subviews are in place and that the
    // (rows,columns) are constrained to lie inside the new frame.  We not only
    // do this when the frame really has changed since it is possible to modify
    // the number of (rows,columns) without changing the frame size.

    // Give all superfluous space to the text view. It might be smaller or
    // larger than it wants to be, but this is needed during live resizing.
    NSRect textViewRect = [self textViewRectForVimViewSize:[self frame].size];
    [textView setFrame:textViewRect];

    // Immediately place the scrollbars instead of deferring till later here.
    // Otherwise in situations like live resize we will see the scroll bars lag.
    self.pendingPlaceScrollbars = NO;
    [self placeScrollbars];

    // It is possible that the current number of (rows,columns) is too big or
    // too small to fit the new frame.  If so, notify Vim that the text
    // dimensions should change, but don't actually change the number of
    // (rows,columns).  These numbers may only change when Vim initiates the
    // change (as opposed to the user dragging the window resizer, for
    // example).
    //
    // Note that the message sent to Vim depends on whether we're in
    // a live resize or not -- this is necessary to avoid the window jittering
    // when the user drags to resize.
    int constrained[2];
    NSSize textViewSize = [textView frame].size;
    [textView constrainRows:&constrained[0] columns:&constrained[1]
                     toSize:textViewSize];

    if (constrained[0] != textView.pendingMaxRows || constrained[1] != textView.pendingMaxColumns) {
        NSData *data = [NSData dataWithBytes:constrained length:2*sizeof(int)];
        int msgid = [self inLiveResize] ? LiveResizeMsgID
                                        : (keepGUISize ? SetTextDimensionsNoResizeWindowMsgID : SetTextDimensionsMsgID);

        ASLogDebug(@"Notify Vim that text dimensions changed from %dx%d to "
                   "%dx%d (%s)", textView.pendingMaxColumns, textView.pendingMaxRows, constrained[1], constrained[0],
                   MMVimMsgIDStrings[msgid]);

        if (msgid == LiveResizeMsgID && self.pendingLiveResize) {
            // We are currently live resizing and there's already an ongoing
            // resize message that we haven't finished handling yet. Wait until
            // we are done with that since we don't want to overload Vim with
            // messages.
            self.pendingLiveResizeQueued = YES;
        }
        else {
            // Live resize messages can be sent really rapidly, especailly if
            // it's from double clicking the window border (to indicate filling
            // all the way to that side to the window manager). We want to rate
            // limit sending live resize one at a time, or the IPC will get
            // swamped which causes slowdowns and some messages will also be dropped.
            // As a result we basically discard all live resize messages if one
            // is already going on. liveResizeDidEnd: will perform a final clean
            // up resizing.
            self.pendingLiveResize = (msgid == LiveResizeMsgID);

            // Cache the new pending size so we can use it to prevent resizing Vim again
            // if we haven't changed the row/col count later. We don't want to
            // immediately resize the textView (hence it's "pending") as we only
            // do that when Vim has acknoledged the message and draws. This leads
            // to a stable drawing.
            [textView setPendingMaxRows:constrained[0] columns:constrained[1]];

            [vimController sendMessageNow:msgid data:data timeout:1];
        }

        // We only want to set the window title if this resize came from
        // a live-resize, not (for example) setting 'columns' or 'lines'.
        if ([self inLiveResize]) {
            [[self window] setTitle:[NSString stringWithFormat:@"%d × %d",
                    constrained[1], constrained[0]]];
        }
    }
}

@end // MMVimView (Private)




@implementation MMScroller

- (id)initWithIdentifier:(int32_t)ident type:(int)theType
{
    // HACK! NSScroller creates a horizontal scroller if it is init'ed with a
    // frame whose with exceeds its height; so create a bogus rect and pass it
    // to initWithFrame.
    NSRect frame = theType == MMScrollerTypeBottom
            ? NSMakeRect(0, 0, 1, 0)
            : NSMakeRect(0, 0, 0, 1);

    self = [super initWithFrame:frame];
    if (!self) return nil;

    identifier = ident;
    type = theType;
    [self setHidden:YES];
    [self setEnabled:YES];
    [self setAutoresizingMask:NSViewNotSizable];

    return self;
}

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag
{
    // Dark mode scrollbars draw a translucent knob slot overlaid on top of
    // whatever background the view has, even when we are using legacy
    // scrollbars with a dedicated space.  This means we need to draw the
    // background with some colors first, or else it would look really black, or
    // show through rendering artifacts (e.g. if guioption 'k' is on, and you
    // turn off the bar bar, the artiacts will show through in the overlay).
    //
    // Note: Another way to fix this is to make sure to draw the underlying
    // MMVimView or the window with the proper color so the scrollbar would just
    // draw on top, but this doesn't work properly right now, and it's difficult
    // to get that to work with the 'transparency' setting as well.
    MMVimView *vimView = [self target];
    NSColor *defaultBackgroundColor = [[vimView textView] defaultBackgroundColor];
    [defaultBackgroundColor setFill];
    NSRectFill(slotRect);

    [super drawKnobSlotInRect:slotRect highlight:flag];
}

- (int32_t)scrollerId
{
    return identifier;
}

- (int)type
{
    return type;
}

- (NSRange)range
{
    return range;
}

- (void)setRange:(NSRange)newRange
{
    range = newRange;
}

- (void)scrollWheel:(NSEvent *)event
{
    // HACK! Pass message on to the text view.
    NSView *vimView = [self superview];
    if ([vimView isKindOfClass:[MMVimView class]])
        [[(MMVimView*)vimView textView] scrollWheel:event];
}

- (void)mouseDown:(NSEvent *)event
{
    // TODO: This is an ugly way of getting the connection to the backend.
    NSConnection *connection = nil;
    id wc = [[self window] windowController];
    if ([wc isKindOfClass:[MMWindowController class]]) {
        MMVimController *vc = [(MMWindowController*)wc vimController];
        id proxy = [vc backendProxy];
        connection = [(NSDistantObject*)proxy connectionForProxy];
    }

    // NOTE: The scroller goes into "event tracking mode" when the user clicks
    // (and holds) the mouse button.  We have to manually add the backend
    // connection to this mode while the mouse button is held, else DO messages
    // from Vim will not be processed until the mouse button is released.
    [connection addRequestMode:NSEventTrackingRunLoopMode];
    [super mouseDown:event];
    [connection removeRequestMode:NSEventTrackingRunLoopMode];
}

@end // MMScroller
