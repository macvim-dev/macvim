#import <Cocoa/Cocoa.h>
#import "MMHoverButton.h"
#import "MMTab.h"

// A tabline containing one or more tabs.

#define MMTablineHeight (23)

@protocol MMTablineDelegate;

@interface MMTabline : NSView

@property (nonatomic) NSUInteger selectedTabIndex;
@property (nonatomic) NSUInteger optimumTabWidth;
@property (nonatomic) NSUInteger minimumTabWidth;
@property (nonatomic) BOOL showsAddTabButton;
@property (nonatomic) BOOL showsTabScrollButtons;
@property (nonatomic, readonly) NSUInteger numberOfTabs;
@property (nonatomic, retain, readonly) MMHoverButton *addTabButton;
@property (nonatomic, retain) NSColor *tablineBgColor;
@property (nonatomic, retain) NSColor *tablineFgColor;
@property (nonatomic, retain) NSColor *tablineSelBgColor;
@property (nonatomic, retain) NSColor *tablineSelFgColor;
@property (nonatomic, retain) NSColor *tablineFillFgColor;
@property (nonatomic, weak) id <MMTablineDelegate> delegate;

- (NSUInteger)addTabAtEnd;
- (NSUInteger)addTabAfterSelectedTab;
- (NSUInteger)addTabAtIndex:(NSUInteger)index;
- (void)closeTab:(MMTab *)tab force:(BOOL)force layoutImmediately:(BOOL)layoutImmediately;
- (void)selectTabAtIndex:(NSUInteger)index;
- (MMTab *)tabAtIndex:(NSUInteger)index;
- (void)scrollTabToVisibleAtIndex:(NSUInteger)index;
- (void)setTablineSelBackground:(NSColor *)back foreground:(NSColor *)fore;

@end

@protocol MMTablineDelegate <NSObject>
@optional

- (BOOL)tabline:(MMTabline *)tabline shouldSelectTabAtIndex:(NSUInteger)index;
- (BOOL)tabline:(MMTabline *)tabline shouldCloseTabAtIndex:(NSUInteger)index;
- (void)tabline:(MMTabline *)tabline didDragTab:(MMTab *)tab toIndex:(NSUInteger)index;
- (NSDragOperation)tabline:(MMTabline *)tabline draggingEntered:(id <NSDraggingInfo>)dragInfo forTabAtIndex:(NSUInteger)index;
- (BOOL)tabline:(MMTabline *)tabline performDragOperation:(id <NSDraggingInfo>)dragInfo forTabAtIndex:(NSUInteger)index;

@end
