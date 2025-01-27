#import <Cocoa/Cocoa.h>

// A tab with a close button and title.

#define MMTabShadowBlurRadius (2)

typedef enum : NSInteger {
    MMTabStateSelected,
    MMTabStateUnselected,
    MMTabStateUnselectedHover,
} MMTabState;

@class MMTabline;

@interface MMTab : NSView

@property (nonatomic, readwrite) NSInteger tag; ///< Unique identifier that caller can set for the tab
@property (nonatomic, copy) NSString *title;
@property (nonatomic, getter=isCloseButtonHidden) BOOL closeButtonHidden;
@property (nonatomic) MMTabState state;

- (instancetype)initWithFrame:(NSRect)frameRect tabline:(MMTabline *)tabline;

@end
