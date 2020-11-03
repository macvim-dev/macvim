#import <Cocoa/Cocoa.h>
#import "MMHoverButton.h"
#import "MMTab.h"

// A tabline containing one or more tabs.

#define MMTablineHeight (23)

@protocol MMTablineDelegate;

@interface MMTabline : NSView

@property (nonatomic) NSInteger selectedTabIndex;
@property (nonatomic) NSInteger optimumTabWidth;
@property (nonatomic) NSInteger minimumTabWidth;
@property (nonatomic) BOOL showsAddTabButton;
@property (nonatomic) BOOL showsTabScrollButtons;
@property (nonatomic, readonly) NSInteger numberOfTabs;
@property (nonatomic, retain, readonly) MMHoverButton *addTabButton;
@property (nonatomic, retain) NSColor *tablineBgColor;
@property (nonatomic, retain) NSColor *tablineFgColor;
@property (nonatomic, retain) NSColor *tablineSelBgColor;
@property (nonatomic, retain) NSColor *tablineSelFgColor;
@property (nonatomic, retain) NSColor *tablineFillFgColor;
@property (nonatomic, weak) id <MMTablineDelegate> delegate;

- (NSInteger)addTabAtEnd;
- (NSInteger)addTabAfterSelectedTab;
- (NSInteger)addTabAtIndex:(NSInteger)index;
- (void)closeTab:(MMTab *)tab force:(BOOL)force layoutImmediately:(BOOL)layoutImmediately;
- (void)selectTabAtIndex:(NSInteger)index;
- (MMTab *)tabAtIndex:(NSInteger)index;
- (void)scrollTabToVisibleAtIndex:(NSInteger)index;
- (void)setTablineSelBackground:(NSColor *)back foreground:(NSColor *)fore;

@end

@protocol MMTablineDelegate <NSObject>
@optional

- (BOOL)tabline:(MMTabline *)tabline shouldSelectTabAtIndex:(NSInteger)index;
- (BOOL)tabline:(MMTabline *)tabline shouldCloseTabAtIndex:(NSInteger)index;
- (void)tabline:(MMTabline *)tabline didDragTab:(MMTab *)tab toIndex:(NSInteger)index;
- (NSDragOperation)tabline:(MMTabline *)tabline draggingEntered:(id <NSDraggingInfo>)dragInfo forTabAtIndex:(NSInteger)index;
- (BOOL)tabline:(MMTabline *)tabline performDragOperation:(id <NSDraggingInfo>)dragInfo forTabAtIndex:(NSInteger)index;

@end
