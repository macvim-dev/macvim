/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMVimView.h"

#import <PSMTabBarControl.h>
#import "MacVim.h"
#import "MMTextView.h"
#import "MMTextStorage.h"
#import "MMTypesetter.h"
#import "MMVimController.h"

#import "MMWindowController.h"  // needed by MMScroller. TODO: remove

// Scroller type; these must match SBAR_* in gui.h
enum {
    MMScrollerTypeLeft = 0,
    MMScrollerTypeRight,
    MMScrollerTypeBottom
};

// TODO:  Move!
@interface NSTabView (MMExtras)
- (void)removeAllTabViewItems;
@end


// TODO:  Move!
@interface MMScroller : NSScroller {
    long identifier;
    int type;
    NSRange range;
}
- (id)initWithIdentifier:(long)ident type:(int)type;
- (long)identifier;
- (int)type;
- (NSRange)range;
- (void)setRange:(NSRange)newRange;
@end


@interface MMVimView (Private)
- (BOOL)bottomScrollbarVisible;
- (BOOL)leftScrollbarVisible;
- (BOOL)rightScrollbarVisible;
- (void)placeScrollbars;
- (int)representedIndexOfTabViewItem:(NSTabViewItem *)tvi;
- (MMScroller *)scrollbarForIdentifier:(long)ident index:(unsigned *)idx;
- (NSSize)contentSizeForTextStorageSize:(NSSize)textViewSize;
- (NSSize)textStorageSizeForTextViewSize:(NSSize)textViewSize;
- (NSTabView *)tabView;
@end


@implementation MMVimView

- (NSRect)tabBarFrameForFrame:(NSRect)frame
{
    NSRect tabFrame = {
        { 0, frame.size.height - 22 },
        { frame.size.width, 22 }
    };
    return tabFrame;
}

- (MMVimView *)initWithFrame:(NSRect)frame
               vimController:(MMVimController *)controller {
    if (![super initWithFrame:frame])
        return nil;
    
    vimController = controller;
    scrollbars = [[NSMutableArray alloc] init];

    // Set up a complete text system.
    textStorage = [[MMTextStorage alloc] init];
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    NSTextContainer *tc = [[NSTextContainer alloc] initWithContainerSize:
                    NSMakeSize(1.0e7,1.0e7)];

    NSString *typesetterString = [[NSUserDefaults standardUserDefaults]
            stringForKey:MMTypesetterKey];
    if (![typesetterString isEqual:@"NSTypesetter"]) {
        MMTypesetter *typesetter = [[MMTypesetter alloc] init];
        [lm setTypesetter:typesetter];
        [typesetter release];
    } else {
        // Only MMTypesetter supports different cell width multipliers.
        [[NSUserDefaults standardUserDefaults]
                setFloat:1.0 forKey:MMCellWidthMultiplierKey];
    }

    [tc setWidthTracksTextView:NO];
    [tc setHeightTracksTextView:NO];
    [tc setLineFragmentPadding:0];

    [textStorage addLayoutManager:lm];
    [lm addTextContainer:tc];

    textView = [[MMTextView alloc] initWithFrame:frame
                                   textContainer:tc];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int left = [ud integerForKey:MMTextInsetLeftKey];
    int top = [ud integerForKey:MMTextInsetTopKey];
    [textView setTextContainerInset:NSMakeSize(left, top)];

    [self addSubview:textView];

    // The text storage retains the layout manager which in turn retains
    // the text container.
    [tc release];
    [lm release];
    
    // Create the tab view (which is never visible, but the tab bar control
    // needs it to function).
    tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];

    // Create the tab bar control (which is responsible for actually
    // drawing the tabline and tabs).
    NSRect tabFrame = [self tabBarFrameForFrame:frame];
    tabBarControl = [[PSMTabBarControl alloc] initWithFrame:tabFrame];

    [tabView setDelegate:tabBarControl];

    [tabBarControl setTabView:tabView];
    [tabBarControl setDelegate:self];
    [tabBarControl setHidden:YES];
    [tabBarControl setCellMinWidth:[ud integerForKey:MMTabMinWidthKey]];
    [tabBarControl setCellMaxWidth:[ud integerForKey:MMTabMaxWidthKey]];
    [tabBarControl setCellOptimumWidth:
                                     [ud integerForKey:MMTabOptimumWidthKey]];
    [tabBarControl setShowAddTabButton:YES];
    [[tabBarControl addTabButton] setTarget:self];
    [[tabBarControl addTabButton] setAction:@selector(addNewTab:)];
    [tabBarControl setAllowsDragBetweenWindows:NO];
    
    [tabBarControl setPartnerView:[self textView]];
    
    // tab bar resizing only works if awakeFromNib is called (that's where
    // the NSViewFrameDidChangeNotification callback is installed). Sounds like
    // a PSMTabBarControl bug, let's live with it for now.
    [tabBarControl awakeFromNib];

    [self addSubview:tabBarControl];

    [self setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(placeViews)
                            name:NSViewFrameDidChangeNotification object:self];

    return self;
}

- (void)dealloc
{
    [tabBarControl release];  tabBarControl = nil;
    [tabView release];  tabView = nil;
    [scrollbars release];  scrollbars = nil;
    [textView release];  textView = nil;
    [textStorage release];  textStorage = nil;

    [super dealloc];
}

- (MMTextView *)textView
{
    return textView;
}

- (MMTextStorage *)textStorage
{
    return textStorage;
}

- (NSMutableArray *)scrollbars
{
    return scrollbars;
}

- (BOOL)inLiveResize
{
    return [textView inLiveResize];
}

- (PSMTabBarControl *)tabBarControl
{
    return tabBarControl;
}

- (NSTabView *)tabView
{
    return tabView;
}


- (void)cleanup
{
    vimController = nil;
    
    // NOTE! There is a bug in PSMTabBarControl in that it retains the delegate
    // (which is the MMWindowController) so reset the delegate here, otherwise
    // the MMWindowController never gets released resulting in a pretty serious
    // memory leak.
    [tabView setDelegate:nil];
    [tabBarControl setDelegate:nil];
    [tabBarControl setTabView:nil];
    [[self window] setDelegate:nil];

    // NOTE! There is another bug in PSMTabBarControl where the control is not
    // removed as an observer, so remove it here (else lots of evil nasty bugs
    // will come and gnaw at your feet while you are sleeping).
    [[NSNotificationCenter defaultCenter] removeObserver:tabBarControl];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [tabBarControl removeFromSuperviewWithoutNeedingDisplay];
    [textView removeFromSuperviewWithoutNeedingDisplay];

    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *sb = [scrollbars objectAtIndex:i];
        [sb removeFromSuperviewWithoutNeedingDisplay];
    }

    [tabView removeAllTabViewItems];
}

- (NSSize)desiredSizeForActualRowsAndColumns
{
    return [self contentSizeForTextStorageSize:[[self textStorage] size]];
}

- (NSSize)getDesiredRows:(int *)r columns:(int *)c forSize:(NSSize)size
{
  NSSize textViewSize = [self textViewRectForContentSize:size].size;
  NSSize textStorageSize = [self textStorageSizeForTextViewSize:textViewSize];
  NSSize newSize = [textStorage fitToSize:textStorageSize rows:r columns:c];
  return [self contentSizeForTextStorageSize:newSize];
}

- (void)getActualRows:(int *)r columns:(int *)c
{
    [textStorage getMaxRows:r columns:c];
}

- (void)setActualRows:(int)r columns:(int)c
{
    [textStorage setMaxRows:r columns:c];
}

- (IBAction)addNewTab:(id)sender
{
    // NOTE! This can get called a lot if the user holds down the key
    // equivalent for this action, which causes the ports to fill up.  If we
    // wait for the message to be sent then the app might become unresponsive.
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
        //int wincount = *((int*)p);  p += sizeof(int);
        int length = *((int*)p);  p += sizeof(int);

        NSString *label = [[NSString alloc]
                initWithBytesNoCopy:(void*)p
                             length:length
                           encoding:NSUTF8StringEncoding
                       freeWhenDone:NO];
        p += length;

        // Set the label of the tab;  add a new tab when needed.
        NSTabViewItem *tvi = [[self tabView] numberOfTabViewItems] <= tabIdx
                ? [self addNewTabViewItem]
                : [tabViewItems objectAtIndex:tabIdx];

        [tvi setLabel:label];

        [label release];

        ++tabIdx;
    }

    // Remove unused tabs from the NSTabView.  Note that when a tab is closed
    // the NSTabView will automatically select another tab, but we want Vim to
    // take care of which tab to select so set the vimTaskSelectedTab flag to
    // prevent the tab selection message to be passed on to the VimTask.
    vimTaskSelectedTab = YES;
    int i, count = [[self tabView] numberOfTabViewItems];
    for (i = count-1; i >= tabIdx; --i) {
        id tvi = [tabViewItems objectAtIndex:i];
        //NSLog(@"Removing tab with index %d", i);
        [[self tabView] removeTabViewItem:tvi];
    }
    vimTaskSelectedTab = NO;

    [self selectTabWithIndex:curtabIdx];
}

- (void)selectTabWithIndex:(int)idx
{
    //NSLog(@"%s%d", _cmd, idx);

    NSArray *tabViewItems = [[self tabBarControl] representedTabViewItems];
    if (idx < 0 || idx >= [tabViewItems count]) {
        NSLog(@"WARNING: No tab with index %d exists.", idx);
        return;
    }

    // Do not try to select a tab if already selected.
    NSTabViewItem *tvi = [tabViewItems objectAtIndex:idx];
    if (tvi != [[self tabView] selectedTabViewItem]) {
        vimTaskSelectedTab = YES;
        [[self tabView] selectTabViewItem:tvi];
        vimTaskSelectedTab = NO;

        // we might need to change the scrollbars that are visible
        [self placeScrollbars];
    }
}

- (NSTabViewItem *)addNewTabViewItem
{
    // NOTE!  A newly created tab is not by selected by default; the VimTask
    // decides which tab should be selected at all times.  However, the AppKit
    // will automatically select the first tab added to a tab view.

    NSTabViewItem *tvi = [[NSTabViewItem alloc] initWithIdentifier:nil];

    // NOTE: If this is the first tab it will be automatically selected.
    vimTaskSelectedTab = YES;
    [[self tabView] addTabViewItem:tvi];
    vimTaskSelectedTab = NO;

    [tvi release];

    return tvi;
}

- (int)representedIndexOfTabViewItem:(NSTabViewItem *)tvi
{
    NSArray *tabViewItems = [[self tabBarControl] representedTabViewItems];
    return [tabViewItems indexOfObject:tvi];
}

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

- (void)createScrollbarWithIdentifier:(long)ident type:(int)type
{
    //NSLog(@"Create scroller %d of type %d", ident, type);

    MMScroller *scroller = [[MMScroller alloc] initWithIdentifier:ident
                                                             type:type];
    [scroller setTarget:self];
    [scroller setAction:@selector(scroll:)];

    [self addSubview:scroller];
    [[self scrollbars] addObject:scroller];
    [scroller release];
}

- (void)destroyScrollbarWithIdentifier:(long)ident
{
    //NSLog(@"Destroy scroller %d", ident);

    unsigned idx = 0;
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:&idx];
    if (scroller) {
        [scroller removeFromSuperview];
        [[self scrollbars] removeObjectAtIndex:idx];

        if (![scroller isHidden]) {
            // A visible scroller was removed, so the window must resize to
            // fit.
            //NSLog(@"Visible scroller %d was destroyed, resizing window.",
            //        ident);
            shouldUpdateWindowSize = YES;
        }
    }
}

- (void)showScrollbarWithIdentifier:(long)ident state:(BOOL)visible
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    if (!scroller) return;

    BOOL wasVisible = ![scroller isHidden];
    //NSLog(@"%s scroller %d (was %svisible)", visible ? "Show" : "Hide",
    //      ident, wasVisible ? "" : "in");
    [scroller setHidden:!visible];

    if (wasVisible != visible) {
        // A scroller was hidden or shown, so the window must resize to fit.
        //NSLog(@"%s scroller %d and resize.", visible ? "Show" : "Hide",
        //        ident);
        shouldUpdateWindowSize = YES;
    }
}

- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(long)ident
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    //NSLog(@"Set thumb value %.2f proportion %.2f for scroller %d",
    //        val, prop, ident);
    [scroller setFloatValue:val knobProportion:prop];
    [scroller setEnabled:prop != 1.f];
}


- (void)scroll:(id)sender
{
    NSMutableData *data = [NSMutableData data];
    long ident = [(MMScroller*)sender identifier];
    int hitPart = [sender hitPart];
    float value = [sender floatValue];

    [data appendBytes:&ident length:sizeof(long)];
    [data appendBytes:&hitPart length:sizeof(int)];
    [data appendBytes:&value length:sizeof(float)];

    [vimController sendMessage:ScrollbarEventMsgID data:data];
}

- (void)placeScrollbars
{
    NSRect textViewFrame = [textView frame];
    BOOL lsbVisible = [self leftScrollbarVisible];

    // HACK!  Find the lowest left&right vertical scrollbars, as well as the
    // rightmost horizontal scrollbar.  This hack continues further down.
    //
    // TODO!  Can there be no more than one horizontal scrollbar?  If so, the
    // code can be simplified.
    unsigned lowestLeftSbIdx = (unsigned)-1;
    unsigned lowestRightSbIdx = (unsigned)-1;
    unsigned rightmostSbIdx = (unsigned)-1;
    unsigned rowMaxLeft = 0, rowMaxRight = 0, colMax = 0;
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if (![scroller isHidden]) {
            NSRange range = [scroller range];
            if ([scroller type] == MMScrollerTypeLeft
                    && range.location >= rowMaxLeft) {
                rowMaxLeft = range.location;
                lowestLeftSbIdx = i;
            } else if ([scroller type] == MMScrollerTypeRight
                    && range.location >= rowMaxRight) {
                rowMaxRight = range.location;
                lowestRightSbIdx = i;
            } else if ([scroller type] == MMScrollerTypeBottom
                    && range.location >= colMax) {
                colMax = range.location;
                rightmostSbIdx = i;
            }
        }
    }

    // Place the scrollbars.
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller isHidden])
            continue;

        NSRect rect;
        if ([scroller type] == MMScrollerTypeBottom) {
            rect = [textStorage rectForColumnsInRange:[scroller range]];
            rect.size.height = [NSScroller scrollerWidth];
            if (lsbVisible)
                rect.origin.x += [NSScroller scrollerWidth];

            // HACK!  Make sure the rightmost horizontal scrollbar covers the
            // text view all the way to the right, otherwise it looks ugly when
            // the user drags the window to resize.
            if (i == rightmostSbIdx) {
                float w = NSMaxX(textViewFrame) - NSMaxX(rect);
                if (w > 0)
                    rect.size.width += w;
            }

            // Make sure scrollbar rect is bounded by the text view frame.
            if (rect.origin.x < textViewFrame.origin.x)
                rect.origin.x = textViewFrame.origin.x;
            else if (rect.origin.x > NSMaxX(textViewFrame))
                rect.origin.x = NSMaxX(textViewFrame);
            if (NSMaxX(rect) > NSMaxX(textViewFrame))
                rect.size.width -= NSMaxX(rect) - NSMaxX(textViewFrame);
            if (rect.size.width < 0)
                rect.size.width = 0;
        } else {
            rect = [textStorage rectForRowsInRange:[scroller range]];
            // Adjust for the fact that text layout is flipped.
            rect.origin.y = NSMaxY(textViewFrame) - rect.origin.y
                    - rect.size.height;
            rect.size.width = [NSScroller scrollerWidth];
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
                && rect.origin.y < [NSScroller scrollerWidth]) {
                rect.size.height -= [NSScroller scrollerWidth] - rect.origin.y;
                rect.origin.y = [NSScroller scrollerWidth];
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

        //NSLog(@"set scroller #%d frame = %@", i, NSStringFromRect(rect));
        NSRect oldRect = [scroller frame];
        if (!NSEqualRects(oldRect, rect)) {
            [scroller setFrame:rect];
            // Clear behind the old scroller frame, or parts of the old
            // scroller might still be visible after setFrame:.
            [[[self window] contentView] setNeedsDisplayInRect:oldRect];
            [scroller setNeedsDisplay:YES];
        }
    }
}

- (MMScroller *)scrollbarForIdentifier:(long)ident index:(unsigned *)idx
{
    unsigned i, count = [[self scrollbars] count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [[self scrollbars] objectAtIndex:i];
        if ([scroller identifier] == ident) {
            if (idx) *idx = i;
            return scroller;
        }
    }

    return nil;
}

- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    NSRange range = NSMakeRange(pos, len);
    if (!NSEqualRanges(range, [scroller range])) {
        //NSLog(@"Set range %@ for scroller %d",
        //        NSStringFromRange(range), ident);
        [scroller setRange:range];
        // TODO!  Should only do this once per update.

        // This could be sent because a text window was created or closed, so
        // we might need to update which scrollbars are visible.
        [self placeScrollbars];
    }
}

- (void)placeViews
{
    NSRect textViewRect = [self textViewRectForContentSize:[self frame].size];

    // Give all superfluous space to the text view. It might be smaller or
    // larger than it wants to be, but this is needed during life resizing
    [[self textView] setFrame:textViewRect];

    // for some reason, autoresizing doesn't work...set tab size manually
    [tabBarControl setFrame:[self tabBarFrameForFrame:[self frame]]];

    [self placeScrollbars];
}

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore
{
    [textStorage setDefaultColorsBackground:back foreground:fore];
    [textView setBackgroundColor:back];
}

- (BOOL)shouldUpdateWindowSize
{
    return shouldUpdateWindowSize;
}

- (void)setShouldUpdateWindowSize:(BOOL)b
{
    shouldUpdateWindowSize = b;
}

- (NSSize)contentSizeForTextStorageSize:(NSSize)textViewSize
{
    NSSize size = textViewSize;

    if (![[self tabBarControl] isHidden])
        size.height += [[self tabBarControl] frame].size.height;

    if ([self bottomScrollbarVisible])
        size.height += [NSScroller scrollerWidth];
    if ([self leftScrollbarVisible])
        size.width += [NSScroller scrollerWidth];
    if ([self rightScrollbarVisible])
        size.width += [NSScroller scrollerWidth];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    size.width += [[self textView] textContainerOrigin].x + right;
    size.height += [[self textView] textContainerOrigin].y + bot;

    return size;
}

- (NSRect)textViewRectForContentSize:(NSSize)contentSize
{
    NSRect rect = { 0, 0, contentSize.width, contentSize.height };

    if (![[self tabBarControl] isHidden])
        rect.size.height -= [[self tabBarControl] frame].size.height;

    if ([self bottomScrollbarVisible]) {
        rect.size.height -= [NSScroller scrollerWidth];
        rect.origin.y += [NSScroller scrollerWidth];
    }
    if ([self leftScrollbarVisible]) {
        rect.size.width -= [NSScroller scrollerWidth];
        rect.origin.x += [NSScroller scrollerWidth];
    }
    if ([self rightScrollbarVisible])
        rect.size.width -= [NSScroller scrollerWidth];

    return rect;
}

- (NSSize)textStorageSizeForTextViewSize:(NSSize)textViewSize
{
    NSSize size = textViewSize;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    size.width -= [[self textView] textContainerOrigin].x + right;
    size.height -= [[self textView] textContainerOrigin].y + bot;

    return size;
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
    // HACK!  The selection message should not be propagated to the VimTask if
    // the VimTask selected the tab (e.g. as opposed the user clicking the
    // tab).  The delegate method has no way of knowing who initiated the
    // selection so a flag is set when the VimTask initiated the selection.
    if (!vimTaskSelectedTab) {
        // Propagate the selection message to the VimTask.
        int idx = [self representedIndexOfTabViewItem:tabViewItem];
        if (NSNotFound != idx) {
            NSData *data = [NSData dataWithBytes:&idx length:sizeof(int)];
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
    int idx = [self representedIndexOfTabViewItem:tabViewItem];
    //NSLog(@"Closing tab with index %d", idx);
    NSData *data = [NSData dataWithBytes:&idx length:sizeof(int)];
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

@end




@implementation NSTabView (MMExtras)

- (void)removeAllTabViewItems
{
    NSArray *existingItems = [self tabViewItems];
    NSEnumerator *e = [existingItems objectEnumerator];
    NSTabViewItem *item;
    while (item = [e nextObject]){
        [self removeTabViewItem:item];
    }
}

@end // NSTabView (MMExtras)




@implementation MMScroller

- (id)initWithIdentifier:(long)ident type:(int)theType
{
    // HACK! NSScroller creates a horizontal scroller if it is init'ed with a
    // frame whose with exceeds its height; so create a bogus rect and pass it
    // to initWithFrame.
    NSRect frame = theType == MMScrollerTypeBottom
            ? NSMakeRect(0, 0, 1, 0)
            : NSMakeRect(0, 0, 0, 1);

    if ((self = [super initWithFrame:frame])) {
        identifier = ident;
        type = theType;
        [self setHidden:YES];
        [self setEnabled:YES];
    }

    return self;
}

- (long)identifier
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
    MMWindowController *wc = [[self window] windowController];
    [[wc textView] scrollWheel:event];
}

@end // MMScroller
