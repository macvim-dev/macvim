#import <Cocoa/Cocoa.h>

// A button that fades in a circular background when hovered.

@interface MMHoverButton : NSButton

@property (nonatomic, retain) NSColor *fgColor;

+ (NSImage *)imageNamed:(NSString *)name;

@end
