//
//  PSMMojaveTabStyle.m
//  PSMTabBarControl
//
//  This file is copied from PSMYosemiteTabStyle to allow for modifications to
//  adapt to Mojave-specific functionality such as Dark Mode without needing to
//  pollute the implementation of Yosemite tab style.
//
//

#import "PSMMojaveTabStyle.h"
#import "PSMRolloverButton.h"


#if HAS_MOJAVE_TAB_STYLE

#define kPSMMetalObjectCounterRadius 7.0
#define kPSMMetalCounterMinWidth 20

void MojaveNSDrawWindowBackground(NSRect rect, NSColor *color)
{
    [color set];
    NSRectFill( rect );
}

@implementation PSMMojaveTabStyle


#pragma mark -
#pragma mark Initializers

- (id)init
{
    self = [super init];
    if (!self) return nil;

    closeButton = [self createCloseButtonImage:16.0 color:[NSColor secondaryLabelColor] backgroundColor:nil];
    closeButtonDown = [self createCloseButtonImage:16.0 color:[NSColor secondaryLabelColor] backgroundColor:[NSColor grayColor]];
    closeButtonOver = [self createCloseButtonImage:16.0 color:[NSColor secondaryLabelColor] backgroundColor:[NSColor grayColor]];
    closeButtonOverDark = [self createCloseButtonImage:16.0 color:[NSColor secondaryLabelColor] backgroundColor:[NSColor darkGrayColor]];

    _addTabButtonImage = [NSImage imageNamed:NSImageNameAddTemplate];

    return self;
}

- (NSString *)name
{
    return @"Mojave";
}

#pragma mark -
#pragma mark Control Specific

- (float)leftMarginForTabBarControl
{
    return -1.0f;
}

- (float)rightMarginForTabBarControl
{
    return 24.0f;
}

#pragma mark -
#pragma mark Add Tab Button

- (void)styleAddTabButton:(PSMRolloverButton *)addTabButton
{
    NSImage *newButtonImage = [self addTabButtonImage];
    if (newButtonImage) {
        [addTabButton setUsualImage:newButtonImage];
        [addTabButton setAlternateImage:newButtonImage];
        [addTabButton setRolloverImage:newButtonImage];
    }
    [addTabButton setButtonType:NSMomentaryLightButton];
}

- (NSImage *)addTabButtonImage
{
    return _addTabButtonImage;
}

- (NSImage *)addTabButtonPressedImage
{
    return _addTabButtonImage;;
}

- (NSImage *)addTabButtonRolloverImage
{
    return _addTabButtonImage;
}

- (NSColor *)backgroundColor:(PSMTabBarCell *)cell isKeyWindow:(BOOL)isKeyWindow isSelected:(BOOL)isSelected
{
    NSColor *backgroundColor;

    BOOL isHighlight = [cell isHighlighted];

    if (isKeyWindow) {
        if (isSelected) {
            backgroundColor = [NSColor colorNamed:@"MojaveTabBackgroundActiveSelected" bundle:[PSMTabBarControl bundle]];
        } else if (isHighlight) {
            backgroundColor = [NSColor colorNamed:@"MojaveTabBackgroundActiveHighlight" bundle:[PSMTabBarControl bundle]];
        } else {
            backgroundColor = [NSColor colorNamed:@"MojaveTabBackgroundActive" bundle:[PSMTabBarControl bundle]];
        }
    } else {
        if (isSelected) {
            backgroundColor = [NSColor colorNamed:@"MojaveTabBackgroundInactiveSelected" bundle:[PSMTabBarControl bundle]];
        } else if (isHighlight) {
            backgroundColor = [NSColor colorNamed:@"MojaveTabBackgroundInactiveHighlight" bundle:[PSMTabBarControl bundle]];
        } else {
            backgroundColor = [NSColor colorNamed:@"MojaveTabBackgroundInactive" bundle:[PSMTabBarControl bundle]];
        }
    }

    return backgroundColor;
}

- (NSColor *)borderColor:(BOOL)isKeyWindow
{
    if (isKeyWindow) {
        return [NSColor colorNamed:@"MojaveTabBorderActive" bundle:[PSMTabBarControl bundle]];
    } else {
        return [NSColor colorNamed:@"MojaveTabBorderInactive" bundle:[PSMTabBarControl bundle]];
    }
}

#pragma mark -
#pragma mark Cell Specific

- (NSRect) closeButtonRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([cell hasCloseButton] == NO) {
        return NSZeroRect;
    }

    NSRect result;
    result.size = [closeButton size];
    result.origin.x = cellFrame.origin.x + MARGIN_X;
    result.origin.y = (cellFrame.size.height - result.size.height) / 2;

    return result;
}

- (NSRect)iconRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([cell hasIcon] == NO) {
        return NSZeroRect;
    }

    NSRect result;
    result.size = NSMakeSize(kPSMTabBarIconWidth, kPSMTabBarIconWidth);
    result.origin.x = cellFrame.origin.x + MARGIN_X;
    result.origin.y = cellFrame.origin.y + MARGIN_Y;

    if([cell hasCloseButton] && ![cell isCloseButtonSuppressed])
        result.origin.x += [closeButton size].width + kPSMTabBarCellPadding;

    if([cell state] == NSControlStateValueOn){
        result.origin.y += 1;
    }

    return result;
}

- (NSRect)indicatorRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([[cell indicator] isHidden]) {
        return NSZeroRect;
    }

    NSRect result;
    result.size = NSMakeSize(kPSMTabBarIndicatorWidth, kPSMTabBarIndicatorWidth);
    result.origin.x = cellFrame.origin.x + cellFrame.size.width - MARGIN_X - kPSMTabBarIndicatorWidth;
    result.origin.y = cellFrame.origin.y + MARGIN_Y;

    if([cell state] == NSControlStateValueOn){
        result.origin.y -= 1;
    }

    return result;
}

- (NSRect)objectCounterRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([cell count] == 0) {
        return NSZeroRect;
    }

    float countWidth = [[self attributedObjectCountValueForTabCell:cell] size].width;
    countWidth += (2 * kPSMMetalObjectCounterRadius - 6.0);
    if(countWidth < kPSMMetalCounterMinWidth)
        countWidth = kPSMMetalCounterMinWidth;

    NSRect result;
    result.size = NSMakeSize(countWidth, 2 * kPSMMetalObjectCounterRadius); // temp
    result.origin.x = cellFrame.origin.x + cellFrame.size.width - MARGIN_X - result.size.width;
    result.origin.y = cellFrame.origin.y + MARGIN_Y + 1.0;

    if(![[cell indicator] isHidden])
        result.origin.x -= kPSMTabBarIndicatorWidth + kPSMTabBarCellPadding;

    return result;
}


- (float)minimumWidthOfTabCell:(PSMTabBarCell *)cell
{
    float resultWidth = 0.0;

    // left margin
    resultWidth = MARGIN_X;

    // close button?
    if([cell hasCloseButton] && ![cell isCloseButtonSuppressed])
        resultWidth += [closeButton size].width + kPSMTabBarCellPadding;

    // icon?
    if([cell hasIcon])
        resultWidth += kPSMTabBarIconWidth + kPSMTabBarCellPadding;

    // the label
    resultWidth += kPSMMinimumTitleWidth;

    // object counter?
    if([cell count] > 0)
        resultWidth += [self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding;

    // indicator?
    if ([[cell indicator] isHidden] == NO)
        resultWidth += kPSMTabBarCellPadding + kPSMTabBarIndicatorWidth;

    // right margin
    resultWidth += MARGIN_X;

    return ceil(resultWidth);
}

- (float)desiredWidthOfTabCell:(PSMTabBarCell *)cell
{
    float resultWidth = 0.0;

    // left margin
    resultWidth = MARGIN_X;

    // close button?
    if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed])
        resultWidth += [closeButton size].width + kPSMTabBarCellPadding;

    // icon?
    if([cell hasIcon])
        resultWidth += kPSMTabBarIconWidth + kPSMTabBarCellPadding;

    // the label
    resultWidth += [[cell attributedStringValue] size].width;

    // object counter?
    if([cell count] > 0)
        resultWidth += [self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding;

    // indicator?
    if ([[cell indicator] isHidden] == NO)
        resultWidth += kPSMTabBarCellPadding + kPSMTabBarIndicatorWidth;

    // right margin
    resultWidth += MARGIN_X;

    return ceil(resultWidth);
}

#pragma mark -
#pragma mark Cell Values

- (NSAttributedString *)attributedObjectCountValueForTabCell:(PSMTabBarCell *)cell
{
    NSMutableAttributedString *attrStr;
    NSFontManager *fm = [NSFontManager sharedFontManager];
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    [nf setLocalizesFormat:YES];
    [nf setFormat:@"0"];
    [nf setHasThousandSeparators:YES];
    NSString *contents = [nf stringFromNumber:[NSNumber numberWithInt:[cell count]]];
    attrStr = [[NSMutableAttributedString alloc] initWithString:contents];
    NSRange range = NSMakeRange(0, [contents length]);

    // Add font attribute
    [attrStr addAttribute:NSFontAttributeName value:[fm convertFont:[NSFont fontWithName:@"Helvetica" size:11.0] toHaveTrait:NSBoldFontMask] range:range];
    [attrStr addAttribute:NSForegroundColorAttributeName value:[[NSColor whiteColor] colorWithAlphaComponent:0.85] range:range];

    return attrStr;
}

- (NSAttributedString *)attributedStringValueForTabCell:(PSMTabBarCell *)cell
{
    NSMutableAttributedString *attrStr;
    NSString *contents = [cell stringValue];
    attrStr = [[NSMutableAttributedString alloc] initWithString:contents];
    NSRange range = NSMakeRange(0, [contents length]);

    // Add font attribute
    [attrStr addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:11.0] range:range];

    PSMTabBarControl *bar = (PSMTabBarControl *)cell.controlView;
    BOOL isKeyWindow = [bar.window isKeyWindow];

    CGFloat textAlpha;
    if ([cell state] == NSControlStateValueOn) {
        textAlpha = (isKeyWindow) ? 1.0f : 0.5f;
    } else {
        textAlpha = (isKeyWindow) ? 0.5f : 0.25f;
    }
    NSColor *textColor = [[NSColor textColor] colorWithAlphaComponent:textAlpha];

    [attrStr addAttribute:NSForegroundColorAttributeName value:textColor range:range];

    // Paragraph Style for Truncating Long Text
    if (!truncatingTailParagraphStyle) {
        truncatingTailParagraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        [truncatingTailParagraphStyle setLineBreakMode:NSLineBreakByTruncatingHead];
        [truncatingTailParagraphStyle setAlignment:NSTextAlignmentCenter];
    }
    [attrStr addAttribute:NSParagraphStyleAttributeName value:truncatingTailParagraphStyle range:range];

    return attrStr;
}

#pragma mark -
#pragma mark ---- drawing ----

- (void)drawTabCell:(PSMTabBarCell *)cell
{
    PSMTabBarControl *bar = (PSMTabBarControl *)cell.controlView;
    BOOL isKeyWindow = [bar.window isKeyWindow];

    NSRect cellFrame = [cell frame];
    NSColor * lineColor = nil;
    NSBezierPath* bezier = [NSBezierPath bezierPath];
    lineColor = [self borderColor:isKeyWindow];

    if ([cell state] == NSControlStateValueOn) {
        // selected tab
        NSRect aRect = NSMakeRect(cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);

        // background
        MojaveNSDrawWindowBackground(aRect, [self backgroundColor:cell isKeyWindow:isKeyWindow isSelected:YES]);

        aRect.size.height -= 1.0f;
        aRect.origin.y += 0.5f;
        // frame
        [lineColor set];
        [bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y+aRect.size.height)];
        [bezier lineToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y)];
        [bezier lineToPoint:NSMakePoint(aRect.origin.x+aRect.size.width, aRect.origin.y)];
        [bezier lineToPoint:NSMakePoint(aRect.origin.x+aRect.size.width, aRect.origin.y+aRect.size.height)];
        [bezier stroke];
    } else {

        // unselected tab
        NSRect aRect = NSMakeRect(cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);

        aRect.origin.x += 0.5;

        // background
        MojaveNSDrawWindowBackground(aRect, [self backgroundColor:cell isKeyWindow:isKeyWindow isSelected:NO]);

        // frame
        [lineColor set];
        [bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y)];
        [bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y)];
        if(!([cell tabState] & PSMTab_RightIsSelectedMask)){
            [bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y + aRect.size.height)];
        }
        [bezier stroke];
    }

    [self drawInteriorWithTabCell:cell inView:[cell controlView]];
}

- (NSImage *)createCloseButtonImage:(CGFloat)size color:(NSColor *)color backgroundColor:(NSColor *)backgroundColor
{
    NSImage *result = [NSImage imageWithSize:NSMakeSize(size,size) flipped:YES drawingHandler:^BOOL(NSRect dstRect) {
        if (backgroundColor) {
            NSBezierPath *bezier = [NSBezierPath bezierPathWithRoundedRect:dstRect
                                                                   xRadius:2.0
                                                                   yRadius:2.0];
            [backgroundColor set];
            [bezier fill];
        }

        NSBezierPath *bezier = NSBezierPath.bezierPath;

        [color set];
        [bezier moveToPoint:NSMakePoint(NSMinX(dstRect)+4.5, NSMinY(dstRect)+4.5)];
        [bezier lineToPoint:NSMakePoint(NSMaxX(dstRect)-4.5, NSMaxY(dstRect)-4.5)];
        [bezier moveToPoint:NSMakePoint(NSMaxX(dstRect)-4.5, NSMinY(dstRect)+4.5)];
        [bezier lineToPoint:NSMakePoint(NSMinX(dstRect)+4.5, NSMaxY(dstRect)-4.5)];
        [bezier stroke];
        
        return YES;
    }];
    
    return result;
}

- (void)drawInteriorWithTabCell:(PSMTabBarCell *)cell inView:(NSView*)controlView
{
    NSRect cellFrame = [cell frame];
    float labelPosition = cellFrame.origin.x + MARGIN_X;

    // close button
    if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed]) {
        NSSize closeButtonSize = NSZeroSize;
        NSRect closeButtonRect = [cell closeButtonRectForFrame:cellFrame];
        NSImage *button = nil;

        if ([cell isHighlighted]) {
            button = closeButton;
        }
        if ([cell closeButtonOver]) {
            NSAppearanceName appearanceName = [controlView.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameDarkAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]];
            
            if ([appearanceName isEqualToString:NSAppearanceNameDarkAqua] || [appearanceName isEqualToString:NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
                button = closeButtonOverDark;
            } else {
                button = closeButtonOver;
            }
        }
        if ([cell closeButtonPressed]) button = closeButtonDown;

        closeButtonSize = [button size];
        [button drawInRect:closeButtonRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    }

    // object counter
    if([cell count] > 0){
        [[NSColor colorWithCalibratedWhite:0.3 alpha:0.6] set];
        NSBezierPath *path = [NSBezierPath bezierPath];
        NSRect myRect = [self objectCounterRectForTabCell:cell];
        [path moveToPoint:NSMakePoint(myRect.origin.x + kPSMMetalObjectCounterRadius, myRect.origin.y)];
        [path lineToPoint:NSMakePoint(myRect.origin.x + myRect.size.width - kPSMMetalObjectCounterRadius, myRect.origin.y)];
        [path appendBezierPathWithArcWithCenter:NSMakePoint(myRect.origin.x + myRect.size.width - kPSMMetalObjectCounterRadius, myRect.origin.y + kPSMMetalObjectCounterRadius) radius:kPSMMetalObjectCounterRadius startAngle:270.0 endAngle:90.0];
        [path lineToPoint:NSMakePoint(myRect.origin.x + kPSMMetalObjectCounterRadius, myRect.origin.y + myRect.size.height)];
        [path appendBezierPathWithArcWithCenter:NSMakePoint(myRect.origin.x + kPSMMetalObjectCounterRadius, myRect.origin.y + kPSMMetalObjectCounterRadius) radius:kPSMMetalObjectCounterRadius startAngle:90.0 endAngle:270.0];
        [path fill];

        // draw attributed string centered in area
        NSRect counterStringRect;
        NSAttributedString *counterString = [self attributedObjectCountValueForTabCell:cell];
        counterStringRect.size = [counterString size];
        counterStringRect.origin.x = myRect.origin.x + ((myRect.size.width - counterStringRect.size.width) / 2.0) + 0.25;
        counterStringRect.origin.y = myRect.origin.y + ((myRect.size.height - counterStringRect.size.height) / 2.0) + 0.5;
        [counterString drawInRect:counterStringRect];
    }

    // label rect
    NSRect labelRect;
    labelRect.origin.x = labelPosition;
    labelRect.size.width = cellFrame.size.width - (labelRect.origin.x - cellFrame.origin.x) - kPSMTabBarCellPadding;
    labelRect.size.height = cellFrame.size.height;
    labelRect.origin.y = cellFrame.origin.y + MARGIN_Y + 1.0;

    if(![[cell indicator] isHidden])
        labelRect.size.width -= (kPSMTabBarIndicatorWidth + kPSMTabBarCellPadding);

    if([cell count] > 0)
        labelRect.size.width -= ([self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding);

    // label
    [[cell attributedStringValue] drawInRect:labelRect];
}

- (void)drawTabBar:(PSMTabBarControl *)bar inRect:(NSRect)rect
{
    BOOL isKeyWindow = [bar.window isKeyWindow];
    MojaveNSDrawWindowBackground(rect, [self backgroundColor:nil isKeyWindow:isKeyWindow isSelected:NO]);

    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.0] set];
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceAtop);
    [[self borderColor:isKeyWindow] set];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x,rect.origin.y+0.5) toPoint:NSMakePoint(rect.origin.x+rect.size.width,rect.origin.y+0.5)];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x,rect.origin.y+rect.size.height-0.5) toPoint:NSMakePoint(rect.origin.x+rect.size.width,rect.origin.y+rect.size.height-0.5)];

    // no tab view == not connected
    if(![bar tabView]){
        NSRect labelRect = rect;
        labelRect.size.height -= 4.0;
        labelRect.origin.y += 4.0;
        NSMutableAttributedString *attrStr;
        NSString *contents = @"PSMTabBarControl";
        attrStr = [[NSMutableAttributedString alloc] initWithString:contents];
        NSRange range = NSMakeRange(0, [contents length]);
        [attrStr addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:11.0] range:range];
        if (!centeredParagraphStyle) {
            centeredParagraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
            [centeredParagraphStyle setAlignment:NSTextAlignmentCenter];
        }
        [attrStr addAttribute:NSParagraphStyleAttributeName value:centeredParagraphStyle range:range];
        [attrStr drawInRect:labelRect];
        return;
    }

    // draw cells
    NSEnumerator *e = [[bar cells] objectEnumerator];
    PSMTabBarCell *cell;
    while(cell = [e nextObject]){
        if(![cell isInOverflowMenu]){
            [cell drawWithFrame:[cell frame] inView:bar];
        }
    }
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:closeButton forKey:@"metalCloseButton"];
        [aCoder encodeObject:closeButtonDown forKey:@"metalCloseButtonDown"];
        [aCoder encodeObject:closeButtonOver forKey:@"metalCloseButtonOver"];
        [aCoder encodeObject:closeButtonOverDark forKey:@"metalCloseButtonOverDark"];
        [aCoder encodeObject:_addTabButtonImage forKey:@"addTabButtonImage"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ([aDecoder allowsKeyedCoding]) {
        closeButton = [aDecoder decodeObjectForKey:@"metalCloseButton"];
        closeButtonDown = [aDecoder decodeObjectForKey:@"metalCloseButtonDown"];
        closeButtonOver = [aDecoder decodeObjectForKey:@"metalCloseButtonOver"];
        closeButtonOverDark = [aDecoder decodeObjectForKey:@"metalCloseButtonOverDark"];
        _addTabButtonImage = [aDecoder decodeObjectForKey:@"addTabButtonImage"];
    }

    return self;
}

@end

#endif
