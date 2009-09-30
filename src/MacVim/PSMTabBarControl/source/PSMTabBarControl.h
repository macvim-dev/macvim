//
//  PSMTabBarControl.h
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

/*
 This view provides a control interface to manage a regular NSTabView.  It looks and works like the tabbed browsing interface of many popular browsers.
 */

#import <Cocoa/Cocoa.h>

#ifndef NSINTEGER_DEFINED
// NSInteger was introduced in 10.5
# if __LP64__ || NS_BUILD_32_LIKE_64
typedef long NSInteger;
typedef unsigned long NSUInteger;
# else
typedef int NSInteger;
typedef unsigned int NSUInteger;
# endif
# define NSINTEGER_DEFINED 1
#endif

#define kPSMTabBarControlHeight 22
// internal cell border
#define MARGIN_X        6
#define MARGIN_Y        3
// padding between objects
#define kPSMTabBarCellPadding 4
// fixed size objects
#define kPSMMinimumTitleWidth 30
#define kPSMTabBarIndicatorWidth 16.0
#define kPSMTabBarIconWidth 16.0
#define kPSMHideAnimationSteps 2.0

@class PSMOverflowPopUpButton;
@class PSMRolloverButton;
@class PSMTabBarCell;
@protocol PSMTabStyle;

enum {
    PSMTab_SelectedMask                 = 1 << 1,
    PSMTab_LeftIsSelectedMask		= 1 << 2,
    PSMTab_RightIsSelectedMask          = 1 << 3,
    PSMTab_PositionLeftMask		= 1 << 4,
    PSMTab_PositionMiddleMask		= 1 << 5,
    PSMTab_PositionRightMask		= 1 << 6,
    PSMTab_PositionSingleMask		= 1 << 7
};

@interface PSMTabBarControl : NSControl
#if (MAC_OS_X_VERSION_MAX_ALLOWED >= 1060)
    // 10.6 has turned delegate messages into formal protocols
    <NSTabViewDelegate>
#endif
{
    
    // control basics
    NSMutableArray              *_cells;                    // the cells that draw the tabs
    IBOutlet NSTabView          *tabView;                   // the tab view being navigated
    PSMOverflowPopUpButton      *_overflowPopUpButton;      // for too many tabs
    PSMRolloverButton           *_addTabButton;
    
    // drawing style
    id<PSMTabStyle>             style;
    BOOL                        _canCloseOnlyTab;
    BOOL                        _hideForSingleTab;
    BOOL                        _showAddTabButton;
    BOOL                        _sizeCellsToFit;
    
    // cell width
    int                         _cellMinWidth;
    int                         _cellMaxWidth;
    int                         _cellOptimumWidth;
    
    // animation for hide/show
    int                         _currentStep;
    BOOL                        _isHidden;
    BOOL                        _hideIndicators;
    IBOutlet id                 partnerView;                // gets resized when hide/show
    BOOL                        _awakenedFromNib;
    
    // drag and drop
    NSEvent                     *_lastMouseDownEvent;      // keep this for dragging reference   
    BOOL                        _allowsDragBetweenWindows;
    BOOL                        _delegateHandlingDrag;
    NSDragOperation             _delegateInitialDragOperation;

    // MVC help
    IBOutlet id                 delegate;
}

// control characteristics
+ (NSBundle *)bundle;

// control configuration
- (BOOL)canCloseOnlyTab;
- (void)setCanCloseOnlyTab:(BOOL)value;
- (NSString *)styleName;
- (void)setStyleNamed:(NSString *)name;
- (BOOL)hideForSingleTab;
- (void)setHideForSingleTab:(BOOL)value;
- (BOOL)showAddTabButton;
- (void)setShowAddTabButton:(BOOL)value;
- (int)cellMinWidth;
- (void)setCellMinWidth:(int)value;
- (int)cellMaxWidth;
- (void)setCellMaxWidth:(int)value;
- (int)cellOptimumWidth;
- (void)setCellOptimumWidth:(int)value;
- (BOOL)sizeCellsToFit;
- (void)setSizeCellsToFit:(BOOL)value;
- (BOOL)allowsDragBetweenWindows;
- (void)setAllowsDragBetweenWindows:(BOOL)flag;

// tool tips
- (void)setToolTip:(NSString *)value forTabViewItem:(NSTabViewItem *)tvi;

// accessors
- (NSTabView *)tabView;
- (void)setTabView:(NSTabView *)view;
- (id)delegate;
- (void)setDelegate:(id)object;
- (id)partnerView;
- (void)setPartnerView:(id)view;

// the buttons
- (PSMRolloverButton *)addTabButton;
- (PSMOverflowPopUpButton *)overflowPopUpButton;
- (NSMutableArray *)representedTabViewItems;

// special effects
- (void)hideTabBar:(BOOL)hide animate:(BOOL)animate;

@end


@interface NSObject (TabBarControlDelegateMethods)
- (BOOL)tabView:(NSTabView *)aTabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)aTabView willCloseTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)aTabView didCloseTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)aTabView didDragTabViewItem:(NSTabViewItem *)tabViewItem toIndex:(int)idx;

- (NSDragOperation)tabBarControl:(PSMTabBarControl *)theTabBarControl draggingEntered:(id <NSDraggingInfo>)sender forTabAtIndex:(NSUInteger)tabIndex;
- (NSDragOperation)tabBarControl:(PSMTabBarControl *)theTabBarControl draggingUpdated:(id <NSDraggingInfo>)sender forTabAtIndex:(NSUInteger)tabIndex;
- (void)tabBarControl:(PSMTabBarControl *)theTabBarControl draggingExited:(id <NSDraggingInfo>)sender forTabAtIndex:(NSUInteger)tabIndex;
- (BOOL)tabBarControl:(PSMTabBarControl *)theTabBarControl prepareForDragOperation:(id <NSDraggingInfo>)sender forTabAtIndex:(NSUInteger)tabIndex;
- (BOOL)tabBarControl:(PSMTabBarControl *)theTabBarControl performDragOperation:(id <NSDraggingInfo>)sender forTabAtIndex:(NSUInteger)tabIndex;
- (void)tabBarControl:(PSMTabBarControl *)theTabBarControl concludeDragOperation:(id <NSDraggingInfo>)sender forTabAtIndex:(NSUInteger)tabIndex;
@end
