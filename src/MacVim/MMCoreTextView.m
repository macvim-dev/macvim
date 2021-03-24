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

#if MAC_OS_X_VERSION_MIN_REQUIRED < 101300
typedef NSString * NSAttributedStringKey;
#endif // MAC_OS_X_VERSION_MIN_REQUIRED < 101300

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
- (NSFont *)fontVariantForTextFlags:(int)textFlags;
- (CTLineRef)lineForCharacterString:(NSString *)string
                          textFlags:(int)flags;
@end


@interface MMCoreTextView (Drawing)
- (NSPoint)pointForRow:(int)row column:(int)column;
- (NSRect)rectFromRow:(int)row1 column:(int)col1
                toRow:(int)row2 column:(int)col2;
- (NSSize)textAreaSize;
- (void)batchDrawData:(NSData *)data;
- (void)setString:(NSString *)string
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
- (void)setInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                      fraction:(int)percent color:(int)color;
- (void)invertBlockFromRow:(int)row column:(int)col numRows:(int)nrows
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

typedef struct {
    unsigned color;
    int shape;
    int fraction;
} GridCellInsertionPoint;

typedef struct {
    // Note: All objects should be weak references.
    // Fields are grouped by draw order.
    BOOL inverted;

    // 1. Background
    unsigned bg;

    // 2. Sign
    NSImage* sign;

    // 3. Insertion point
    GridCellInsertionPoint insertionPoint;

    // 4. Text
    unsigned fg;
    unsigned sp;
    int textFlags;
    NSString* string; // Owned by characterStrings.
} GridCell;

typedef struct {
    GridCell *cells;
    int rows;
    int cols;
} Grid;

static GridCell* grid_cell(Grid *grid, int row, int col) {
    return grid->cells + row * grid->cols + col;
}

// Returns a static cell if row or col is out of bounds. Draw commands can point
// out of bounds if -setMaxRows:columns: is called while Vim is still drawing at
// a different size, which has been observed when exiting non-native fullscreen
// with `:set nofu`. If that gets fixed, then delete this workaround.
static GridCell* grid_cell_safe(Grid *grid, int row, int col) {
    if (row >= grid->rows || col >= grid->cols) {
        static GridCell scratch_cell = {};
        return &scratch_cell;
    }
    return grid_cell(grid, row, col);
}

static void grid_resize(Grid *grid, int rows, int cols) {
    if (rows == grid->rows && cols == grid->cols)
        return;
    if (cols == grid->cols && grid->cells != NULL) {
        // If only the number of rows is changing, resize and zero out new rows.
        size_t oldSize = grid->rows * grid->cols;
        size_t newSize = rows * cols;
        grid->cells = realloc(grid->cells, newSize * sizeof(GridCell));
        if (newSize > oldSize)
            bzero(grid->cells + oldSize, (newSize - oldSize) * sizeof(GridCell));
    } else {
        // Otherwise, allocate a new buffer.
        GridCell *oldCells = grid->cells;
        grid->cells = calloc(rows * cols, sizeof(GridCell));
        if (oldCells) {
            for (int r = 1; r < MIN(grid->rows, rows); r++)
                memcpy(grid->cells + cols * r, oldCells + grid->cols * r, MIN(grid->cols, cols) * sizeof(GridCell));
            free(oldCells);
        }
    }
    grid->rows = rows;
    grid->cols = cols;
}

static void grid_free(Grid *grid) {
    if (grid->cells == NULL)
        return;
    free(grid->cells);
    grid->cells = NULL;
}

@implementation MMCoreTextView {
    Grid grid;
}

- (id)initWithFrame:(NSRect)frame
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    forceRefreshFont = NO;
    
    self.wantsLayer = YES;
    
    // NOTE: If the default changes to 'NO' then the intialization of
    // p_antialias in option.c must change as well.
    antialias = YES;

    [self setFont:[NSFont userFixedPitchFontOfSize:0]];
    fontVariants = [[NSMutableDictionary alloc] init];
    characterStrings = [[NSMutableSet alloc] init];
    characterLines = [[NSMutableDictionary alloc] init];
    
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
    [fontVariants release];  fontVariants = nil;
    [characterStrings release];  characterStrings = nil;
    [characterLines release];  characterLines = nil;
    
    [helper setTextView:nil];
    [helper release];  helper = nil;

    grid_free(&grid);

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
    grid_resize(&grid, rows, cols);
    maxRows = rows;
    maxColumns = cols;
}

- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor
{
    if (defaultBackgroundColor != bgColor) {
        [defaultBackgroundColor release];
        defaultBackgroundColor = bgColor ? [bgColor retain] : nil;
        self.needsDisplay = YES;
    }

    // NOTE: The default foreground color isn't actually used for anything, but
    // other class instances might want to be able to access it so it is stored
    // here.
    if (defaultForegroundColor != fgColor) {
        [defaultForegroundColor release];
        defaultForegroundColor = fgColor ? [fgColor retain] : nil;
    }
    [self setNeedsDisplay:YES];
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
    if (!newFont) {
        ASLogInfo(@"Trying to set null font");
        return;
    }
    if (!forceRefreshFont) {
        if ([font isEqual:newFont])
            return;
    }
    forceRefreshFont = NO;

    const double em = round(defaultAdvanceForFont(newFont));

    const float cellWidthMultiplier = [[NSUserDefaults standardUserDefaults]
            floatForKey:MMCellWidthMultiplierKey];

    // Some fonts have non-standard line heights, and historically MacVim has
    // chosen to ignore it. Provide the option for the user to choose whether to
    // use the font's line height. If not preserving, will create a new font
    // from scratch with just name and pt size, which will disard the line
    // height information.
    //
    // Defaults to the new behavior (preserveLineHeight==true) because it's
    // simpler and respects the font's design more.
    //
    // Note: this behavior is somewhat inconsistent across editors and
    // terminals. Xcode, for example, seems to be equivalent to
    // (preserveLineHeight==true), but other editors/terminals behave
    // differently. Xcode respecting the line height is partially the motivation
    // for setting that as the default.
    const BOOL preserveLineHeight = [[NSUserDefaults standardUserDefaults]
                                     boolForKey:MMFontPreserveLineSpacingKey];

    [font release];
    if (!preserveLineHeight) {
        double pt = round([newFont pointSize]);

        CTFontDescriptorRef desc = CTFontDescriptorCreateWithNameAndSize((CFStringRef)[newFont fontName], pt);
        CTFontRef fontRef = CTFontCreateWithFontDescriptor(desc, pt, NULL);
        CFRelease(desc);
        if (!fontRef) {
            ASLogInfo(@"CTFontCreateWithFontDescriptor failed (preserveLineHeight == false, fontName: %@), pt: %f", [newFont fontName], pt);
        }
        font = (NSFont*)fontRef;
    } else {
        font = [newFont retain];
    }
    fontDescent = ceil(CTFontGetDescent((CTFontRef)font));

    // NOTE! Even though NSFontFixedAdvanceAttribute is a float, it will
    // only render at integer sizes.  Hence, we restrict the cell width to
    // an integer here, otherwise the window width and the actual text
    // width will not match.
    cellSize.width = columnspace + ceil(em * cellWidthMultiplier);
    cellSize.height = linespace + defaultLineHeightForFont(font);

    [self clearAll];
    [fontVariants removeAllObjects];
    [characterStrings removeAllObjects];
    [characterLines removeAllObjects];
}

- (void)setWideFont:(NSFont *)newFont
{
    if (!newFont) {
        // Use the normal font as the wide font (note that the normal font may
        // very well include wide characters.)
        if (font) {
            [self setWideFont:font];
            return;
        }
    } else if (newFont != fontWide) {
        [fontWide release];
        fontWide = [newFont retain];
    }

    [self clearAll];
    [fontVariants removeAllObjects];
    [characterStrings removeAllObjects];
    [characterLines removeAllObjects];
}

- (void)refreshFonts
{
    // Mark force refresh, so that we won't try to use the cached font later.
    forceRefreshFont = YES;

    // Go through the standard path of updating fonts by passing the current
    // font in. This lets Vim itself knows about the font change and initiates
    // the resizing (depends on guioption-k) and redraws.
    [self changeFont:NSFontManager.sharedFontManager];
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
    [characterLines removeAllObjects];
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
    return self.layer == nil || self.defaultBackgroundColor.alphaComponent == 1;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)isFlipped
{
    return NO;
}

- (void)setNeedsDisplayFromRow:(int)row column:(int)col toRow:(int)row2
                        column:(int)col2 {
    [self setNeedsDisplayInRect:[self rectForRow:row column:0 numRows:row2-row+1 numColumns:maxColumns]];
}

- (void)drawRect:(NSRect)rect
{
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    CGContextRef ctx = context.CGContext;
    [context setShouldAntialias:antialias];
    {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        if (colorSpace) {
            CGContextSetFillColorSpace(ctx, colorSpace);
            CGColorSpaceRelease(colorSpace);
        } else {
            ASLogInfo(@"Could not create sRGB color space");
        }
    }
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    CGContextSetFontSize(ctx, [font pointSize]);
    CGContextSetShouldSmoothFonts(ctx, YES);
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);

    int originalSmoothingStyle = 0;
    if (thinStrokes) {
        originalSmoothingStyle = CGContextGetFontSmoothingStyle(ctx);
        CGContextSetFontSmoothingStyle(ctx, fontSmoothingStyleLight);
    }
    const unsigned defaultBg = defaultBackgroundColor.argbInt;
    CGContextSetFillColor(ctx, COMPONENTS(defaultBg));

    CGContextFillRect(ctx, rect);

    for (size_t r = 0; r < grid.rows; r++) {
        CGRect rowRect = [self rectForRow:r column:0 numRows:1 numColumns:grid.cols];
        CGRect rowClipRect = CGRectIntersection(rowRect, rect);
        if (CGRectIsNull(rowClipRect))
            continue;
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, rowClipRect);
        
        __block NSMutableString *lineString = nil;
        __block CGFloat lineStringStart = 0;
        __block CFRange lineStringRange = {};
        __block GridCell lastStringCell = {};
        void (^flushLineString)() = ^{
            if (!lineString.length)
                return;
            CGPoint positionsByIndex[lineString.length];
            for (size_t i = 0, stringIndex = 0; i < lineStringRange.length; i++) {
                GridCell cell = *grid_cell(&grid, r, lineStringRange.location + i);
                size_t cell_length = cell.string.length;
                for (size_t j = 0; j < cell_length; j++)
                    positionsByIndex[stringIndex++] = CGPointMake(i * cellSize.width, 0);
                if (cell.textFlags & DRAW_WIDE)
                    i++;
            }
            CGContextSetFillColor(ctx, COMPONENTS(lastStringCell.fg));
            CGContextSetTextPosition(ctx, lineStringStart, rowRect.origin.y + fontDescent);
            CGContextSetBlendMode(ctx, kCGBlendModeNormal);

            const NSUInteger lineStringLength = lineString.length;
            CTLineRef line = [self lineForCharacterString:lineString textFlags:lastStringCell.textFlags];
            NSArray* glyphRuns = (NSArray*)CTLineGetGlyphRuns(line);
            if ([glyphRuns count] == 0) {
                ASLogDebug(@"CTLineGetGlyphRuns no glyphs for: %@", lineString);
            }
            for (id obj in glyphRuns) {
                CTRunRef run = (CTRunRef)obj;
                CFIndex glyphCount = CTRunGetGlyphCount(run);
                CFIndex indices[glyphCount];
                CGPoint positions[glyphCount];
                CGGlyph glyphs[glyphCount];
                CTRunGetStringIndices(run, CFRangeMake(0, 0), indices);
                CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphs);
                for (CFIndex i = 0; i < glyphCount; i++) {
                    if (indices[i] >= lineStringLength) {
                        ASLogDebug(@"Invalid glyph pos index: %ld, len: %lu", (long)indices[i], (unsigned long)lineStringLength);
                        continue;
                    }
                    positions[i] = positionsByIndex[indices[i]];
                }
                CTFontRef font = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
                if (!font) {
                    ASLogDebug(@"Null font for rendering. glyphCount: %ld", (long)glyphCount);
                }
                CTFontDrawGlyphs(font, glyphs, positions, glyphCount, ctx);
            }

            CGContextSetBlendMode(ctx, kCGBlendModeCopy);
            [lineString deleteCharactersInRange:NSMakeRange(0, lineString.length)];
        };
        for (size_t c = 0; c < grid.cols; c++) {
            GridCell cell = *grid_cell(&grid, r, c);
            CGRect cellRect = {{rowRect.origin.x + cellSize.width * c, rowRect.origin.y}, cellSize};
            if (cell.textFlags & DRAW_WIDE)
                cellRect.size.width *= 2;
            if (cell.inverted) {
                cell.bg ^= 0xFFFFFF;
                cell.fg ^= 0xFFFFFF;
                cell.sp ^= 0xFFFFFF;
            }
            if (cell.bg != defaultBg && ALPHA(cell.bg) > 0) {
                CGContextSetFillColor(ctx, COMPONENTS(cell.bg));
                CGContextFillRect(ctx, cellRect);
            }
            if (cell.sign) {
                CGRect signRect = cellRect;
                signRect.size.width *= 2;
                [cell.sign drawInRect:signRect
                             fromRect:(NSRect){{0, 0}, cell.sign.size}
                            operation:(cell.inverted ? NSCompositingOperationDifference : NSCompositingOperationSourceOver)
                             fraction:1.0];
            }
            if (cell.insertionPoint.color && cell.insertionPoint.fraction) {
                float frac = cell.insertionPoint.fraction / 100.0;
                NSRect rect = cellRect;
                if (MMInsertionPointHorizontal == cell.insertionPoint.shape) {
                    rect.size.height = cellSize.height * frac;
                } else if (MMInsertionPointVertical == cell.insertionPoint.shape) {
                    rect.size.width = cellSize.width * frac;
                } else if (MMInsertionPointVerticalRight == cell.insertionPoint.shape) {
                    rect.size.width = cellSize.width * frac;
                    rect.origin.x += cellRect.size.width - rect.size.width;
                }
                rect = [self backingAlignedRect:rect options:NSAlignAllEdgesInward];
                
                [[NSColor colorWithArgbInt:cell.insertionPoint.color] set];
                if (MMInsertionPointHollow == cell.insertionPoint.shape) {
                    [NSBezierPath strokeRect:NSInsetRect(rect, 0.5, 0.5)];
                } else {
                    NSRectFill(rect);
                }
            }
            if (cell.textFlags & DRAW_UNDERL) {
                CGRect rect = CGRectMake(cellRect.origin.x, cellRect.origin.y+0.4*fontDescent, cellRect.size.width, 1);
                CGContextSetFillColor(ctx, COMPONENTS(cell.sp));
                CGContextFillRect(ctx, rect);
            } else if (cell.textFlags & DRAW_UNDERC) {
                const float x = cellRect.origin.x, y = cellRect.origin.y+1, w = cellSize.width, h = 0.5*fontDescent;
                CGContextMoveToPoint(ctx, x, y);
                CGContextAddCurveToPoint(ctx, x+0.25*w, y, x+0.25*w, y+h, x+0.5*w, y+h);
                CGContextAddCurveToPoint(ctx, x+0.75*w, y+h, x+0.75*w, y, x+w, y);
                CGContextSetRGBStrokeColor(ctx, RED(cell.sp), GREEN(cell.sp), BLUE(cell.sp), ALPHA(cell.sp));
                CGContextStrokePath(ctx);
            }
            if (cell.string) {
                if (!ligatures || lastStringCell.fg != cell.fg || lastStringCell.textFlags != cell.textFlags)
                    flushLineString();
                if (!lineString)
                    lineString = [[NSMutableString alloc] init];
                if (!lineString.length) {
                    lineStringStart = cellRect.origin.x;
                    lineStringRange = CFRangeMake(c, 1);
                }
                [lineString appendString:cell.string];
                lineStringRange.length = c - lineStringRange.location + 1;
                lastStringCell = cell;
            } else {
                flushLineString();
            }
            if (cell.textFlags & DRAW_WIDE)
                c++;
        }
        flushLineString();
        [lineString release];
        CGContextRestoreGState(ctx);
    }
    if (thinStrokes) {
        CGContextSetFontSmoothingStyle(ctx, originalSmoothingStyle);
    }
}

- (void)performBatchDrawWithData:(NSData *)data
{
    [self batchDrawData:data];
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

// Called when font panel selection has been made. Send the selected font to
// MMBackend so it would set guifont which will send a message back to MacVim to
// call MMWindowController::setFont.
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

- (NSFont *)fontVariantForTextFlags:(int)textFlags {
    NSNumber *cacheFlags = @(textFlags & (DRAW_WIDE | DRAW_ITALIC | DRAW_BOLD));
    NSFont *fontRef = fontVariants[cacheFlags];
    if (!fontRef) {
        fontRef = textFlags & DRAW_WIDE ? fontWide : font;
        if (textFlags & DRAW_ITALIC)
            fontRef = [NSFontManager.sharedFontManager convertFont:fontRef toHaveTrait:NSFontItalicTrait];
        if (textFlags & DRAW_BOLD)
            fontRef = [NSFontManager.sharedFontManager convertFont:fontRef toHaveTrait:NSFontBoldTrait];

        fontVariants[cacheFlags] = fontRef;
    }
    return fontRef;
}

- (CTLineRef)lineForCharacterString:(NSString *)string
                          textFlags:(int)flags {
    int cacheFlags = flags & (DRAW_WIDE | DRAW_ITALIC | DRAW_BOLD);
    NSNumber *key = @(cacheFlags);
    NSCache<NSString *,id> *strCache = characterLines[key];
    if (!strCache){
        strCache = characterLines[key] = [[[NSCache alloc] init] autorelease];
    }
    CTLineRef line = (CTLineRef)[[strCache objectForKey:string] retain];
    if (!line) {
        NSAttributedString *attrString = [[NSAttributedString alloc]
            initWithString:string
            attributes:@{
                NSFontAttributeName: [self fontVariantForTextFlags:flags],
                NSLigatureAttributeName: @(ligatures ? 1 : 0),
                (NSString *)kCTForegroundColorFromContextAttributeName: @YES,
            }];
        line = CTLineCreateWithAttributedString((CFAttributedStringRef)attrString);
        [attrString release];
        [strCache setObject:(id)line forKey:[[string copy] autorelease]];
    }
    return (CTLineRef)[(id)line autorelease];
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

// TODO: move this to a utility class to be shared
// Reader / writer utilities to interact with the batch draw data stream.
struct DrawCmdClearAll
{
};

struct DrawCmdClearBlock
{
    unsigned color;
    int row1;
    int col1;
    int row2;
    int col2;
};

struct DrawCmdDeleteLines
{
    unsigned color;
    int row;
    int count;
    int bot;
    int left;
    int right;
};

struct DrawCmdDrawSign
{
    int strSize;
    const char *imgName;
    int col;
    int row;
    int width;
    int height;
};

struct DrawCmdDrawString
{
    int bg;
    int fg;
    int sp;
    int row;
    int col;
    int cells;
    int flags;
    int len;
    UInt8 *str;
};

struct DrawCmdInsertLines
{
    unsigned color;
    int row;
    int count;
    int bot;
    int left;
    int right;
};

struct DrawCmdDrawCursor
{
    unsigned color;
    int row;
    int col;
    int shape;
    int percent;
};

struct DrawCmdDrawInvertedRect
{
    int row;
    int col;
    int nr;
    int nc;
    int invert;
};

struct DrawCmdSetCursorPos
{
    int row;
    int col;
};

struct DrawCmd
{
    union
    {
        struct DrawCmdClearAll drawCmdClearAll;
        struct DrawCmdClearBlock drawCmdClearBlock;
        struct DrawCmdDeleteLines drawCmdDeleteLines;
        struct DrawCmdDrawSign drawCmdDrawSign;
        struct DrawCmdDrawString drawCmdDrawString;
        struct DrawCmdInsertLines drawCmdInsertLines;
        struct DrawCmdDrawCursor drawCmdDrawCursor;
        struct DrawCmdDrawInvertedRect drawCmdDrawInvertedRect;
        struct DrawCmdSetCursorPos drawCmdSetCursorPos;
    };

    int type;
};

// Read a single draw command from the batch draw data stream, and returns the
// draw type (the type is also stored in drawCmd->type).
static int ReadDrawCmd(const void **bytesRef, struct DrawCmd *drawCmd)
{
    const void *bytes = *bytesRef;
    
    int type = *((int*)bytes);  bytes += sizeof(int);
    
    switch (type) {
        case ClearAllDrawType:
            break;
        case ClearBlockDrawType:
        {
            struct DrawCmdClearBlock *cmd = &drawCmd->drawCmdClearBlock;
            cmd->color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            cmd->row1 = *((int*)bytes);  bytes += sizeof(int);
            cmd->col1 = *((int*)bytes);  bytes += sizeof(int);
            cmd->row2 = *((int*)bytes);  bytes += sizeof(int);
            cmd->col2 = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DeleteLinesDrawType:
        {
            struct DrawCmdDeleteLines *cmd = &drawCmd->drawCmdDeleteLines;
            cmd->color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->count = *((int*)bytes);  bytes += sizeof(int);
            cmd->bot = *((int*)bytes);  bytes += sizeof(int);
            cmd->left = *((int*)bytes);  bytes += sizeof(int);
            cmd->right = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DrawSignDrawType:
        {
            struct DrawCmdDrawSign *cmd = &drawCmd->drawCmdDrawSign;
            cmd->strSize = *((int*)bytes);  bytes += sizeof(int);
            cmd->imgName = (const char*)bytes; bytes += cmd->strSize;
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->width = *((int*)bytes);  bytes += sizeof(int);
            cmd->height = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DrawStringDrawType:
        {
            struct DrawCmdDrawString *cmd = &drawCmd->drawCmdDrawString;
            cmd->bg = *((int*)bytes);  bytes += sizeof(int);
            cmd->fg = *((int*)bytes);  bytes += sizeof(int);
            cmd->sp = *((int*)bytes);  bytes += sizeof(int);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
            cmd->cells = *((int*)bytes);  bytes += sizeof(int);
            cmd->flags = *((int*)bytes);  bytes += sizeof(int);
            cmd->len = *((int*)bytes);  bytes += sizeof(int);
            cmd->str = (UInt8 *)bytes;  bytes += cmd->len;
        }
            break;
        case InsertLinesDrawType:
        {
            struct DrawCmdInsertLines *cmd = &drawCmd->drawCmdInsertLines;
            cmd->color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->count = *((int*)bytes);  bytes += sizeof(int);
            cmd->bot = *((int*)bytes);  bytes += sizeof(int);
            cmd->left = *((int*)bytes);  bytes += sizeof(int);
            cmd->right = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DrawCursorDrawType:
        {
            struct DrawCmdDrawCursor *cmd = &drawCmd->drawCmdDrawCursor;
            cmd->color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
            cmd->shape = *((int*)bytes);  bytes += sizeof(int);
            cmd->percent = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DrawInvertedRectDrawType:
        {
            struct DrawCmdDrawInvertedRect *cmd = &drawCmd->drawCmdDrawInvertedRect;
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
            cmd->nr = *((int*)bytes);  bytes += sizeof(int);
            cmd->nc = *((int*)bytes);  bytes += sizeof(int);
            cmd->invert = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case SetCursorPosDrawType:
        {
            struct DrawCmdSetCursorPos *cmd = &drawCmd->drawCmdSetCursorPos;
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        default:
        {
            ASLogWarn(@"Unknown draw type (type=%d)", type);
            type = InvalidDrawType;
        }
            break;
    }
    
    *bytesRef = bytes;
    drawCmd->type = type;
    return type;
}

- (void)batchDrawData:(NSData *)data
{
    const void *bytes = [data bytes];
    const void *end = bytes + [data length];

#if MM_DEBUG_DRAWING
    ASLogNotice(@"====> BEGIN");
#endif
    // TODO: Sanity check input

    while (bytes < end) {
        struct DrawCmd drawCmd;
        int type = ReadDrawCmd(&bytes, &drawCmd);

        if (ClearAllDrawType == type) {
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Clear all");
#endif
            [self clearAll];
        } else if (ClearBlockDrawType == type) {
            struct DrawCmdClearBlock *cmd = &drawCmd.drawCmdClearBlock;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Clear block (%d,%d) -> (%d,%d)", cmd->row1, cmd->col1,
                    cmd->row2, cmd->col2);
#endif
            [self clearBlockFromRow:cmd->row1 column:cmd->col1
                    toRow:cmd->row2 column:cmd->col2
                    color:cmd->color];
        } else if (DeleteLinesDrawType == type) {
            struct DrawCmdDeleteLines *cmd = &drawCmd.drawCmdDeleteLines;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Delete %d line(s) from %d", cmd->count, cmd->row);
#endif
            [self deleteLinesFromRow:cmd->row lineCount:cmd->count
                    scrollBottom:cmd->bot left:cmd->left right:cmd->right
                           color:cmd->color];
        } else if (DrawSignDrawType == type) {
            struct DrawCmdDrawSign *cmd = &drawCmd.drawCmdDrawSign;
            NSString *imgName =
                [NSString stringWithUTF8String:cmd->imgName];
            NSImage *signImg = [helper signImageForName:imgName];
            grid_cell_safe(&grid, cmd->row, cmd->col)->sign = signImg;
            [self setNeedsDisplayFromRow:cmd->row column:cmd->col toRow:cmd->row column:cmd->col];
        } else if (DrawStringDrawType == type) {
            struct DrawCmdDrawString *cmd = &drawCmd.drawCmdDrawString;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Draw string len=%d row=%d col=%d flags=%#x",
                    cmd->len, cmd->row, cmd->col, cmd->flags);
#endif

            // Convert UTF-8 chars to UTF-16
            NSString *sref = [[NSString alloc] initWithBytes:cmd->str length:cmd->len encoding:NSUTF8StringEncoding];
            if (sref == NULL) {
                ASLogWarn(@"Conversion error: some text may not be rendered");
                continue;
            }
            [self setString:sref
                      atRow:cmd->row column:cmd->col cells:cmd->cells
                  withFlags:cmd->flags
            foregroundColor:cmd->fg
            backgroundColor:cmd->bg
               specialColor:cmd->sp];

            [sref release];
        } else if (InsertLinesDrawType == type) {
            struct DrawCmdInsertLines *cmd = &drawCmd.drawCmdInsertLines;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Insert %d line(s) at row %d", cmd->count, cmd->row);
#endif
            [self insertLinesAtRow:cmd->row lineCount:cmd->count
                             scrollBottom:cmd->bot left:cmd->left right:cmd->right
                                    color:cmd->color];
        } else if (DrawCursorDrawType == type) {
            struct DrawCmdDrawCursor *cmd = &drawCmd.drawCmdDrawCursor;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Draw cursor at (%d,%d)", cmd->row, cmd->col);
#endif
            [self setInsertionPointAtRow:cmd->row column:cmd->col shape:cmd->shape
                                fraction:cmd->percent
                                   color:cmd->color];
        } else if (DrawInvertedRectDrawType == type) {
            struct DrawCmdDrawInvertedRect *cmd = &drawCmd.drawCmdDrawInvertedRect;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Draw inverted rect: row=%d col=%d nrows=%d "
                   "ncols=%d", cmd->row, cmd->col, cmd->nr, cmd->nc);
#endif
            [self invertBlockFromRow:cmd->row column:cmd->col numRows:cmd->nr
                          numColumns:cmd->nc];
        } else if (SetCursorPosDrawType == type) {
            // TODO: This is used for Voice Over support in MMTextView,
            // MMCoreTextView currently does not support Voice Over.
#if MM_DEBUG_DRAWING
            struct DrawCmdSetCursorPos *cmd = &drawCmd.drawCmdSetCursorPos;
            ASLogNotice(@"   Set cursor row=%d col=%d", cmd->row, cmd->col);
#endif
        } else {
            ASLogWarn(@"Unknown draw type (type=%d)", type);
        }
    }

#if MM_DEBUG_DRAWING
    ASLogNotice(@"<==== END");
#endif
}

- (void)setString:(NSString *)string
            atRow:(int)row column:(int)col cells:(int)cells
        withFlags:(int)flags foregroundColor:(int)fg
  backgroundColor:(int)bg specialColor:(int)sp
{
    const BOOL wide = flags & DRAW_WIDE ? YES : NO;
    __block size_t cells_filled = 0;
    [string enumerateSubstringsInRange:NSMakeRange(0, string.length)
                               options:NSStringEnumerationByComposedCharacterSequences
                            usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        const int curCol = col + cells_filled++ * (wide ? 2 : 1);
        GridCell *cell = grid_cell_safe(&grid, row, curCol);
        GridCellInsertionPoint insertionPoint = {0};
        if (flags & DRAW_TRANSP)
            insertionPoint = cell->insertionPoint;

        NSString *characterString = nil;
        if (![substring isEqualToString:@" "]) {
            characterString = [characterStrings member:substring];
            if (!characterString) {
                characterString = substring;
                [characterStrings addObject:characterString];
            }
        }
        *cell = (GridCell){
            .bg = bg,
            .fg = fg,
            .sp = sp,
            .textFlags = flags,
            .insertionPoint = insertionPoint,
            .string = characterString,
        };

        if (wide) {
            // Also clear the next cell just to be tidy (even though this cell would be skipped during rendering)
            const GridCell clearCell = { .bg = defaultBackgroundColor.argbInt };
            GridCell *nextCell = grid_cell_safe(&grid, row, curCol + 1);
            *nextCell = clearCell;
        }
    }];
    [self setNeedsDisplayFromRow:row
                          column:col
                           toRow:row
                          column:col+cells_filled*(wide ? 2 : 1)];
}

- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(int)color
{
    for (size_t r = row; r + count <= MIN(grid.rows - 1, bottom); r++) {
        memcpy(grid_cell(&grid, r, left),
               grid_cell(&grid, r + count, left),
               sizeof(GridCell) * (MIN(grid.cols, right + 1) - MIN(grid.cols, left)));
    }
    const GridCell clearCell = { .bg = color };
    for (size_t r = bottom - count + 1; r <= MIN(grid.rows - 1, bottom); r++) {
        for (size_t c = left; c <= MIN(grid.cols - 1, right); c++)
            *grid_cell(&grid, r, c) = clearCell;
    }
    [self setNeedsDisplayFromRow:row column:left toRow:bottom column:right];
}

- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(int)color
{
    for (size_t r = MIN(grid.rows - 1, bottom); r >= row + count; r--) {
        memcpy(grid_cell(&grid, r, left),
               grid_cell(&grid, r - count, left),
               sizeof(GridCell) * (MIN(grid.cols, right + 1) - MIN(grid.cols, left)));
    }
    const GridCell clearCell = { .bg = color };
    for (size_t r = row; r < MIN(grid.rows, row + count); r++) {
        for (size_t c = left; c <= right; c++)
            *grid_cell(&grid, r, c) = clearCell;
    }
    [self setNeedsDisplayFromRow:row column:left toRow:bottom column:right];
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(int)color
{
    const GridCell clearCell = { .bg = color };
    for (size_t r = row1; r <= row2; r++) {
        for (size_t c = col1; c <= col2; c++)
            *grid_cell_safe(&grid, r, c) = clearCell;
    }
    [self setNeedsDisplayFromRow:row1 column:col1 toRow:row2 column:col2];
}

- (void)clearAll
{
    const GridCell clearCell = { .bg = defaultBackgroundColor.argbInt };
    for (size_t r = 0; r < maxRows; r++) {
        for (size_t c = 0; c < maxColumns; c++)
            *grid_cell(&grid, r, c) = clearCell;
    }
    self.needsDisplay = YES;
}

- (void)setInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                      fraction:(int)percent color:(int)color
{
    GridCell *cell = grid_cell_safe(&grid, row, col);
    cell->insertionPoint = (GridCellInsertionPoint){
        .color = color,
        .shape = shape,
        .fraction = percent,
    };
    [self setNeedsDisplayFromRow:row column:col toRow:row column:col];
}

- (void)invertBlockFromRow:(int)row column:(int)col numRows:(int)nrows
                   numColumns:(int)ncols
{
    for (size_t r = row; r < row + nrows; r++) {
        for (size_t c = col; c < col + ncols; c++) {
            grid_cell_safe(&grid, r, c)->inverted ^= 1;
        }
    }
    [self setNeedsDisplayFromRow:row column:col toRow:row + nrows column:col + ncols];
}

@end // MMCoreTextView (Drawing)
