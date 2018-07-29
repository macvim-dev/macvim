/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * MMCoreTextView
 *
 * Dispatches keyboard and mouse input to the backend.  Handles drag-n-drop of
 * files onto window.  The rendering is done using CoreText.
 *
 * The text view area consists of two parts:
 *   1. The text area - this is where text is rendered; the size is governed by
 *      the current number of rows and columns.
 *   2. The inset area - this is a border around the text area; the size is
 *      governed by the user defaults MMTextInset[Left|Right|Top|Bottom].
 *
 * The current size of the text view frame does not always match the desired
 * area, i.e. the area determined by the number of rows, columns plus text
 * inset.  This distinction is particularly important when the view is being
 * resized.
 */

#import "Miscellaneous.h"
#import "MMAppController.h"
#import "MMCoreTextView.h"
#import "MMTextViewHelper.h"
#import "MMVimController.h"
#import "MMWindowController.h"


// TODO: What does DRAW_TRANSP flag do?  If the background isn't drawn when
// this flag is set, then sometimes the character after the cursor becomes
// blank.  Everything seems to work fine by just ignoring this flag.
#define DRAW_TRANSP               0x01    /* draw with transparent bg */
#define DRAW_BOLD                 0x02    /* draw bold text */
#define DRAW_UNDERL               0x04    /* draw underline text */
#define DRAW_UNDERC               0x08    /* draw undercurl text */
#define DRAW_ITALIC               0x10    /* draw italic text */
#define DRAW_CURSOR               0x20
#define DRAW_WIDE                 0x80    /* draw wide text */
#define DRAW_COMP                 0x100   /* drawing composing char */

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_8
#define kCTFontOrientationDefault kCTFontDefaultOrientation
#endif // MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_8

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);
#define fontSmoothingStyleLight (2 << 3)

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
    static void
CTFontDrawGlyphs(CTFontRef fontRef, const CGGlyph glyphs[],
                 const CGPoint positions[], UniCharCount count,
                 CGContextRef context)
{
    CGFontRef cgFontRef = CTFontCopyGraphicsFont(fontRef, NULL);
    CGContextSetFont(context, cgFontRef);
    CGContextShowGlyphsAtPositions(context, glyphs, positions, count);
    CGFontRelease(cgFontRef);
}
#endif // MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7

@interface MMCoreTextView (Private)
- (MMWindowController *)windowController;
- (MMVimController *)vimController;
@end


@interface MMCoreTextView (Drawing)
- (NSPoint)pointForRow:(int)row column:(int)column;
- (NSRect)rectFromRow:(int)row1 column:(int)col1
                toRow:(int)row2 column:(int)col2;
- (NSSize)textAreaSize;
- (void)batchDrawData:(NSData *)data;
- (void)drawString:(const UniChar *)chars length:(UniCharCount)length
             atRow:(int)row column:(int)col cells:(int)cells
         withFlags:(int)flags foregroundColor:(int)fg
   backgroundColor:(int)bg specialColor:(int)sp;
- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(int)color;
- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(int)color;
- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(int)color;
- (void)clearAll;
- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                       fraction:(int)percent color:(int)color;
- (void)drawInvertedRectAtRow:(int)row column:(int)col numRows:(int)nrows
                   numColumns:(int)ncols;
@end



    static float
defaultLineHeightForFont(NSFont *font)
{
    // HACK: -[NSFont defaultLineHeightForFont] is deprecated but since the
    // CoreText renderer does not use NSLayoutManager we create one
    // temporarily.
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    float height = [lm defaultLineHeightForFont:font];
    [lm release];

    return height;
}

    static double
defaultAdvanceForFont(NSFont *font)
{
    // NOTE: Previously we used CTFontGetAdvancesForGlyphs() to get the advance
    // for 'm' but this sometimes returned advances that were too small making
    // the font spacing look too tight.
    // Instead use the same method to query the width of 'm' as MMTextStorage
    // uses to make things consistent across renderers.

    NSDictionary *a = [NSDictionary dictionaryWithObject:font
                                                  forKey:NSFontAttributeName];
    return [@"m" sizeWithAttributes:a].width;
}

@implementation MMCoreTextView

- (id)initWithFrame:(NSRect)frame
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    cgLayerEnabled = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMUseCGLayerAlwaysKey];
    cgLayerLock = [NSLock new];

    // NOTE!  It does not matter which font is set here, Vim will set its
    // own font on startup anyway.  Just set some bogus values.
    font = [[NSFont userFixedPitchFontOfSize:0] retain];
    cellSize.width = cellSize.height = 1;

    // NOTE: If the default changes to 'NO' then the intialization of
    // p_antialias in option.c must change as well.
    antialias = YES;

    drawData = [[NSMutableArray alloc] init];
    fontCache = [[NSMutableArray alloc] init];

    helper = [[MMTextViewHelper alloc] init];
    [helper setTextView:self];

    [self registerForDraggedTypes:[NSArray arrayWithObjects:
            NSFilenamesPboardType, NSStringPboardType, nil]];

    ligatures = NO;
    return self;
}

- (void)dealloc
{
    [font release];  font = nil;
    [fontWide release];  fontWide = nil;
    [defaultBackgroundColor release];  defaultBackgroundColor = nil;
    [defaultForegroundColor release];  defaultForegroundColor = nil;
    [drawData release];  drawData = nil;
    [fontCache release];  fontCache = nil;

    [helper setTextView:nil];
    [helper release];  helper = nil;

    if (glyphs) { free(glyphs); glyphs = NULL; }
    if (positions) { free(positions); positions = NULL; }

    [super dealloc];
}

- (int)maxRows
{
    return maxRows;
}

- (int)maxColumns
{
    return maxColumns;
}

- (void)getMaxRows:(int*)rows columns:(int*)cols
{
    if (rows) *rows = maxRows;
    if (cols) *cols = maxColumns;
}

- (void)setMaxRows:(int)rows columns:(int)cols
{
    // NOTE: Just remember the new values, the actual resizing is done lazily.
    maxRows = rows;
    maxColumns = cols;
}

- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor
{
    if (defaultBackgroundColor != bgColor) {
        [defaultBackgroundColor release];
        defaultBackgroundColor = bgColor ? [bgColor retain] : nil;
    }

    // NOTE: The default foreground color isn't actually used for anything, but
    // other class instances might want to be able to access it so it is stored
    // here.
    if (defaultForegroundColor != fgColor) {
        [defaultForegroundColor release];
        defaultForegroundColor = fgColor ? [fgColor retain] : nil;
    }
}

- (NSColor *)defaultBackgroundColor
{
    return defaultBackgroundColor;
}

- (NSColor *)defaultForegroundColor
{
    return defaultForegroundColor;
}

- (void)setTextContainerInset:(NSSize)size
{
    insetSize = size;
}

- (NSRect)rectForRowsInRange:(NSRange)range
{
    // Compute rect whose vertical dimensions cover the rows in the given
    // range.
    // NOTE: The rect should be in _flipped_ coordinates and the first row must
    // include the top inset as well.  (This method is only used to place the
    // scrollbars inside MMVimView.)

    NSRect rect = { {0, 0}, {0, 0} };
    unsigned start = range.location > maxRows ? maxRows : range.location;
    unsigned length = range.length;

    if (start + length > maxRows)
        length = maxRows - start;

    if (start > 0) {
        rect.origin.y = cellSize.height * start + insetSize.height;
        rect.size.height = cellSize.height * length;
    } else {
        // Include top inset
        rect.origin.y = 0;
        rect.size.height = cellSize.height * length + insetSize.height;
    }

    return rect;
}

- (NSRect)rectForColumnsInRange:(NSRange)range
{
    // Compute rect whose horizontal dimensions cover the columns in the given
    // range.
    // NOTE: The first column must include the left inset.  (This method is
    // only used to place the scrollbars inside MMVimView.)

    NSRect rect = { {0, 0}, {0, 0} };
    unsigned start = range.location > maxColumns ? maxColumns : range.location;
    unsigned length = range.length;

    if (start+length > maxColumns)
        length = maxColumns - start;

    if (start > 0) {
        rect.origin.x = cellSize.width * start + insetSize.width;
        rect.size.width = cellSize.width * length;
    } else {
        // Include left inset
        rect.origin.x = 0;
        rect.size.width = cellSize.width * length + insetSize.width;
    }

    return rect;
}


- (void)setFont:(NSFont *)newFont
{
    if (!(newFont && font != newFont))
        return;

    double em = round(defaultAdvanceForFont(newFont));
    double pt = round([newFont pointSize]);

    CTFontDescriptorRef desc = CTFontDescriptorCreateWithNameAndSize((CFStringRef)[newFont fontName], pt);
    CTFontRef fontRef = CTFontCreateWithFontDescriptor(desc, pt, NULL);
    CFRelease(desc);

    [font release];
    font = (NSFont*)fontRef;

    float cellWidthMultiplier = [[NSUserDefaults standardUserDefaults]
            floatForKey:MMCellWidthMultiplierKey];

    // NOTE! Even though NSFontFixedAdvanceAttribute is a float, it will
    // only render at integer sizes.  Hence, we restrict the cell width to
    // an integer here, otherwise the window width and the actual text
    // width will not match.
    cellSize.width = columnspace + ceil(em * cellWidthMultiplier);
    cellSize.height = linespace + defaultLineHeightForFont(font);

    fontDescent = ceil(CTFontGetDescent(fontRef));

    [fontCache removeAllObjects];
}

- (void)setWideFont:(NSFont *)newFont
{
    if (!newFont) {
        // Use the normal font as the wide font (note that the normal font may
        // very well include wide characters.)
        if (font) [self setWideFont:font];
    } else if (newFont != fontWide) {
        // NOTE: No need to set point size etc. since this is taken from the
        // regular font when drawing.
        [fontWide release];

        // Use 'Apple Color Emoji' font for rendering emoji
        CGFloat size = [font pointSize];
        NSFontDescriptor *emojiDesc = [NSFontDescriptor
            fontDescriptorWithName:@"Apple Color Emoji" size:size];
        NSFontDescriptor *newFontDesc = [newFont fontDescriptor];
        NSDictionary *attrs = [NSDictionary
            dictionaryWithObject:[NSArray arrayWithObject:newFontDesc]
                          forKey:NSFontCascadeListAttribute];
        NSFontDescriptor *desc =
            [emojiDesc fontDescriptorByAddingAttributes:attrs];
        fontWide = [[NSFont fontWithDescriptor:desc size:size] retain];
    }
}

- (NSFont *)font
{
    return font;
}

- (NSFont *)fontWide
{
    return fontWide;
}

- (NSSize)cellSize
{
    return cellSize;
}

- (void)setLinespace:(float)newLinespace
{
    linespace = newLinespace;

    // NOTE: The linespace is added to the cell height in order for a multiline
    // selection not to have white (background color) gaps between lines.  Also
    // this simplifies the code a lot because there is no need to check the
    // linespace when calculating the size of the text view etc.  When the
    // linespace is non-zero the baseline will be adjusted as well; check
    // MMTypesetter.
    cellSize.height = linespace + defaultLineHeightForFont(font);
}

- (void)setColumnspace:(float)newColumnspace
{
    columnspace = newColumnspace;

    double em = round(defaultAdvanceForFont(font));
    float cellWidthMultiplier = [[NSUserDefaults standardUserDefaults]
            floatForKey:MMCellWidthMultiplierKey];

    cellSize.width = columnspace + ceil(em * cellWidthMultiplier);
}




- (void)deleteSign:(NSString *)signName
{
    [helper deleteImage:signName];
}

- (void)setShouldDrawInsertionPoint:(BOOL)on
{
}

- (void)setPreEditRow:(int)row column:(int)col
{
    [helper setPreEditRow:row column:col];
}

- (void)setMouseShape:(int)shape
{
    [helper setMouseShape:shape];
}

- (void)setAntialias:(BOOL)state
{
    antialias = state;
}

- (void)setLigatures:(BOOL)state
{
    ligatures = state;
}

- (void)setThinStrokes:(BOOL)state
{
    thinStrokes = state;
}

- (void)setImControl:(BOOL)enable
{
    [helper setImControl:enable];
}

- (void)activateIm:(BOOL)enable
{
    [helper activateIm:enable];
}

- (void)checkImState
{
    [helper checkImState];
}

- (BOOL)_wantsKeyDownForEvent:(id)event
{
    // HACK! This is an undocumented method which is called from within
    // -[NSWindow sendEvent] (and perhaps in other places as well) when the
    // user presses e.g. Ctrl-Tab or Ctrl-Esc .  Returning YES here effectively
    // disables the Cocoa "key view loop" (which is undesirable).  It may have
    // other side-effects, but we really _do_ want to process all key down
    // events so it seems safe to always return YES.
    return YES;
}

- (void)setFrameSize:(NSSize)newSize {
    if (!drawPending && !NSEqualSizes(newSize, self.frame.size) && drawData.count == 0) {
        [NSAnimationContext beginGrouping];
        drawPending = YES;
    }
    [super setFrameSize:newSize];
}

- (void)keyDown:(NSEvent *)event
{
    [helper keyDown:event];
}

- (void)insertText:(id)string
{
    [helper insertText:string];
}

- (void)doCommandBySelector:(SEL)selector
{
    [helper doCommandBySelector:selector];
}

- (BOOL)hasMarkedText
{
    return [helper hasMarkedText];
}

- (NSRange)markedRange
{
    return [helper markedRange];
}

- (NSDictionary *)markedTextAttributes
{
    return [helper markedTextAttributes];
}

- (void)setMarkedTextAttributes:(NSDictionary *)attr
{
    [helper setMarkedTextAttributes:attr];
}

- (void)setMarkedText:(id)text selectedRange:(NSRange)range
{
    [helper setMarkedText:text selectedRange:range];
}

- (void)unmarkText
{
    [helper unmarkText];
}

- (void)scrollWheel:(NSEvent *)event
{
    [helper scrollWheel:event];
}

- (void)mouseDown:(NSEvent *)event
{
    [helper mouseDown:event];
}

- (void)rightMouseDown:(NSEvent *)event
{
    [helper mouseDown:event];
}

- (void)otherMouseDown:(NSEvent *)event
{
    [helper mouseDown:event];
}

- (void)mouseUp:(NSEvent *)event
{
    [helper mouseUp:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
    [helper mouseUp:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
    [helper mouseUp:event];
}

- (void)mouseDragged:(NSEvent *)event
{
    [helper mouseDragged:event];
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [helper mouseDragged:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
    [helper mouseDragged:event];
}

- (void)mouseMoved:(NSEvent *)event
{
    [helper mouseMoved:event];
}

- (void)swipeWithEvent:(NSEvent *)event
{
    [helper swipeWithEvent:event];
}

- (void)pressureChangeWithEvent:(NSEvent *)event
{
    [helper pressureChangeWithEvent:event];
}

- (NSMenu*)menuForEvent:(NSEvent *)event
{
    // HACK! Return nil to disable default popup menus (Vim provides its own).
    // Called when user Ctrl-clicks in the view (this is already handled in
    // rightMouseDown:).
    return nil;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    return [helper performDragOperation:sender];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    return [helper draggingEntered:sender];
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
    return [helper draggingUpdated:sender];
}



- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (BOOL)isOpaque
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)isFlipped
{
    return NO;
}

- (void)drawRect:(NSRect)rect
{
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context setShouldAntialias:antialias];

    if (cgLayerEnabled && drawData.count == 0) {
        // during a live resize, we will have around a stale layer until the
        // refresh messages travel back from the vim process. We push the old
        // layer in at an offset to get rid of jitter due to lines changing
        // position.
        [cgLayerLock lock];
        CGLayerRef l = [self getCGLayer];
        CGSize cgLayerSize = CGLayerGetSize(l);
        CGSize frameSize = [self frame].size;
        NSRect drawRect = NSMakeRect(
                0,
                frameSize.height - cgLayerSize.height,
                cgLayerSize.width,
                cgLayerSize.height);

        CGContextRef cgContext = [context graphicsPort];

        const NSRect *rects;
        long count;
        [self getRectsBeingDrawn:&rects count:&count];

        int i;
        for (i = 0; i < count; i++) {
           CGContextSaveGState(cgContext);
           CGContextClipToRect(cgContext, rects[i]);
           CGContextSetBlendMode(cgContext, kCGBlendModeCopy);
           CGContextDrawLayerInRect(cgContext, drawRect, l);
           CGContextRestoreGState(cgContext);
        }
        [cgLayerLock unlock];
    } else {
       id data;
       NSEnumerator *e = [drawData objectEnumerator];
       while ((data = [e nextObject]))
          [self batchDrawData:data];

       [drawData removeAllObjects];
    }
}

- (void)performBatchDrawWithData:(NSData *)data
{
    if (cgLayerEnabled && drawData.count == 0 && [self getCGContext]) {
        [cgLayerLock lock];
        [self batchDrawData:data];
        [cgLayerLock unlock];
    } else {
        [drawData addObject:data];
        [self setNeedsDisplay:YES];
    }
    if (drawPending) {
        [NSAnimationContext endGrouping];
        drawPending = NO;
    }
}

- (void)setCGLayerEnabled:(BOOL)enabled
{
    cgLayerEnabled = enabled;

    if (!cgLayerEnabled)
        [self releaseCGLayer];
}

- (void)releaseCGLayer
{
    if (cgLayer)  {
        CGLayerRelease(cgLayer);
        cgLayer = nil;
        cgLayerContext = nil;
    }
}

- (CGLayerRef)getCGLayer
{
    NSParameterAssert(cgLayerEnabled);
    if (!cgLayer && [self lockFocusIfCanDraw]) {
        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        NSRect frame = [self frame];
        cgLayer = CGLayerCreateWithContext(
            [context graphicsPort], frame.size, NULL);
        [self unlockFocus];
    }
    return cgLayer;
}

- (CGContextRef)getCGContext
{
    if (cgLayerEnabled) {
        if (!cgLayerContext)
            cgLayerContext = CGLayerGetContext([self getCGLayer]);
        return cgLayerContext;
    } else {
        return [[NSGraphicsContext currentContext] graphicsPort];
    }
}

- (void)setNeedsDisplayCGLayerInRect:(CGRect)rect
{
    if (cgLayerEnabled)
       [self setNeedsDisplayInRect:rect];
}

- (void)setNeedsDisplayCGLayer:(BOOL)flag
{
    if (cgLayerEnabled)
       [self setNeedsDisplay:flag];
}


- (NSSize)constrainRows:(int *)rows columns:(int *)cols toSize:(NSSize)size
{
    // TODO:
    // - Rounding errors may cause size change when there should be none
    // - Desired rows/columns shold not be 'too small'

    // Constrain the desired size to the given size.  Values for the minimum
    // rows and columns are taken from Vim.
    NSSize desiredSize = [self desiredSize];
    int desiredRows = maxRows;
    int desiredCols = maxColumns;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    if (size.height != desiredSize.height) {
        float fh = cellSize.height;
        float ih = insetSize.height + bot;
        if (fh < 1.0f) fh = 1.0f;

        desiredRows = floor((size.height - ih)/fh);
        desiredSize.height = fh*desiredRows + ih;
    }

    if (size.width != desiredSize.width) {
        float fw = cellSize.width;
        float iw = insetSize.width + right;
        if (fw < 1.0f) fw = 1.0f;

        desiredCols = floor((size.width - iw)/fw);
        desiredSize.width = fw*desiredCols + iw;
    }

    if (rows) *rows = desiredRows;
    if (cols) *cols = desiredCols;

    return desiredSize;
}

- (NSSize)desiredSize
{
    // Compute the size the text view should be for the entire text area and
    // inset area to be visible with the present number of rows and columns.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    return NSMakeSize(maxColumns * cellSize.width + insetSize.width + right,
                      maxRows * cellSize.height + insetSize.height + bot);
}

- (NSSize)minSize
{
    // Compute the smallest size the text view is allowed to be.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    return NSMakeSize(MMMinColumns * cellSize.width + insetSize.width + right,
                      MMMinRows * cellSize.height + insetSize.height + bot);
}

- (void)changeFont:(id)sender
{
    NSFont *newFont = [sender convertFont:font];

    if (newFont) {
        NSString *name = [newFont fontName];
        unsigned len = [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (len > 0) {
            NSMutableData *data = [NSMutableData data];
            float pointSize = [newFont pointSize];

            [data appendBytes:&pointSize length:sizeof(float)];

            ++len;  // include NUL byte
            [data appendBytes:&len length:sizeof(unsigned)];
            [data appendBytes:[name UTF8String] length:len];

            [[self vimController] sendMessage:SetFontMsgID data:data];
        }
    }
}


//
// NOTE: The menu items cut/copy/paste/undo/redo/select all/... must be bound
// to the same actions as in IB otherwise they will not work with dialogs.  All
// we do here is forward these actions to the Vim process.
//
- (IBAction)cut:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)copy:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)paste:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)undo:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)redo:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)selectAll:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column
{
    point.y = [self bounds].size.height - point.y;

    NSPoint origin = { insetSize.width, insetSize.height };

    if (!(cellSize.width > 0 && cellSize.height > 0))
        return NO;

    if (row) *row = floor((point.y-origin.y-1) / cellSize.height);
    if (column) *column = floor((point.x-origin.x-1) / cellSize.width);

    //ASLogDebug(@"point=%@ row=%d col=%d",
    //      NSStringFromPoint(point), *row, *column);

    return YES;
}

- (NSRect)rectForRow:(int)row column:(int)col numRows:(int)nr
          numColumns:(int)nc
{
    // Return the rect for the block which covers the specified rows and
    // columns.  The lower-left corner is the origin of this rect.
    // NOTE: The coordinate system is _NOT_ flipped!
    NSRect rect;
    NSRect frame = [self bounds];

    rect.origin.x = col*cellSize.width + insetSize.width;
    rect.origin.y = frame.size.height - (row+nr)*cellSize.height -
                    insetSize.height;
    rect.size.width = nc*cellSize.width;
    rect.size.height = nr*cellSize.height;

    return rect;
}

- (NSArray *)validAttributesForMarkedText
{
    return nil;
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range
{
    return nil;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
    return NSNotFound;
}

- (NSInteger)conversationIdentifier
{
    return (NSInteger)self;
}

- (NSRange)selectedRange
{
    return [helper imRange];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
{
    return [helper firstRectForCharacterRange:range];
}

@end // MMCoreTextView




@implementation MMCoreTextView (Private)

- (MMWindowController *)windowController
{
    id windowController = [[self window] windowController];
    if ([windowController isKindOfClass:[MMWindowController class]])
        return (MMWindowController*)windowController;
    return nil;
}

- (MMVimController *)vimController
{
    return [[self windowController] vimController];
}

@end // MMCoreTextView (Private)




@implementation MMCoreTextView (Drawing)

- (NSPoint)pointForRow:(int)row column:(int)col
{
    NSRect frame = [self bounds];
    return NSMakePoint(
            col*cellSize.width + insetSize.width,
            frame.size.height - (row+1)*cellSize.height - insetSize.height);
}

- (NSRect)rectFromRow:(int)row1 column:(int)col1
                toRow:(int)row2 column:(int)col2
{
    NSRect frame = [self bounds];
    return NSMakeRect(
            insetSize.width + col1*cellSize.width,
            frame.size.height - insetSize.height - (row2+1)*cellSize.height,
            (col2 + 1 - col1) * cellSize.width,
            (row2 + 1 - row1) * cellSize.height);
}

- (NSSize)textAreaSize
{
    // Calculate the (desired) size of the text area, i.e. the text view area
    // minus the inset area.
    return NSMakeSize(maxColumns * cellSize.width, maxRows * cellSize.height);
}

#define MM_DEBUG_DRAWING 0

- (void)batchDrawData:(NSData *)data
{
    const void *bytes = [data bytes];
    const void *end = bytes + [data length];

#if MM_DEBUG_DRAWING
    ASLogNotice(@"====> BEGIN");
#endif
    // TODO: Sanity check input

    while (bytes < end) {
        int type = *((int*)bytes);  bytes += sizeof(int);

        if (ClearAllDrawType == type) {
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Clear all");
#endif
            [self clearAll];
        } else if (ClearBlockDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row1 = *((int*)bytes);  bytes += sizeof(int);
            int col1 = *((int*)bytes);  bytes += sizeof(int);
            int row2 = *((int*)bytes);  bytes += sizeof(int);
            int col2 = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Clear block (%d,%d) -> (%d,%d)", row1, col1,
                    row2,col2);
#endif
            [self clearBlockFromRow:row1 column:col1
                    toRow:row2 column:col2
                    color:color];
        } else if (DeleteLinesDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Delete %d line(s) from %d", count, row);
#endif
            [self deleteLinesFromRow:row lineCount:count
                    scrollBottom:bot left:left right:right
                           color:color];
        } else if (DrawSignDrawType == type) {
            int strSize = *((int*)bytes);  bytes += sizeof(int);
            NSString *imgName =
                [NSString stringWithUTF8String:(const char*)bytes];
            bytes += strSize;

            int col = *((int*)bytes);  bytes += sizeof(int);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int width = *((int*)bytes);  bytes += sizeof(int);
            int height = *((int*)bytes);  bytes += sizeof(int);

            NSImage *signImg = [helper signImageForName:imgName];
            NSRect r = [self rectForRow:row
                                 column:col
                                numRows:height
                             numColumns:width];
            if (cgLayerEnabled) {
                CGContextRef context = [self getCGContext];
                CGImageRef cgImage = [signImg CGImageForProposedRect:&r
                                                             context:nil
                                                               hints:nil];
                CGContextDrawImage(context, r, cgImage);
            } else {
                [signImg drawInRect:r
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationSourceOver
                           fraction:1.0];
            }
            [self setNeedsDisplayCGLayerInRect:r];
        } else if (DrawStringDrawType == type) {
            int bg = *((int*)bytes);  bytes += sizeof(int);
            int fg = *((int*)bytes);  bytes += sizeof(int);
            int sp = *((int*)bytes);  bytes += sizeof(int);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int cells = *((int*)bytes);  bytes += sizeof(int);
            int flags = *((int*)bytes);  bytes += sizeof(int);
            int len = *((int*)bytes);  bytes += sizeof(int);
            UInt8 *s = (UInt8 *)bytes;  bytes += len;

#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Draw string len=%d row=%d col=%d flags=%#x",
                    len, row, col, flags);
#endif

            // Convert UTF-8 chars to UTF-16
            CFStringRef sref = CFStringCreateWithBytesNoCopy(NULL, s, len,
                                kCFStringEncodingUTF8, false, kCFAllocatorNull);
            if (sref == NULL) {
                ASLogWarn(@"Conversion error: some text may not be rendered");
                continue;
            }
            CFIndex unilength = CFStringGetLength(sref);
            const UniChar *unichars = CFStringGetCharactersPtr(sref);
            UniChar *buffer = NULL;
            if (unichars == NULL) {
                buffer = malloc(unilength * sizeof(UniChar));
                CFStringGetCharacters(sref, CFRangeMake(0, unilength), buffer);
                unichars = buffer;
            }

            [self drawString:unichars length:unilength
                       atRow:row column:col cells:cells
                              withFlags:flags
                        foregroundColor:fg
                        backgroundColor:bg
                           specialColor:sp];

            if (buffer) {
                free(buffer);
                buffer = NULL;
            }
            CFRelease(sref);
        } else if (InsertLinesDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Insert %d line(s) at row %d", count, row);
#endif
            [self insertLinesAtRow:row lineCount:count
                             scrollBottom:bot left:left right:right
                                    color:color];
        } else if (DrawCursorDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int shape = *((int*)bytes);  bytes += sizeof(int);
            int percent = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Draw cursor at (%d,%d)", row, col);
#endif
            [self drawInsertionPointAtRow:row column:col shape:shape
                                     fraction:percent
                                        color:color];
        } else if (DrawInvertedRectDrawType == type) {
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int nr = *((int*)bytes);  bytes += sizeof(int);
            int nc = *((int*)bytes);  bytes += sizeof(int);
            /*int invert = *((int*)bytes);*/  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Draw inverted rect: row=%d col=%d nrows=%d "
                   "ncols=%d", row, col, nr, nc);
#endif
            [self drawInvertedRectAtRow:row column:col numRows:nr
                             numColumns:nc];
        } else if (SetCursorPosDrawType == type) {
            // TODO: This is used for Voice Over support in MMTextView,
            // MMCoreTextView currently does not support Voice Over.
#if MM_DEBUG_DRAWING
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            ASLogNotice(@"   Set cursor row=%d col=%d", row, col);
#else
            /*cursorRow = *((int*)bytes);*/  bytes += sizeof(int);
            /*cursorCol = *((int*)bytes);*/  bytes += sizeof(int);
#endif
        } else {
            ASLogWarn(@"Unknown draw type (type=%d)", type);
        }
    }

#if MM_DEBUG_DRAWING
    ASLogNotice(@"<==== END");
#endif
}

    static CTFontRef
lookupFont(NSMutableArray *fontCache, const unichar *chars, UniCharCount count,
           CTFontRef currFontRef)
{
    CGGlyph glyphs[count];

    // See if font in cache can draw at least one character
    NSUInteger i;
    for (i = 0; i < [fontCache count]; ++i) {
        NSFont *font = [fontCache objectAtIndex:i];

        if (CTFontGetGlyphsForCharacters((CTFontRef)font, chars, glyphs, count))
            return (CTFontRef)[font retain];
    }

    // Ask Core Text for a font (can be *very* slow, which is why we cache
    // fonts in the first place)
    CFRange r = { 0, count };
    CFStringRef strRef = CFStringCreateWithCharacters(NULL, chars, count);
    CTFontRef newFontRef = CTFontCreateForString(currFontRef, strRef, r);
    CFRelease(strRef);

    // Verify the font can actually convert all the glyphs.
    if (!CTFontGetGlyphsForCharacters(newFontRef, chars, glyphs, count))
        return nil;

    if (newFontRef)
        [fontCache addObject:(NSFont *)newFontRef];

    return newFontRef;
}

    static CFAttributedStringRef
attributedStringForString(NSString *string, const CTFontRef font,
                          BOOL useLigatures)
{
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                            (id)font, kCTFontAttributeName,
                            // 2 - full ligatures including rare
                            // 1 - basic ligatures
                            // 0 - no ligatures
                            [NSNumber numberWithBool:useLigatures],
                            kCTLigatureAttributeName,
                            nil
    ];

    return CFAttributedStringCreate(NULL, (CFStringRef)string,
                                    (CFDictionaryRef)attrs);
}

    static UniCharCount
fetchGlyphsAndAdvances(const CTLineRef line, CGGlyph *glyphs, CGSize *advances,
                       CGPoint *positions, UniCharCount length)
{
    NSArray *glyphRuns = (NSArray*)CTLineGetGlyphRuns(line);

    // get a hold on the actual character widths and glyphs in line
    UniCharCount offset = 0;
    for (id item in glyphRuns) {
        CTRunRef run  = (CTRunRef)item;
        CFIndex count = CTRunGetGlyphCount(run);

        if (count > 0) {
            if (count > length - offset)
                count = length - offset;

            CFRange range = CFRangeMake(0, count);

            if (glyphs != NULL)
                CTRunGetGlyphs(run, range, &glyphs[offset]);
            if (advances != NULL)
                CTRunGetAdvances(run, range, &advances[offset]);
            if (positions != NULL)
                CTRunGetPositions(run, range, &positions[offset]);

            offset += count;
            if (offset >= length)
                break;
        }
    }

    return offset;
}

    static UniCharCount
gatherGlyphs(CGGlyph glyphs[], UniCharCount count)
{
    // Gather scattered glyphs that was happended by Surrogate pair chars
    UniCharCount glyphCount = 0;
    NSUInteger pos = 0;
    NSUInteger i;
    for (i = 0; i < count; ++i) {
        if (glyphs[i] != 0) {
            ++glyphCount;
            glyphs[pos++] = glyphs[i];
        }
    }
    return glyphCount;
}

    static UniCharCount
composeGlyphsForChars(const unichar *chars, CGGlyph *glyphs,
                      CGPoint *positions, UniCharCount length, CTFontRef font,
                      BOOL isComposing, BOOL useLigatures)
{
    memset(glyphs, 0, sizeof(CGGlyph) * length);

    NSString *plainText = [NSString stringWithCharacters:chars length:length];
    CFAttributedStringRef composedText = attributedStringForString(plainText,
                                                                   font,
                                                                   useLigatures);

    CTLineRef line = CTLineCreateWithAttributedString(composedText);

    // get the (composing)glyphs and advances for the new text
    UniCharCount offset = fetchGlyphsAndAdvances(line, glyphs, NULL,
                                                 isComposing ? positions : NULL,
                                                 length);

    CFRelease(composedText);
    CFRelease(line);

    // as ligatures composing characters it is required to adjust the
    // original length value
    return offset;
}

    static void
recurseDraw(const unichar *chars, CGGlyph *glyphs, CGPoint *positions,
            UniCharCount length, CGContextRef context, CTFontRef fontRef,
            NSMutableArray *fontCache, BOOL isComposing, BOOL useLigatures)
{
    if (CTFontGetGlyphsForCharacters(fontRef, chars, glyphs, length)) {
        // All chars were mapped to glyphs, so draw all at once and return.
        length = isComposing || useLigatures
                ? composeGlyphsForChars(chars, glyphs, positions, length,
                                        fontRef, isComposing, useLigatures)
                : gatherGlyphs(glyphs, length);
        CTFontDrawGlyphs(fontRef, glyphs, positions, length, context);
        return;
    }

    CGGlyph *glyphsEnd = glyphs+length, *g = glyphs;
    CGPoint *p = positions;
    const unichar *c = chars;
    while (glyphs < glyphsEnd) {
        if (*g) {
            // Draw as many consecutive glyphs as possible in the current font
            // (if a glyph is 0 that means it does not exist in the current
            // font).
            BOOL surrogatePair = NO;
            while (*g && g < glyphsEnd) {
                if (CFStringIsSurrogateHighCharacter(*c)) {
                    surrogatePair = YES;
                    g += 2;
                    c += 2;
                } else {
                    ++g;
                    ++c;
                }
                ++p;
            }

            int count = g-glyphs;
            if (surrogatePair)
                count = gatherGlyphs(glyphs, count);
            CTFontDrawGlyphs(fontRef, glyphs, positions, count, context);
        } else {
            // Skip past as many consecutive chars as possible which cannot be
            // drawn in the current font.
            while (0 == *g && g < glyphsEnd) {
                if (CFStringIsSurrogateHighCharacter(*c)) {
                    g += 2;
                    c += 2;
                } else {
                    ++g;
                    ++c;
                }
                ++p;
            }

            // Try to find a fallback font that can render the entire
            // invalid range. If that fails, repeatedly halve the attempted
            // range until a font is found.
            UniCharCount count = c - chars;
            UniCharCount attemptedCount = count;
            CTFontRef fallback = nil;
            while (fallback == nil && attemptedCount > 0) {
                fallback = lookupFont(fontCache, chars, attemptedCount,
                                      fontRef);
                if (!fallback)
                    attemptedCount /= 2;
            }

            if (!fallback)
                return;

            recurseDraw(chars, glyphs, positions, attemptedCount, context,
                        fallback, fontCache, isComposing, useLigatures);

            // If only a portion of the invalid range was rendered above,
            // the remaining range needs to be attempted by subsequent
            // iterations of the draw loop.
            c -= count - attemptedCount;
            g -= count - attemptedCount;
            p -= count - attemptedCount;

            CFRelease(fallback);
        }

        if (glyphs == g) {
           // No valid chars in the glyphs. Exit from the possible infinite
           // recursive call.
           break;
        }

        chars = c;
        glyphs = g;
        positions = p;
    }
}

- (void)drawString:(const UniChar *)chars length:(UniCharCount)length
             atRow:(int)row column:(int)col cells:(int)cells
         withFlags:(int)flags foregroundColor:(int)fg
   backgroundColor:(int)bg specialColor:(int)sp
{
    CGContextRef context = [self getCGContext];
    NSRect frame = [self bounds];
    float x = col*cellSize.width + insetSize.width;
    float y = frame.size.height - insetSize.height - (1+row)*cellSize.height;
    float w = cellSize.width;
    BOOL wide = flags & DRAW_WIDE ? YES : NO;
    BOOL composing = flags & DRAW_COMP ? YES : NO;

    if (wide) {
        // NOTE: It is assumed that either all characters in 'chars' are wide
        // or all are normal width.
        w *= 2;
    }

    CGContextSaveGState(context);

    int originalFontSmoothingStyle = 0;
    if (thinStrokes) {
        CGContextSetShouldSmoothFonts(context, YES);
        originalFontSmoothingStyle = CGContextGetFontSmoothingStyle(context);
        CGContextSetFontSmoothingStyle(context, fontSmoothingStyleLight);
    }

    // NOTE!  'cells' is zero if we're drawing a composing character
    CGFloat clipWidth = cells > 0 ? cells*cellSize.width : w;
    CGRect clipRect = { {x, y}, {clipWidth, cellSize.height} };
    CGContextClipToRect(context, clipRect);

    if (!(flags & DRAW_TRANSP)) {
        // Draw the background of the text.  Note that if we ignore the
        // DRAW_TRANSP flag and always draw the background, then the insert
        // mode cursor is drawn over.
        CGRect rect = { {x, y}, {cells*cellSize.width, cellSize.height} };
        CGContextSetRGBFillColor(context, RED(bg), GREEN(bg), BLUE(bg),
                                 ALPHA(bg));

        // Antialiasing may cause bleeding effects which are highly undesirable
        // when clearing the background (this code is also called to draw the
        // cursor sometimes) so disable it temporarily.
        CGContextSetShouldAntialias(context, NO);
        CGContextSetBlendMode(context, kCGBlendModeCopy);
        CGContextFillRect(context, rect);
        CGContextSetShouldAntialias(context, antialias);
        CGContextSetBlendMode(context, kCGBlendModeNormal);
    }

    if (flags & DRAW_UNDERL) {
        // Draw underline
        CGRect rect = { {x, y+0.4*fontDescent}, {cells*cellSize.width, 1} };
        CGContextSetRGBFillColor(context, RED(sp), GREEN(sp), BLUE(sp),
                                 ALPHA(sp));
        CGContextFillRect(context, rect);
    } else if (flags & DRAW_UNDERC) {
        // Draw curly underline
        int k;
        float x0 = x, y0 = y+1, w = cellSize.width, h = 0.5*fontDescent;

        CGContextMoveToPoint(context, x0, y0);
        for (k = 0; k < cells; ++k) {
            CGContextAddCurveToPoint(context, x0+0.25*w, y0, x0+0.25*w, y0+h,
                                     x0+0.5*w, y0+h);
            CGContextAddCurveToPoint(context, x0+0.75*w, y0+h, x0+0.75*w, y0,
                                     x0+w, y0);
            x0 += w;
        }

        CGContextSetRGBStrokeColor(context, RED(sp), GREEN(sp), BLUE(sp),
                                   ALPHA(sp));
        CGContextStrokePath(context);
    }

    if (length > maxlen) {
        if (glyphs) free(glyphs);
        if (positions) free(positions);
        glyphs = (CGGlyph*)calloc(length, sizeof(CGGlyph));
        positions = (CGPoint*)calloc(length, sizeof(CGPoint));
        maxlen = length;
    }

    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextDrawingMode(context, kCGTextFill);
    CGContextSetRGBFillColor(context, RED(fg), GREEN(fg), BLUE(fg), ALPHA(fg));
    CGContextSetFontSize(context, [font pointSize]);

    // Calculate position of each glyph relative to (x,y).
    float xrel = composing ? .0 : w;
    for (unsigned i = 0; i < length; ++i) {
        positions[i].x = i * xrel;
        positions[i].y = .0;
    }

    CTFontRef fontRef = (CTFontRef)(wide ? [fontWide retain]
                                         : [font retain]);
    unsigned traits = 0;
    if (flags & DRAW_ITALIC)
        traits |= kCTFontItalicTrait;
    if (flags & DRAW_BOLD)
        traits |= kCTFontBoldTrait;

    if (traits) {
        CTFontRef fr = CTFontCreateCopyWithSymbolicTraits(fontRef, 0.0, NULL,
                                                          traits, traits);
        if (fr) {
            CFRelease(fontRef);
            fontRef = fr;
        }
    }

    CGContextSetTextPosition(context, x, y+fontDescent);
    recurseDraw(chars, glyphs, positions, length, context, fontRef, fontCache,
                composing, ligatures);

    CFRelease(fontRef);
    if (thinStrokes)
        CGContextSetFontSmoothingStyle(context, originalFontSmoothingStyle);
    CGContextRestoreGState(context);

    [self setNeedsDisplayCGLayerInRect:clipRect];
}

- (void)scrollRect:(NSRect)rect lineCount:(int)count
{
    if (cgLayerEnabled) {
        CGContextRef context = [self getCGContext];
        int yOffset = count * cellSize.height;
        NSRect clipRect = rect;
        clipRect.origin.y -= yOffset;

        // draw self on top of self, offset so as to "scroll" lines vertically
        CGContextSaveGState(context);
        CGContextClipToRect(context, clipRect);
        CGContextSetBlendMode(context, kCGBlendModeCopy);
        CGContextDrawLayerAtPoint(
                context, CGPointMake(0, -yOffset), [self getCGLayer]);
        CGContextRestoreGState(context);
        [self setNeedsDisplayCGLayerInRect:clipRect];
    } else {
        NSSize delta={0, -count * cellSize.height};
        [self scrollRect:rect by:delta];
    }
}

- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(int)color
{
    NSRect rect = [self rectFromRow:row + count
                             column:left
                              toRow:bottom
                             column:right];

    // move rect up for count lines
    [self scrollRect:rect lineCount:-count];
    [self clearBlockFromRow:bottom - count + 1
                     column:left
                      toRow:bottom
                     column:right
                      color:color];
}

- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(int)color
{
    NSRect rect = [self rectFromRow:row
                             column:left
                              toRow:bottom - count
                             column:right];

    // move rect down for count lines
    [self scrollRect:rect lineCount:count];
    [self clearBlockFromRow:row
                     column:left
                      toRow:row + count - 1
                     column:right
                      color:color];
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(int)color
{
    CGContextRef context = [self getCGContext];
    NSRect rect = [self rectFromRow:row1 column:col1 toRow:row2 column:col2];

    CGContextSetRGBFillColor(context, RED(color), GREEN(color), BLUE(color),
                             ALPHA(color));

    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextFillRect(context, *(CGRect*)&rect);
    CGContextSetBlendMode(context, kCGBlendModeNormal);
    [self setNeedsDisplayCGLayerInRect:rect];
}

- (void)clearAll
{
    [self releaseCGLayer];
    CGContextRef context = [self getCGContext];
    NSRect rect = [self bounds];
    float r = [defaultBackgroundColor redComponent];
    float g = [defaultBackgroundColor greenComponent];
    float b = [defaultBackgroundColor blueComponent];
    float a = [defaultBackgroundColor alphaComponent];

    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextSetRGBFillColor(context, r, g, b, a);
    CGContextFillRect(context, *(CGRect*)&rect);
    CGContextSetBlendMode(context, kCGBlendModeNormal);

    [self setNeedsDisplayCGLayer:YES];
}

- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                       fraction:(int)percent color:(int)color
{
    CGContextRef context = [self getCGContext];
    NSRect rect = [self rectForRow:row column:col numRows:1 numColumns:1];

    CGContextSaveGState(context);

    if (MMInsertionPointHorizontal == shape) {
        int frac = (cellSize.height * percent + 99)/100;
        rect.size.height = frac;
    } else if (MMInsertionPointVertical == shape) {
        int frac = (cellSize.width * percent + 99)/100;
        rect.size.width = frac;
    } else if (MMInsertionPointVerticalRight == shape) {
        int frac = (cellSize.width * percent + 99)/100;
        rect.origin.x += rect.size.width - frac;
        rect.size.width = frac;
    }

    // Temporarily disable antialiasing since we are only drawing square
    // cursors.  Failing to disable antialiasing can cause the cursor to bleed
    // over into adjacent display cells and it may look ugly.
    CGContextSetShouldAntialias(context, NO);

    if (MMInsertionPointHollow == shape) {
        // When stroking a rect its size is effectively 1 pixel wider/higher
        // than we want so make it smaller to avoid having it bleed over into
        // the adjacent display cell.
        // We also have to shift the rect by half a point otherwise it will be
        // partially drawn outside its bounds on a Retina display.
        rect.size.width -= 1;
        rect.size.height -= 1;
        rect.origin.x += 0.5;
        rect.origin.y += 0.5;

        CGContextSetRGBStrokeColor(context, RED(color), GREEN(color),
                                   BLUE(color), ALPHA(color));
        CGContextStrokeRect(context, *(CGRect*)&rect);
    } else {
        CGContextSetRGBFillColor(context, RED(color), GREEN(color), BLUE(color),
                                 ALPHA(color));
        CGContextFillRect(context, *(CGRect*)&rect);
    }

    [self setNeedsDisplayCGLayerInRect:rect];
    CGContextRestoreGState(context);
}

- (void)drawInvertedRectAtRow:(int)row column:(int)col numRows:(int)nrows
                   numColumns:(int)ncols
{
    // TODO: THIS CODE HAS NOT BEEN TESTED!
    CGContextRef cgctx = [self getCGContext];
    CGContextSaveGState(cgctx);
    CGContextSetBlendMode(cgctx, kCGBlendModeDifference);
    CGContextSetRGBFillColor(cgctx, 1.0, 1.0, 1.0, 1.0);

    NSRect rect = [self rectForRow:row column:col numRows:nrows
                        numColumns:ncols];
    CGContextFillRect(cgctx, *(CGRect*)&rect);

    [self setNeedsDisplayCGLayerInRect:rect];
    CGContextRestoreGState(cgctx);
}

@end // MMCoreTextView (Drawing)
