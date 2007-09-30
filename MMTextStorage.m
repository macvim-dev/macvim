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
#import "MacVim.h"




// TODO: support DRAW_TRANSP flag
#define DRAW_TRANSP               0x01    /* draw with transparant bg */
#define DRAW_BOLD                 0x02    /* draw bold text */
#define DRAW_UNDERL               0x04    /* draw underline text */
#define DRAW_UNDERC               0x08    /* draw undercurl text */
#define DRAW_ITALIC               0x10    /* draw italic text */




@interface MMTextStorage (Private)
- (void)lazyResize;
@end



@implementation MMTextStorage

- (id)init
{
    if ((self = [super init])) {
        attribString = [[NSMutableAttributedString alloc] initWithString:@""];
        // NOTE!  It does not matter which font is set here, Vim will set its
        // own font on startup anyway.  Just set some bogus values.
        font = [[NSFont userFixedPitchFontOfSize:0] retain];
        boldFont = [font retain];
        italicFont = [font retain];
        boldItalicFont = [font retain];
        cellSize.height = [font pointSize];
        cellSize.width = [font defaultLineHeightForFont];
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);

    [emptyRowString release];
    [boldItalicFont release];
    [italicFont release];
    [boldFont release];
    [font release];
    [defaultBackgroundColor release];
    [defaultForegroundColor release];
    [attribString release];
    [super dealloc];
}

- (NSString *)string
{
    //NSLog(@"%s : attribString=%@", _cmd, attribString);
    return [attribString string];
}

- (NSDictionary *)attributesAtIndex:(unsigned)index
                     effectiveRange:(NSRangePointer)range
{
    //NSLog(@"%s", _cmd);
    if (index>=[attribString length]) {
        //NSLog(@"%sWARNING: index (%d) out of bounds", _cmd, index);
        if (range) {
            *range = NSMakeRange(NSNotFound, 0);
        }
        return [NSDictionary dictionary];
    }

    return [attribString attributesAtIndex:index effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range
                      withString:(NSString *)string
{
    //NSLog(@"replaceCharactersInRange:(%d,%d) withString:%@", range.location,
    //        range.length, string);
    NSLog(@"WARNING: calling %s on MMTextStorage is unsupported", _cmd);
    //[attribString replaceCharactersInRange:range withString:string];
}

- (void)setAttributes:(NSDictionary *)attributes range:(NSRange)range
{
    // NOTE!  This method must be implemented since the text system calls it
    // constantly to 'fix attributes', apply font substitution, etc.
#if 0
    [attribString setAttributes:attributes range:range];
#else
    // HACK! If the font attribute is being modified, then ensure that the new
    // font has a fixed advancement which is either the same as the current
    // font or twice that, depending on whether it is a 'wide' character that
    // is being fixed or not.  This code really only works if 'range' has
    // length 1 or 2.
    NSFont *newFont = [attributes objectForKey:NSFontAttributeName];
    if (newFont) {
        float adv = cellSize.width;
        if ([attribString length] > range.location+1) {
            // If the first char is followed by zero-width space, then it is a
            // 'wide' character, so double the advancement.
            NSString *string = [attribString string];
            if ([string characterAtIndex:range.location+1] == 0x200b)
                adv += adv;
        }

        // Create a new font which has the 'fixed advance attribute' set.
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithFloat:adv], NSFontFixedAdvanceAttribute, nil];
        NSFontDescriptor *desc = [newFont fontDescriptor];
        desc = [desc fontDescriptorByAddingAttributes:dict];
        newFont = [NSFont fontWithDescriptor:desc size:[newFont pointSize]];

        // Now modify the 'attributes' dictionary to hold the new font.
        NSMutableDictionary *newAttr = [NSMutableDictionary
            dictionaryWithDictionary:attributes];
        [newAttr setObject:newFont forKey:NSFontAttributeName];

        [attribString setAttributes:newAttr range:range];
    } else {
        [attribString setAttributes:attributes range:range];
    }
#endif
}

- (int)maxRows
{
    return maxRows;
}

- (int)maxColumns
{
    return maxColumns;
}

- (int)actualRows
{
    return actualRows;
}

- (int)actualColumns
{
    return actualColumns;
}

- (float)linespace
{
    return linespace;
}

- (void)setLinespace:(float)newLinespace
{
    NSLayoutManager *lm = [[self layoutManagers] objectAtIndex:0];

    linespace = newLinespace;

    // NOTE: The linespace is added to the cell height in order for a multiline
    // selection not to have white (background color) gaps between lines.  Also
    // this simplifies the code a lot because there is no need to check the
    // linespace when calculating the size of the text view etc.  When the
    // linespace is non-zero the baseline will be adjusted as well; check
    // MMTypesetter.
    cellSize.height = linespace + (lm ? [lm defaultLineHeightForFont:font]
                                      : [font defaultLineHeightForFont]);
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

- (void)replaceString:(NSString *)string atRow:(int)row column:(int)col
            withFlags:(int)flags foregroundColor:(NSColor *)fg
      backgroundColor:(NSColor *)bg specialColor:(NSColor *)sp
{
    //NSLog(@"replaceString:atRow:%d column:%d withFlags:%d", row, col, flags);
    [self lazyResize];

    // TODO: support DRAW_TRANSP
    if (flags & DRAW_TRANSP)
        return;

    if (row < 0 || row >= maxRows || col < 0 || col >= maxColumns
            || col+[string length] > maxColumns) {
        //NSLog(@"[%s] WARNING : out of range, row=%d (%d) col=%d (%d) "
        //        "length=%d (%d)", _cmd, row, maxRows, col, maxColumns,
        //        [string length], [attribString length]);
        return;
    }

    // NOTE: If 'string' was initialized with bad data it might be nil; this
    // may be due to 'enc' being set to an unsupported value, so don't print an
    // error message or stdout will most likely get flooded.
    if (!string) return;

    if (!(fg && bg && sp)) {
        NSLog(@"[%s] WARNING: background, foreground or special color not "
                "specified", _cmd);
        return;
    }

    NSRange range = NSMakeRange(col+row*(maxColumns+1), [string length]);
    [attribString replaceCharactersInRange:range withString:string];

    NSFont *theFont = font;
    if (flags & DRAW_BOLD)
        theFont = flags & DRAW_ITALIC ? boldItalicFont : boldFont;
    else if (flags & DRAW_ITALIC)
        theFont = italicFont;

    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            theFont, NSFontAttributeName,
            bg, NSBackgroundColorAttributeName,
            fg, NSForegroundColorAttributeName,
            sp, NSUnderlineColorAttributeName,
            nil];
    [attribString setAttributes:attributes range:range];

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

    NSRange emptyRange = {0,width};
    NSAttributedString *emptyString =
            [emptyRowString attributedSubstringFromRange: emptyRange];
    NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            color, NSBackgroundColorAttributeName, nil];

    for (i = 0; i < count; ++i) {
        [attribString replaceCharactersInRange:destRange
                          withAttributedString:emptyString];
        [attribString setAttributes:attribs range:destRange];
        [self edited:(NSTextStorageEditedAttributes
                | NSTextStorageEditedCharacters) range:destRange
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
    
    NSRange emptyRange = {0,width};
    NSAttributedString *emptyString =
            [emptyRowString attributedSubstringFromRange:emptyRange];
    NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            color, NSBackgroundColorAttributeName, nil];
    
    for (i = 0; i < count; ++i) {
        [attribString replaceCharactersInRange:destRange
                          withAttributedString:emptyString];
        [attribString setAttributes:attribs range:destRange];
        [self edited:(NSTextStorageEditedAttributes
                | NSTextStorageEditedCharacters) range:destRange
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
            color, NSBackgroundColorAttributeName, nil];

    NSRange range = { row1*(maxColumns+1) + col1, col2-col1+1 };
    
    NSRange emptyRange = {0,col2-col1+1};
    NSAttributedString *emptyString =
            [emptyRowString attributedSubstringFromRange:emptyRange];
    int r;
    for (r=row1; r<=row2; ++r) {
        [attribString replaceCharactersInRange:range
                          withAttributedString:emptyString];
        [attribString setAttributes:attribs range:range];
        [self edited:(NSTextStorageEditedAttributes
                | NSTextStorageEditedCharacters) range:range
                                        changeInLength:0];
        range.location += maxColumns+1;
    }
}

- (void)clearAllWithColor:(NSColor *)color
{
    //NSLog(@"%s%@", _cmd, color);
    [self lazyResize];

    [attribString release];
    attribString = [[NSMutableAttributedString alloc] init];
    NSRange fullRange = NSMakeRange(0, [attribString length]);

    int i;
    for (i=0; i<maxRows; ++i)
        [attribString appendAttributedString:emptyRowString];

    NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            color, NSBackgroundColorAttributeName, nil];
    [attribString setAttributes:attribs range:fullRange];

    [self edited:(NSTextStorageEditedCharacters|NSTextStorageEditedAttributes)
           range:fullRange changeInLength:0];
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

- (void)setFont:(NSFont*)newFont
{
    if (newFont && font != newFont) {
        [font release];

        // NOTE! When setting a new font we make sure that the advancement of
        // each glyph is fixed. 

        float em = [newFont widthOfString:@"m"];
        float cellWidthMultiplier = [[NSUserDefaults standardUserDefaults]
                floatForKey:MMCellWidthMultiplierKey];

        // NOTE! Even though NSFontFixedAdvanceAttribute is a float, it will
        // only render at integer sizes.  Hence, we restrict the cell width to
        // an integer here, otherwise the window width and the actual text
        // width will not match.
        cellSize.width = ceilf(em * cellWidthMultiplier);

        float pointSize = [newFont pointSize];
        NSDictionary *dict = [NSDictionary
            dictionaryWithObject:[NSNumber numberWithFloat:cellSize.width]
                          forKey:NSFontFixedAdvanceAttribute];

        NSFontDescriptor *desc = [newFont fontDescriptor];
        desc = [desc fontDescriptorByAddingAttributes:dict];
        font = [NSFont fontWithDescriptor:desc size:pointSize];
        [font retain];

        NSLayoutManager *lm = [[self layoutManagers] objectAtIndex:0];
        cellSize.height = linespace + (lm ? [lm defaultLineHeightForFont:font]
                                          : [font defaultLineHeightForFont]);

        // NOTE: The font manager does not care about the 'font fixed advance'
        // attribute, so after converting the font we have to add this
        // attribute again.
        boldFont = [[NSFontManager sharedFontManager]
            convertFont:font toHaveTrait:NSBoldFontMask];
        desc = [boldFont fontDescriptor];
        desc = [desc fontDescriptorByAddingAttributes:dict];
        boldFont = [NSFont fontWithDescriptor:desc size:pointSize];
        [boldFont retain];

        italicFont = [[NSFontManager sharedFontManager]
            convertFont:font toHaveTrait:NSItalicFontMask];
        desc = [italicFont fontDescriptor];
        desc = [desc fontDescriptorByAddingAttributes:dict];
        italicFont = [NSFont fontWithDescriptor:desc size:pointSize];
        [italicFont retain];

        boldItalicFont = [[NSFontManager sharedFontManager]
            convertFont:italicFont toHaveTrait:NSBoldFontMask];
        desc = [boldItalicFont fontDescriptor];
        desc = [desc fontDescriptorByAddingAttributes:dict];
        boldItalicFont = [NSFont fontWithDescriptor:desc size:pointSize];
        [boldItalicFont retain];
    }
}

- (NSFont*)font
{
    return font;
}

- (NSColor *)defaultBackgroundColor
{
    return defaultBackgroundColor;
}

- (NSColor *)defaultForegroundColor
{
    return defaultForegroundColor;
}

- (NSSize)size
{
    return NSMakeSize(maxColumns*cellSize.width, maxRows*cellSize.height);
}

- (NSSize)cellSize
{
    return cellSize;
}

- (NSRect)rectForRowsInRange:(NSRange)range
{
    NSRect rect = { 0, 0, 0, 0 };
    unsigned start = range.location > maxRows ? maxRows : range.location;
    unsigned length = range.length;

    if (start+length > maxRows)
        length = maxRows - start;

    rect.origin.y = cellSize.height * start;
    rect.size.height = cellSize.height * length;

    return rect;
}

- (NSRect)rectForColumnsInRange:(NSRange)range
{
    NSRect rect = { 0, 0, 0, 0 };
    unsigned start = range.location > maxColumns ? maxColumns : range.location;
    unsigned length = range.length;

    if (start+length > maxColumns)
        length = maxColumns - start;

    rect.origin.x = cellSize.width * start;
    rect.size.width = cellSize.width * length;

    return rect;
}

- (unsigned)characterIndexForRow:(int)row column:(int)col
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
    NSSize curSize = [self size];
    NSSize fitSize = curSize;
    int fitRows = maxRows;
    int fitCols = maxColumns;

    if (size.height < curSize.height) {
        // Remove lines until the height of the text storage fits inside
        // 'size'.  However, always make sure there are at least 3 lines in the
        // text storage.  (Why 3? It seem Vim never allows less than 3 lines.)
        //
        // TODO: No need to search since line height is fixed, just calculate
        // the new height.
        int rowCount = maxRows;
        int rowsToRemove;
        for (rowsToRemove = 0; rowsToRemove < maxRows-3; ++rowsToRemove) {
            float height = cellSize.height*rowCount;

            if (height <= size.height) {
                fitSize.height = height;
                break;
            }

            --rowCount;
        }

        fitRows -= rowsToRemove;
    } else if (size.height > curSize.height) {
        float fh = cellSize.height;
        if (fh < 1.0f) fh = 1.0f;

        fitRows = floor(size.height/fh);
        fitSize.height = fh*fitRows;
    }

    if (size.width != curSize.width) {
        float fw = cellSize.width;
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
- (void)lazyResize
{
    int i;

    // Do nothing if the dimensions are already right.
    if (actualRows == maxRows && actualColumns == maxColumns)
        return;

    NSRange oldRange = NSMakeRange(0, actualRows*(actualColumns+1));

    actualRows = maxRows;
    actualColumns = maxColumns;

    NSDictionary *dict;
    if (defaultBackgroundColor) {
        dict = [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                defaultBackgroundColor, NSBackgroundColorAttributeName, nil];
    } else {
        dict = [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName, nil];
    }
            
    NSMutableString *rowString = [NSMutableString string];
    for (i = 0; i < maxColumns; ++i) {
        [rowString appendString:@" "];
    }
    [rowString appendString:@"\n"];

    [emptyRowString release];
    emptyRowString = [[NSAttributedString alloc] initWithString:rowString
                                                     attributes:dict];

    [attribString release];
    attribString = [[NSMutableAttributedString alloc] init];
    for (i=0; i<maxRows; ++i) {
        [attribString appendAttributedString:emptyRowString];
    }

    NSRange fullRange = NSMakeRange(0, [attribString length]);
    [self edited:(NSTextStorageEditedCharacters|NSTextStorageEditedAttributes)
           range:oldRange changeInLength:fullRange.length-oldRange.length];
}

@end // MMTextStorage (Private)
