#import <Cocoa/Cocoa.h>

// A button that fades in a circular background when hovered.

@interface MMHoverButton : NSButton

@property (nonatomic, retain) NSColor *fgColor;

typedef enum : NSUInteger {
    MMHoverButtonImageAddTab = 0,
    MMHoverButtonImageCloseTab,
    MMHoverButtonImageScrollLeft,
    MMHoverButtonImageScrollRight,
    MMHoverButtonImageCount
} MMHoverButtonImage;

+ (NSImage *)imageFromType:(MMHoverButtonImage)imageType;

@end
