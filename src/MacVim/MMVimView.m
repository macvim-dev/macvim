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
#import <PSMTabBarControl/PSMTabBarControl.h>



// Scroller type; these must match SBAR_* in gui.h
enum {
    MMScrollerTypeLeft = 0,
    MMScrollerTypeRight,
    MMScrollerTypeBottom
};


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


@interface MMVimView (Private)
- (BOOL)bottomScrollbarVisible;
- (BOOL)leftScrollbarVisible;
- (BOOL)rightScrollbarVisible;
- (void)placeScrollbars;
- (NSUInteger)representedIndexOfTabViewItem:(NSTabViewItem *)tvi;
- (MMScroller *)scrollbarForIdentifier:(int32_t)ident index:(unsigned *)idx;
- (NSSize)vimViewSizeForTextViewSize:(NSSize)textViewSize;
- (NSRect)textViewRectForVimViewSize:(NSSize)contentSize;
- (NSTabView *)tabView;
- (void)frameSizeMayHaveChanged;
@end


// This is an informal protocol implemented by MMWindowController (maybe it
// shold be a formal protocol, but ...).
@interface NSWindowController (MMVimViewDelegate)
- (void)liveResizeWillStart;
- (void)liveResizeDidEnd;
@end



@implementation MMVimView

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
    int left = [ud integerForKey:MMTextInsetLeftKey];
    int top = [ud integerForKey:MMTextInsetTopKey];
    [textView setTextContainerInset:NSMakeSize(left, top)];

    [textView setAutoresizingMask:NSViewNotSizable];
    [self addSubview:textView];
    
    // Create the tab view (which is never visible, but the tab bar control
    // needs it to function).
    tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];

    // Create the tab bar control (which is responsible for actually
    // drawing the tabline and tabs).
    NSRect tabFrame = { { 0, frame.size.height - kPSMTabBarControlHeight },
                        { frame.size.width, kPSMTabBarControlHeight } };
    tabBarControl = [[PSMTabBarControl alloc] initWithFrame:tabFrame];

    [tabView setDelegate:tabBarControl];

    [tabBarControl setTabView:tabView];
    [tabBarControl setDelegate:self];
    [tabBarControl setHidden:YES];

    if (shouldUseYosemiteTabBarStyle()) {
        CGFloat screenWidth = [[NSScreen mainScreen] frame].size.width;
        int tabMaxWidth = [ud integerForKey:MMTabMaxWidthKey];
        if (tabMaxWidth == 0)
            tabMaxWidth = screenWidth;
        int tabOptimumWidth = [ud integerForKey:MMTabOptimumWidthKey];
        if (tabOptimumWidth == 0)
            tabOptimumWidth = screenWidth;

        [tabBarControl setStyleNamed:@"Yosemite"];
        [tabBarControl setCellMinWidth:[ud integerForKey:MMTabMinWidthKey]];
        [tabBarControl setCellMaxWidth:tabMaxWidth];
        [tabBarControl setCellOptimumWidth:tabOptimumWidth];
    } else {
        [tabBarControl setCellMinWidth:[ud integerForKey:MMTabMinWidthKey]];
        [tabBarControl setCellMaxWidth:[ud integerForKey:MMTabMaxWidthKey]];
        [tabBarControl setCellOptimumWidth:
                                     [ud integerForKey:MMTabOptimumWidthKey]];
    }

    [tabBarControl setShowAddTabButton:[ud boolForKey:MMShowAddTabButtonKey]];
    [[tabBarControl addTabButton] setTarget:self];
    [[tabBarControl addTabButton] setAction:@selector(addNewTab:)];
    [tabBarControl setAllowsDragBetweenWindows:NO];
    [tabBarControl registerForDraggedTypes:
                            [NSArray arrayWithObject:NSFilenamesPboardType]];

    [tabBarControl setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];
    
    //[tabBarControl setPartnerView:textView];
    
    // tab bar resizing only works if awakeFromNib is called (that's where
    // the NSViewFrameDidChangeNotification callback is installed). Sounds like
    // a PSMTabBarControl bug, let's live with it for now.
    [tabBarControl awakeFromNib];

    [self addSubview:tabBarControl];

    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [tabBarControl release];  tabBarControl = nil;
    [tabView release];  tabView = nil;
    [scrollbars release];  scrollbars = nil;

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
    return YES;
}

- (void)drawRect:(NSRect)rect
{
    // On Leopard, we want to have a textured window background for nice
    // looking tabs. However, the textured window background looks really
    // weird behind the window resize throbber, so emulate the look of an
    // NSScrollView in the bottom right corner.
    if (![[self window] showsResizeIndicator]  // XXX: make this a flag
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

- (MMTextView *)textView
{
    return textView;
}

- (PSMTabBarControl *)tabBarControl
{
    return tabBarControl;
}

- (void)cleanup
{
    vimController = nil;
    
    // NOTE! There is a bug in PSMTabBarControl in that it retains the delegate
    // so reset the delegate here, otherwise the delegate may never get
    // released.
    [tabView setDelegate:nil];
    [tabBarControl setDelegate:nil];
    [tabBarControl setTabView:nil];
    [[self window] setDelegate:nil];

    // NOTE! There is another bug in PSMTabBarControl where the control is not
    // removed as an observer, so remove it here (failing to remove an observer
    // may lead to very strange bugs).
    [[NSNotificationCenter defaultCenter] removeObserver:tabBarControl];

    [tabBarControl removeFromSuperviewWithoutNeedingDisplay];
    [textView removeFromSuperviewWithoutNeedingDisplay];

    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *sb = [scrollbars objectAtIndex:i];
        [sb removeFromSuperviewWithoutNeedingDisplay];
    }

    [tabView removeAllTabViewItems];
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
    [vimController sendMessage:AddNewTabMsgID data:nil];
}

- (void)updateTabsWithData:(NSData *)data
{
    const void *p = [data bytes];
    const void *end = p + [data length];
    int tabIdx = 0;

    // HACK!  Current tab is first in the message.  This way it is not
    // necessary to guess which tab should be the selected one (this can be
    // problematic for instance when new tabs are created).
    int curtabIdx = *((int*)p);  p += sizeof(int);

    NSArray *tabViewItems = [[self tabBarControl] representedTabViewItems];

    while (p < end) {
        NSTabViewItem *tvi = nil;

        //int wincount = *((int*)p);  p += sizeof(int);
        int infoCount = *((int*)p); p += sizeof(int);
        unsigned i;
        for (i = 0; i < infoCount; ++i) {
            int length = *((int*)p);  p += sizeof(int);
            if (length <= 0)
                continue;

            NSString *val = [[NSString alloc]
                    initWithBytes:(void*)p length:length
                         encoding:NSUTF8StringEncoding];
            p += length;

            switch (i) {
                case MMTabLabel:
                    // Set the label of the tab, adding a new tab when needed.
                    tvi = [[self tabView] numberOfTabViewItems] <= tabIdx
                            ? [self addNewTabViewItem]
                            : [tabViewItems objectAtIndex:tabIdx];
                    [tvi setLabel:val];
                    ++tabIdx;
                    break;
                case MMTabToolTip:
                    if (tvi)
                        [[self tabBarControl] setToolTip:val
                                          forTabViewItem:tvi];
                    break;
                default:
                    ASLogWarn(@"Unknown tab info for index: %d", i);
            }

            [val release];
        }
    }

    // Remove unused tabs from the NSTabView.  Note that when a tab is closed
    // the NSTabView will automatically select another tab, but we want Vim to
    // take care of which tab to select so set the vimTaskSelectedTab flag to
    // prevent the tab selection message to be passed on to the VimTask.
    vimTaskSelectedTab = YES;
    int i, count = [[self tabView] numberOfTabViewItems];
    for (i = count-1; i >= tabIdx; --i) {
        id tvi = [tabViewItems objectAtIndex:i];
        [[self tabView] removeTabViewItem:tvi];
    }
    vimTaskSelectedTab = NO;

    [self selectTabWithIndex:curtabIdx];
}

- (void)selectTabWithIndex:(int)idx
{
    NSArray *tabViewItems = [[self tabBarControl] representedTabViewItems];
    if (idx < 0 || idx >= [tabViewItems count]) {
        ASLogWarn(@"No tab with index %d exists.", idx);
        return;
    }

    // Do not try to select a tab if already selected.
    NSTabViewItem *tvi = [tabViewItems objectAtIndex:idx];
    if (tvi != [[self tabView] selectedTabViewItem]) {
        vimTaskSelectedTab = YES;
        [[self tabView] selectTabViewItem:tvi];
        vimTaskSelectedTab = NO;

        // We might need to change the scrollbars that are visible.
        [self placeScrollbars];
    }
}

- (NSTabViewItem *)addNewTabViewItem
{
    // NOTE!  A newly created tab is not by selected by default; Vim decides
    // which tab should be selected at all times.  However, the AppKit will
    // automatically select the first tab added to a tab view.

    // The documentation claims initWithIdentifier can be given a nil identifier, but the API itself
    // is decorated such that doing so produces a warning, so the tab count is used as identifier.
    NSInteger identifier = [[self tabView] numberOfTabViewItems];
    NSTabViewItem *tvi = [[NSTabViewItem alloc] initWithIdentifier:[NSNumber numberWithInt:identifier]];

    // NOTE: If this is the first tab it will be automatically selected.
    vimTaskSelectedTab = YES;
    [[self tabView] addTabViewItem:tvi];
    vimTaskSelectedTab = NO;

    [tvi autorelease];

    return tvi;
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
}

- (BOOL)destroyScrollbarWithIdentifier:(int32_t)ident
{
    unsigned idx = 0;
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:&idx];
    if (!scroller) return NO;

    [scroller removeFromSuperview];
    [scrollbars removeObjectAtIndex:idx];

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
    int hitPart = [sender hitPart];
    float value = [sender floatValue];

    [data appendBytes:&ident length:sizeof(int32_t)];
    [data appendBytes:&hitPart length:sizeof(int)];
    [data appendBytes:&value length:sizeof(float)];

    [vimController sendMessage:ScrollbarEventMsgID data:data];
}

- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(int32_t)ident
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    NSRange range = NSMakeRange(pos, len);
    if (!NSEqualRanges(range, [scroller range])) {
        [scroller setRange:range];
        // TODO!  Should only do this once per update.

        // This could be sent because a text window was created or closed, so
        // we might need to update which scrollbars are visible.
        [self placeScrollbars];
    }
}

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore
{
    [textView setDefaultColorsBackground:back foreground:fore];
}


// -- PSMTabBarControl delegate ----------------------------------------------


- (BOOL)tabView:(NSTabView *)theTabView shouldSelectTabViewItem:
    (NSTabViewItem *)tabViewItem
{
    // NOTE: It would be reasonable to think that 'shouldSelect...' implies
    // that this message only gets sent when the user clicks the tab.
    // Unfortunately it is not so, which is why we need the
    // 'vimTaskSelectedTab' flag.
    //
    // HACK!  The selection message should not be propagated to Vim if Vim
    // selected the tab (e.g. as opposed the user clicking the tab).  The
    // delegate method has no way of knowing who initiated the selection so a
    // flag is set when Vim initiated the selection.
    if (!vimTaskSelectedTab) {
        // Propagate the selection message to Vim.
        NSUInteger idx = [self representedIndexOfTabViewItem:tabViewItem];
        if (NSNotFound != idx) {
            int i = (int)idx;   // HACK! Never more than MAXINT tabs?!
            NSData *data = [NSData dataWithBytes:&i length:sizeof(int)];
            [vimController sendMessage:SelectTabMsgID data:data];
        }
    }

    // Unless Vim selected the tab, return NO, and let Vim decide if the tab
    // should get selected or not.
    return vimTaskSelectedTab;
}

- (BOOL)tabView:(NSTabView *)theTabView shouldCloseTabViewItem:
        (NSTabViewItem *)tabViewItem
{
    // HACK!  This method is only called when the user clicks the close button
    // on the tab.  Instead of letting the tab bar close the tab, we return NO
    // and pass a message on to Vim to let it handle the closing.
    NSUInteger idx = [self representedIndexOfTabViewItem:tabViewItem];
    int i = (int)idx;   // HACK! Never more than MAXINT tabs?!
    NSData *data = [NSData dataWithBytes:&i length:sizeof(int)];
    [vimController sendMessage:CloseTabMsgID data:data];

    return NO;
}

- (void)tabView:(NSTabView *)theTabView didDragTabViewItem:
        (NSTabViewItem *)tabViewItem toIndex:(int)idx
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&idx length:sizeof(int)];

    [vimController sendMessage:DraggedTabMsgID data:data];
}

- (NSDragOperation)tabBarControl:(PSMTabBarControl *)theTabBarControl
        draggingEntered:(id <NSDraggingInfo>)sender
        forTabAtIndex:(NSUInteger)tabIndex
{
    NSPasteboard *pb = [sender draggingPasteboard];
    return [[pb types] containsObject:NSFilenamesPboardType]
            ? NSDragOperationCopy
            : NSDragOperationNone;
}

- (BOOL)tabBarControl:(PSMTabBarControl *)theTabBarControl
        performDragOperation:(id <NSDraggingInfo>)sender
        forTabAtIndex:(NSUInteger)tabIndex
{
    NSPasteboard *pb = [sender draggingPasteboard];
    if ([[pb types] containsObject:NSFilenamesPboardType]) {
        NSArray *filenames = [pb propertyListForType:NSFilenamesPboardType];
        if ([filenames count] == 0)
            return NO;
        if (tabIndex != NSNotFound) {
            // If dropping on a specific tab, only open one file
            [vimController file:[filenames objectAtIndex:0]
                draggedToTabAtIndex:tabIndex];
        } else {
            // Files were dropped on empty part of tab bar; open them all
            [vimController filesDraggedToTabBar:filenames];
        }
        return YES;
    } else {
        return NO;
    }
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
    [self frameSizeMayHaveChanged];
}

- (void)setFrame:(NSRect)frame
{
    // See comment in setFrameSize: above.
    [super setFrame:frame];
    [self frameSizeMayHaveChanged];
}

@end // MMVimView




@implementation MMVimView (Private)

- (BOOL)bottomScrollbarVisible
{
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeBottom && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (BOOL)leftScrollbarVisible
{
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeLeft && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (BOOL)rightScrollbarVisible
{
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
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
    unsigned lowestLeftSbIdx = (unsigned)-1;
    unsigned lowestRightSbIdx = (unsigned)-1;
    unsigned rowMaxLeft = 0, rowMaxRight = 0;
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
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
    for (i = 0; i < count; ++i) {
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
            if ([[self window] showsResizeIndicator]  // XXX: make this a flag
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

    // HACK: If there is no bottom or right scrollbar the resize indicator will
    // cover the bottom-right corner of the text view so tell NSWindow not to
    // draw it in this situation.
    [[self window] setShowsResizeIndicator:(rightSbVisible||botSbVisible)];
}

- (NSUInteger)representedIndexOfTabViewItem:(NSTabViewItem *)tvi
{
    NSArray *tabViewItems = [[self tabBarControl] representedTabViewItems];
    return [tabViewItems indexOfObject:tvi];
}

- (MMScroller *)scrollbarForIdentifier:(int32_t)ident index:(unsigned *)idx
{
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller scrollerId] == ident) {
            if (idx) *idx = i;
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

    if (![[self tabBarControl] isHidden])
        size.height += [[self tabBarControl] frame].size.height;

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

    if (![[self tabBarControl] isHidden])
        rect.size.height -= [[self tabBarControl] frame].size.height;

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

- (NSTabView *)tabView
{
    return tabView;
}

- (void)frameSizeMayHaveChanged
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

    int rows, cols;
    [textView getMaxRows:&rows columns:&cols];

    if (constrained[0] != rows || constrained[1] != cols) {
        NSData *data = [NSData dataWithBytes:constrained length:2*sizeof(int)];
        int msgid = [self inLiveResize] ? LiveResizeMsgID
                                        : SetTextDimensionsMsgID;

        ASLogDebug(@"Notify Vim that text dimensions changed from %dx%d to "
                   "%dx%d (%s)", cols, rows, constrained[1], constrained[0],
                   MessageStrings[msgid]);

        [vimController sendMessageNow:msgid data:data timeout:1];

        // We only want to set the window title if this resize came from
        // a live-resize, not (for example) setting 'columns' or 'lines'.
        if ([self inLiveResize]) {
            [[self window] setTitle:[NSString stringWithFormat:@"%dx%d",
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
