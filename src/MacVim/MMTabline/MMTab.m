#import <QuartzCore/QuartzCore.h>
#import "MMTab.h"
#import "MMTabline.h"
#import "MMHoverButton.h"

// Only imported for AVAILABLE_MAC_OS
#import "MacVim.h"

#if !defined(MAC_OS_X_VERSION_10_13) || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_13
typedef NSString * NSAnimatablePropertyKey;
#endif

@interface MMTab ()
@property (nonatomic) NSColor *fillColor;
@end

@implementation MMTab
{
    MMTabline __weak *_tabline;
    MMHoverButton *_closeButton;
    NSTextField *_titleLabel;
}

@synthesize tag = _tag;

+ (id)defaultAnimationForKey:(NSAnimatablePropertyKey)key
{
    if ([key isEqualToString:@"fillColor"]) {
        CABasicAnimation *anim = [CABasicAnimation new];
        anim.duration = 0.1;
        return anim;
    }
    return [super defaultAnimationForKey:key];
}

- (instancetype)initWithFrame:(NSRect)frameRect tabline:(MMTabline *)tabline
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _tabline = tabline;
        
        _closeButton = [MMHoverButton new];
        _closeButton.imageTemplate = [MMHoverButton imageFromType:MMHoverButtonImageCloseTab];
        _closeButton.target = self;
        _closeButton.action = @selector(closeTab:);
        _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_closeButton];

        _titleLabel = [NSTextField new];
#if defined(MAC_OS_X_VERSION_10_11) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_11
        if (AVAILABLE_MAC_OS(10,11)) {
            _titleLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold];
        } else
#endif
        {
            _titleLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        }
        _titleLabel.textColor = NSColor.controlTextColor;
        _titleLabel.editable = NO;
        _titleLabel.selectable = NO;
        _titleLabel.bordered = NO;
        _titleLabel.bezeled = NO;
        _titleLabel.drawsBackground = NO;
        _titleLabel.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        // Title can be compressed smaller than its contents. See centerConstraint
        // below where priority is set less than here for compression resistance.
        // This breaks centering and allows label to fill all available space.
        [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityFittingSizeCompression+2 forOrientation:NSLayoutConstraintOrientationHorizontal];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];
        
        NSDictionary *viewDict = NSDictionaryOfVariableBindings(_closeButton, _titleLabel);
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-9-[_closeButton]-(>=5)-[_titleLabel]-(>=16)-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:viewDict]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:_titleLabel attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
        NSLayoutConstraint *centerConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:_titleLabel attribute:NSLayoutAttributeCenterX multiplier:1 constant:0];
        centerConstraint.priority = NSLayoutPriorityFittingSizeCompression+1;
        [self addConstraint:centerConstraint];

        self.state = MMTabStateUnselected;
    }
    return self;
}

- (void)closeTab:(id)sender
{
    [_tabline closeTab:self force:NO layoutImmediately:NO];
}

- (NSString *)title
{
    return _titleLabel.stringValue;
}

- (void)setTitle:(NSString *)title
{
    _titleLabel.stringValue = title;
}

- (void)setCloseButtonHidden:(BOOL)closeButtonHidden
{
    _closeButtonHidden = closeButtonHidden;
    _closeButton.hidden = closeButtonHidden;
}

- (void)setFillColor:(NSColor *)fillColor
{
    _fillColor = fillColor;
    self.needsDisplay = YES;
}

- (void)setState:(MMTabState)state
{
    const BOOL hasFocus = (self.window == nil) || [self.window isKeyWindow];

    // Transitions to and from MMTabStateSelected
    // DO NOT animate so that UX feels snappier.
    if (state == MMTabStateSelected) {
        _closeButton.fgColor = _tabline.tablineSelFgColor;
        _titleLabel.textColor = hasFocus ? _tabline.tablineSelFgColor : _tabline.tablineUnfocusedSelFgColor;
        self.fillColor = _tabline.tablineSelBgColor;
    }
    else if (state == MMTabStateUnselected) {
        if (_state == MMTabStateSelected) {
            _closeButton.fgColor = _tabline.tablineFgColor;
            _titleLabel.textColor = hasFocus ? _tabline.tablineFgColor : _tabline.tablineUnfocusedFgColor;
            self.fillColor = _tabline.tablineBgColor;
        } else {
            _closeButton.animator.fgColor = _tabline.tablineFgColor;
            _titleLabel.animator.textColor = hasFocus ? _tabline.tablineFgColor : _tabline.tablineUnfocusedFgColor;
            self.animator.fillColor = _tabline.tablineBgColor;
        }
    }
    else { // state == MMTabStateUnselectedHover
        _closeButton.animator.fgColor = _tabline.tablineSelFgColor;
        _titleLabel.animator.textColor = hasFocus ? _tabline.tablineSelFgColor : _tabline.tablineUnfocusedSelFgColor;
        self.animator.fillColor = self.unselectedHoverColor;
    }
    _state = state;
}

- (NSColor *)unselectedHoverColor
{
    return [_tabline.tablineSelBgColor blendedColorWithFraction:0.6 ofColor:_tabline.tablineBgColor];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [self.fillColor set];
    CGFloat minX = MMTabShadowBlurRadius;
    CGFloat maxX = NSMaxX(self.bounds);
    CGFloat maxY = MMTablineHeight;
    NSBezierPath *p = [NSBezierPath new];
    [p moveToPoint:NSMakePoint(minX, 0)];
    [p lineToPoint:NSMakePoint(minX + 3.6, maxY - 2.5)];
    [p curveToPoint: NSMakePoint(minX + 6.5, maxY) controlPoint1: NSMakePoint(minX + 3.8, maxY - 1) controlPoint2: NSMakePoint(minX + 5.1, maxY)];
    [p lineToPoint:NSMakePoint(maxX - 6.5 - minX, maxY)];
    [p curveToPoint:NSMakePoint(maxX - 3.6 - minX, maxY - 2.5) controlPoint1: NSMakePoint(maxX - 5.1 - minX, maxY) controlPoint2: NSMakePoint(maxX - 3.8 - minX, maxY - 1)];
    [p lineToPoint:NSMakePoint(maxX - minX, 0)];
    [p closePath];
    // On macOS 11, translate the tab down 1 pt to provide a thin
    // line between the top of the tab and the window's title bar.
    // It looks better given the new way macOS 11 draws title bars.
    // Older macOS versions don't need this.
    if (AVAILABLE_MAC_OS(11,0)) {
        NSAffineTransform *transform = [NSAffineTransform new];
        [transform translateXBy:0 yBy:-1.0];
        [p transformUsingAffineTransform:transform];
    }
    [p fill];
    NSColor *strokeColor = _tabline.tablineStrokeColor;
    if (strokeColor != nil) {
        [strokeColor set];
        [p stroke];
    }
}

@end
