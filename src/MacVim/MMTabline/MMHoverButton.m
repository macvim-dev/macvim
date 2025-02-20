#import "MMHoverButton.h"

@implementation MMHoverButton
{
    NSTrackingArea *_trackingArea;
    NSBox *_circle;
}

+ (NSImage *)imageFromType:(MMHoverButtonImage)imageType
{
    if (imageType >= MMHoverButtonImageCount)
        return nil;

    CGFloat size = imageType == MMHoverButtonImageCloseTab ? 15 : 17;

    static __weak NSImage *imageCache[MMHoverButtonImageCount] = { nil };
    if (imageCache[imageType] != nil)
        return imageCache[imageType];

    BOOL (^drawFuncs[MMHoverButtonImageCount])(NSRect) = {
        // AddTab
        ^BOOL(NSRect dstRect) {
            NSBezierPath *p = [NSBezierPath new];
            [p moveToPoint:NSMakePoint( 8.5,  4.5)];
            [p lineToPoint:NSMakePoint( 8.5, 12.5)];
            [p moveToPoint:NSMakePoint( 4.5,  8.5)];
            [p lineToPoint:NSMakePoint(12.5,  8.5)];
            [p setLineWidth:1.2];
            [p stroke];
            return YES;
        },
        // CloseTab
        ^BOOL(NSRect dstRect) {
            NSBezierPath *p = [NSBezierPath new];
            [p moveToPoint:NSMakePoint( 4.5,  4.5)];
            [p lineToPoint:NSMakePoint(10.5, 10.5)];
            [p moveToPoint:NSMakePoint( 4.5, 10.5)];
            [p lineToPoint:NSMakePoint(10.5,  4.5)];
            [p setLineWidth:1.2];
            [p stroke];
            return YES;
        },
        // ScrollLeft
        ^BOOL(NSRect dstRect) {
            NSBezierPath *p = [NSBezierPath new];
            [p moveToPoint:NSMakePoint( 5.0,  8.5)];
            [p lineToPoint:NSMakePoint(10.0,  4.5)];
            [p lineToPoint:NSMakePoint(10.0, 12.5)];
            [p fill];
            return YES;
        },
        // ScrollRight
        ^BOOL(NSRect dstRect) {
            NSBezierPath *p = [NSBezierPath new];
            [p moveToPoint:NSMakePoint(12.0,  8.5)];
            [p lineToPoint:NSMakePoint( 7.0,  4.5)];
            [p lineToPoint:NSMakePoint( 7.0, 12.5)];
            [p fill];
            return YES;
        }
    };
    NSImage *img = [NSImage imageWithSize:NSMakeSize(size, size)
                                  flipped:NO
                           drawingHandler:drawFuncs[imageType]];
    imageCache[imageType] = img;
    return img;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.buttonType = NSButtonTypeMomentaryChange;
        self.bordered = NO;
        self.imagePosition = NSImageOnly;
        
        // This view will fade in/out when hovered.
        _circle = [NSBox new];
        _circle.boxType = NSBoxCustom;
        _circle.borderWidth = 0;
        _circle.alphaValue = 0.16;
        _circle.fillColor = NSColor.clearColor;
        _circle.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _circle.frame = self.bounds;
        [self addSubview:_circle positioned:NSWindowBelow relativeTo:nil];
    }
    return self;
}

- (void)setFgColor:(NSColor *)color
{
    _fgColor = color;
    [self setImageTemplate:_imageTemplate];
}

- (void)setImageTemplate:(NSImage *)imageTemplate
{
    _imageTemplate = imageTemplate;
    _circle.cornerRadius = imageTemplate.size.width / 2.0;
    NSColor *fillColor = self.fgColor ?: NSColor.controlTextColor;
    NSImage *image = [NSImage imageWithSize:imageTemplate.size
                                    flipped:NO
                             drawingHandler:^BOOL(NSRect dstRect) {
        [imageTemplate drawInRect:dstRect];
        [fillColor set];
        NSRectFillUsingOperation(dstRect, NSCompositingOperationSourceAtop);
        return YES;
    }];
    self.image = image;
}

- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
    [self evaluateHover];
}

- (void)updateTrackingAreas
{
    [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow) owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
    [self evaluateHover];
    [super updateTrackingAreas];
}

- (void)backgroundCircleShouldHighlight:(BOOL)shouldHighlight
{
    NSColor *fillColor = NSColor.clearColor;
    if (shouldHighlight) {
        fillColor = self.fgColor ?: NSColor.controlTextColor;
    }
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.1];
    _circle.animator.fillColor = fillColor;
    [NSAnimationContext endGrouping];
}

- (void)evaluateHover
{
    NSPoint mouseLocation = [self.window mouseLocationOutsideOfEventStream];
    mouseLocation = [self convertPoint:mouseLocation fromView:nil];
    if (NSPointInRect(mouseLocation, self.bounds)) {
        if (self.enabled) [self backgroundCircleShouldHighlight:YES];
        else [self backgroundCircleShouldHighlight:NO];
    } else {
        [self backgroundCircleShouldHighlight:NO];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    if (self.enabled) [self backgroundCircleShouldHighlight:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    [self backgroundCircleShouldHighlight:NO];
}

@end
