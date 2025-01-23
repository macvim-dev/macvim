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
#define DRAW_TRANSP               0x01    // draw with transparent bg
#define DRAW_BOLD                 0x02    // draw bold text
#define DRAW_UNDERL               0x04    // draw underline text
#define DRAW_UNDERC               0x08    // draw undercurl text
#define DRAW_ITALIC               0x10    // draw italic text
#define DRAW_CURSOR               0x20
#define DRAW_STRIKE               0x40    // draw strikethrough text
#define DRAW_UNDERDOUBLE          0x80	  // draw double underline
#define DRAW_UNDERDOTTED          0x100	  // draw dotted underline
#define DRAW_UNDERDASHED          0x200	  // draw dashed underline
#define DRAW_WIDE                 0x1000  // (MacVim only) draw wide text
#define DRAW_COMP                 0x2000  // (MacVim only) drawing composing char

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_13
typedef NSString * NSAttributedStringKey;
#endif // MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_13

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
- (void)setCmdlineRow:(int)row;
@end


@interface MMCoreTextView (Drawing)
- (NSPoint)pointForRow:(int)row column:(int)column;
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

/// A cell in the grid. Each cell represents a grapheme, which could consist of one or more
/// characters. If textFlags contains DRAW_WIDE, then it's a 'wide' cell, which means a grapheme
/// takes up two cell spaces to render (e.g. emoji or CJK characters). When this is the case, the
/// next cell in the grid should be ignored and skipped.
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
    NSString* string; ///< Owned by characterStrings. Length would be >1 if there are composing chars.
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

    BOOL alignCmdLineToBottom; ///< Whether to pin the Vim command-line to the bottom of the window
    int cmdlineRow; ///< Row number (0-indexed) where the cmdline starts. Used for pinning it to the bottom if desired.

    /// Number of rows to expand when redrawing to make sure we don't clip tall
    /// characters whose glyphs extend beyond the bottom/top of the cell.
    ///
    /// Note: This is a short-term hacky solution as it permanently increases
    /// the number of rows to expand every time we redraw. Eventually we should
    /// calculate each line's glyphs' bounds before issuing a redraw and use
    /// that to determine the accurate redraw bounds instead. Currently we
    /// calculate the glyph run too late (inside the draw call itself).
    unsigned int redrawExpandRows;
}

- (instancetype)initWithFrame:(NSRect)frame
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

    [self registerForDraggedTypes:@[getPasteboardFilenamesType(),
                                    NSPasteboardTypeString]];

    ligatures = NO;

    alignCmdLineToBottom = NO; // this would be updated to the user preferences later
    cmdlineRow = -1; // this would be updated by Vim
    redrawExpandRows = 0; // start at 0, until we see a tall character. and then we expand it.

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
    pendingMaxRows = rows;
    pendingMaxColumns = cols;
}

- (int)pendingMaxRows
{
    return pendingMaxRows;
}

- (int)pendingMaxColumns
{
    return pendingMaxColumns;
}

- (void)setPendingMaxRows:(int)rows columns:(int)cols
{
    pendingMaxRows = rows;
    pendingMaxColumns = cols;
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

    // Note: This doesn't really take alignCmdLineToBottom into account right now.

    NSRect rect = { {0, 0}, {0, 0} };
    NSUInteger start = range.location > maxRows ? maxRows : range.location;
    NSUInteger length = range.length;

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
    NSUInteger start = range.location > maxColumns ? maxColumns : range.location;
    NSUInteger length = range.length;

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
    fontDescent = CTFontGetDescent((CTFontRef)font);
    fontAscent = CTFontGetAscent((CTFontRef)font);
    fontXHeight = CTFontGetXHeight((CTFontRef)font);

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

/// Update the cmdline row number from Vim's state and cmdline alignment user settings.
- (void)updateCmdlineRow
{
    [self setCmdlineRow: [[[self vimController] objectForVimStateKey:@"cmdline_row"] intValue]];
}

/// Shows the dictionary looup / definition of the provided text at row/col.
/// This is usually invoked from Vimscript via the showdefinition() function.
- (void)showDefinitionForCustomString:(NSString *)text row:(int)row col:(int)col
{
    const NSRect cursorRect = [self rectForRow:row column:col numRows:1 numColumns:1];

    NSPoint baselinePt = cursorRect.origin;
    baselinePt.y += fontDescent;

    NSAttributedString *attrText = [[[NSAttributedString alloc] initWithString:text
                                                                    attributes:@{NSFontAttributeName: font}
                                    ] autorelease];

    [self showDefinitionForAttributedString:attrText atPoint:baselinePt];
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

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
    // We are not currently replacementRange right now.
    [helper insertText:string];
}

- (void)doCommandBySelector:(SEL)selector
{
    [helper doCommandBySelector:selector];
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
    row -= redrawExpandRows;
    row2 += redrawExpandRows;
    [self setNeedsDisplayInRect:[self rectForRow:row column:0 numRows:row2-row+1 numColumns:maxColumns]];
}

- (void)drawRect:(NSRect)rect
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    const BOOL clipTextToRow = [ud boolForKey:MMRendererClipToRowKey]; // Specify whether to clip tall characters by the row boundary.


#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_14_0
    // On macOS 14+ by default views don't clip their content, which is good as it allows tall texts
    // on first line to be drawn fully without getting clipped. However, in this case we should make
    // sure the background color fill is clipped properly, as otherwise it will interfere with
    // non-native fullscreen's background color setting.
    const BOOL clipBackground = !self.clipsToBounds;
#else
    const BOOL clipBackground = NO;
#endif

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10
    CGContextRef ctx = context.CGContext;
#else
    CGContextRef ctx = [context graphicsPort];
#endif

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

    if (clipBackground) {
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, self.bounds);
    }
    CGContextFillRect(ctx, rect);
    if (clipBackground) {
        CGContextRestoreGState(ctx);
    }

    // Function to draw all rows
    void (^drawAllRows)(void (^)(CGContextRef,CGRect,int)) = ^(void (^drawFunc)(CGContextRef,CGRect,int)){
        for (int r = 0; r < grid.rows; r++) {
            const CGRect rowRect = [self rectForRow:(int)r
                                             column:0
                                            numRows:1
                                         numColumns:grid.cols];

            // Expand the clip rect to include some above/below rows in case we have tall characters.
            const CGRect rowExpandedRect = [self rectForRow:(int)(r-redrawExpandRows)
                                                     column:0
                                                    numRows:(1+redrawExpandRows*2)
                                                 numColumns:grid.cols];

            const CGRect rowClipRect = CGRectIntersection(rowExpandedRect, rect);
            if (CGRectIsNull(rowClipRect))
                continue;
            CGContextSaveGState(ctx);
            if (clipTextToRow)
                CGContextClipToRect(ctx, rowClipRect);

            drawFunc(ctx, rowRect, (int)r);

            CGContextRestoreGState(ctx);
        }
    };

    // Function to draw a row of background colors, signs, and cursor rect. These should go below
    // any text.
    void (^drawBackgroundAndCursorFunc)(CGContextRef,CGRect,int) = ^(CGContextRef ctx, CGRect rowRect, int r){
        for (int c = 0; c < grid.cols; c++) {
            GridCell cell = *grid_cell(&grid, r, c);
            CGRect cellRect = {{rowRect.origin.x + cellSize.width * c, rowRect.origin.y}, cellSize};
            if (cell.textFlags & DRAW_WIDE)
                cellRect.size.width *= 2;
            if (cell.inverted) {
                cell.bg ^= 0xFFFFFF;
                cell.fg ^= 0xFFFFFF;
                cell.sp ^= 0xFFFFFF;
            }

            // Fill background
            if (cell.bg != defaultBg && ALPHA(cell.bg) > 0) {
                CGRect fillCellRect = cellRect;

                if (c == grid.cols - 1 || (c == grid.cols - 2 && (cell.textFlags & DRAW_WIDE))) {
                    // Fill a little extra to the right if this is the last
                    // column, and the frame size isn't exactly the same size
                    // as the grid (due to smooth resizing, etc). This makes it
                    // look less ugly and more consisten. See rectForRow:'s
                    // implementation for extra comments.
                    CGFloat extraWidth = rowRect.origin.x + rowRect.size.width - (cellRect.size.width + cellRect.origin.x);
                    fillCellRect.size.width += extraWidth;
                }

                CGContextSetFillColor(ctx, COMPONENTS(cell.bg));
                CGContextFillRect(ctx, fillCellRect);
            }

            // Handle signs
            if (cell.sign) {
                CGRect signRect = cellRect;
                signRect.size.width *= 2;
                [cell.sign drawInRect:signRect
                             fromRect:(NSRect){{0, 0}, cell.sign.size}
                            operation:(cell.inverted ? NSCompositingOperationDifference : NSCompositingOperationSourceOver)
                             fraction:1.0];
            }

            // Insertion point (cursor)
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
        }
    };

    // Function to draw a row of text with their corresponding text styles.
    void (^drawTextFunc)(CGContextRef,CGRect,int) = ^(CGContextRef ctx, CGRect rowRect, int r){
        __block NSMutableString *lineString = nil;
        __block CGFloat lineStringStart = 0;
        __block CFRange lineStringRange = {};
        __block GridCell lastStringCell = {};
        void (^flushLineString)() = ^{
            // This function flushes the current pending line out to be rendered. When ligature is
            // enabled it could be quite long.  Otherwise, lineString would be just one cell/grapheme. Note
            // that even one cell can have lineString.length > 1 and also multiple glyphs due to
            // composing characters (limited by Vim's 'maxcombine').
            if (!lineString.length)
                return;
            size_t cellOffsetByIndex[lineString.length];
            for (int i = 0, stringIndex = 0; i < (int)lineStringRange.length; i++) {
                GridCell cell = *grid_cell(&grid, r, (int)lineStringRange.location + i);
                size_t cell_length = cell.string.length;
                for (size_t j = 0; j < cell_length; j++) {
                    cellOffsetByIndex[stringIndex++] = i;
                }
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

            CGSize accumAdvance = CGSizeZero; // Accumulated advance for the currently cell's glyphs (we can get more than one glyph when we have composing chars)
            CGPoint expectedGlyphPosition = CGPointZero; // The expected layout glyph position produced by CTLine
            size_t curCell = -1; // The current cell offset within lineStrangeRange

            for (id obj in glyphRuns) {
                CTRunRef run = (CTRunRef)obj;
                CFIndex glyphCount = CTRunGetGlyphCount(run);

                CTFontRef runFont = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
                if (!runFont) {
                    ASLogDebug(@"Null font for rendering. glyphCount: %ld", (long)glyphCount);
                }

                CGPoint positions[glyphCount];

                CFIndex indices_storage[glyphCount];
                const CFIndex* indices = NULL;
                if ((indices = CTRunGetStringIndicesPtr(run)) == NULL) {
                    CTRunGetStringIndices(run, CFRangeMake(0, 0), indices_storage);
                    indices = indices_storage;
                }

                const CGGlyph* glyphs = NULL;
                CGGlyph glyphs_storage[glyphCount];
                if ((glyphs = CTRunGetGlyphsPtr(run)) == NULL) {
                    CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphs_storage);
                    glyphs = glyphs_storage;
                }

                const CGSize* advances = NULL;
                CGSize advances_storage[glyphCount];
                if ((advances = CTRunGetAdvancesPtr(run)) == NULL) {
                    CTRunGetAdvances(run, CFRangeMake(0, 0), advances_storage);
                    advances = advances_storage;
                }

                const CGPoint* layoutPositions = CTRunGetPositionsPtr(run);
                CGPoint layoutPositions_storage[glyphCount];
                if (layoutPositions == NULL) {
                    CTRunGetPositions(run, CFRangeMake(0, 0), layoutPositions_storage);
                    layoutPositions = layoutPositions_storage;
                }

                const int maxRedrawExpandRows = clipTextToRow ? 0 : 3; // Hard-code a sane maximum for now to prevent degenerate edge cases
                if (redrawExpandRows < maxRedrawExpandRows) {
                    // Check if we encounter any glyphs in this line that are too tall and would be
                    // clipped / not redrawn properly. If we encounter that, increase
                    // redrawExpandRows and redraw.
                    // Note: This is kind of a hacky solution. See comments for redrawExpandRows.
                    CGRect lineBounds = CTRunGetImageBounds(run, ctx, CFRangeMake(0,0));
                    if (!CGRectIsNull(lineBounds)) {
                        unsigned int newRedrawExpandRows = 0;
                        if (lineBounds.origin.y < rowRect.origin.y) {
                            newRedrawExpandRows = (int)ceil((rowRect.origin.y - lineBounds.origin.y) / cellSize.height);
                        }
                        if (lineBounds.origin.y + lineBounds.size.height > rowRect.origin.y + cellSize.height) {
                            int rowsAbove = (int)ceil(((lineBounds.origin.y + lineBounds.size.height) - (rowRect.origin.y + cellSize.height)) / cellSize.height);
                            if (rowsAbove > newRedrawExpandRows) {
                                newRedrawExpandRows = rowsAbove;
                            }
                        }

                        if (newRedrawExpandRows > redrawExpandRows) {
                            redrawExpandRows = newRedrawExpandRows;
                            if (redrawExpandRows > maxRedrawExpandRows) {
                                redrawExpandRows = maxRedrawExpandRows;
                            }
                            [self setNeedsDisplay:YES];
                        }
                    }
                }
                else {
                    redrawExpandRows = maxRedrawExpandRows;
                }

                for (CFIndex i = 0; i < glyphCount; i++) {
                    if (indices[i] >= lineStringLength) {
                        ASLogDebug(@"Invalid glyph pos index: %ld, len: %lu", (long)indices[i], (unsigned long)lineStringLength);
                        continue;
                    }
                    if (curCell != -1 && curCell == cellOffsetByIndex[indices[i]]) {
                        // We are still in the same cell/grapheme as last glyph. This usually only happens
                        // when we have 1 or more composing characters (e.g. U+20E3 or U+20D7), and
                        // Core Text decides to render them as separate glyphs instead of a single
                        // one (e.g. 'â' will result in a single glyph instead).
                        //
                        // Don't do anything to allow the last glyph's advance to accumulate.
                    } else {
                        // We are in a new cell/grapheme with a new string to render. This is the
                        // normal case.
                        // In this situation we reset the accumulated advances because we render
                        // every cell aligned to the grid and force everything to a monospace.
                        accumAdvance = CGSizeZero;
                        curCell = cellOffsetByIndex[indices[i]];
                    }

                    // Align the position to the grid cell. Ignore what the typesetter wants (we
                    // should be using a monospace font anyway, but if you are say entering CJK
                    // characters font substitution will result in a non-monospaced typesetting)
                    const CGPoint curCellPosition = CGPointMake(curCell * cellSize.width, 0);
                    positions[i] = curCellPosition;

                    // Add the accumulated advances, which would be non-zero if this is not the
                    // first glyph for this cell/character (due to composing chars).
                    positions[i].x += accumAdvance.width;
                    positions[i].y += accumAdvance.height;

                    // The expected glyph position should usually match what the layout wants to do.
                    // Sometimes though the typesetter will offset it slightly (e.g. when rendering
                    // 'x゙⃣', the first 'x' will be offsetted to give space to the later composing
                    // chars. Since we are manually rendering to curCellPosition to align to a grid,
                    // we take the offset and apply that instead of directly using layoutPositions.
                    positions[i].x += (layoutPositions[i].x - expectedGlyphPosition.x);
                    positions[i].y += (layoutPositions[i].y - expectedGlyphPosition.y);

                    // Accumulate the glyph's advance
                    accumAdvance.width += advances[i].width;
                    accumAdvance.height += advances[i].height;
                    expectedGlyphPosition.x += advances[i].width;
                    expectedGlyphPosition.y += advances[i].height;

                }
                CTFontDrawGlyphs(runFont, glyphs, positions, glyphCount, ctx);
            }

            CGContextSetBlendMode(ctx, kCGBlendModeCopy);
            [lineString deleteCharactersInRange:NSMakeRange(0, lineString.length)];
        };

        BOOL hasStrikeThrough = NO;

        for (int c = 0; c < grid.cols; c++) {
            GridCell cell = *grid_cell(&grid, r, c);
            CGRect cellRect = {{rowRect.origin.x + cellSize.width * c, rowRect.origin.y}, cellSize};
            if (cell.textFlags & DRAW_WIDE)
                cellRect.size.width *= 2;
            if (cell.inverted) {
                cell.bg ^= 0xFFFFFF;
                cell.fg ^= 0xFFFFFF;
                cell.sp ^= 0xFFFFFF;
            }

            // Text underline styles. We only allow one of them to be active.
            // Note: We are not currently using underlineThickness or underlinePosition. Should fix to use them.
            const CGFloat underlineY = 0.4*fontDescent; // Just a hard-coded value for now. Should fix to use underlinePosition.
            if (cell.textFlags & DRAW_UNDERC) {
                const CGFloat x = cellRect.origin.x, y = cellRect.origin.y+1, w = cellSize.width, h = 0.5*fontDescent;
                CGContextMoveToPoint(ctx, x, y);
                CGContextAddCurveToPoint(ctx, x+0.25*w, y, x+0.25*w, y+h, x+0.5*w, y+h);
                CGContextAddCurveToPoint(ctx, x+0.75*w, y+h, x+0.75*w, y, x+w, y);
                if (cell.textFlags & DRAW_WIDE) {
                    // Need to draw another set for double-width characters
                    const CGFloat x2 = x + cellSize.width;
                    CGContextAddCurveToPoint(ctx, x2+0.25*w, y, x2+0.25*w, y+h, x2+0.5*w, y+h);
                    CGContextAddCurveToPoint(ctx, x2+0.75*w, y+h, x2+0.75*w, y, x2+w, y);
                }
                CGContextSetRGBStrokeColor(ctx, RED(cell.sp), GREEN(cell.sp), BLUE(cell.sp), ALPHA(cell.sp));
                CGContextStrokePath(ctx);
            }
            else if (cell.textFlags & DRAW_UNDERDASHED) {
                const CGFloat dashLengths[] = {cellSize.width / 4, cellSize.width / 4};

                const CGFloat x = cellRect.origin.x;
                const CGFloat y = cellRect.origin.y+underlineY;
                CGContextMoveToPoint(ctx, x, y);
                CGContextAddLineToPoint(ctx, x + cellRect.size.width, y);
                CGContextSetRGBStrokeColor(ctx, RED(cell.sp), GREEN(cell.sp), BLUE(cell.sp), ALPHA(cell.sp));
                CGContextSetLineDash(ctx, 0, dashLengths, 2);
                CGContextStrokePath(ctx);
            }
            else if (cell.textFlags & DRAW_UNDERDOTTED) {
                // Calculate dot size to use. Normally, just do 1-pixel dots/gaps, since the line is one pixel thick.
                CGFloat dotSize = 1, gapSize = 1;
                if (fmod(cellSize.width, 2) != 0) {
                    // Width is not even number, so spacing them would look weird. Find another way.
                    if (fmod(cellSize.width, 3) == 0) {
                        // Width is divisible by 3, so just make the gap twice as long so they can be spaced out.
                        dotSize = 1;
                        gapSize = 2;
                    }
                    else {
                        // Not disible by 2 or 3. Just Re-calculate dot size so be slightly larger than 1 so we can exactly
                        // equal number of dots and gaps. This does mean we have a non-integer size, so we are relying
                        // on anti-aliasing here to help this not look too bad, but it will still look slightly blurry.
                        dotSize = cellSize.width / (ceil(cellSize.width / 2) * 2);
                        gapSize = dotSize;
                    }
                }
                const CGFloat dashLengths[] = {dotSize, gapSize};

                const CGFloat x = cellRect.origin.x;
                const CGFloat y = cellRect.origin.y+underlineY;
                CGContextMoveToPoint(ctx, x, y);
                CGContextAddLineToPoint(ctx, x + cellRect.size.width, y);
                CGContextSetRGBStrokeColor(ctx, RED(cell.sp), GREEN(cell.sp), BLUE(cell.sp), ALPHA(cell.sp));
                CGContextSetLineDash(ctx, 0, dashLengths, 2);
                CGContextStrokePath(ctx);
            }
            else if (cell.textFlags & DRAW_UNDERDOUBLE) {
                CGRect rect = CGRectMake(cellRect.origin.x, cellRect.origin.y+underlineY, cellRect.size.width, 1);
                CGContextSetFillColor(ctx, COMPONENTS(cell.sp));
                CGContextFillRect(ctx, rect);

                // Draw second underline
                if (underlineY - 3 < 0) {
                    // Not enough fontDescent to draw another line below, just draw above. This is not the desired
                    // solution but works.
                    rect = CGRectMake(cellRect.origin.x, cellRect.origin.y+underlineY + 3, cellRect.size.width, 1);
                } else {
                    // Nominal situation. Just a second one below first one.
                    rect = CGRectMake(cellRect.origin.x, cellRect.origin.y+underlineY - 3, cellRect.size.width, 1);
                }
                CGContextSetFillColor(ctx, COMPONENTS(cell.sp));
                CGContextFillRect(ctx, rect);
            } else if (cell.textFlags & DRAW_UNDERL) {
                CGRect rect = CGRectMake(cellRect.origin.x, cellRect.origin.y+underlineY, cellRect.size.width, 1);
                CGContextSetFillColor(ctx, COMPONENTS(cell.sp));
                CGContextFillRect(ctx, rect);
            }

            // Text strikethrough
            // We delay the rendering of strikethrough and only do it as a second-pass since we want to draw them on top
            // of text, and text rendering is currently delayed via flushLineString(). This is important for things like
            // emojis where the color of the text is different from the underline's color.
            if (cell.textFlags & DRAW_STRIKE) {
                hasStrikeThrough = YES;
            }

            // Draw the actual text
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

        if (hasStrikeThrough) {
            // Second pass to render strikethrough. Unfortunately have to duplicate a little bit of code here to loop
            // through the cells.
            for (int c = 0; c < grid.cols; c++) {
                GridCell cell = *grid_cell(&grid, r, c);
                CGRect cellRect = {{rowRect.origin.x + cellSize.width * c, rowRect.origin.y}, cellSize};
                if (cell.textFlags & DRAW_WIDE)
                    cellRect.size.width *= 2;
                if (cell.inverted) {
                    cell.bg ^= 0xFFFFFF;
                    cell.fg ^= 0xFFFFFF;
                    cell.sp ^= 0xFFFFFF;
                }

                // Text strikethrough
                if (cell.textFlags & DRAW_STRIKE) {
                    CGRect rect = CGRectMake(cellRect.origin.x, cellRect.origin.y + fontDescent + fontXHeight / 2, cellRect.size.width, 1);
                    CGContextSetFillColor(ctx, COMPONENTS(cell.sp));
                    CGContextFillRect(ctx, rect);
                }

            }
        }
    };

    // Render passes:

    // 1. Draw background color and cursor rect.
    drawAllRows(drawBackgroundAndCursorFunc);

    // 2. Draw text.
    // We need to do this in a separate pass in case some characters are taller than a cell. This
    // could easily happen when we have composed characters (e.g. T゙̂⃗) that either goes below or above
    // the cell boundary. We draw the background colors in 1st pass to make sure all the texts will
    // be drawn on top of them. Also see redrawExpandRows which handles making such tall characters
    // redraw/clip correctly.
    drawAllRows(drawTextFunc);

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
    NSInteger right = [ud integerForKey:MMTextInsetRightKey];
    NSInteger bot = [ud integerForKey:MMTextInsetBottomKey];

    if (size.height != desiredSize.height) {
        float fh = cellSize.height;
        float ih = insetSize.height + bot;
        if (fh < 1.0f) fh = 1.0f;

        desiredRows = floor((size.height - ih)/fh);
        // Sanity checking in case unusual window sizes lead to degenerate results
        if (desiredRows < 1)
            desiredRows = 1;
        desiredSize.height = fh*desiredRows + ih;
    }

    if (size.width != desiredSize.width) {
        float fw = cellSize.width;
        float iw = insetSize.width + right;
        if (fw < 1.0f) fw = 1.0f;

        desiredCols = floor((size.width - iw)/fw);
        // Sanity checking in case unusual window sizes lead to degenerate results
        if (desiredCols < 1)
            desiredCols = 1;
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
    NSInteger right = [ud integerForKey:MMTextInsetRightKey];
    NSInteger bot = [ud integerForKey:MMTextInsetBottomKey];

    return NSMakeSize(maxColumns * cellSize.width + insetSize.width + right,
                      maxRows * cellSize.height + insetSize.height + bot);
}

- (NSSize)minSize
{
    // Compute the smallest size the text view is allowed to be.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger right = [ud integerForKey:MMTextInsetRightKey];
    NSInteger bot = [ud integerForKey:MMTextInsetBottomKey];

    return NSMakeSize(MMMinColumns * cellSize.width + insetSize.width + right,
                      MMMinRows * cellSize.height + insetSize.height + bot);
}

// Called when font panel selection has been made or when adjusting font size
// using modifyFont/NSSizeUpFontAction. Send the selected font to MMBackend so
// it would set guifont which will send a message back to MacVim to call
// MMWindowController::setFont.
- (void)changeFont:(id)sender
{
    NSFont *newFont = [sender convertFont:font];

    if (newFont) {
        NSString *name = [newFont fontName];
        unsigned len = (unsigned)[name lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (len > 0) {
            NSMutableData *data = [NSMutableData data];
            float pointSize = [newFont pointSize];

            [data appendBytes:&pointSize length:sizeof(float)];

            ++len;  // include NUL byte
            [data appendBytes:&len length:sizeof(unsigned)];
            [data appendBytes:[name UTF8String] length:len];

            // We don't update guifontwide for now, as panel font selection
            // shouldn't affect them. This does mean Cmd +/- does not work for
            // them for now.
            const unsigned wideLen = 0;
            [data appendBytes:&wideLen length:sizeof(unsigned)];

            [[self vimController] sendMessage:SetFontMsgID data:data];
        }
    }
}

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    // Lets the user pick only the font face / size, as other properties as not
    // useful. Still enable text/document colors as these affect the preview.
    // Otherwise it could just be white text on white background in the preview.
    return NSFontPanelModesMaskStandardModes & (~NSFontPanelModeMaskAllEffects | NSFontPanelModeMaskTextColorEffect | NSFontPanelModeMaskDocumentColorEffect);
}
#endif

/// Specifies whether the menu item should be enabled/disabled.
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(cut:)
        || [item action] == @selector(copy:)
        || [item action] == @selector(paste:)
        || [item action] == @selector(undo:)
        || [item action] == @selector(redo:)
        || [item action] == @selector(selectAll:))
        return [item tag];

    // This class should not have any special macOS menu itmes, so theoretically
    // all of them should just return item.tag, but just in case macOS decides
    // to inject some menu items to the parent NSView class without us knowing,
    // we let the superclass handle this.
    return YES;
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

/// Converts a point in this NSView to a specific Vim row/column.
///
/// @param point The point in NSView. Note that it's y-up as that's Mac convention, whereas row starts from the top.
- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column
{
    // Convert y-up to y-down.
    point.y = [self bounds].size.height - point.y;

    NSPoint origin = { insetSize.width, insetSize.height };

    if (!(cellSize.width > 0 && cellSize.height > 0))
        return NO;

    if (alignCmdLineToBottom) {
        // Account for the gap we added to pin cmdline to the bottom of the window
        const NSRect frame = [self bounds];
        const NSInteger insetBottom = [[NSUserDefaults standardUserDefaults] integerForKey:MMTextInsetBottomKey];
        const CGFloat gapHeight = frame.size.height - grid.rows*cellSize.height - insetSize.height - insetBottom;
        const CGFloat cmdlineRowY = insetSize.height + cmdlineRow*cellSize.height + 1;
        if (point.y > cmdlineRowY) {
            point.y -= gapHeight;
            if (point.y <= cmdlineRowY) {
                // This was inside the gap between top and bottom lines. Round it down
                // to the next line.
                point.y = cmdlineRowY + 1;
            }
        }
    }

    if (row) *row = floor((point.y-origin.y-1) / cellSize.height);
    if (column) *column = floor((point.x-origin.x-1) / cellSize.width);

    //ASLogDebug(@"point=%@ row=%d col=%d",
    //      NSStringFromPoint(point), *row, *column);

    return YES;
}

/// Calculates the rect for the row/column range, accounting for insets. This also
/// has additional for accounting for aligning cmdline to bottom, and filling last
/// column to the right.
///
/// @return Rectangle containing the row/column range.
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

    // Under smooth resizing, full screen, or guioption-k; we frequently have a frame size that's not
    // aligned with the exact grid size. If the user has 'cursorline' set, or the color scheme uses
    // the NonText highlight group, this will leave a small gap on the right filled with bg color looking
    // a little weird. Just fill a little extra to the right for the last column to make it look less weird.
    //
    // Note that we don't do this for filling the bottom since it's used only for cmdline which isn't usually
    // colored anyway.
    if (col + nc == grid.cols) {
        const NSInteger insetRight = [[NSUserDefaults standardUserDefaults] integerForKey:MMTextInsetRightKey];
        CGFloat extraWidth = frame.size.width - insetRight - (rect.size.width + rect.origin.x);
        rect.size.width += extraWidth;
    }

    // When configured to align cmdline to bottom, need to adjust the rect with an additional gap to pin
    // the rect to the bottom.
    if (alignCmdLineToBottom) {
        const NSInteger insetBottom = [[NSUserDefaults standardUserDefaults] integerForKey:MMTextInsetBottomKey];
        const CGFloat gapHeight = frame.size.height - grid.rows*cellSize.height - insetSize.height - insetBottom;
        if (row >= cmdlineRow) {
            rect.origin.y -= gapHeight;
        } else if (row + nr - 1 >= cmdlineRow) {
            // This is an odd case where the gap between cmdline and the top-aligned content is inside
            // the rect so we need to adjust the height as well. During rendering we draw line-by-line
            // so this shouldn't cause any issues as we only encounter this situation when calculating
            // the rect in setNeedsDisplayFromRow:.
            rect.size.height += gapHeight;
            rect.origin.y -= gapHeight;
        }
    }
    return rect;
}

#pragma mark Text Input Client
#pragma region Text Input Client

//
// Text input client implementation.
// 
// Note that we are implementing this as a row-major indexed grid of the
// current display. This is not the same as Vim's internal knowledge of the
// buffers. We don't really have access to that easily because MacVim is purely
// a GUI into Vim through a multi-process model. It's theoretically possible to
// get access to it, but it increases latency and complexity, and we won't be
// able to get access to the message output.
//
// Because of this quirk, proper marked text implementation is quite difficult.
// The OS assumes a proper text strage backing, and that marked texts are a
// contiguous region in that storage (see how markedRange API returns a single
// NSRange). This is not possible for us if Vim has the marked texts wrapped
// into multiple lines while we have split windows, or just that a long marked
// text could be hidden. Because of that, we fake it by testing for
// hasMarkedText: If we have marked texts, we always tell the OS we are
// starting from 0, and the selectedRange/markedRange/etc all treat the text
// storage as having the marked text starting from 0, and
// firstRectForCharacterRange just handles that specially to make sure we still
// draw the input method's candidate list properly. Otherwise, we just treat
// the text storage as a row-major grid of the currently displayed text, which
// works fine for dictionary lookups.
//
// Also, note that whenever the OS API uses a character index or range, it
// always refers to the unicode length, so the calculation between row/col and
// character index/range needs to go through each character and calculate its
// length. We could optimize it to cache each row's total char length if we
// want if this is an issue.
//

/// Takes a point and convert it into a single index into the entire window's
/// text. The text is converted into a row-major format, and the lines are
/// concatenated together without injecting any spaces or newlines. Note that
/// this doesn't take into account of Vim's own window splits and whatnot for
/// now so a wrapped text in Vim would not be returned as contiguous.
///
/// The concatenation is done without injecting newlines for simplicity and to
/// allow wrapped lines to come together but that could be changed if it's
/// undesired.
static NSUInteger utfCharIndexFromRowCol(const Grid* grid, int row, int col)
{
    // Find the raw index for the character. Note that this is not good enough. With localized / wide texts,
    // some character will be single-width but have length > 1, and some character will be double-width. We
    // don't pre-calculate these information (since this is needed infrequently), and so we have to search
    // from first character onwards and accumulating the lengths.
    // See attributedSubstringForProposedRange which also does the same thing.
    const int rawIndex = row * grid->cols + col;
    const int gridSize = grid->cols * grid->rows;

    NSUInteger utfIndex = 0;
    for (int i = 0; i < gridSize && i < rawIndex; i++) {
        NSString *str = grid->cells[i].string;
        utfIndex += str == nil ? 1 : str.length; // Note: nil string means empty space.

        if (grid->cells[i].textFlags & DRAW_WIDE) {
            i += 1;
        }
    }
    return utfIndex;
}

/// Given grid position, and a UTF-8 character offset, return the new column on
/// the same line. This doesn't support multi-line for now as there is no need
/// to.
///
/// @param utfIndexOffset The character offset from the row/col provided. Can
///        be positive or negative.
///
/// @return The column at the specified offset. Note that this clamps at
///         [0,cols-1] since we are only looking for the same line.
static int colFromUtfOffset(const Grid* grid, int row, int col, NSInteger utfIndexOffset)
{
    if (row < 0 || col < 0 || row >= grid->rows || col >= grid->cols) {
        // Should not happen
        return 0;
    }
    if (utfIndexOffset == 0)
        return col;

    const int advance = utfIndexOffset > 0 ? 1 : -1;
    NSUInteger accUtfIndexOffset = 0;

    int c;
    for (c = col; c > 0 && c < grid->cols - 1 && accUtfIndexOffset < labs(utfIndexOffset); c += advance) {
        int rawIndex = row * grid->cols + c;

        if (advance < 0) {
            // If going backwards, we have to use the last character's length
            // instead, including walking back 2 chars if it happens to be a
            // wide char.
            rawIndex -= 1;
            if (c - 2 >= 0 && grid->cells[rawIndex - 1].textFlags & DRAW_WIDE) {
                c += advance;
                rawIndex -= 1;
            }
        }

        NSString *str = grid->cells[rawIndex].string;
        accUtfIndexOffset += str == nil ? 1 : str.length; // Note: nil string means empty space.

        if (advance > 0) {
            if (grid->cells[rawIndex].textFlags & DRAW_WIDE) {
                c += advance;
            }
        }
    }

    // Make sure nothing out of bounds happened due to some issue with wide-character skipping.
    if (c < 0)
        c = 0;
    if (c >= grid->cols)
        c = grid->cols - 1;

    return c;
}

/// Given a range of UTF-8 character indices, find the row/col of the beginning
/// of the range, and the end of the range *on the same line*. This doesn't
/// support searching for the end past the first line because there's no need
/// to right now. Sort of the reverse of utfCharIndexFromRowCol.
///
/// This assumes the text representation is a row-major representation of the
/// whole grid, with no newline/spaces to separate the lines.
///
/// @param row Return the starting character's row.
/// @param col Return the starting character's column.
/// @param firstLineNumCols Return the number of columns to the end character's
///        on the same line. If the end char is on the next line, then this
///        will just find the last column of the line.
/// @param firstLineUtf8Len Return the length of the characters on the first
///        line, in UTF-8 length.
static void rowColFromUtfRange(const Grid* grid, NSRange range,
                            int *row, int *col,
                            int *firstLineNumCols, int *firstLineUtf8Len)
{
    int startUtfIndex = -1;
    int outRow = -1;
    int outCol = -1;
    int outFirstLineNumCols = -1;
    int outFirstLineLen = -1;

    const int gridSize = grid->cols * grid->rows;
    int utfIndex = 0;
    for (int i = 0; i < gridSize; i++) {
        if (utfIndex >= (int)range.location) {
            // We are now past the start of the character.
            const int curRow = i / grid->cols;
            const int curCol = i % grid->cols;

            if (outRow == -1) {
                // Record the beginning
                startUtfIndex = utfIndex;
                outRow = curRow;
                outCol = curCol;
            }

            if (utfIndex >= (int)range.location + (int)range.length) {
                // Record the end if we found it.
                if (outFirstLineNumCols == -1) {
                    outFirstLineLen = utfIndex - startUtfIndex;
                    outFirstLineNumCols = curCol - outCol;
                }
                break;
            }

            if (curRow > outRow) {
                // We didn't find the end, but we are already at next line, so
                // just clamp it to the last column from the last line.
                outFirstLineLen = utfIndex - startUtfIndex;
                outFirstLineNumCols = grid->cols - outCol;
                break;
            }

        }

        NSString *str = grid->cells[i].string;
        utfIndex += str == nil ? 1 : (int)str.length; // Note: nil string means empty space.

        if (grid->cells[i].textFlags & DRAW_WIDE) {
            i += 1;
        }
    }

    if (outRow == -1)
    {
        *row = 0;
        *col = 1;
        *firstLineNumCols = 0;
        *firstLineUtf8Len = 0;
        return;
    }
    if (outFirstLineNumCols == -1)
    {
        outFirstLineLen = utfIndex - startUtfIndex;
        outFirstLineNumCols = grid->cols;
    }
    *row = outRow;
    *col = outCol;
    *firstLineNumCols = outFirstLineNumCols;
    *firstLineUtf8Len = outFirstLineLen;
}

- (nonnull NSArray<NSAttributedStringKey> *)validAttributesForMarkedText
{
    // Not implementing this for now. Properly implementing this would allow things like bolded underline
    // for certain texts in the marked range, etc, but we would need SetMarkedTextMsgID to support it.
    return @[];
}

/// Returns an attributed string containing the proposed range. This method is
/// usually called for two reasons:
/// 1. Input methods. It's unclear why the OS calls this during marked text
///    operation and returning nil doesn't seem to have any negative effect.
///    However, for operations like Hangul->Hanja (by pressing Option-Return),
///    it does rely on this after inserting the original Hangul text.
/// 2. Dictionary lookup. This is used for retrieving the formatted text that
///    the OS uses to look up and to show within the yellow box.
- (nullable NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange;
{
    // Because of Unicode / wide characters, we have to unfortunately loop through the entire text to
    // find the range. We could add better accelerated data structure here if for some reason this is
    // slow (it should only be called when inputting special / localized characters or when doing
    // quickLook lookup (e.g. Cmd-Ctrl-D). This step is important though or emojis and say Chinese
    // characters would not behave properly. See characterIndexForPoint which also does the same thing.

    if (range.length == 0) {
        return nil;
    }

    if ([helper hasMarkedText]) {
        // Since marked text changes the meaning of the text storage ranges (see above overall design),
        // just don't return anything for now. We could simply return the marked text if we want to and
        // have a need to do so.
        return nil;
    }

    NSMutableString *retStr = nil;
    NSUInteger utfIndex = 0;

    const int gridSize = grid.cols * grid.rows;
    for (int i = 0; i < gridSize; i++) {
        NSString *str = grid.cells[i].string;
        if (str == nil) {
            str = @" ";
        }

        if (utfIndex >= range.location) {
            if (retStr == nil) {
                // Lazily initialize the return string in case the passed in range is just completely
                // out of bounds.
                retStr = [NSMutableString stringWithCapacity:range.length];;
            }
            [retStr appendString:str];
        }
        if (retStr.length >= range.length) {
            break;
        }

        // Increment counters
        utfIndex += str.length;
        if (grid.cells[i].textFlags & DRAW_WIDE) {
            i += 1;
        }
    }

    if (retStr == nil) {
        return nil;
    }
    if (actualRange != NULL) {
        actualRange->length = retStr.length;
    }
    // Return an attributed string with the correct font so it will long right.
    // Note that this won't get us a perfect replica of the displayed texts,
    // but good enough. Some reasons why it's not perfect:
    // - Asian characters don't get displayed in double-width under OS
    //   rendering and will be narrower.
    // - We aren't passing through bold/italics/underline/strike-through/etc
    //   for now. This is probably ok. If we want to tackle this maybe just
    //   bold/underline is enough. Even NSTextView doesn't pass the
    //   underline/etc styles over, presumably because they make reading it
    //   hard.
    // - Font substitutions aren't handled the same way.
    return [[[NSAttributedString alloc] initWithString:retStr
                                            attributes:@{NSFontAttributeName: font}
            ] autorelease];
}

- (BOOL)hasMarkedText
{
    return [helper hasMarkedText];
}

- (NSRange)markedRange
{
    // This will return the range marked from 0 to size of marked text. See the
    // overall text input client implementation above for more description of
    // the design choice of handling marked text in this API.
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

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange;
{
    // We are not using replacementRange right now
    [helper setMarkedText:string selectedRange:selectedRange];
}

- (void)unmarkText
{
    [helper unmarkText];
}

/// Returns a character index to the overall text storage.
///
/// This is used mostly for quickLookWithEvent: calls for the OS to be able to
/// understand the textual content of this text input client.
- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
    // Not using convertPointFromScreen because it's 10.12+ only.
    NSRect screenRect = {point, NSZeroSize};
    NSPoint windowPt = [[self window] convertRectFromScreen:screenRect].origin;
    NSPoint viewPt = [self convertPoint:windowPt fromView:nil];
    int row, col;
    if (![self convertPoint:viewPt toRow:&row column:&col]) {
        return NSNotFound;
    }

    return utfCharIndexFromRowCol(&grid, row, col);
}

/// Returns the cursor location in the text storage. Note that the API is
/// supposed to return a range if there are selected texts, but since we don't
/// have access to the full text storage in MacVim (it requires IPC calls to
/// Vim), we just return the cursor with the range always having zero length.
/// This affects the quickLookWithEvent: implementation where we have to
/// manually handle the selected text case.
- (NSRange)selectedRange
{
    if ([helper hasMarkedText]) {
        // This returns the current cursor position relative to the marked
        // range, starting from 0. See above overall comments on text input
        // client implementation for marked text API decision.
        return [helper imRange];
    }

    // Find the character index.
    int row = [helper preEditRow];
    int col = [helper preEditColumn];
    NSUInteger charIndex = utfCharIndexFromRowCol(&grid, row, col);

    // We don't support selected texts for now, so always return length = 0;
    NSRange result = {charIndex, 0};
    return result;
}

/// Return the first line's rectangle for a range of characters. This is
/// usually called either during marked text operation to decide where to show
/// a candidate list, or when doing dictionary lookup and the UI wants to draw
/// a box right on top of this text seamlessly.
///
/// @param range The range to show rect for. Note that during marked text
///        operation, this could be different from imRange. For example, when using
///        Japanese input to input a long line of text, the user could use
///        left/right arrow keys to jump to different section of the
///        in-progress phrase and pick a new candidate. When doing that, this
///        will get called with different range's in order to show the
///        candidate list box right below the current section under
///        consideration.
/// @param actualRange The actual range this rect represents. Only used for
///        non-marked text situations for now.
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange
{
    if ([helper hasMarkedText]) {
        // Marked texts have special handling (see above overall comments for
        // marked text API design).

        // Because we just expose the range as 0 to marked length, the range
        // here doesn't represent the final screen position. Instead, we use
        // the current cursor position as basis. We know that during marked
        // text operations it has to be inside the marked range as specified by
        // setMarkedText's range.
        const int cursorRow = [helper preEditRow];
        const int cursorCol = [helper preEditColumn];

        // Now, we retrieve the IM range that setMarkedText gave us, and
        // compare with what the OS wants now (range). Find the rectangle
        // surrounding that.
        const NSRange imRange = [helper imRange];
        const NSInteger startIndexOffset = range.location - imRange.location;
        const NSInteger endIndexOffset = range.location + range.length - imRange.location;

        const int rectBeginCol = colFromUtfOffset(&grid, cursorRow, cursorCol, startIndexOffset);
        const int rectEndCol = colFromUtfOffset(&grid, cursorRow, cursorCol, endIndexOffset);

        return [helper firstRectForCharacterRange:cursorRow column:rectBeginCol length:(rectEndCol - rectBeginCol)];
    } else {
        int row = 0, col = 0, firstLineNumCols = 0, firstLineUtf8Len = 0;
        rowColFromUtfRange(&grid, range, &row, &col, &firstLineNumCols, &firstLineUtf8Len);
        if (actualRange != NULL) {
            actualRange->location = range.location;
            actualRange->length = firstLineUtf8Len;
        }
        return [helper firstRectForCharacterRange:row column:col length:firstLineNumCols];
    }
}

/// Optional function in text input client. Returns the proper baseline delta
/// for the returned rect. We need to do this because we take the ceil() of
/// fontDescent, which subtly changes the baseline relative to what the OS thinks,
/// and would have resulted in a slightly offset text under certain fonts/sizes.
- (CGFloat)baselineDeltaForCharacterAtIndex:(NSUInteger)anIndex
{
    // Note that this function is calculated top-down, so we need to subtract from height.
    return cellSize.height - fontDescent;
}

#pragma endregion // Text Input Client

/// Perform data lookup. This gets called by the OS when the user uses
/// Ctrl-Cmd-D or the trackpad to look up data.
///
/// This implementation will default to using the OS's implementation,
/// but also perform special checking for selected text, and perform data
/// detection for URLs, etc.
- (void)quickLookWithEvent:(NSEvent *)event
{
    // The default implementation would query using the NSTextInputClient API
    // which works fine.
    //
    // However, by default, if there are texts that are selected, *and* the
    // user performs lookup when the mouse is on top of said selected text, the
    // OS will use that for the lookup instead. E.g. if the user has selected
    // "ice cream" and perform a lookup on it, the lookup will be "ice cream"
    // instead of "ice" or "cream". We need to implement this in a custom
    // fashion because our `selectedRange` implementation doesn't properly
    // return the selected text (which we cannot do easily since our text
    // storage isn't representative of the Vim's internal buffer, see above
    // design notes), by querying Vim for the selected text manually.
    //
    // Another custom implementation we do is by first feeding the data through
    // an NSDataDetector first. This helps us catch URLs, addresses, and so on.
    // Otherwise for an URL, it will not include the whole https:// part and
    // won't show a web page. Note that NSTextView/WebKit/etc all use an
    // internal API called Reveal which does this for free and more powerful,
    // but we don't have access to that as a third-party software that
    // implements a custom text view.

    const NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
    int row = 0, col = 0;
    if ([self convertPoint:pt toRow:&row column:&col]) {
        // 1. If we have selected text. Proceed to see if the mouse is directly on
        // top of said selection and if so, show definition of that instead.
        MMVimController *vc = [self vimController];
        id<MMBackendProtocol> backendProxy = [vc backendProxy];
        if ([backendProxy selectedTextToPasteboard:nil]) {
            int selRow = 0, selCol = 0;
            const BOOL isMouseInSelection = [backendProxy mouseScreenposIsSelection:row column:col selRow:&selRow selCol:&selCol];

            if (isMouseInSelection) {
                NSString *selectedText = [backendProxy selectedText];
                if (selectedText) {
                    NSAttributedString *attrText = [[[NSAttributedString alloc] initWithString:selectedText
                                                                                    attributes:@{NSFontAttributeName: font}
                                                    ] autorelease];

                    const NSRect selRect = [self rectForRow:selRow
                                                     column:selCol
                                                    numRows:1
                                                 numColumns:1];

                    NSPoint baselinePt = selRect.origin;
                    baselinePt.y += fontDescent;

                    // We have everything we need. Just show the definition and return.
                    [self showDefinitionForAttributedString:attrText atPoint:baselinePt];
                    return;
                }
            }
        }

        // 2. Check if we have specialized data. Honestly the OS should really do this
        // for us as we are just calling text input client APIs here.
        const NSUInteger charIndex = utfCharIndexFromRowCol(&grid, row, col);
        NSTextCheckingTypes checkingTypes = NSTextCheckingTypeAddress
                                            | NSTextCheckingTypeLink
                                            | NSTextCheckingTypePhoneNumber;
                                            // | NSTextCheckingTypeDate // Date doesn't really work for showDefinition without private APIs
                                            // | NSTextCheckingTypeTransitInformation // Flight info also doesn't work without private APIs
        NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:checkingTypes error:nil];
        if (detector != nil) {
            // Just check [-100,100) around the mouse cursor. That should be more than enough to find interesting information.
            const NSUInteger rangeSize = 100;
            const NSUInteger rangeOffset = charIndex > rangeSize ? rangeSize : charIndex;
            const NSRange checkRange = NSMakeRange(charIndex - rangeOffset, charIndex + rangeSize * 2);

            NSAttributedString *attrStr = [self attributedSubstringForProposedRange:checkRange actualRange:nil];

            __block NSUInteger count = 0;
            __block NSRange foundRange = NSMakeRange(0, 0);
            [detector enumerateMatchesInString:attrStr.string
                                       options:0
                                         range:NSMakeRange(0, attrStr.length)
                                    usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop){
                if (++count >= 30) {
                    // Sanity checking
                    *stop = YES;
                }

                NSRange matchRange = [match range];
                if (!NSLocationInRange(rangeOffset, matchRange)) {
                    // We found something interesting nearby, but it's not where the mouse cursor is, just move on.
                    return;
                }
                if (match.resultType == NSTextCheckingTypeLink) {
                    foundRange = matchRange;
                    *stop = YES; // URL is highest priority, so we always terminate.
                } else if (match.resultType == NSTextCheckingTypePhoneNumber || match.resultType == NSTextCheckingTypeAddress) {
                    foundRange = matchRange;
                }
            }];

            if (foundRange.length != 0) {
                // We found something interesting! Show that instead of going through the default OS behavior.
                NSUInteger startIndex = charIndex + foundRange.location - rangeOffset;

                int row = 0, col = 0, firstLineNumCols = 0, firstLineUtf8Len = 0;
                rowColFromUtfRange(&grid, NSMakeRange(startIndex, 0), &row, &col, &firstLineNumCols, &firstLineUtf8Len);
                const NSRect rectToShow = [self rectForRow:row
                                                    column:col
                                                   numRows:1
                                                numColumns:1];

                NSPoint baselinePt = rectToShow.origin;
                baselinePt.y += fontDescent;

                [self showDefinitionForAttributedString:attrStr
                                                  range:foundRange
                                                options:@{}
                                 baselineOriginProvider:^NSPoint(NSRange adjustedRange) {
                    return baselinePt;
                }];
                return;
            }
        }
    }

    // Just call the default implementation, which will call misc
    // NSTextInputClient methods on us and use that to determine what/where to
    // show.
    [super quickLookWithEvent:event];
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

/// Set Vim's cmdline row number. This will mark the relevant parts to be repainted
/// if the row number has changed as we are pinning the cmdline to the bottom,
/// because otherwise we will have a gap that doesn't get cleared and leaves artifacts.
///
/// @param row The row (0-indexed) of the current cmdline in Vim.
- (void)setCmdlineRow:(int)row
{
    const BOOL newAlignCmdLineToBottom = [[NSUserDefaults standardUserDefaults] boolForKey:MMCmdLineAlignBottomKey];

    if (newAlignCmdLineToBottom != alignCmdLineToBottom) {
        // The user settings has changed (usually through the settings panel). Just update everything.
        alignCmdLineToBottom = newAlignCmdLineToBottom;
        cmdlineRow = row;
        [self setNeedsDisplay:YES];
        return;
    }

    if (row != cmdlineRow) {
        // The cmdline row has changed. Need to redraw the necessary parts if we
        // are configured to pin cmdline to the bottom.
        if (alignCmdLineToBottom) {
            // Since we are changing the cmdline row, we need to repaint the
            // parts where the gap changed. Just for simplicity, we repaint
            // both the old/new cmdline rows and the row above them. This way
            // the gap in between the top and bottom aligned rows should be
            // touched in the repainting and cleared to bg.
            [self setNeedsDisplayFromRow:cmdlineRow-1
                                  column:grid.cols
                                   toRow:cmdlineRow
                                  column:grid.cols];

            // Have to do this between the two calls as cmdlineRow would affect
            // the calculation in them.
            cmdlineRow = row;

            [self setNeedsDisplayFromRow:cmdlineRow-1
                                  column:grid.cols
                                   toRow:cmdlineRow
                                  column:grid.cols];
        } else {
            cmdlineRow = row;
        }
    }
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

    // Update the cmdline rows to decide if we need to update based on whether we are pinning cmdline to bottom or not.
    [self updateCmdlineRow];

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
    __block int cells_filled = 0;
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
    for (int r = row; r + count <= MIN(grid.rows - 1, bottom); r++) {
        memcpy(grid_cell(&grid, r, left),
               grid_cell(&grid, r + count, left),
               sizeof(GridCell) * (MIN(grid.cols, right + 1) - MIN(grid.cols, left)));
    }
    const GridCell clearCell = { .bg = color };
    for (int r = bottom - count + 1; r <= MIN(grid.rows - 1, bottom); r++) {
        for (int c = left; c <= MIN(grid.cols - 1, right); c++)
            *grid_cell(&grid, r, c) = clearCell;
    }
    [self setNeedsDisplayFromRow:row column:left toRow:bottom column:right];
}

- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(int)color
{
    for (int r = MIN(grid.rows - 1, bottom); r >= row + count; r--) {
        memcpy(grid_cell(&grid, r, left),
               grid_cell(&grid, r - count, left),
               sizeof(GridCell) * (MIN(grid.cols, right + 1) - MIN(grid.cols, left)));
    }
    const GridCell clearCell = { .bg = color };
    for (int r = row; r < MIN(grid.rows, row + count); r++) {
        for (int c = left; c <= right; c++)
            *grid_cell(&grid, r, c) = clearCell;
    }
    [self setNeedsDisplayFromRow:row column:left toRow:bottom column:right];
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(int)color
{
    const GridCell clearCell = { .bg = color };
    for (int r = row1; r <= row2; r++) {
        for (int c = col1; c <= col2; c++)
            *grid_cell_safe(&grid, r, c) = clearCell;
    }
    [self setNeedsDisplayFromRow:row1 column:col1 toRow:row2 column:col2];
}

- (void)clearAll
{
    const GridCell clearCell = { .bg = defaultBackgroundColor.argbInt };
    for (int r = 0; r < maxRows; r++) {
        for (int c = 0; c < maxColumns; c++)
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
    for (int r = row; r < row + nrows; r++) {
        for (int c = col; c < col + ncols; c++) {
            grid_cell_safe(&grid, r, c)->inverted ^= 1;
        }
    }
    [self setNeedsDisplayFromRow:row column:col toRow:row + nrows column:col + ncols];
}

@end // MMCoreTextView (Drawing)
