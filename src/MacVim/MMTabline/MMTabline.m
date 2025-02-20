#import <time.h>
#import <QuartzCore/QuartzCore.h>
#import "MMTabline.h"

// Only imported for getCurrentAppearance()
#import "Miscellaneous.h"

typedef struct TabWidth {
    CGFloat width;
    CGFloat remainder;
} TabWidth;

static const CGFloat OptimumTabWidth = 200;
static const CGFloat MinimumTabWidth = 100;
static const CGFloat TabOverlap      = 6;
static const CGFloat ScrollOneTabAllowance = 0.25; // If we are showing 75+% of the tab, consider it to be fully shown when deciding whether to scroll to next tab.

static MMHoverButton* MakeHoverButton(MMTabline *tabline, MMHoverButtonImage imageType, NSString *tooltip, SEL action, BOOL continuous) {
    MMHoverButton *button = [MMHoverButton new];
    button.imageTemplate = [MMHoverButton imageFromType:imageType];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.target = tabline;
    button.action = action;
    button.continuous = continuous;
    [button sizeToFit];
    [button setToolTip:tooltip];
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
    MMTab *_draggedTab;
    CGFloat _xOffsetForDrag;
    NSInteger _initialDraggedTabIndex;
    NSInteger _finalDraggedTabIndex;
    MMHoverButton *_backwardScrollButton;
    MMHoverButton *_forwardScrollButton;
    id _scrollWheelEventMonitor;
    AppearanceType _appearance; // cached appearance to avoid querying it every time
}

@synthesize tablineBgColor = _tablineBgColor;
@synthesize tablineFgColor = _tablineFgColor;
@synthesize tablineSelBgColor = _tablineSelBgColor;
@synthesize tablineSelFgColor = _tablineSelFgColor;
@synthesize tablineFillBgColor = _tablineFillBgColor;
@synthesize tablineUnfocusedFgColor = _tablineUnfocusedFgColor;
@synthesize tablineUnfocusedSelFgColor = _tablineUnfocusedSelFgColor;

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES; // we use -updateLayer to fill background
        
        _tabs = [NSMutableArray new];
        _showsAddTabButton = YES; // get from NSUserDefaults
        _showsTabScrollButtons = YES; // get from NSUserDefaults
        _useAnimation = YES; // get from NSUserDefaults

        _selectedTabIndex = -1;

        _initialDraggedTabIndex = _finalDraggedTabIndex = NSNotFound;

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

        _addTabButton = MakeHoverButton(
                self,
                MMHoverButtonImageAddTab,
                NSLocalizedString(@"create-new-tab-button", @"Create a new tab button"),
                @selector(addTabAtEnd),
                NO);
        _backwardScrollButton = MakeHoverButton(
                self,
                [self useRightToLeft] ? MMHoverButtonImageScrollRight : MMHoverButtonImageScrollLeft,
                NSLocalizedString(@"scroll-tabs-backward", @"Scroll backward button in tabs line"),
                @selector(scrollBackwardOneTab),
                YES);
        _forwardScrollButton = MakeHoverButton(
                self,
                [self useRightToLeft] ? MMHoverButtonImageScrollLeft : MMHoverButtonImageScrollRight,
                NSLocalizedString(@"scroll-tabs-forward", @"Scroll forward button in tabs line"),
                @selector(scrollForwardOneTab),
                YES);

        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[_backwardScrollButton][_forwardScrollButton]-5-[_scrollView]-5-[_addTabButton]" options:NSLayoutFormatAlignAllCenterY metrics:nil views:NSDictionaryOfVariableBindings(_scrollView, _backwardScrollButton, _forwardScrollButton, _addTabButton)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_scrollView]|" options:0 metrics:nil views:@{@"_scrollView":_scrollView}]];
        
        _tabScrollButtonsLeadingConstraint = [NSLayoutConstraint constraintWithItem:_backwardScrollButton attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeading multiplier:1 constant:5];
        [self addConstraint:_tabScrollButtonsLeadingConstraint];
        
        _addTabButtonTrailingConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:_addTabButton attribute:NSLayoutAttributeTrailing multiplier:1 constant:5];
        [self addConstraint:_addTabButtonTrailingConstraint];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didScroll:) name:NSViewBoundsDidChangeNotification object:_scrollView.contentView];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTabStates) name:NSWindowDidBecomeKeyNotification object:self.window];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTabStates) name:NSWindowDidResignKeyNotification object:self.window];
        if ([self useRightToLeft]) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTabsContainerBoundsForRTL:) name:NSViewFrameDidChangeNotification object:_tabsContainer];
        }

        [self addScrollWheelMonitor];

        _appearance = getCurrentAppearance(self.effectiveAppearance);
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
    self.layer.backgroundColor = self.tablineFillBgColor.CGColor;
}

- (void)viewDidChangeEffectiveAppearance
{
    _appearance = getCurrentAppearance(self.effectiveAppearance);
    [self updateTabStates];
}

- (void)viewDidHide
{
    if (_scrollWheelEventMonitor != nil) {
        [NSEvent removeMonitor:_scrollWheelEventMonitor];
        _scrollWheelEventMonitor = nil;
    }
    [super viewDidHide];
}

- (void)viewDidUnhide
{
    [self addScrollWheelMonitor];
    [super viewDidUnhide];
}

- (void)dealloc
{
    if (_scrollWheelEventMonitor != nil) {
        [NSEvent removeMonitor:_scrollWheelEventMonitor];
        _scrollWheelEventMonitor = nil;
    }

    // This is not necessary after macOS 10.11, but there's no harm in doing so
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
        _tabScrollButtonsLeadingConstraint.constant = showsTabScrollButtons ? 5 : -((NSWidth(_backwardScrollButton.frame) * 2) + 5 + MMTabShadowBlurRadius);
    }
}

- (NSColor *)tablineBgColor
{
    if (_tablineBgColor != nil)
        return _tablineBgColor;
    switch (_appearance) {
        case AppearanceLight:
        default:
            return [NSColor colorWithWhite:0.8 alpha:1];
        case AppearanceDark:
            return [NSColor colorWithWhite:0.2 alpha:1];
        case AppearanceLightHighContrast:
            return [NSColor colorWithWhite:0.7 alpha:1];
        case AppearanceDarkHighContrast:
            return [NSColor colorWithWhite:0.15 alpha:1];
    }
}

- (NSColor *)tablineFgColor
{
    return _tablineFgColor ?: NSColor.secondaryLabelColor;
}

- (NSColor *)tablineSelBgColor
{
    return _tablineSelBgColor ?: (_appearance == AppearanceLight || _appearance == AppearanceLightHighContrast)
        ? [NSColor colorWithWhite:0.95 alpha:1]
        : [NSColor colorWithWhite:0.4 alpha:1];
}

- (NSColor *)tablineSelFgColor
{
    return _tablineSelFgColor ?: NSColor.controlTextColor;
}

- (NSColor *)tablineFillBgColor
{
    return _tablineFillBgColor ?: (_appearance == AppearanceLight || _appearance == AppearanceLightHighContrast)
        ? [NSColor colorWithWhite:0.85 alpha:1]
        : [NSColor colorWithWhite:0.23 alpha:1];
}

- (NSColor *)tablineFillFgColor
{
    return _addTabButton.fgColor;
}

- (NSColor *)tablineUnfocusedFgColor
{
    return _tablineUnfocusedFgColor ?: _tablineFgColor ?: NSColor.tertiaryLabelColor;
}

- (NSColor *)tablineUnfocusedSelFgColor
{
    return _tablineUnfocusedSelFgColor ?: _tablineSelFgColor ?: NSColor.tertiaryLabelColor;
}

- (NSColor *)tablineStrokeColor
{
    if (_appearance == AppearanceLight || _appearance == AppearanceDark)
        return nil; // non-high-contrast modes

    // High-contrast modes. Should stroke to make it easier to read.
    NSColor *bgColor = self.tablineBgColor;
    CGFloat brightness = 1;
    if (bgColor.colorSpace.colorSpaceModel == NSColorSpaceModelRGB)
        brightness = bgColor.brightnessComponent;
    else if (bgColor.colorSpace.colorSpaceModel == NSColorSpaceModelGray)
        brightness = bgColor.whiteComponent;
    if (brightness > 0.5)
        return NSColor.blackColor;
    else
        return NSColor.whiteColor;
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
    frame.origin.x    = index * (t.width - TabOverlap);
    frame = [self flipRectRTL:frame];
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
        [tab removeFromSuperview];
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
        [self fixupLayoutWithAnimation:YES delayResize:!layoutImmediately];
    } else {
        NSLog(@"CANNOT FIND TAB TO REMOVE");
    }
}

- (void)closeAllTabs
{
    _selectedTabIndex = -1;
    _draggedTab = nil;
    _initialDraggedTabIndex = _finalDraggedTabIndex = NSNotFound;
    for (MMTab *tab in _tabs) {
        [tab removeFromSuperview];
    }
    [_tabs removeAllObjects];
    [self fixupLayoutWithAnimation:NO];
}

- (void)updateTabsByTags:(NSInteger *)tags len:(NSUInteger)len delayTabResize:(BOOL)delayTabResize
{
    BOOL needUpdate = NO;
    if (len != _tabs.count) {
        needUpdate = YES;
    } else {
        for (NSUInteger i = 0; i < len; i++) {
            MMTab *tab = _tabs[i];
            if (tab.tag != tags[i]) {
                needUpdate = YES;
                break;
            }
        }
    }
    if (!needUpdate)
        return;

    // Perform a diff between the existing tabs (using MMTab's tags as unique
    // identifiers) and the input specified tags

    // Create a mapping for tags->index. Could potentially cache this but it's
    // simpler to recreate this every time to avoid tracking states.
    NSMutableDictionary *tagToTabIdx = [NSMutableDictionary dictionaryWithCapacity:_tabs.count];
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        MMTab *tab = _tabs[i];
        if (tagToTabIdx[@(tab.tag)] != nil) {
            NSLog(@"Duplicate tag found in tabs");
            // Duplicates are not supposed to exist. We need to remove the view
            // here because the algorithm below will not handle this case and
            // leaves stale views.
            [tab removeFromSuperview];
            continue;
        }
        tagToTabIdx[@(tab.tag)] = @(i);
    }

    const NSInteger oldSelectedTabTag = _selectedTabIndex < 0 ? 0 : _tabs[_selectedTabIndex].tag;
    NSInteger newSelectedTabIndex = -1;

    // Allocate a new tabs list and store all the new and moved tabs there. This
    // is simpler than an in-place algorithm.
    NSMutableArray *newTabs = [NSMutableArray arrayWithCapacity:len];
    for (NSUInteger i = 0; i < len; i++) {
        NSInteger tag = tags[i];
        NSNumber *newTabIdxObj = [tagToTabIdx objectForKey:@(tag)];
        if (newTabIdxObj == nil) {
            // Create new tab
            TabWidth t        = [self tabWidthForTabs:len];
            NSRect frame      = _tabsContainer.bounds;
            frame.size.width  = i == (len - 1) ? t.width + t.remainder : t.width;
            frame.origin.x    = i * (t.width - TabOverlap);
            frame = [self flipRectRTL:frame];
            MMTab *newTab = [[MMTab alloc] initWithFrame:frame tabline:self];
            newTab.tag = tag;
            [newTabs addObject:newTab];
            [_tabsContainer addSubview:newTab];
        } else {
            // Move existing tab
            NSUInteger newTabIdx = [newTabIdxObj unsignedIntegerValue];
            [newTabs addObject:_tabs[newTabIdx]];
            [tagToTabIdx removeObjectForKey:@(tag)];

            // Remap indices if needed
            if (newTabIdx == _selectedTabIndex) {
                newSelectedTabIndex = newTabs.count - 1;
            }
            if (newTabIdx == _initialDraggedTabIndex) {
                _initialDraggedTabIndex = newTabs.count - 1;
                _finalDraggedTabIndex = _initialDraggedTabIndex;
            }
        }
    }

    // Now go through the remaining tabs that did not make it to the new list
    // and remove them.
    NSInteger numDeletedTabsBeforeSelected = 0;
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        MMTab *tab = _tabs[i];
        if ([tagToTabIdx objectForKey:@(tab.tag)] == nil) {
            continue;
        }
        [tab removeFromSuperview];
        if (i < _selectedTabIndex) {
            numDeletedTabsBeforeSelected++;
        }
        if (_draggedTab != nil && _draggedTab == tab) {
            _draggedTab = nil;
            _initialDraggedTabIndex = _finalDraggedTabIndex = NSNotFound;
        }
    }
    const BOOL selectedTabMovedByDeleteOnly = newSelectedTabIndex != -1 &&
        (newSelectedTabIndex == _selectedTabIndex - numDeletedTabsBeforeSelected);

    _tabs = newTabs;

    if (newSelectedTabIndex == -1) {
        // The old selected tab is removed. Select a new one nearby.
        newSelectedTabIndex = _selectedTabIndex >= _tabs.count ? _tabs.count - 1 : _selectedTabIndex;
    }
    [self selectTabAtIndex:newSelectedTabIndex];

    [self fixupLayoutWithAnimation:YES delayResize:delayTabResize];
    [self fixupCloseButtons];
    [self evaluateHoverStateForMouse:[self.window mouseLocationOutsideOfEventStream]];

    // Heuristics for scrolling to the selected tab after update:
    // 1. If 'delayTabResize' is set, we are trying to line up tab positions, do
    //    DON'T scroll, even if the old selected tab was removed.
    // 2. Otherwise if we changed tab selection (happens when the selected tab
    //    was removed), just scroll to the new selected tab.
    // 3. If the selected tab has moved in position, scroll to it, unless it
    //    only moved due to the earlier tabs being deleted (meaning that the tab
    //    ordering was preserved). This helps prevent unnecessary scrolling
    //    around when the user is trying to delete tabs in other areas.
    // This chould potentially be exposed to the caller for more custimization.
    const NSInteger newSelectedTabTag = _selectedTabIndex < 0 ? 0 : _tabs[_selectedTabIndex].tag;
    BOOL scrollToSelected = NO;
    if (!delayTabResize) {
        if (oldSelectedTabTag != newSelectedTabTag)
            scrollToSelected = YES;
        else if (!selectedTabMovedByDeleteOnly)
            scrollToSelected = YES;
    }
    if (scrollToSelected)
        [self scrollTabToVisibleAtIndex:_selectedTabIndex];
}

- (void)selectTabAtIndex:(NSInteger)index
{
    if (_draggedTab != nil) {
        // Selected a non-dragged tab, simply unset the dragging operation. This
        // is somewhat Vim-specific, as it does not support re-ordering a
        // non-active tab. Could be made configurable in the future.
        if (index < 0 || index >= _tabs.count || _tabs[index] != _draggedTab) {
            _draggedTab = nil;
            _initialDraggedTabIndex = _finalDraggedTabIndex = NSNotFound;
            [self fixupLayoutWithAnimation:YES];
        }
    }
    if (_selectedTabIndex >= 0 && _selectedTabIndex <= _tabs.count - 1) {
        _tabs[_selectedTabIndex].state = MMTabStateUnselected;
    }
    if (index <= _tabs.count - 1) {
        _selectedTabIndex = index;
        if (index >= 0)
            _tabs[_selectedTabIndex].state = MMTabStateSelected;
    }
    else {
        NSLog(@"TRIED TO SELECT OUT OF BOUNDS: %ld/%ld", index, _tabs.count - 1);
    }
    [self fixupTabZOrder];
}

- (MMTab *)tabAtIndex:(NSInteger)index
{
    if (index >= _tabs.count) {
        [NSException raise:NSRangeException format:@"Index (%lu) beyond bounds (%lu)", index, _tabs.count - 1];
    }
    return _tabs[index];
}

- (void)setColorsTabBg:(NSColor *)tabBg tabFg:(NSColor *)tabFg
                 selBg:(NSColor *)selBg selFg:(NSColor *)selFg
                fillBg:(NSColor *)fillBg fillFg:(NSColor *)fillFg
{
    // Don't use the property mutators as we just want to update the states in
    // one go at the end.
    _tablineSelBgColor = selBg;
    _tablineSelFgColor = selFg;
    _tablineBgColor = tabBg;
    _tablineFgColor = tabFg;
    _tablineFillBgColor = fillBg;

    _tablineUnfocusedFgColor = [_tablineFgColor blendedColorWithFraction:0.4 ofColor:_tablineBgColor];
    _tablineUnfocusedSelFgColor = [_tablineSelFgColor blendedColorWithFraction:0.38 ofColor:_tablineSelBgColor];

    _addTabButton.fgColor = fillFg;
    _backwardScrollButton.fgColor = fillFg;
    _forwardScrollButton.fgColor = fillFg;

    [self updateTabStates];
    self.needsDisplay = YES;
}

- (void)setAutoColorsSelBg:(NSColor *)back fg:(NSColor *)fore;
{
    // Set the colors for the tabline based on the default background and
    // foreground colors.

    // Calculate CIE Lab color. This is used for deriving other colors that are
    // brighter / darker versions of the background color. Using Lab gives better
    // results than simpy blending non-linearized RGB values.
    // Note: We don't use CGColorSpaceCreateWithName(kCGColorSpaceGenericLab)
    //       because the API is only available on macOS 10.13+.
    const CGFloat whitePoint[3] = {0.95947,1,1.08883}; // D65 white point
    const CGFloat blackPoint[3] = {0,0,0};
    const CGFloat ranges[4] = {-127, 127, -127, 127};
    CGColorSpaceRef labRef = CGColorSpaceCreateLab(whitePoint, blackPoint, ranges);
    NSColorSpace *lab = [[NSColorSpace alloc] initWithCGColorSpace:labRef];
    NSColor *backLab = [back colorUsingColorSpace:lab];
    CGColorSpaceRelease(labRef);
    if (backLab.numberOfComponents > 4)
        backLab = nil; // don't know how this could happen, but just to be safe

    CGFloat backComponents[4] = { 1, 0, 0, 1 }; // L*/a*/b*/alpha. L* is perceptual lightness from 0-100.
    [backLab getComponents:backComponents];
    CGFloat newComponents[4];
    memcpy(newComponents, backComponents, sizeof(newComponents));

    // Contrast (different in lightness) for fill bg and tab bg colors relative to the background color
    // Note that this is not perceptively accurate to just add a fixed offset to the L* value but it's
    // good enough for our purpose.
    const CGFloat fillContrastDark = 17.0;
    const CGFloat bgContrastDark = fillContrastDark * 0.71;
    const CGFloat fillContrastLight = -19.0;
    const CGFloat bgContrastLight = fillContrastLight * 0.70;

    const CGFloat fillContrast = backComponents[0] >= 40 ? fillContrastLight : fillContrastDark;
    const CGFloat bgContrast = backComponents[0] >= 40 ? bgContrastLight : bgContrastDark;

    // Assign the colors
    _tablineSelBgColor = back;

    _tablineSelFgColor = [fore blendedColorWithFraction:0.6
                                                ofColor:(backComponents[0] >= 50 ? NSColor.blackColor : NSColor.whiteColor)];
    _addTabButton.fgColor = _tablineSelFgColor;
    _backwardScrollButton.fgColor = _tablineSelFgColor;
    _forwardScrollButton.fgColor = _tablineSelFgColor;

    newComponents[0] = backComponents[0] + bgContrast;
    _tablineBgColor = [[NSColor colorWithColorSpace:lab
                                         components:newComponents
                                              count:4]
                       colorUsingColorSpace:NSColorSpace.sRGBColorSpace];

    _tablineFgColor = [_tablineSelFgColor blendedColorWithFraction:0.5 ofColor:_tablineBgColor];

    _tablineUnfocusedFgColor = [_tablineFgColor blendedColorWithFraction:0.4 ofColor:_tablineBgColor];
    _tablineUnfocusedSelFgColor = [_tablineSelFgColor blendedColorWithFraction:0.38 ofColor:_tablineSelBgColor];

    newComponents[0] = backComponents[0] + fillContrast;
    _tablineFillBgColor = [[NSColor colorWithColorSpace:lab
                                             components:newComponents
                                                  count:4]
                           colorUsingColorSpace:NSColorSpace.sRGBColorSpace];

    [self updateTabStates];
    self.needsDisplay = YES;
}

#pragma mark - Helpers

NSComparisonResult SortTabsForZOrder(MMTab *tab1, MMTab *tab2, void *draggedTab, BOOL rtl)
{   // Z-order, highest to lowest: dragged, selected, hovered, rightmost
    if (tab1 == (__bridge MMTab *)draggedTab) return NSOrderedDescending;
    if (tab2 == (__bridge MMTab *)draggedTab) return NSOrderedAscending;
    if (tab1.state == MMTabStateSelected) return NSOrderedDescending;
    if (tab2.state == MMTabStateSelected) return NSOrderedAscending;
    if (tab1.state == MMTabStateUnselectedHover) return NSOrderedDescending;
    if (tab2.state == MMTabStateUnselectedHover) return NSOrderedAscending;
    if (rtl) {
        if (NSMinX(tab1.frame) > NSMinX(tab2.frame)) return NSOrderedAscending;
        if (NSMinX(tab1.frame) < NSMinX(tab2.frame)) return NSOrderedDescending;
    } else {
        if (NSMinX(tab1.frame) < NSMinX(tab2.frame)) return NSOrderedAscending;
        if (NSMinX(tab1.frame) > NSMinX(tab2.frame)) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

NSComparisonResult SortTabsForZOrderLTR(MMTab *tab1, MMTab *tab2, void *draggedTab)
{
    return SortTabsForZOrder(tab1, tab2, draggedTab, NO);
}


NSComparisonResult SortTabsForZOrderRTL(MMTab *tab1, MMTab *tab2, void *draggedTab)
{
    return SortTabsForZOrder(tab1, tab2, draggedTab, YES);
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

/// Install a scroll wheel event monitor so that we can convert vertical scroll
/// wheel events to horizontal ones, so that the user doesn't have to hold down
/// SHIFT key while scrolling.
///
/// Caller *has* to call `removeMonitor:` on `_scrollWheelEventMonitor`
/// afterwards.
- (void)addScrollWheelMonitor
{
    // We have to use a local event monitor because we are not allowed to
    // override NSScrollView's scrollWheel: method. If we do so we will lose
    // macOS responsive scrolling. See:
    // https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/index.html#10_9Scrolling
    if (_scrollWheelEventMonitor != nil)
        return;
    __weak NSScrollView *scrollView_weak = _scrollView;
    __weak __typeof__(self) self_weak = self;
    _scrollWheelEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        // We want an event:
        //   - that actually belongs to this window
        //   - initiated by the scroll wheel and not the trackpad
        //   - is a vertical scroll event (if this is a horizontal scroll event
        //     either via holding SHIFT or third-party software we just let it
        //     through)
        //   - where the mouse is over the scroll view
        if (event.window == self_weak.window
            && !event.hasPreciseScrollingDeltas
            && (event.scrollingDeltaX == 0 && event.scrollingDeltaY != 0)
            && [scrollView_weak mouse:[scrollView_weak convertPoint:event.locationInWindow fromView:nil]
                               inRect:scrollView_weak.bounds])
        {
            // Create a new scroll wheel event based on the original,
            // but set the new deltaX to the original's deltaY.
            // stackoverflow.com/a/38991946/111418
            CGEventRef cgEvent = CGEventCreateCopy(event.CGEvent);
            CGEventSetIntegerValueField(cgEvent, kCGScrollWheelEventDeltaAxis1, 0);
            CGEventSetIntegerValueField(cgEvent, kCGScrollWheelEventDeltaAxis2, event.scrollingDeltaY);
            NSEvent *newEvent = [NSEvent eventWithCGEvent:cgEvent];
            CFRelease(cgEvent);
            return newEvent;
        }
        return event;
    }];
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
    if ([self useRightToLeft]) {
        [_tabsContainer sortSubviewsUsingFunction:SortTabsForZOrderRTL
                                          context:(__bridge void *)(_draggedTab)];
    } else {
        [_tabsContainer sortSubviewsUsingFunction:SortTabsForZOrderLTR
                                          context:(__bridge void *)(_draggedTab)];
    }
}

/// The main layout function that calculates the tab positions and animate them
/// accordingly. Call this every time tabs have been added/removed/moved.
- (void)fixupLayoutWithAnimation:(BOOL)shouldAnimate delayResize:(BOOL)delayResize
{
    if (!self.useAnimation)
        shouldAnimate = NO;

    if (_tabs.count == 0) {
        NSRect frame = _tabsContainer.frame;
        frame.size.width = 0;
        _tabsContainer.frame = frame;
        [self updateTabScrollButtonsEnabledState];
        return;
    }

    if (delayResize) {
        // The pending delayed resize is trigged by mouse exit, but if we are
        // already outside, then there's nothing to delay.
        NSPoint locationInWindow = [self.window mouseLocationOutsideOfEventStream];
        if (![self mouse:locationInWindow inRect:self.frame]) {
            delayResize = NO;
        }
    }

    TabWidth t = [self tabWidthForTabs:_tabs.count];
    for (NSInteger i = 0; i < _tabs.count; i++) {
        MMTab *tab = _tabs[i];
        if (_draggedTab == tab) continue;
        NSRect frame = tab.frame;
        if (delayResize) {
            frame.origin.x = i != 0 ? i * (NSWidth(_tabs[i-1].frame) - TabOverlap) : 0;
        } else {
            frame.size.width = i == _tabs.count - 1 ? t.width + t.remainder : t.width;
            frame.origin.x = i != 0 ? i * (t.width - TabOverlap) : 0;
        }
        frame = [self flipRectRTL:frame];
        if (shouldAnimate) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
                context.allowsImplicitAnimation = YES;
                tab.animator.frame = frame;
                [tab layout];
            } completionHandler:nil];
        } else {
            tab.frame = frame;
        }
    }
    if (delayResize) {
        _pendingFixupLayout = YES;
    } else {
        // _tabsContainer expands to fit tabs, is at least as wide as _scrollView.
        NSRect frame = _tabsContainer.frame;
        frame.size.width = t.width * _tabs.count - TabOverlap * (_tabs.count - 1);
        frame.size.width = NSWidth(frame) < NSWidth(_scrollView.frame) ? NSWidth(_scrollView.frame) : NSWidth(frame);
        const BOOL sizeDecreasing = NSWidth(frame) < NSWidth(_tabsContainer.frame);
        if ([self useRightToLeft]) {
            // In RTL mode we flip the X coords and grow from 0 to negative.
            // See updateTabsContainerBoundsForRTL which auto-updates the
            // bounds to match the frame.
            frame.origin.x = -NSWidth(frame);
        }
        if (shouldAnimate && sizeDecreasing) {
            // Need to animate to make sure we don't immediately get clamped by
            // the new size if we are already scrolled all the way to the back.
            _tabsContainer.animator.frame = frame;
        } else {
            _tabsContainer.frame = frame;
        }
        [self updateTabScrollButtonsEnabledState];
    }
}

- (void)fixupLayoutWithAnimation:(BOOL)shouldAnimate
{
    [self fixupLayoutWithAnimation:shouldAnimate delayResize:NO];
}

- (void)updateTabStates
{
    for (MMTab *tab in _tabs) tab.state = tab.state;
}

#pragma mark - Right-to-left (RTL) support

- (BOOL)useRightToLeft
{
    // MMTabs support RTL locales. In such locales user interface items are
    // laid out from right to left. The layout of hover buttons and views are
    // automatically flipped by AppKit, but we need to handle this manually in
    // the tab placement logic since that is custom logic.
    return self.userInterfaceLayoutDirection == NSUserInterfaceLayoutDirectionRightToLeft;
}

- (void)updateTabsContainerBoundsForRTL:(NSNotification *)notification
{
    // In RTL mode, we grow the tabs container to the left. We want to preserve
    // stability of the scroll view's bounds, and also have the tabs animate
    // correctly. To do this, we have to make sure the container bounds matches
    // the frame at all times. This "cancels out" the negative X offsets with
    // each other and ease calculations.
    // E.g. an MMTab with origin (-100,0) inside the _tabsContainer coordinate
    // space will actually be (-100,0) in the scroll view as well.
    // In LTR mode we don't need this, since _tabsContainer's origin is always
    // at (0,0).
    _tabsContainer.bounds = _tabsContainer.frame;
}

- (NSRect)flipRectRTL:(NSRect)frame
{
    if ([self useRightToLeft]) {
        // In right-to-left mode, we flip the X coordinates for all the tabs so
        // they start at 0 and grow in the negative direction.
        frame.origin.x = -NSMaxX(frame);
    }
    return frame;
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
    _initialDraggedTabIndex = _finalDraggedTabIndex = NSNotFound;
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
    MMTab *selectedTab = _selectedTabIndex == -1 ? nil : _tabs[_selectedTabIndex];
    const BOOL rightToLeft = [self useRightToLeft];
    [_tabs sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(MMTab *t1, MMTab *t2) {
        if (rightToLeft) {
            if (NSMaxX(t1.frame) >= NSMaxX(t2.frame)) return NSOrderedAscending;
            if (NSMaxX(t1.frame) <  NSMaxX(t2.frame)) return NSOrderedDescending;
        } else {
            if (NSMinX(t1.frame) <= NSMinX(t2.frame)) return NSOrderedAscending;
            if (NSMinX(t1.frame) >  NSMinX(t2.frame)) return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    _selectedTabIndex = _selectedTabIndex == -1 ? -1 : [_tabs indexOfObject:selectedTab];
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
        _backwardScrollButton.enabled = NO;
        _forwardScrollButton.enabled = NO;
    } else {
        BOOL scrollLeftEnabled = NSMinX(clipBounds) > NSMinX(_tabsContainer.frame);
        BOOL scrollRightEnabled = NSMaxX(clipBounds) < NSMaxX(_tabsContainer.frame);
        if ([self useRightToLeft]) {
            _backwardScrollButton.enabled = scrollRightEnabled;
            _forwardScrollButton.enabled = scrollLeftEnabled;
        } else {
            _backwardScrollButton.enabled = scrollLeftEnabled;
            _forwardScrollButton.enabled = scrollRightEnabled;
        }
    }
}

- (void)scrollTabToVisibleAtIndex:(NSInteger)index
{
    if (_tabs.count == 0) return;
    index = index < 0 ? 0 : (index >= _tabs.count ? _tabs.count - 1 : index);

    // Get the amount of time elapsed between the previous invocation
    // of this method and now. Use this elapsed time to set the animation
    // duration such that rapid invocations of this method result in
    // faster animations. For example, the user might hold down the tab
    // scrolling buttons (causing them to repeatedly fire) or they might
    // rapidly click them.
#if defined(MAC_OS_X_VERSION_10_12) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_12
    static NSTimeInterval lastTime = 0;
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    NSTimeInterval currentTime = t.tv_sec + t.tv_nsec * 1.e-9;
    NSTimeInterval elapsedTime = currentTime - lastTime;
    lastTime = currentTime;
#else
    // clock_gettime was only added in macOS 10.12. Just use a fixed value
    // here. No need to find an alternative API for legacy macOS versions.
    NSTimeInterval elapsedTime = 0.1;
#endif

    NSRect tabFrame = _tabs[index].animator.frame;
    NSRect clipBounds =_scrollView.contentView.animator.bounds;
    // One side or the other of the selected tab is clipped.
    if (!NSContainsRect(clipBounds, tabFrame)) {
        if (NSMinX(tabFrame) > NSMinX(clipBounds)) {
            // Right side of the selected tab is clipped.
            clipBounds.origin.x = NSMaxX(tabFrame) - NSWidth(clipBounds);
        } else {
            // Left side of the selected tab is clipped.
            clipBounds.origin.x = tabFrame.origin.x;
        }
        if (_useAnimation) {
            [NSAnimationContext beginGrouping];
            [NSAnimationContext.currentContext setDuration:elapsedTime < 0.2 ? 0.05 : 0.2];
            [_scrollView.contentView.animator setBoundsOrigin:clipBounds.origin];
            [NSAnimationContext endGrouping];
        } else {
            [_scrollView.contentView setBoundsOrigin:clipBounds.origin];
        }
    }
}

- (void)scrollBackwardOneTab
{
    NSRect clipBounds = _scrollView.contentView.animator.bounds;
    for (NSInteger i = _tabs.count - 1; i >= 0; i--) {
        NSRect tabFrame = _tabs[i].frame;
        if (!NSContainsRect(clipBounds, tabFrame)) {
            const CGFloat allowance = (i == 0) ?
                0 : NSWidth(tabFrame) * ScrollOneTabAllowance;
            const BOOL outOfBounds = [self useRightToLeft] ?
                NSMaxX(tabFrame) - allowance > NSMaxX(clipBounds) :
                NSMinX(tabFrame) + allowance < NSMinX(clipBounds);
            if (outOfBounds) {
                [self scrollTabToVisibleAtIndex:i];
                break;
            }
        }
    }
}

- (void)scrollForwardOneTab
{
    NSRect clipBounds = _scrollView.contentView.animator.bounds;
    for (NSInteger i = 0; i < _tabs.count; i++) {
        NSRect tabFrame = _tabs[i].frame;
        if (!NSContainsRect(clipBounds, tabFrame)) {
            const CGFloat allowance = (i == _tabs.count - 1) ?
                0 : NSWidth(tabFrame) * ScrollOneTabAllowance;
            const BOOL outOfBounds = [self useRightToLeft] ?
                NSMinX(tabFrame) + allowance < NSMinX(clipBounds) :
                NSMaxX(tabFrame) - allowance > NSMaxX(clipBounds);
            if (outOfBounds) {
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
