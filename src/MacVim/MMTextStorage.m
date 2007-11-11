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
 * MMTextStorage
 *
 * Text rendering related code.
 */

#import "MMTextStorage.h"
#import "MacVim.h"




// TODO: What does DRAW_TRANSP flag do?  If the background isn't drawn when
// this flag is set, then sometimes the character after the cursor becomes
// blank.  Everything seems to work fine by just ignoring this flag.
#define DRAW_TRANSP               0x01    /* draw with transparant bg */
#define DRAW_BOLD                 0x02    /* draw bold text */
#define DRAW_UNDERL               0x04    /* draw underline text */
#define DRAW_UNDERC               0x08    /* draw undercurl text */
#define DRAW_ITALIC               0x10    /* draw italic text */
#define DRAW_CURSOR               0x20


static NSString *MMWideCharacterAttributeName = @"MMWideChar";




@interface MMTextStorage (Private)
- (void)lazyResize:(BOOL)force;
- (NSRange)charRangeForRow:(int)row column:(int)col cells:(int)cells;
- (void)fixInvalidCharactersInRange:(NSRange)range;
@end



@implementation MMTextStorage

- (id)init
{
    if ((self = [super init])) {
        attribString = [[NSMutableAttributedString alloc] initWithString:@""];
        // NOTE!  It does not matter which font is set here, Vim will set its
        // own font on startup anyway.  Just set some bogus values.
        font = [[NSFont userFixedPitchFontOfSize:0] retain];
        cellSize.height = [font pointSize];
        cellSize.width = [font defaultLineHeightForFont];
    }

    return self;
}

- (void)dealloc
{
#if MM_USE_ROW_CACHE
    if (rowCache) {
        free(rowCache);
        rowCache = NULL;
    }
#endif
    [emptyRowString release];
    [boldItalicFontWide release];
    [italicFontWide release];
    [boldFontWide release];
    [fontWide release];
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
    return [attribString string];
}

- (NSDictionary *)attributesAtIndex:(unsigned)index
                     effectiveRange:(NSRangePointer)range
{
    if (index >= [attribString length]) {
        if (range)
            *range = NSMakeRange(NSNotFound, 0);

        return [NSDictionary dictionary];
    }

    return [attribString attributesAtIndex:index effectiveRange:range];
}

- (id)attribute:(NSString *)attrib atIndex:(unsigned)index
        effectiveRange:(NSRangePointer)range
{
    return [attribString attribute:attrib atIndex:index effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range
                      withString:(NSString *)string
{
    NSLog(@"WARNING: calling %s on MMTextStorage is unsupported", _cmd);
    //[attribString replaceCharactersInRange:range withString:string];
}

- (void)setAttributes:(NSDictionary *)attributes range:(NSRange)range
{
    // NOTE!  This method must be implemented since the text system calls it
    // constantly to 'fix attributes', apply font substitution, etc.
#if 0
    [attribString setAttributes:attributes range:range];
#elif 1
    // HACK! If the font attribute is being modified, then ensure that the new
    // font has a fixed advancement which is either the same as the current
    // font or twice that, depending on whether it is a 'wide' character that
    // is being fixed or not.
    //
    // TODO: This code assumes that the characters in 'range' all have the same
    // width.
    NSFont *newFont = [attributes objectForKey:NSFontAttributeName];
    if (newFont) {
        // Allow disabling of font substitution via a user default.  Not
        // recommended since the typesetter hides the corresponding glyphs and
        // the display gets messed up.
        if ([[NSUserDefaults standardUserDefaults]
                boolForKey:MMNoFontSubstitutionKey])
            return;

        float adv = cellSize.width;
        if ([attribString attribute:MMWideCharacterAttributeName
                            atIndex:range.location
                     effectiveRange:NULL])
            adv += adv;

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

- (void)drawString:(NSString *)string atRow:(int)row column:(int)col
             cells:(int)cells withFlags:(int)flags
   foregroundColor:(NSColor *)fg backgroundColor:(NSColor *)bg
      specialColor:(NSColor *)sp
{
    //NSLog(@"replaceString:atRow:%d column:%d withFlags:%d "
    //          "foreground:%@ background:%@ special:%@",
    //          row, col, flags, fg, bg, sp);
    [self lazyResize:NO];

    if (row < 0 || row >= maxRows || col < 0 || col >= maxColumns
            || col+cells > maxColumns || !string || !(fg && bg && sp))
        return;

    // Find range of characters in text storage to replace.
    NSRange range = [self charRangeForRow:row column:col cells:cells];
    if (NSMaxRange(range) > [[attribString string] length]) {
        NSLog(@"%s Out of bounds");
        return;
    }

    // Create dictionary of attributes to apply to the new characters.
    NSFont *theFont = font;
    if (flags & DRAW_WIDE) {
        if (flags & DRAW_BOLD)
            theFont = flags & DRAW_ITALIC ? boldItalicFontWide : boldFontWide;
        else if (flags & DRAW_ITALIC)
            theFont = italicFontWide;
        else
            theFont = fontWide;
    } else {
        if (flags & DRAW_BOLD)
            theFont = flags & DRAW_ITALIC ? boldItalicFont : boldFont;
        else if (flags & DRAW_ITALIC)
            theFont = italicFont;
    }

    NSMutableDictionary *attributes =
        [NSMutableDictionary dictionaryWithObjectsAndKeys:
            theFont, NSFontAttributeName,
            bg, NSBackgroundColorAttributeName,
            fg, NSForegroundColorAttributeName,
            sp, NSUnderlineColorAttributeName,
            nil];

    if (flags & DRAW_UNDERL) {
        NSNumber *value = [NSNumber numberWithInt:(NSUnderlineStyleSingle
                | NSUnderlinePatternSolid)]; // | NSUnderlineByWordMask
        [attributes setObject:value forKey:NSUnderlineStyleAttributeName];
    }

    if (flags & DRAW_UNDERC) {
        // TODO: figure out how do draw proper undercurls
        NSNumber *value = [NSNumber numberWithInt:(NSUnderlineStyleThick
                | NSUnderlinePatternDot)]; // | NSUnderlineByWordMask
        [attributes setObject:value forKey:NSUnderlineStyleAttributeName];
    }

    // Mark these characters as wide.  This attribute is subsequently checked
    // when translating (row,col) pairs to offsets within 'attribString'.
    if (flags & DRAW_WIDE)
        [attributes setObject:[NSNull null]
                       forKey:MMWideCharacterAttributeName];

    // Replace characters in text storage and apply new attributes.
    NSRange r = NSMakeRange(range.location, [string length]);
    [attribString replaceCharactersInRange:range withString:string];
    [attribString setAttributes:attributes range:r];

    if ((flags & DRAW_WIDE) || [string length] != cells)
        characterEqualsColumn = NO;

    [self fixInvalidCharactersInRange:r];

    [self edited:(NSTextStorageEditedCharacters|NSTextStorageEditedAttributes)
           range:range changeInLength:[string length]-range.length];

#if MM_USE_ROW_CACHE
    rowCache[row].length += [string length] - range.length;
#endif
}

/*
 * Delete 'count' lines from 'row' and insert 'count' empty lines at the bottom
 * of the scroll region.
 */
- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(NSColor *)color
{
    //NSLog(@"deleteLinesFromRow:%d lineCount:%d color:%@", row, count, color);
    [self lazyResize:NO];

    if (row < 0 || row+count > maxRows)
        return;

    int total = 1 + bottom - row;
    int move = total - count;
    int width = right - left + 1;
    int destRow = row;
    NSRange destRange, srcRange;
    int i;

    for (i = 0; i < move; ++i, ++destRow) {
        destRange = [self charRangeForRow:destRow column:left cells:width];
        srcRange = [self charRangeForRow:(destRow+count) column:left
                                   cells:width];
        NSAttributedString *srcString = [attribString
                attributedSubstringFromRange:srcRange];

        [attribString replaceCharactersInRange:destRange
                          withAttributedString:srcString];
        [self edited:(NSTextStorageEditedCharacters
                | NSTextStorageEditedAttributes) range:destRange
                changeInLength:([srcString length]-destRange.length)];

#if MM_USE_ROW_CACHE
        rowCache[destRow].length += [srcString length] - destRange.length;
#endif
    }
    
    NSRange emptyRange = {0,width};
    NSAttributedString *emptyString =
            [emptyRowString attributedSubstringFromRange:emptyRange];
    NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            color, NSBackgroundColorAttributeName, nil];

    for (i = 0; i < count; ++i, ++destRow) {
        destRange = [self charRangeForRow:destRow column:left cells:width];

        [attribString replaceCharactersInRange:destRange
                          withAttributedString:emptyString];
        [attribString setAttributes:attribs
                              range:NSMakeRange(destRange.location, width)];

        [self edited:(NSTextStorageEditedAttributes
                | NSTextStorageEditedCharacters) range:destRange
                changeInLength:([emptyString length]-destRange.length)];

#if MM_USE_ROW_CACHE
        rowCache[destRow].length += [emptyString length] - destRange.length;
#endif
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
    //NSLog(@"insertLinesAtRow:%d lineCount:%d color:%@", row, count, color);
    [self lazyResize:NO];

    if (row < 0 || row+count > maxRows)
        return;

    int total = 1 + bottom - row;
    int move = total - count;
    int width = right - left + 1;
    int destRow = bottom;
    int srcRow = row + move - 1;
    NSRange destRange, srcRange;
    int i;

    for (i = 0; i < move; ++i, --destRow, --srcRow) {
        destRange = [self charRangeForRow:destRow column:left cells:width];
        srcRange = [self charRangeForRow:srcRow column:left cells:width];
        NSAttributedString *srcString = [attribString
                attributedSubstringFromRange:srcRange];
        [attribString replaceCharactersInRange:destRange
                          withAttributedString:srcString];
        [self edited:(NSTextStorageEditedCharacters
                | NSTextStorageEditedAttributes) range:destRange
                changeInLength:([srcString length]-destRange.length)];

#if MM_USE_ROW_CACHE
        rowCache[destRow].length += [srcString length] - destRange.length;
#endif
    }
    
    NSRange emptyRange = {0,width};
    NSAttributedString *emptyString =
            [emptyRowString attributedSubstringFromRange:emptyRange];
    NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            color, NSBackgroundColorAttributeName, nil];
    
    for (i = 0; i < count; ++i, --destRow) {
        destRange = [self charRangeForRow:destRow column:left cells:width];

        [attribString replaceCharactersInRange:destRange
                          withAttributedString:emptyString];
        [attribString setAttributes:attribs
                              range:NSMakeRange(destRange.location, width)];

        [self edited:(NSTextStorageEditedAttributes
                | NSTextStorageEditedCharacters) range:destRange
                changeInLength:([emptyString length]-destRange.length)];

#if MM_USE_ROW_CACHE
        rowCache[destRow].length += [emptyString length] - destRange.length;
#endif
    }
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(NSColor *)color
{
    //NSLog(@"clearBlockFromRow:%d column:%d toRow:%d column:%d color:%@",
    //        row1, col1, row2, col2, color);
    [self lazyResize:NO];

    if (row1 < 0 || row2 >= maxRows || col1 < 0 || col2 > maxColumns)
        return;

    NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            color, NSBackgroundColorAttributeName, nil];
    int cells = col2 - col1 + 1;
    NSRange range, emptyRange = {0, cells};
    NSAttributedString *emptyString =
            [emptyRowString attributedSubstringFromRange:emptyRange];
    int r;

    for (r=row1; r<=row2; ++r) {
        range = [self charRangeForRow:r column:col1 cells:cells];

        [attribString replaceCharactersInRange:range
                          withAttributedString:emptyString];
        [attribString setAttributes:attribs
                              range:NSMakeRange(range.location, cells)];

        [self edited:(NSTextStorageEditedAttributes
                | NSTextStorageEditedCharacters) range:range
                                        changeInLength:cells-range.length];

#if MM_USE_ROW_CACHE
        rowCache[r].length += cells - range.length;
#endif
    }
}

- (void)clearAll
{
    //NSLog(@"%s", _cmd);
    [self lazyResize:YES];
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
        [boldItalicFont release];
        [italicFont release];
        [boldFont release];
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

- (void)setWideFont:(NSFont *)newFont
{
    if (!newFont) {
        // Use the normal font as the wide font (note that the normal font may
        // very well include wide characters.)
        if (font) [self setWideFont:font];
    } else if (newFont != fontWide) {
        [boldItalicFontWide release];
        [italicFontWide release];
        [boldFontWide release];
        [fontWide release];

        float pointSize = [newFont pointSize];
        NSFontDescriptor *desc = [newFont fontDescriptor];
        NSDictionary *dictWide = [NSDictionary
            dictionaryWithObject:[NSNumber numberWithFloat:2*cellSize.width]
                          forKey:NSFontFixedAdvanceAttribute];

        desc = [desc fontDescriptorByAddingAttributes:dictWide];
        fontWide = [NSFont fontWithDescriptor:desc size:pointSize];
        [fontWide retain];

        boldFontWide = [[NSFontManager sharedFontManager]
            convertFont:fontWide toHaveTrait:NSBoldFontMask];
        desc = [boldFontWide fontDescriptor];
        desc = [desc fontDescriptorByAddingAttributes:dictWide];
        boldFontWide = [NSFont fontWithDescriptor:desc size:pointSize];
        [boldFontWide retain];

        italicFontWide = [[NSFontManager sharedFontManager]
            convertFont:fontWide toHaveTrait:NSItalicFontMask];
        desc = [italicFontWide fontDescriptor];
        desc = [desc fontDescriptorByAddingAttributes:dictWide];
        italicFontWide = [NSFont fontWithDescriptor:desc size:pointSize];
        [italicFontWide retain];

        boldItalicFontWide = [[NSFontManager sharedFontManager]
            convertFont:italicFontWide toHaveTrait:NSBoldFontMask];
        desc = [boldItalicFontWide fontDescriptor];
        desc = [desc fontDescriptorByAddingAttributes:dictWide];
        boldItalicFontWide = [NSFont fontWithDescriptor:desc size:pointSize];
        [boldItalicFontWide retain];
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
    NSRange range = [self charRangeForRow:row column:col cells:1];
    return range.location != NSNotFound ? range.location : 0;
}

// XXX: unused at the moment
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

- (NSRect)boundingRectForCharacterAtRow:(int)row column:(int)col
{
#if 1
    // This properly computes the position of where Vim expects the glyph to be
    // drawn.  Had the typesetter actually computed the right position of each
    // character and not hidden some, this code would be correct.
    NSRect rect = NSZeroRect;

    rect.origin.x = col*cellSize.width;
    rect.origin.y = row*cellSize.height;
    rect.size = cellSize;

    // Wide character take up twice the width of a normal character.
    NSRange r = [self charRangeForRow:row column:col cells:1];
    if (NSNotFound != r.location
            && [attribString attribute:MMWideCharacterAttributeName
                               atIndex:r.location
                        effectiveRange:nil])
        rect.size.width += rect.size.width;

    return rect;
#else
    // Use layout manager to compute bounding rect.  This works in situations
    // where the layout manager decides to hide glyphs (Vim assumes all glyphs
    // are drawn).
    NSLayoutManager *lm = [[self layoutManagers] objectAtIndex:0];
    NSTextContainer *tc = [[lm textContainers] objectAtIndex:0];
    NSRange range = [self charRangeForRow:row column:col cells:1];
    NSRange glyphRange = [lm glyphRangeForCharacterRange:range
                                    actualCharacterRange:NULL];

    return [lm boundingRectForGlyphRange:glyphRange inTextContainer:tc];
#endif
}

#if MM_USE_ROW_CACHE
- (MMRowCacheEntry *)rowCache
{
    return rowCache;
}
#endif

@end // MMTextStorage




@implementation MMTextStorage (Private)

- (void)lazyResize:(BOOL)force
{
    // Do nothing if the dimensions are already right.
    if (!force && actualRows == maxRows && actualColumns == maxColumns)
        return;

    NSRange oldRange = NSMakeRange(0, [attribString length]);

    actualRows = maxRows;
    actualColumns = maxColumns;
    characterEqualsColumn = YES;

#if MM_USE_ROW_CACHE
    free(rowCache);
    rowCache = (MMRowCacheEntry*)calloc(actualRows, sizeof(MMRowCacheEntry));
#endif

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
    int i;
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
#if MM_USE_ROW_CACHE
        rowCache[i].length = actualColumns + 1;
#endif
        [attribString appendAttributedString:emptyRowString];
    }

    NSRange fullRange = NSMakeRange(0, [attribString length]);
    [self edited:(NSTextStorageEditedCharacters|NSTextStorageEditedAttributes)
           range:oldRange changeInLength:fullRange.length-oldRange.length];
}

- (NSRange)charRangeForRow:(int)row column:(int)col cells:(int)cells
{
    // If no wide chars are used and if every char has length 1 (no composing
    // characters, no > 16 bit characters), then we can compute the range.
    if (characterEqualsColumn)
        return NSMakeRange(row*(actualColumns+1) + col, cells);

    NSString *string = [attribString string];
    NSRange r, range = { NSNotFound, 0 };
    unsigned idx;
    int i;

    if (row < 0 || row >= actualRows || col < 0 || col >= actualColumns
            || col+cells > actualColumns) {
        NSLog(@"%s row=%d col=%d cells=%d is out of range (length=%d)",
                _cmd, row, col, cells, [string length]);
        return range;
    }

#if MM_USE_ROW_CACHE
    // Locate the beginning of the row
    MMRowCacheEntry *cache = rowCache;
    idx = 0;
    for (i = 0; i < row; ++i, ++cache)
        idx += cache->length;
#else
    // Locate the beginning of the row by scanning for EOL characters.
    r.location = 0;
    for (i = 0; i < row; ++i) {
        r.length = [string length] - r.location;
        r = [string rangeOfString:@"\n" options:NSLiteralSearch range:r];
        if (NSNotFound == r.location)
            return range;
        ++r.location;
    }
#endif

    // Locate the column
#if MM_USE_ROW_CACHE
    cache = &rowCache[row];

    i = cache->col;
    if (col == i) {
        // Cache hit
        idx += cache->colOffset;
    } else {
        range.location = idx;

        // Cache miss
        if (col < i - col) {
            // Search forward from beginning of line.
            i = 0;
        } else if (actualColumns - col < col - i) {
            // Search backward from end of line.
            i = actualColumns - 1;
            idx += cache->length - 2;
        } else {
            // Search from cache spot (forward or backward).
            idx += cache->colOffset;
        }

        if (col > i) {
            // Forward search
            while (col > i) {
                r = [string rangeOfComposedCharacterSequenceAtIndex:idx];

                // Wide chars take up two display cells.
                if ([attribString attribute:MMWideCharacterAttributeName
                                    atIndex:idx
                             effectiveRange:nil])
                    ++i;

                idx += r.length;
                ++i;
            }
        } else if (col < i) {
            // Backward search
            while (col < i) {
                r = [string rangeOfComposedCharacterSequenceAtIndex:idx-1];
                idx -= r.length;
                --i;

                // Wide chars take up two display cells.
                if ([attribString attribute:MMWideCharacterAttributeName
                                    atIndex:idx
                             effectiveRange:nil])
                    --i;
            }
        }

        cache->col = i;
        cache->colOffset = idx - range.location;
    }
#else
    idx = r.location;
    for (i = 0; i < col; ++i) {
        r = [string rangeOfComposedCharacterSequenceAtIndex:idx];

        // Wide chars take up two display cells.
        if ([attribString attribute:MMWideCharacterAttributeName
                            atIndex:idx
                     effectiveRange:nil])
            ++i;

        idx += r.length;
    }
#endif

    // Count the number of characters that cover the cells.
    range.location = idx;
    for (i = 0; i < cells; ++i) {
        r = [string rangeOfComposedCharacterSequenceAtIndex:idx];

        // Wide chars take up two display cells.
        if ([attribString attribute:MMWideCharacterAttributeName
                            atIndex:idx
                     effectiveRange:nil])
            ++i;

        idx += r.length;
        range.length += r.length;
    }

    return range;
}

- (void)fixInvalidCharactersInRange:(NSRange)range
{
    static NSCharacterSet *invalidCharacterSet = nil;
    NSRange invalidRange;
    unsigned end;

    if (!invalidCharacterSet)
        invalidCharacterSet = [[NSCharacterSet characterSetWithRange:
            NSMakeRange(0x2028, 2)] retain];

    // HACK! Replace characters that the text system can't handle (currently
    // LINE SEPARATOR U+2028 and PARAGRAPH SEPARATOR U+2029) with space.
    //
    // TODO: Treat these separately inside of Vim so we don't have to bother
    // here.
    while (range.length > 0) {
        invalidRange = [[attribString string]
            rangeOfCharacterFromSet:invalidCharacterSet
                            options:NSLiteralSearch
                              range:range];
        if (NSNotFound == invalidRange.location)
            break;

        [attribString replaceCharactersInRange:invalidRange withString:@" "];

        end = NSMaxRange(invalidRange);
        range.length -= end - range.location;
        range.location = end;
    }
}

@end // MMTextStorage (Private)
