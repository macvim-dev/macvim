/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMTextStorage.h"

// If 0 DRAW_TRANSP flag will be ignored.  Setting it to 1 causes the cursor
// background to be drawn in white.
#define HEED_DRAW_TRANSP 0

#define DRAW_TRANSP               0x01    /* draw with transparant bg */
#define DRAW_BOLD                 0x02    /* draw bold text */
#define DRAW_UNDERL               0x04    /* draw underline text */
#define DRAW_UNDERC               0x08    /* draw undercurl text */
#define DRAW_ITALIC               0x10    /* draw italic text */


//static float LINEHEIGHT = 30.0f;

#define MM_SIMPLE_TS_CALC 1

#if MM_TS_LAZY_SET
# define MM_SIMPLE_TS_CALC 1
#endif


@interface MMTextStorage (Private)
#if MM_TS_LAZY_SET
- (void)doSetMaxRows:(int)rows columns:(int)cols;
- (void)lazyResize;
#endif
- (float)cellWidth;
- (float)widthOfEmptyRow;
@end



@implementation MMTextStorage

- (id)init
{
    if ((self = [super init])) {
        attribString = [[NSMutableAttributedString alloc] initWithString:@""];
        // NOTE!  It does not matter which font is set here, Vim will set its
        // own font on startup anyway.
        font = [[NSFont userFixedPitchFontOfSize:0] retain];

#if 0
        paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        [paragraphStyle setMinimumLineHeight:LINEHEIGHT];
        [paragraphStyle setMaximumLineHeight:LINEHEIGHT];
        [paragraphStyle setLineSpacing:0];
#endif
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);

    [emptyRowString release];
    //[paragraphStyle release];
    [font release];
    [defaultBackgroundColor release];
    [attribString release];
    [super dealloc];
}

- (NSString *)string
{
    //NSLog(@"%s : attribString=%@", _cmd, attribString);
    return [attribString string];
}

- (NSDictionary *)attributesAtIndex:(unsigned)index
                     effectiveRange:(NSRangePointer)aRange
{
    //NSLog(@"%s", _cmd);
    if (index>=[attribString length]) {
        //NSLog(@"%sWARNING: index (%d) out of bounds", _cmd, index);
        if (aRange) {
            *aRange = NSMakeRange(NSNotFound, 0);
        }
        return [NSDictionary dictionary];
    }

    return [attribString attributesAtIndex:index effectiveRange:aRange];
}

- (void)replaceCharactersInRange:(NSRange)aRange
                      withString:(NSString *)aString
{
    //NSLog(@"replaceCharactersInRange:(%d,%d) withString:%@", aRange.location,
    //        aRange.length, aString);
    NSLog(@"WARNING: calling %s on MMTextStorage is unsupported", _cmd);
    //[attribString replaceCharactersInRange:aRange withString:aString];
}

- (void)setAttributes:(NSDictionary *)attributes range:(NSRange)aRange
{
    // NOTE!  This method must be implemented since the text system calls it
    // constantly to 'fix attributes', apply font substitution, etc.
    [attribString setAttributes:attributes range:aRange];
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
#if MM_TS_LAZY_SET
    maxRows = rows;
    maxColumns = cols;
#else
    [self doSetMaxRows:rows columns:cols];
#endif
}

- (void)replaceString:(NSString*)string atRow:(int)row column:(int)col
        withFlags:(int)flags foregroundColor:(NSColor*)fg
        backgroundColor:(NSColor*)bg
{
    //NSLog(@"replaceString:atRow:%d column:%d withFlags:%d", row, col, flags);
    [self lazyResize];

    if (row < 0 || row >= maxRows || col < 0 || col >= maxColumns
            || col+[string length] > maxColumns) {
        //NSLog(@"[%s] WARNING : out of range, row=%d (%d) col=%d (%d) "
        //        "length=%d (%d)", _cmd, row, maxRows, col, maxColumns,
        //        [string length], [attribString length]);
        return;
    }

    if (!(fg && bg)) {
        NSLog(@"[%s] WARNING: background or foreground color not specified",
                _cmd);
        return;
    }

    NSRange range = NSMakeRange(col+row*(maxColumns+1), [string length]);
    [attribString replaceCharactersInRange:range withString:string];

    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            //paragraphStyle, NSParagraphStyleAttributeName,
#if !HEED_DRAW_TRANSP
            bg, NSBackgroundColorAttributeName,
#endif
            fg, NSForegroundColorAttributeName, nil];
    [attribString setAttributes:attributes range:range];

#if HEED_DRAW_TRANSP
    if ( !(flags & DRAW_TRANSP) ) {
        [attribString addAttribute:NSBackgroundColorAttributeName value:bg
                range:range];
    }
#endif

    // TODO: cache bold font and apply in setAttributes:range:
    if (flags & DRAW_BOLD) {
        [attribString applyFontTraits:NSBoldFontMask range:range];
    }

    // TODO: cache italic font and apply in setAttributes:range:
    if (flags & DRAW_ITALIC) {
        [attribString applyFontTraits:NSItalicFontMask range:range];
    }

    if (flags & DRAW_UNDERL) {
        NSNumber *value = [NSNumber numberWithInt:(NSUnderlineStyleSingle
                | NSUnderlinePatternSolid)]; // | NSUnderlineByWordMask
        [attribString addAttribute:NSUnderlineStyleAttributeName
                value:value range:range];
    }

    // TODO: figure out how do draw proper undercurls
    if (flags & DRAW_UNDERC) {
        NSNumber *value = [NSNumber numberWithInt:(NSUnderlineStyleThick
                | NSUnderlinePatternDot)]; // | NSUnderlineByWordMask
        [attribString addAttribute:NSUnderlineStyleAttributeName
                value:value range:range];
    }

#if 0
    [attribString addAttribute:NSParagraphStyleAttributeName
                         value:paragraphStyle
                         range:NSMakeRange(0, [attribString length])];
#endif

    [self edited:(NSTextStorageEditedCharacters|NSTextStorageEditedAttributes)
           range:range changeInLength:0];
}

/*
 * Delete 'count' lines from 'row' and insert 'count' empty lines at the bottom
 * of the scroll region.
 */
- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(NSColor *)color
{
    //NSLog(@"deleteLinesFromRow:%d lineCount:%d", row, count);
    [self lazyResize];

    if (row < 0 || row+count > maxRows) {
        //NSLog(@"[%s] WARNING : out of range, row=%d (%d) count=%d", _cmd, row,
        //        maxRows, count);
        return;
    }

    int total = 1 + bottom - row;
    int move = total - count;
    int width = right - left + 1;
    NSRange destRange = { row*(maxColumns+1) + left, width };
    NSRange srcRange = { (row+count)*(maxColumns+1) + left, width };
    int i;

    for (i = 0; i < move; ++i) {
        NSAttributedString *srcString = [attribString
                attributedSubstringFromRange:srcRange];
        [attribString replaceCharactersInRange:destRange
                          withAttributedString:srcString];
        [self edited:(NSTextStorageEditedCharacters
                | NSTextStorageEditedAttributes)
                range:destRange changeInLength:0];
        destRange.location += maxColumns+1;
        srcRange.location += maxColumns+1;
    }

    for (i = 0; i < count; ++i) {
        NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                color, NSForegroundColorAttributeName,
                color, NSBackgroundColorAttributeName, nil];
        [attribString setAttributes:attribs range:destRange];
        [self edited:NSTextStorageEditedAttributes range:destRange
                changeInLength:0];
        destRange.location += maxColumns+1;
    }
}

/*
 * Insert 'count' empty lines at 'row' and delete 'count' lines from the bottom
 * of the scroll region.
 */
- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(NSColor *)color
{
    //NSLog(@"insertLinesAtRow:%d lineCount:%d", row, count);
    [self lazyResize];

    if (row < 0 || row+count > maxRows) {
        //NSLog(@"[%s] WARNING : out of range, row=%d (%d) count=%d", _cmd, row,
        //        maxRows, count);
        return;
    }

    int total = 1 + bottom - row;
    int move = total - count;
    int width = right - left + 1;
    NSRange destRange = { bottom*(maxColumns+1) + left, width };
    NSRange srcRange = { (row+move-1)*(maxColumns+1) + left, width };
    int i;

    for (i = 0; i < move; ++i) {
        NSAttributedString *srcString = [attribString
                attributedSubstringFromRange:srcRange];
        [attribString replaceCharactersInRange:destRange
                          withAttributedString:srcString];
        [self edited:(NSTextStorageEditedCharacters
                | NSTextStorageEditedAttributes)
                range:destRange changeInLength:0];
        destRange.location -= maxColumns+1;
        srcRange.location -= maxColumns+1;
    }

    for (i = 0; i < count; ++i) {
        NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                color, NSForegroundColorAttributeName,
                color, NSBackgroundColorAttributeName, nil];
        [attribString setAttributes:attribs range:destRange];
        [self edited:NSTextStorageEditedAttributes range:destRange
                changeInLength:0];
        destRange.location -= maxColumns+1;
    }
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(NSColor *)color
{
    //NSLog(@"clearBlockFromRow:%d column:%d toRow:%d column:%d", row1, col1,
    //        row2, col2);
    [self lazyResize];

    if (row1 < 0 || row2 >= maxRows || col1 < 0 || col2 > maxColumns) {
        //NSLog(@"[%s] WARNING : out of range, row1=%d row2=%d (%d) col1=%d "
        //        "col2=%d (%d)", _cmd, row1, row2, maxRows, col1, col2,
        //        maxColumns);
        return;
    }

    NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            color, NSForegroundColorAttributeName,
            color, NSBackgroundColorAttributeName, nil];

    NSRange range = { row1*(maxColumns+1) + col1, col2-col1+1 };

    int r;
    for (r=row1; r<=row2; ++r) {
        [attribString setAttributes:attribs range:range];
        [self edited:NSTextStorageEditedAttributes range:range
                changeInLength:0];
        range.location += maxColumns+1;
    }
}

- (void)clearAllWithColor:(NSColor *)color
{
    //NSLog(@"%s%@", _cmd, color);

    NSRange range = { 0, [attribString length] };
    NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            color, NSForegroundColorAttributeName,
            color, NSBackgroundColorAttributeName, nil];
    [attribString setAttributes:attribs range:range];
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor
{
    // NOTE: Foreground color is ignored.
    [defaultBackgroundColor release];

#if 0
    if (bgColor) {
        defaultBackgroundColor = [bgColor retain];
#if 1
        NSMutableAttributedString *string = [emptyRowString mutableCopy];
        [string addAttribute:NSBackgroundColorAttributeName value:bgColor
                       range:NSMakeRange(0, [emptyRowString length])];
        [emptyRowString release];
        emptyRowString = string;
#endif
        [self clearAllWithColor:bgColor];
    } else {
        defaultBackgroundColor = nil;
    }
#else
    defaultBackgroundColor = bgColor ? [bgColor retain] : nil;
#endif
}

- (void)setFont:(NSFont*)newFont
{
#if 0
    if (font != newFont) {
        //NSLog(@"Changing font from %@ to %@", font, newFont);
        [font release];
        font = [newFont retain];
        NSRange range = { 0, [attribString length] };
        [attribString addAttribute:NSFontAttributeName value:font
                range:range];
        [self setDefaultFg:norm_pixel bg:gui.back_pixel];
        [self edited:NSTextStorageEditedAttributes range:range
                changeInLength:0];
    }
#else
    if (newFont && font != newFont) {
        //NSLog(@"Setting font %@", newFont);
        [font release];
        font = [newFont retain];
        // TODO! Change paragraph style to match line height of new font
    }
#endif
}

- (NSFont*)font
{
    return font;
}

- (NSSize)size
{
    if (![[self layoutManagers] count]) return NSZeroSize;
    NSLayoutManager *lm = [[self layoutManagers] objectAtIndex:0];

#if MM_SIMPLE_TS_CALC
    float h = [lm defaultLineHeightForFont:font];
    NSSize size = NSMakeSize([self cellWidth]*maxColumns, h*maxRows);
#else
    if (![[lm textContainers] count]) return NSZeroSize;
    NSTextContainer *tc = [[lm textContainers] objectAtIndex:0];

    NSRange range = [lm glyphRangeForTextContainer:tc];
    NSRect rect = [lm boundingRectForGlyphRange:range inTextContainer:tc];
    //[lm glyphRangeForTextContainer:tc];
    //NSRect rect = [lm usedRectForTextContainer:tc];

    NSSize size = NSMakeSize([self widthOfEmptyRow], rect.size.height);
    //NSSize size = NSMakeSize([self widthOfEmptyRow], maxRows*LINEHEIGHT);
    //NSLog(@"size=(%.2f,%.2f) rows=%d cols=%d layoutManager size=(%.2f,%.2f)",
    //        size.width, size.height, maxRows, maxColumns, rect.size.width,
    //        rect.size.height);
#endif

    return size;
}

- (NSSize)calculateAverageFontSize
{
    if (![[self layoutManagers] count]) return NSZeroSize;

    NSSize size;
    NSLayoutManager *lm = [[self layoutManagers] objectAtIndex:0];
    size.height = [lm defaultLineHeightForFont:font];
    size.width = [self cellWidth];
    if (size.height < 1.0f) size.height = 1.0f;
    if (size.width < 1.0f) size.width = 1.0f;

    return size;
}

- (NSRect)rectForRowsInRange:(NSRange)range
{
    if (![[self layoutManagers] count]) return NSZeroRect;

    // TODO!  Take range.location into account when computing height (in case
    // the line height varies).
    NSRect rect = { 0, 0, 0, 0 };
    NSLayoutManager *lm = [[self layoutManagers] objectAtIndex:0];
    float fontHeight = [lm defaultLineHeightForFont:font];

    unsigned start = range.location > maxRows ? maxRows : range.location;
    unsigned length = range.length;
    if (start+length > maxRows)
        length = maxRows - start;

    rect.origin.y = fontHeight * start;
    rect.size.height = fontHeight * length;

    return rect;
}

- (NSRect)rectForColumnsInRange:(NSRange)range
{
    NSRect rect = { 0, 0, 0, 0 };
    float fontWidth = [self cellWidth];

    unsigned start = range.location > maxColumns ? maxColumns : range.location;
    unsigned length = range.length;
    if (start+length > maxColumns)
        length = maxColumns - start;

    rect.origin.x = fontWidth * start;
    rect.size.width = fontWidth * length;

    return rect;
}

- (unsigned)offsetFromRow:(int)row column:(int)col
{
    // Ensure the offset returned is valid.
    // This code also works if maxRows and/or maxColumns is 0.
    if (row >= maxRows) row = maxRows-1;
    if (row < 0) row = 0;
    if (col >= maxColumns) col = maxColumns-1;
    if (col < 0) col = 0;

    return (unsigned)(col + row*(maxColumns+1));
}

- (BOOL)resizeToFitSize:(NSSize)size
{
    int rows = maxRows, cols = maxColumns;

    [self fitToSize:size rows:&rows columns:&cols];
    if (rows != maxRows || cols != maxColumns) {
        [self setMaxRows:rows columns:cols];
        return YES;
    }

    // Return NO only if dimensions did not change.
    return NO;
}

- (NSSize)fitToSize:(NSSize)size
{
    return [self fitToSize:size rows:NULL columns:NULL];
}

- (NSSize)fitToSize:(NSSize)size rows:(int *)rows columns:(int *)columns
{
    if (![[self layoutManagers] count]) return size;
    NSLayoutManager *lm = [[self layoutManagers] objectAtIndex:0];

#if !MM_SIMPLE_TS_CALC
    if (![[lm textContainers] count]) return size;
    NSTextContainer *tc = [[lm textContainers] objectAtIndex:0];
#endif

    NSSize curSize = [self size];
    NSSize fitSize = curSize;
    int fitRows = maxRows;
    int fitCols = maxColumns;

    if (size.height < curSize.height) {
        // Remove lines until the height of the text storage fits inside
        // 'size'.  However, always make sure there are at least 3 lines in the
        // text storage.  (Why 3? It seem Vim never allows less than 3 lines.)
        //
        // TODO: Use binary search instead of the current linear one.
#if MM_TS_LAZY_SET
        int rowCount = maxRows;
        int rowsToRemove;
        for (rowsToRemove = 0; rowsToRemove < maxRows-3; ++rowsToRemove) {
            float height = [lm defaultLineHeightForFont:font]*rowCount;

            if (height <= size.height) {
                fitSize.height = height;
                break;
            }

            --rowCount;
        }
#else
        NSRange charRange = { 0, maxRows*(maxColumns+1) };
        int rowsToRemove;
        for (rowsToRemove = 0; rowsToRemove < maxRows-3; ++rowsToRemove) {
            NSRange glyphRange = [lm glyphRangeForCharacterRange:charRange
                                            actualCharacterRange:nil];
            float height = [lm boundingRectForGlyphRange:glyphRange
                                         inTextContainer:tc].size.height;
            
            if (height <= size.height) {
                fitSize.height = height;
                break;
            }

            charRange.length -= (maxColumns+1);
        }
#endif

        fitRows -= rowsToRemove;
    } else if (size.height > curSize.height) {
        float fh = [lm defaultLineHeightForFont:font];
        if (fh < 1.0f) fh = 1.0f;

        fitRows = floor(size.height/fh);
        fitSize.height = fh*fitRows;
    }

    if (size.width != curSize.width) {
        float fw = [self cellWidth];
        if (fw < 1.0f) fw = 1.0f;

        fitCols = floor(size.width/fw);
        fitSize.width = fw*fitCols;
    }

    if (rows) *rows = fitRows;
    if (columns) *columns = fitCols;

    return fitSize;
}

@end // MMTextStorage




@implementation MMTextStorage (Private)
#if MM_TS_LAZY_SET
- (void)lazyResize
{
    if (actualRows != maxRows || actualColumns != maxColumns) {
        [self doSetMaxRows:maxRows columns:maxColumns];
    }
}
#endif // MM_TS_LAZY_SET

- (void)doSetMaxRows:(int)rows columns:(int)cols
{
#if MM_TS_LAZY_SET
    // Do nothing if the dimensions are already right.
    if (actualRows == rows && actualColumns == cols)
        return;

    NSRange oldRange = NSMakeRange(0, actualRows*(actualColumns+1));
#else
    // Do nothing if the dimensions are already right.
    if (maxRows == rows && maxColumns == cols)
        return;

    NSRange oldRange = NSMakeRange(0, maxRows*(maxColumns+1));
#endif

    maxRows = rows;
    maxColumns = cols;

    NSString *fmt = [NSString stringWithFormat:@"%%%dc\%C", maxColumns,
             NSLineSeparatorCharacter];
    NSDictionary *dict;
    if (defaultBackgroundColor) {
        dict = [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                defaultBackgroundColor, NSBackgroundColorAttributeName, nil];
    } else {
        dict = [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName, nil];
    }
            
    [emptyRowString release];
    emptyRowString = [[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:fmt, ' ']
                attributes:dict];

    [attribString release];
    attribString = [[NSMutableAttributedString alloc] init];
    int i;
    for (i=0; i<maxRows; ++i) {
        [attribString appendAttributedString:emptyRowString];
    }

    NSRange fullRange = NSMakeRange(0, [attribString length]);
    [self edited:(NSTextStorageEditedCharacters|NSTextStorageEditedAttributes)
           range:oldRange changeInLength:fullRange.length-oldRange.length];

#if MM_TS_LAZY_SET
    actualRows = rows;  actualColumns = cols;
#endif
}

- (float)cellWidth
{
    return [font widthOfString:@"W"];
}

- (float)widthOfEmptyRow
{
    return [font widthOfString:[emptyRowString string]];
}

@end // MMTextStorage (Private)
