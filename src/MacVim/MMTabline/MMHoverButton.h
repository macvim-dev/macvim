#import <Cocoa/Cocoa.h>

// A button that fades in a circular background when hovered.

@interface MMHoverButton : NSButton

@property (nonatomic, retain) NSColor *fgColor;
@property (nonatomic, retain) NSImage *imageTemplate;

typedef enum : NSUInteger {
    MMHoverButtonImageAddTab = 0,
    MMHoverButtonImageCloseTab,
    MMHoverButtonImageScrollLeft,
    MMHoverButtonImageScrollRight,
    MMHoverButtonImageCount
} MMHoverButtonImage;

+ (NSImage *)imageFromType:(MMHoverButtonImage)imageType;

@end
