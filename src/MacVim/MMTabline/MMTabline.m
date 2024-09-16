#import <time.h>
#import <QuartzCore/QuartzCore.h>
#import "MMTabline.h"
#import "Miscellaneous.h"

typedef struct TabWidth {
    CGFloat width;
    CGFloat remainder;
} TabWidth;

const CGFloat OptimumTabWidth = 200;
const CGFloat MinimumTabWidth = 100;
const CGFloat TabOverlap      = 6;

MMHoverButton* MakeHoverButton(MMTabline *tabline, NSString *imageName, NSString *tooltip, SEL action, BOOL continuous) {
    MMHoverButton *button = [MMHoverButton new];
    button.image = [MMHoverButton imageNamed:imageName];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.target = tabline;
    button.action = action;
    button.continuous = continuous;
    [button sizeToFit];
    [button setToolTip:NSLocalizedString(tooltip, @"Tabline button")];
    [tabline addSubview:button];
    return button;
}

@implementation MMTabline
{
    NSView *_tabsContainer;
    NSScrollView *_scrollView;
    NSMutableArray <MMTab *> *_tabs;
    NSTrackingArea *_trackingArea;
    NSLayoutConstraint *_tabScrollButtonsLeadingConstraint;
    NSLayoutConstraint *_addTabButtonTrailingConstraint;
    BOOL _pendingFixupLayout;
    MMTab *_selectedTab;
    MMTab *_draggedTab;
    CGFloat _xOffsetForDrag;
    NSInteger _initialDraggedTabIndex;
    NSInteger _finalDraggedTabIndex;
    MMHoverButton *_leftScrollButton;
    MMHoverButton *_rightScrollButton;
    id _scrollWheelEventMonitor;
}

@synthesize tablineBgColor = _tablineBgColor;
@synthesize tablineFgColor = _tablineFgColor;
@synthesize tablineSelBgColor = _tablineSelBgColor;
@synthesize tablineSelFgColor = _tablineSelFgColor;
@synthesize tablineFillFgColor = _tablineFillFgColor;

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES; // we use -updateLayer to fill background
        
        _tabs = [NSMutableArray new];
        _showsAddTabButton = YES; // get from NSUserDefaults
        _showsTabScrollButtons = YES; // get from NSUserDefaults
        
        // This view holds the tab views.
        _tabsContainer = [NSView new];
        _tabsContainer.frame = (NSRect){{0, 0}, frameRect.size};
        
        _scrollView = [NSScrollView new];
        _scrollView.drawsBackground = NO;
        _scrollView.verticalScrollElasticity = NSScrollElasticityNone;
        _scrollView.contentView.postsBoundsChangedNotifications = YES;
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollView.documentView = _tabsContainer;
        [self addSubview:_scrollView];

        _addTabButton = MakeHoverButton(self, @"AddTabButton", @"New Tab (⌘T)", @selector(addTabAtEnd), NO);
        _leftScrollButton = MakeHoverButton(self, @"ScrollLeftButton", @"Scroll Tabs", @selector(scrollLeftOneTab), YES);
        _rightScrollButton = MakeHoverButton(self, @"ScrollRightButton", @"Scroll Tabs", @selector(scrollRightOneTab), YES);

        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[_leftScrollButton][_rightScrollButton]-5-[_scrollView]-5-[_addTabButton]" options:NSLayoutFormatAlignAllCenterY metrics:nil views:NSDictionaryOfVariableBindings(_scrollView, _leftScrollButton, _rightScrollButton, _addTabButton)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_scrollView]|" options:0 metrics:nil views:@{@"_scrollView":_scrollView}]];
        
        _tabScrollButtonsLeadingConstraint = [NSLayoutConstraint constraintWithItem:_leftScrollButton attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeading multiplier:1 constant:5];
        [self addConstraint:_tabScrollButtonsLeadingConstraint];
        
        _addTabButtonTrailingConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:_addTabButton attribute:NSLayoutAttributeTrailing multiplier:1 constant:5];
        [self addConstraint:_addTabButtonTrailingConstraint];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didScroll:) name:NSViewBoundsDidChangeNotification object:_scrollView.contentView];

        // Monitor for scroll wheel events so we can scroll the tabline
        // horizontally without the user having to hold down SHIFT.
        _scrollWheelEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
            NSPoint location = [_scrollView convertPoint:event.locationInWindow fromView:nil];
            // We want events:
            //   where the mouse is over the _scrollView
            //   and where the user is not modifying it with the SHIFT key
            //   and initiated by the scroll wheel and not the trackpad
            if ([_scrollView mouse:location inRect:_scrollView.bounds]
                && !event.modifierFlags
                && !event.hasPreciseScrollingDeltas)
            {
                // Create a new scroll wheel event based on the original,
                // but set the new deltaX to the original's deltaY.
                // stackoverflow.com/a/38991946/111418
                CGEventRef cgEvent = CGEventCreateCopy(event.CGEvent);
                CGEventSetIntegerValueField(cgEvent, kCGScrollWheelEventDeltaAxis2, event.scrollingDeltaY);
                NSEvent *newEvent = [NSEvent eventWithCGEvent:cgEvent];
                CFRelease(cgEvent);
                return newEvent;
            }
            return event;
        }];
    }
    return self;
}

- (void)layout
{
    [super layout];
    [self fixupLayoutWithAnimation:NO];
}

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer
{
    self.layer.backgroundColor = self.tablineFillFgColor.CGColor;
}

- (void)viewDidChangeEffectiveAppearance
{
    for (MMTab *tab in _tabs) tab.state = tab.state;
}

#pragma mark - Accessors

- (NSInteger)numberOfTabs
{
    return _tabs.count;
}

- (NSInteger)optimumTabWidth
{
    return _optimumTabWidth ?: OptimumTabWidth;
}

- (NSInteger)minimumTabWidth
{
    return _minimumTabWidth ?: MinimumTabWidth;
}

- (void)setShowsAddTabButton:(BOOL)showsAddTabButton
{
    // showsAddTabButton:
    //   The trailing constraint is a 5pt margin.
    // !showsAddTabButton:
    //   The trailing constraint is a negative margin so the add
    //   button is clipped out of the right side of the view. The
    //   amount of negative margin is the width of the button plus
    //   5 to account for the margin between the scroll view and
    //   the button plus the shadow blur radius of each tab (see
    //   -drawRect: in MMTab.m).
    if (_showsAddTabButton != showsAddTabButton) {
        _showsAddTabButton = showsAddTabButton;
        _addTabButtonTrailingConstraint.constant = showsAddTabButton ? 5 : -(NSWidth(_addTabButton.frame) + 5 + MMTabShadowBlurRadius);
    }
}

- (void)setShowsTabScrollButtons:(BOOL)showsTabScrollButtons
{
    // showsTabScrollButtons:
    //   The leading constraint is a 5pt margin.
    // !showsTabScrollButtons:
    //   The leading constraint is a negative margin so the scroll
    //   buttons are clipped out of the left side of the view. The
    //   amount of the negative margin is the width of each button
    //   plus 5 to account for the margin between the buttons and
    //   the scroll view plus the shadow blur radius of each tab
    //   (see -drawRect: in MMTab.m).
    if (_showsTabScrollButtons != showsTabScrollButtons) {
        _showsTabScrollButtons = showsTabScrollButtons;
        _tabScrollButtonsLeadingConstraint.constant = showsTabScrollButtons ? 5 : -((NSWidth(_leftScrollButton.frame) * 2) + 5 + MMTabShadowBlurRadius);
    }
}

- (NSColor *)tablineBgColor
{
    return _tablineBgColor ?: getCurrentAppearance(self.effectiveAppearance)
        ? [NSColor colorWithWhite:0.2 alpha:1]
        : [NSColor colorWithWhite:0.8 alpha:1];
}

- (void)setTablineBgColor:(NSColor *)color
{
    _tablineBgColor = color;
    for (MMTab *tab in _tabs) tab.state = tab.state;
}

- (NSColor *)tablineFgColor
{
    return _tablineFgColor ?: NSColor.disabledControlTextColor;
}

- (void)setTablineFgColor:(NSColor *)color
{
    _tablineFgColor = color;
    for (MMTab *tab in _tabs) tab.state = tab.state;
}

- (NSColor *)tablineSelBgColor
{
    return _tablineSelBgColor ?: getCurrentAppearance(self.effectiveAppearance)
        ? [NSColor colorWithWhite:0.4 alpha:1]
        : NSColor.whiteColor;
}

- (void)setTablineSelBgColor:(NSColor *)color
{
    _tablineSelBgColor = color;
    for (MMTab *tab in _tabs) tab.state = tab.state;
}

- (NSColor *)tablineSelFgColor
{
    return _tablineSelFgColor ?: NSColor.controlTextColor;
}

- (void)setTablineSelFgColor:(NSColor *)color
{
    _tablineSelFgColor = color;
    _addTabButton.fgColor = color;
    _leftScrollButton.fgColor = color;
    _rightScrollButton.fgColor = color;
    for (MMTab *tab in _tabs) tab.state = tab.state;
}

- (NSColor *)tablineFillFgColor
{
    return _tablineFillFgColor ?: getCurrentAppearance(self.effectiveAppearance)
        ? [NSColor colorWithWhite:0.2 alpha:1]
        : [NSColor colorWithWhite:0.8 alpha:1];
}

- (void)setTablineFillFgColor:(NSColor *)color
{
    _tablineFillFgColor = color;
    self.needsDisplay = YES;
}

- (NSInteger)addTabAtEnd
{
    return [self addTabAtIndex:(_tabs.count ? _tabs.count : 0)];
}

- (NSInteger)addTabAfterSelectedTab
{
    return [self addTabAtIndex:(_tabs.count ? _selectedTabIndex + 1 : 0)];
}

- (NSInteger)addTabAtIndex:(NSInteger)index
{
    if (!self.superview || index > _tabs.count) return NSNotFound;
    
    TabWidth t        = [self tabWidthForTabs:_tabs.count + 1];
    NSRect frame      = _tabsContainer.bounds;
    frame.size.width  = index == _tabs.count ? t.width + t.remainder : t.width;
    frame.origin.x    = index ? index * (t.width - TabOverlap) : 0;
    MMTab *newTab = [[MMTab alloc] initWithFrame:frame tabline:self];

    [_tabs insertObject:newTab atIndex:index];
    [_tabsContainer addSubview:newTab];
    
    [self selectTabAtIndex:index];
    [self fixupLayoutWithAnimation:YES];
    [self fixupCloseButtons];
    /* Let MacVim handle scrolling to selected tab.
    [self scrollTabToVisibleAtIndex:_selectedTabIndex]; */
    [self evaluateHoverStateForMouse:[self.window mouseLocationOutsideOfEventStream]];
    
    return index;
}

- (void)closeTab:(MMTab *)tab force:(BOOL)force layoutImmediately:(BOOL)layoutImmediately
{
    NSInteger index = [_tabs indexOfObject:tab];
    if (!force && [self.delegate respondsToSelector:@selector(tabline:shouldCloseTabAtIndex:)]) {
        if (![self.delegate tabline:self shouldCloseTabAtIndex:index]) return;
    }
    if (index != NSNotFound) {
        CGFloat w = NSWidth(tab.frame) - TabOverlap;
        [tab removeFromSuperview];
        for (NSInteger i = index + 1; i < _tabs.count; i++) {
            MMTab *tv = _tabs[i];
            NSRect frame = tv.frame;
            frame.origin.x -= w;
            tv.animator.frame = frame;
        }
        [_tabs removeObject:tab];
        if (index <= _selectedTabIndex) {
            if (index < _selectedTabIndex || index > _tabs.count - 1) {
                [self selectTabAtIndex:_selectedTabIndex - 1];
            }
            else {
                [self selectTabAtIndex:_selectedTabIndex];
            }
        }
        [self fixupCloseButtons];
        [self evaluateHoverStateForMouse:[self.window mouseLocationOutsideOfEventStream]];
        if (layoutImmediately) [self fixupLayoutWithAnimation:YES];
        else _pendingFixupLayout = YES;
    } else {
        NSLog(@"CANNOT FIND TAB TO REMOVE");
    }
}

- (void)selectTabAtIndex:(NSInteger)index
{
    if (_selectedTabIndex <= _tabs.count - 1) {
        _tabs[_selectedTabIndex].state = MMTabStateUnselected;
    }
    if (index <= _tabs.count - 1) {
        _selectedTabIndex = index;
        _tabs[_selectedTabIndex].state = MMTabStateSelected;
    }
    else {
        NSLog(@"TRIED TO SELECT OUT OF BOUNDS: %ld/%ld", index, _tabs.count - 1);
    }
    _selectedTab = _tabs[_selectedTabIndex];
    [self fixupTabZOrder];
}

- (MMTab *)tabAtIndex:(NSInteger)index
{
    if (index >= _tabs.count) {
        [NSException raise:NSRangeException format:@"Index (%lu) beyond bounds (%lu)", index, _tabs.count - 1];
    }
    return _tabs[index];
}

- (void)setTablineSelBackground:(NSColor *)back foreground:(NSColor *)fore
{
    // Reset to default tabline colors if user doesn't want auto-generated ones.
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"MMDefaultTablineColors"]) {
        self.tablineBgColor = nil;
        self.tablineFgColor = nil;
        self.tablineSelBgColor = nil;
        self.tablineSelFgColor = nil;
        self.tablineFillFgColor = nil;
        return;
    }

    // Set the colors for the tabline based on the default background and
    // foreground colors. Calculate brightness according to a formula from
    // the W3C that gives brightness as the eye perceives it. Then lighten
    // or darken the default colors based on whether brightness is greater
    // than 50% to achieve good visual contrast.
    // www.w3.org/WAI/ER/WD-AERT/#color-contrast
    CGFloat r, g, b, brightness;
    [back getRed:&r green:&g blue:&b alpha:NULL];
    brightness = r * 0.299 + g * 0.114 + b * 0.587;
    
    self.tablineSelBgColor = back;

    self.tablineSelFgColor = (brightness > 0.5)
        ? [fore blendedColorWithFraction:0.6 ofColor:NSColor.blackColor]
        : [fore blendedColorWithFraction:0.6 ofColor:NSColor.whiteColor];

    self.tablineBgColor = (brightness > 0.5)
        ? [back blendedColorWithFraction:0.16 ofColor:NSColor.blackColor]
        : [back blendedColorWithFraction:0.13 ofColor:NSColor.whiteColor];

    self.tablineFgColor = [self.tablineSelFgColor blendedColorWithFraction:0.5 ofColor:self.tablineBgColor];

    self.tablineFillFgColor = (brightness > 0.5)
        ? [back blendedColorWithFraction:0.25 ofColor:NSColor.blackColor]
        : [back blendedColorWithFraction:0.18 ofColor:NSColor.whiteColor];
}

#pragma mark - Helpers

NSComparisonResult SortTabsForZOrder(MMTab *tab1, MMTab *tab2, void *draggedTab)
{   // Z-order, highest to lowest: dragged, selected, hovered, rightmost
    if (tab1 == (__bridge MMTab *)draggedTab) return NSOrderedDescending;
    if (tab2 == (__bridge MMTab *)draggedTab) return NSOrderedAscending;
    if (tab1.state == MMTabStateSelected) return NSOrderedDescending;
    if (tab2.state == MMTabStateSelected) return NSOrderedAscending;
    if (tab1.state == MMTabStateUnselectedHover) return NSOrderedDescending;
    if (tab2.state == MMTabStateUnselectedHover) return NSOrderedAscending;
    if (NSMinX(tab1.frame) < NSMinX(tab2.frame)) return NSOrderedAscending;
    if (NSMinX(tab1.frame) > NSMinX(tab2.frame)) return NSOrderedDescending;
    return NSOrderedSame;
}

- (TabWidth)tabWidthForTabs:(NSInteger)numTabs
{
    // Each tab (except the first) overlaps the previous tab by TabOverlap
    // points so we add TabOverlap * (numTabs - 1) to account for this.
    CGFloat availableWidthForTabs = NSWidth(_scrollView.frame) + TabOverlap * (numTabs - 1);
    CGFloat tabWidth = (availableWidthForTabs / numTabs);
    if (tabWidth > self.optimumTabWidth) {
        return (TabWidth){self.optimumTabWidth, 0};
    }
    if (tabWidth < self.minimumTabWidth) {
        return (TabWidth){self.minimumTabWidth, 0};
    }
    // Round tabWidth down to nearest 0.5
    CGFloat f = floor(tabWidth);
    tabWidth = (tabWidth - f < 0.5) ? f : f + 0.5;
    return (TabWidth){tabWidth, availableWidthForTabs - tabWidth * numTabs};
}

- (void)fixupCloseButtons
{
    if (_tabs.count == 1) {
        _tabs.firstObject.closeButtonHidden = YES;
    }
    else for (MMTab *tab in _tabs) {
        tab.closeButtonHidden = NO;
    }
}

- (void)fixupTabZOrder
{
    [_tabsContainer sortSubviewsUsingFunction:SortTabsForZOrder context:(__bridge void *)(_draggedTab)];
}

- (void)fixupLayoutWithAnimation:(BOOL)shouldAnimate
{
    if (_tabs.count == 0) return;
    
    TabWidth t = [self tabWidthForTabs:_tabs.count];
    for (NSInteger i = 0; i < _tabs.count; i++) {
        MMTab *tab = _tabs[i];
        if (_draggedTab == tab) continue;
        NSRect frame = tab.frame;
        frame.size.width = i == _tabs.count - 1 ? t.width + t.remainder : t.width;
        frame.origin.x = i ? i * (t.width - TabOverlap) : 0;
        if (shouldAnimate) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
                context.allowsImplicitAnimation = YES;
                tab.animator.frame = frame;
                [tab layout];
            }];
        } else tab.frame = frame;
    }
    // _tabsContainer expands to fit tabs, is at least as wide as _scrollView.
    NSRect frame = _tabsContainer.frame;
    frame.size.width = t.width * _tabs.count - TabOverlap * (_tabs.count - 1);
    frame.size.width = NSWidth(frame) < NSWidth(_scrollView.frame) ? NSWidth(_scrollView.frame) : NSWidth(frame);
    if (shouldAnimate) _tabsContainer.animator.frame = frame;
    else _tabsContainer.frame = frame;
    [self updateTabScrollButtonsEnabledState];
}

#pragma mark - Mouse

- (void)updateTrackingAreas
{
    [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:_scrollView.frame options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow) owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
    [super updateTrackingAreas];
}

- (BOOL)mouse:(NSPoint)windowLocation inTab:(MMTab *)tab
{
    // YES if windowLocation is inside _scrollview AND tab.
    NSPoint location = [_scrollView convertPoint:windowLocation fromView:nil];
    if ([_scrollView mouse:location inRect:_scrollView.bounds]) {
        location = [tab convertPoint:windowLocation fromView:nil];
        return [tab mouse:location inRect:tab.bounds];
    }
    return NO;
}

- (NSInteger)indexOfTabAtMouse:(NSPoint)windowLocation
{
    for (MMTab *tab in _tabs)
        if ([self mouse:windowLocation inTab:tab])
            return [_tabs indexOfObject:tab];
    return NSNotFound;
}

- (void)evaluateHoverStateForMouse:(NSPoint)locationInWindow
{
    for (MMTab *tab in _tabs) {
        if ([self mouse:locationInWindow inTab:tab]) {
            if (tab.state == MMTabStateUnselected) {
                tab.state = MMTabStateUnselectedHover;
            }
        }
        else if (tab.state == MMTabStateUnselectedHover) {
            tab.state = MMTabStateUnselected;
        }
    }
    [self fixupTabZOrder];
}

- (void)mouseExited:(NSEvent *)event
{
    for (MMTab *tab in _tabs) {
        if (tab.state == MMTabStateUnselectedHover) {
            tab.state = MMTabStateUnselected;
        }
    }
    if (_pendingFixupLayout) {
        _pendingFixupLayout = NO;
        [self fixupLayoutWithAnimation:YES];
    }
    [self fixupTabZOrder];
}

- (void)mouseMoved:(NSEvent *)event
{
    [self evaluateHoverStateForMouse:event.locationInWindow];
}

- (void)mouseDown:(NSEvent *)event
{
    _draggedTab = nil;
    _initialDraggedTabIndex = _finalDraggedTabIndex = NSNotFound;
    
    // Select clicked tab, possibly pending delegate's approval.
    for (MMTab *tab in _tabs) {
        if ([self mouse:event.locationInWindow inTab:tab]) {
            _draggedTab = tab;
            if (tab.state != MMTabStateSelected) {
                NSInteger index = [_tabs indexOfObject:tab];
                if ([self.delegate respondsToSelector:@selector(tabline:shouldSelectTabAtIndex:)]) {
                    if (![self.delegate tabline:self shouldSelectTabAtIndex:index]) break;
                }
                [self selectTabAtIndex:index];
            }
            [self scrollTabToVisibleAtIndex:_selectedTabIndex];
            break;
        }
    }
}

- (void)mouseUp:(NSEvent *)event
{
    _draggedTab = nil;
    [self fixupLayoutWithAnimation:YES];
    [self fixupTabZOrder];
    if (_finalDraggedTabIndex != NSNotFound) [self scrollTabToVisibleAtIndex:_finalDraggedTabIndex];
    if (_initialDraggedTabIndex != NSNotFound &&
        _initialDraggedTabIndex != _finalDraggedTabIndex) {
        if ([self.delegate respondsToSelector:@selector(tabline:didDragTab:toIndex:)]) {
            [self.delegate tabline:self didDragTab:_tabs[_finalDraggedTabIndex] toIndex:_finalDraggedTabIndex];
        }
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    if (!_draggedTab || _tabs.count < 2) return;
    NSPoint mouse = [_tabsContainer convertPoint:event.locationInWindow fromView:nil];
    if (_initialDraggedTabIndex == NSNotFound) {
        _initialDraggedTabIndex = [_tabs indexOfObject:_draggedTab];
        _xOffsetForDrag = mouse.x - _draggedTab.frame.origin.x;
    }
    [_tabsContainer autoscroll:event];
    [self fixupTabZOrder];
    [_draggedTab setFrameOrigin:NSMakePoint(mouse.x - _xOffsetForDrag, 0)];
    [_tabs sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(MMTab *t1, MMTab *t2) {
        if (NSMinX(t1.frame) <= NSMinX(t2.frame)) return NSOrderedAscending;
        if (NSMinX(t1.frame) >  NSMinX(t2.frame)) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    _selectedTabIndex = [_tabs indexOfObject:_selectedTab];
    _finalDraggedTabIndex = [_tabs indexOfObject:_draggedTab];
    [self fixupLayoutWithAnimation:YES];
}

#pragma mark - Scroll

- (void)didScroll:(NSNotification *)note
{
    [self evaluateHoverStateForMouse:[self.window mouseLocationOutsideOfEventStream]];
    [self updateTabScrollButtonsEnabledState];
}

- (void)updateTabScrollButtonsEnabledState
{
    // Enable scroll buttons if there is scrollable content
    // on either side of _scrollView.
    NSRect clipBounds = _scrollView.contentView.bounds;
    if (NSWidth(_tabsContainer.frame) <= NSWidth(clipBounds)) {
        _leftScrollButton.enabled = NO;
        _rightScrollButton.enabled = NO;
    } else {
        _leftScrollButton.enabled  = clipBounds.origin.x > 0;
        _rightScrollButton.enabled = clipBounds.origin.x + NSWidth(clipBounds) < NSMaxX(_tabsContainer.frame);
    }
}

- (void)scrollTabToVisibleAtIndex:(NSInteger)index
{
    if (_tabs.count == 0) return;
    
    // Get the amount of time elapsed between the previous invocation
    // of this method and now. Use this elapsed time to set the animation
    // duration such that rapid invocations of this method result in
    // faster animations. For example, the user might hold down the tab
    // scrolling buttons (causing them to repeatedly fire) or they might
    // rapidly click them.
    static NSTimeInterval lastTime = 0;
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    NSTimeInterval currentTime = t.tv_sec + t.tv_nsec * 1.e-9;
    NSTimeInterval elapsedTime = currentTime - lastTime;
    lastTime = currentTime;

    NSRect tabFrame = _tabs[index].frame;
    NSRect clipBounds = _scrollView.contentView.bounds;
    // One side or the other of the selected tab is clipped.
    if (!NSContainsRect(clipBounds, tabFrame)) {
        if (NSMinX(tabFrame) > NSMinX(clipBounds)) {
            // Right side of the selected tab is clipped.
            clipBounds.origin.x = NSMaxX(tabFrame) - NSWidth(clipBounds);
        } else {
            // Left side of the selected tab is clipped.
            clipBounds.origin.x = tabFrame.origin.x;
        }
        [NSAnimationContext beginGrouping];
        [NSAnimationContext.currentContext setDuration:elapsedTime < 0.2 ? 0.05 : 0.2];
        _scrollView.contentView.animator.bounds = clipBounds;
        [NSAnimationContext endGrouping];
    }
}

- (void)scrollLeftOneTab
{
    NSRect clipBounds = _scrollView.contentView.bounds;
    for (NSInteger i = _tabs.count - 1; i >= 0; i--) {
        NSRect tabFrame = _tabs[i].frame;
        if (!NSContainsRect(clipBounds, tabFrame)) {
            if (NSMinX(tabFrame) < NSMinX(clipBounds)) {
                [self scrollTabToVisibleAtIndex:i];
                break;
            }
        }
    }
}

- (void)scrollRightOneTab
{
    NSRect clipBounds = _scrollView.contentView.bounds;
    for (NSInteger i = 0; i < _tabs.count; i++) {
        NSRect tabFrame = _tabs[i].frame;
        if (!NSContainsRect(clipBounds, tabFrame)) {
            if (NSMaxX(tabFrame) > NSMaxX(clipBounds)) {
                [self scrollTabToVisibleAtIndex:i];
                break;
            }
        }
    }
}


#pragma mark - Drag and drop

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)dragInfo
{
    [self evaluateHoverStateForMouse:dragInfo.draggingLocation];
    if (self.delegate && [self.delegate respondsToSelector:@selector(tabline:draggingEntered:forTabAtIndex:)]) {
        NSInteger index = [self indexOfTabAtMouse:dragInfo.draggingLocation];
        return [self.delegate tabline:self draggingEntered:dragInfo forTabAtIndex:index];
    }
    return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)dragInfo
{
    return [self draggingEntered:dragInfo];
}

- (void)draggingExited:(id<NSDraggingInfo>)dragInfo
{
    [self evaluateHoverStateForMouse:dragInfo.draggingLocation];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)dragInfo
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(tabline:performDragOperation:forTabAtIndex:)]) {
        NSInteger index = [self indexOfTabAtMouse:dragInfo.draggingLocation];
        return [self.delegate tabline:self performDragOperation:dragInfo forTabAtIndex:index];
    }
    return NO;
}

@end
