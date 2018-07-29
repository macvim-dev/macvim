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
 * MMTextView
 *
 * Dispatches keyboard and mouse input to the backend.  Handles drag-n-drop of
 * files onto window.
 *
 * Support for input managers is somewhat hacked together.  Marked text is
 * drawn "pseudo-inline"; it will simply draw on top of existing text and it
 * does not respect Vim-window boundaries.
 */

#import "MMAppController.h"
#import "MMTextStorage.h"
#import "MMTextView.h"
#import "MMTextViewHelper.h"
#import "MMTypesetter.h"
#import "MMVimController.h"
#import "MMWindowController.h"
#import "Miscellaneous.h"



// This is taken from gui.h
#define DRAW_CURSOR 0x20



@interface MMTextView (Private)
- (MMWindowController *)windowController;
- (MMVimController *)vimController;
- (void)setShouldDrawInsertionPoint:(BOOL)on;
- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                       fraction:(int)percent;
- (void)drawInvertedRectAtRow:(int)row column:(int)col numRows:(int)nrows
                   numColumns:(int)ncols invert:(int)invert;
@end



@implementation MMTextView

- (id)initWithFrame:(NSRect)frame
{
    // Set up a Cocoa text system.  Note that the textStorage is released in
    // -[MMVimView dealloc].
    MMTextStorage *textStorage = [[MMTextStorage alloc] init];
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    NSTextContainer *tc = [[NSTextContainer alloc] initWithContainerSize:
                    NSMakeSize(1.0e7,1.0e7)];

    NSString *typesetterString = [[NSUserDefaults standardUserDefaults]
            stringForKey:MMTypesetterKey];
    if ([typesetterString isEqual:@"MMTypesetter"]) {
        NSTypesetter *typesetter = [[MMTypesetter alloc] init];
        [lm setTypesetter:typesetter];
        [typesetter release];
#if MM_USE_ROW_CACHE
    } else if ([typesetterString isEqual:@"MMTypesetter2"]) {
        NSTypesetter *typesetter = [[MMTypesetter2 alloc] init];
        [lm setTypesetter:typesetter];
        [typesetter release];
#endif // MM_USE_ROW_CACHE
    } else {
        // Only MMTypesetter supports different cell width multipliers.
        [[NSUserDefaults standardUserDefaults]
                setFloat:1.0 forKey:MMCellWidthMultiplierKey];
    }

    // The characters in the text storage are in display order, so disable
    // bidirectional text processing (this call is 10.4 only).
    [[lm typesetter] setBidiProcessingEnabled:NO];

    [tc setWidthTracksTextView:NO];
    [tc setHeightTracksTextView:NO];
    [tc setLineFragmentPadding:0];

    [textStorage addLayoutManager:lm];
    [lm addTextContainer:tc];

    // The text storage retains the layout manager which in turn retains
    // the text container.
    [tc autorelease];
    [lm autorelease];

    // NOTE: This will make the text storage the principal owner of the text
    // system.  Releasing the text storage will in turn release the layout
    // manager, the text container, and finally the text view (self).  This
    // complicates deallocation somewhat, see -[MMVimView dealloc].
    if (!(self = [super initWithFrame:frame textContainer:tc])) {
        [textStorage release];
        return nil;
    }

    helper = [[MMTextViewHelper alloc] init];
    [helper setTextView:self];

    // NOTE: If the default changes to 'NO' then the intialization of
    // p_antialias in option.c must change as well.
    antialias = YES;

    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    if (invertRects) {
        free(invertRects);
        invertRects = NULL;
        numInvertRects = 0;
    }

    [helper setTextView:nil];
    [helper release];  helper = nil;

    [super dealloc];
}

- (BOOL)shouldDrawInsertionPoint
{
    // NOTE: The insertion point is drawn manually in drawRect:.  It would be
    // nice to be able to use the insertion point related methods of
    // NSTextView, but it seems impossible to get them to work properly (search
    // the cocoabuilder archives).
    return NO;
}

- (void)setPreEditRow:(int)row column:(int)col
{
    [helper setPreEditRow:row column:col];
}

#define MM_DEBUG_DRAWING 0

- (void)performBatchDrawWithData:(NSData *)data
{
    MMTextStorage *textStorage = (MMTextStorage *)[self textStorage];
    if (!textStorage)
        return;

    const void *bytes = [data bytes];
    const void *end = bytes + [data length];
    int cursorRow = -1, cursorCol = 0;

#if MM_DEBUG_DRAWING
    ASLogDebug(@"====> BEGIN %s", _cmd);
#endif
    [textStorage beginEditing];

    // TODO: Sanity check input

    while (bytes < end) {
        int type = *((int*)bytes);  bytes += sizeof(int);

        if (ClearAllDrawType == type) {
#if MM_DEBUG_DRAWING
            ASLogDebug(@"   Clear all");
#endif
            [textStorage clearAll];
        } else if (ClearBlockDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row1 = *((int*)bytes);  bytes += sizeof(int);
            int col1 = *((int*)bytes);  bytes += sizeof(int);
            int row2 = *((int*)bytes);  bytes += sizeof(int);
            int col2 = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogDebug(@"   Clear block (%d,%d) -> (%d,%d)", row1, col1,
                       row2,col2);
#endif
            [textStorage clearBlockFromRow:row1 column:col1
                    toRow:row2 column:col2
                    color:[NSColor colorWithArgbInt:color]];
        } else if (DeleteLinesDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogDebug(@"   Delete %d line(s) from %d", count, row);
#endif
            [textStorage deleteLinesFromRow:row lineCount:count
                    scrollBottom:bot left:left right:right
                           color:[NSColor colorWithArgbInt:color]];
        } else if (DrawStringDrawType == type) {
            int bg = *((int*)bytes);  bytes += sizeof(int);
            int fg = *((int*)bytes);  bytes += sizeof(int);
            int sp = *((int*)bytes);  bytes += sizeof(int);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int cells = *((int*)bytes);  bytes += sizeof(int);
            int flags = *((int*)bytes);  bytes += sizeof(int);
            int len = *((int*)bytes);  bytes += sizeof(int);
            NSString *string = [[NSString alloc]
                    initWithBytes:(void*)bytes length:len
                         encoding:NSUTF8StringEncoding];
            bytes += len;

#if MM_DEBUG_DRAWING
            ASLogDebug(@"   Draw string at (%d,%d) length=%d flags=%d fg=0x%x "
                       "bg=0x%x sp=0x%x (%@)", row, col, len, flags, fg, bg, sp,
                       len > 0 ? [string substringToIndex:1] : @"");
#endif
            // NOTE: If this is a call to draw the (block) cursor, then cancel
            // any previous request to draw the insertion point, or it might
            // get drawn as well.
            if (flags & DRAW_CURSOR)
                [self setShouldDrawInsertionPoint:NO];

            [textStorage drawString:string
                              atRow:row column:col cells:cells
                          withFlags:flags
                    foregroundColor:[NSColor colorWithRgbInt:fg]
                    backgroundColor:[NSColor colorWithArgbInt:bg]
                       specialColor:[NSColor colorWithRgbInt:sp]];

            [string release];
        } else if (InsertLinesDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogDebug(@"   Insert %d line(s) at row %d", count, row);
#endif
            [textStorage insertLinesAtRow:row lineCount:count
                             scrollBottom:bot left:left right:right
                                    color:[NSColor colorWithArgbInt:color]];
        } else if (DrawCursorDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int shape = *((int*)bytes);  bytes += sizeof(int);
            int percent = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogDebug(@"   Draw cursor at (%d,%d)", row, col);
#endif
            [helper setInsertionPointColor:[NSColor colorWithRgbInt:color]];
            [self drawInsertionPointAtRow:row column:col shape:shape
                                 fraction:percent];
        } else if (DrawInvertedRectDrawType == type) {
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int nr = *((int*)bytes);  bytes += sizeof(int);
            int nc = *((int*)bytes);  bytes += sizeof(int);
            int invert = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            ASLogDebug(@"   Draw inverted rect: row=%d col=%d nrows=%d "
                       "ncols=%d", row, col, nr, nc);
#endif
            [self drawInvertedRectAtRow:row column:col numRows:nr numColumns:nc
                                 invert:invert];
        } else if (SetCursorPosDrawType == type) {
            cursorRow = *((int*)bytes);  bytes += sizeof(int);
            cursorCol = *((int*)bytes);  bytes += sizeof(int);
        } else {
            ASLogWarn(@"Unknown draw type (type=%d)", type);
        }
    }

    [textStorage endEditing];

    if (cursorRow >= 0) {
        unsigned off = [textStorage characterIndexForRow:cursorRow
                                                  column:cursorCol];
        unsigned maxoff = [[textStorage string] length];
        if (off > maxoff) off = maxoff;

        [self setSelectedRange:NSMakeRange(off, 0)];
    }

    // NOTE: During resizing, Cocoa only sends draw messages before Vim's rows
    // and columns are changed (due to ipc delays). Force a redraw here.
    if ([self inLiveResize])
        [self display];

#if MM_DEBUG_DRAWING
    ASLogDebug(@"<==== END   %s", _cmd);
#endif
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

- (NSFont *)font
{
    return [(MMTextStorage*)[self textStorage] font];
}

- (void)setFont:(NSFont *)newFont
{
    [(MMTextStorage*)[self textStorage] setFont:newFont];
}

- (NSFont *)fontWide
{
    return [(MMTextStorage*)[self textStorage] fontWide];
}

- (void)setWideFont:(NSFont *)newFont
{
    [(MMTextStorage*)[self textStorage] setWideFont:newFont];
}

- (NSSize)cellSize
{
    return [(MMTextStorage*)[self textStorage] cellSize];
}

- (void)setLinespace:(float)newLinespace
{
    return [(MMTextStorage*)[self textStorage] setLinespace:newLinespace];
}

- (void)setColumnspace:(float)newColumnspace
{
    return [(MMTextStorage*)[self textStorage] setColumnspace:newColumnspace];
}

- (int)maxRows
{
    MMTextStorage *ts = (MMTextStorage *)[self textStorage];
    return [ts maxRows];
}

- (int)maxColumns
{
    MMTextStorage *ts = (MMTextStorage *)[self textStorage];
    return [ts maxColumns];
}

- (void)getMaxRows:(int*)rows columns:(int*)cols
{
    return [(MMTextStorage*)[self textStorage] getMaxRows:rows columns:cols];
}

- (void)setMaxRows:(int)rows columns:(int)cols
{
    return [(MMTextStorage*)[self textStorage] setMaxRows:rows columns:cols];
}

- (NSRect)rectForRowsInRange:(NSRange)range
{
    return [(MMTextStorage*)[self textStorage] rectForRowsInRange:range];
}

- (NSRect)rectForColumnsInRange:(NSRange)range
{
    return [(MMTextStorage*)[self textStorage] rectForColumnsInRange:range];
}

- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor
{
    [self setBackgroundColor:bgColor];
    return [(MMTextStorage*)[self textStorage]
            setDefaultColorsBackground:bgColor foreground:fgColor];
}

- (NSColor *)defaultBackgroundColor
{
    return [(MMTextStorage*)[self textStorage] defaultBackgroundColor];
}

- (NSColor *)defaultForegroundColor
{
    return [(MMTextStorage*)[self textStorage] defaultForegroundColor];
}

- (NSSize)constrainRows:(int *)rows columns:(int *)cols toSize:(NSSize)size
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    size.width -= [self textContainerOrigin].x + right;
    size.height -= [self textContainerOrigin].y + bot;

    NSSize newSize = [(MMTextStorage*)[self textStorage] fitToSize:size
                                                              rows:rows
                                                           columns:cols];

    newSize.width += [self textContainerOrigin].x + right;
    newSize.height += [self textContainerOrigin].y + bot;

    return newSize;
}

- (NSSize)desiredSize
{
    NSSize size = [(MMTextStorage*)[self textStorage] size];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    size.width += [self textContainerOrigin].x + right;
    size.height += [self textContainerOrigin].y + bot;

    return size;
}

- (NSSize)minSize
{
    NSSize cellSize = [(MMTextStorage*)[self textStorage] cellSize];
    NSSize size = { MMMinColumns*cellSize.width, MMMinRows*cellSize.height };

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    size.width += [self textContainerOrigin].x + right;
    size.height += [self textContainerOrigin].y + bot;

    return size;
}

- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column
{
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    NSSize cellSize = [ts cellSize];
    if (!(cellSize.width > 0 && cellSize.height > 0))
        return NO;
    NSPoint origin = [self textContainerOrigin];

    if (row) *row = floor((point.y-origin.y-1) / cellSize.height);
    if (column) *column = floor((point.x-origin.x-1) / cellSize.width);

    return YES;
}

- (NSPoint)pointForRow:(int)row column:(int)col
{
    // Return the upper-left coordinate for (row,column).
    // NOTE: The coordinate system is flipped!
    NSPoint pt = [self textContainerOrigin];
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    NSSize cellSize = [ts cellSize];

    pt.x += col * cellSize.width;
    pt.y += row * cellSize.height;

    return pt;
}

- (NSRect)rectForRow:(int)row column:(int)col numRows:(int)nr
          numColumns:(int)nc
{
    // Return the rect for the block which covers the specified rows and
    // columns.  The upper-left corner is the origin of this rect.
    // NOTE: The coordinate system is flipped!
    NSRect rect;
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    NSSize cellSize = [ts cellSize];

    rect.origin = [self textContainerOrigin];
    rect.origin.x += col * cellSize.width;
    rect.origin.y += row * cellSize.height;
    rect.size.width = cellSize.width * nc;
    rect.size.height = cellSize.height * nr;

    return rect;
}

- (void)deleteSign:(NSString *)signName
{
    // ONLY in Core Text!
}

- (void)setToolTipAtMousePoint:(NSString *)string
{
    // ONLY in Core Text!
}

- (void)setCGLayerEnabled:(BOOL)enabled
{
    // ONLY in Core Text!
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)drawRect:(NSRect)rect
{
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context setShouldAntialias:antialias];

    [super drawRect:rect];

    if (invertRects) {
        CGContextRef cgctx = (CGContextRef)[context graphicsPort];
        CGContextSaveGState(cgctx);
        CGContextSetBlendMode(cgctx, kCGBlendModeDifference);
        CGContextSetRGBFillColor(cgctx, 1.0, 1.0, 1.0, 1.0);

        int i;
        CGRect *rect = (CGRect*)invertRects;
        for (i = 0; i < numInvertRects; ++i)
            CGContextFillRect(cgctx, rect[i]);

        CGContextRestoreGState(cgctx);

        free(invertRects);
        invertRects = NULL;
        numInvertRects = 0;
    }

#ifdef INCLUDE_OLD_IM_CODE
    if ([self hasMarkedText] && ![helper useInlineIm]) {
        shouldDrawInsertionPoint = YES;
        MMTextStorage *ts = (MMTextStorage*)[self textStorage];
        NSSize inset = [self textContainerInset];

        // HACK! Get the baseline of the zeroth glyph and use that as the
        // baseline for the marked text.  (Is there a better way to figure out
        // what baseline NSTextView uses?)
        NSLayoutManager *lm = [self layoutManager];
        NSTypesetter *tsr = [lm typesetter];
        float baseline = [tsr baselineOffsetInLayoutManager:lm glyphIndex:0];

        // Also adjust for 'linespace' option (TODO: Why not .5*linespace?)
        baseline -= floor([ts linespace]);

        inset.height -= baseline;

        int len = [[helper markedText] length];
        // The following implementation should be re-written with
        // more efficient way...

        // Calculate how many wide-font characters can be inserted at
        // a first line, and draw those characters.
        int cols = ([ts actualColumns] - insertionPointColumn);
        NSFont *theFont = [[self markedTextAttributes]
                valueForKey:NSFontAttributeName];
        if (theFont == [ts fontWide])
            cols = cols / 2;
        int done = 0;
        int lend = cols > len ? len : cols;
        NSAttributedString *aString = [[helper markedText]
                attributedSubstringFromRange:NSMakeRange(done, lend)];
        [aString drawAtPoint:NSMakePoint(
                [helper preEditColumn]*[ts cellSize].width + inset.width,
                [helper preEditRow]*[ts cellSize].height + inset.height)];

        done = lend;
        // Check whether there're charecters that aren't drawn at
        // the first line. If everything is already done, the follow
        // check fails.
        if (done != len) {
            int r;
            // Calculate How many rows are needed to draw all the left
            // characters.
            int rows = (len - done) / ([ts actualColumns] / 2) + 1;
            for (r = 1; r <= rows; r++) {
                lend = len - done > [ts actualColumns] / 2
                        ? [ts actualColumns] / 2 : len - done;
                aString = [[helper markedText] attributedSubstringFromRange:
                        NSMakeRange(done, lend)];
                [aString drawAtPoint:NSMakePoint(
                        inset.width,
                        ([helper preEditRow] + r)*[ts cellSize].height
                            + inset.height)];
                done += lend;
            }
        }
    }
#endif // INCLUDE_OLD_IM_CODE

    if (shouldDrawInsertionPoint) {
        MMTextStorage *ts = (MMTextStorage*)[self textStorage];

        NSRect ipRect = [ts boundingRectForCharacterAtRow:[helper preEditRow]
                                                   column:[helper preEditColumn]];
        ipRect.origin.x += [self textContainerOrigin].x;
        ipRect.origin.y += [self textContainerOrigin].y;

#ifdef INCLUDE_OLD_IM_CODE
        // Draw insertion point inside marked text.
        if ([self hasMarkedText] && ![helper useInlineIm]) {
            NSFont *theFont = [[self markedTextAttributes]
                    valueForKey:NSFontAttributeName];
            if (theFont == [ts font])
                ipRect.origin.x += [ts cellSize].width *
                                   ([helper imRange].location +
                                   [helper imRange].length);
            else
                ipRect.origin.x += [ts cellSize].width * 2 *
                                   ([helper imRange].location +
                                   [helper imRange].length);
        }
#endif // INCLUDE_OLD_IM_CODE

        if (MMInsertionPointHorizontal == insertionPointShape) {
            int frac = ([ts cellSize].height * insertionPointFraction + 99)/100;
            ipRect.origin.y += ipRect.size.height - frac;
            ipRect.size.height = frac;
        } else if (MMInsertionPointVertical == insertionPointShape) {
            int frac = ([ts cellSize].width * insertionPointFraction + 99)/100;
            ipRect.size.width = frac;
        } else if (MMInsertionPointVerticalRight == insertionPointShape) {
            int frac = ([ts cellSize].width * insertionPointFraction + 99)/100;
            ipRect.origin.x += ipRect.size.width - frac;
            ipRect.size.width = frac;
        }

        [[helper insertionPointColor] set];
        if (MMInsertionPointHollow == insertionPointShape) {
            NSFrameRect(ipRect);
        } else {
            NSRectFill(ipRect);
        }

        // NOTE: We only draw the cursor once and rely on Vim to say when it
        // should be drawn again.
        shouldDrawInsertionPoint = NO;
    }

#if 0
    // this code invalidates the shadow, so we don't 
    // get shifting ghost text on scroll and resize
    // but makes speed unusable
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    if ([ts defaultBackgroundAlpha] < 1.0f) {
        if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_1)
        {
            [[self window] setHasShadow:NO];
            [[self window] setHasShadow:YES];
        }
        else
            [[self window] invalidateShadow];

    }
#endif
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

- (NSRect)firstRectForCharacterRange:(NSRange)range
{
    return [helper firstRectForCharacterRange:range];
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
    // HACK! Return nil to disable NSTextView's popup menus (Vim provides its
    // own).  Called when user Ctrl-clicks in the view (this is already handled
    // in rightMouseDown:).
    return nil;
}

- (NSArray *)acceptableDragTypes
{
    return [NSArray arrayWithObjects:NSFilenamesPboardType,
           NSStringPboardType, nil];
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

- (void)changeFont:(id)sender
{
    [helper changeFont:sender];
}

- (void)resetCursorRects
{
    // No need to set up cursor rects since Vim handles cursor changes.
}

- (void)updateFontPanel
{
    // The font panel is updated whenever the font is set.
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

- (IBAction)cancelOperation:(id)sender
{
    // NSTextView overrides this method to send complete:, whereas NSResponder
    // sends cancel: by default.  So override it yet again to revert to the
    // default behavior (we resond to cancel: in MMTextViewHelper).
    [self doCommandBySelector:@selector(cancel:)];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(cut:)
            || [item action] == @selector(copy:)
            || [item action] == @selector(paste:)
            || [item action] == @selector(undo:)
            || [item action] == @selector(redo:)
            || [item action] == @selector(selectAll:))
        return [item tag];

    return YES;
}

@end // MMTextView




@implementation MMTextView (Private)

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

- (void)setShouldDrawInsertionPoint:(BOOL)on
{
    shouldDrawInsertionPoint = on;
}

- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                       fraction:(int)percent
{
    // This only stores where to draw the insertion point, the actual drawing
    // is done in drawRect:.
    shouldDrawInsertionPoint = YES;
    insertionPointRow = row;
    insertionPointColumn = col;
    insertionPointShape = shape;
    insertionPointFraction = percent;
}

- (void)drawInvertedRectAtRow:(int)row column:(int)col numRows:(int)nrows
                   numColumns:(int)ncols invert:(int)invert
{
    if (invert) {
        // The result should be inverted.
        int n = numInvertRects++;
        invertRects = reallocf(invertRects,
                               numInvertRects*sizeof(NSRect));
        if (NULL != invertRects) {
            invertRects[n] = [self rectForRow:row column:col numRows:nrows
                                   numColumns:ncols];
            [self setNeedsDisplayInRect:invertRects[n]];
        } else {
            numInvertRects = 0;
        }
    } else {
        // The result should look normal; all we need to do is to mark
        // the rect for redrawing and Cocoa will redraw the text.
        NSRect rect = [self rectForRow:row column:col numRows:nrows
                            numColumns:ncols];
        [self setNeedsDisplayInRect:rect];
    }
}

@end // MMTextView (Private)
