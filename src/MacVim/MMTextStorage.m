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
 *
 * Note that:
 * - There are exactly 'actualRows' number of rows
 * - Each row is terminated by an EOL character ('\n')
 * - Each row must cover exactly 'actualColumns' display cells
 * - The attribute "MMWideChar" denotes a character that covers two cells, a
 *   character without this attribute covers one cell
 * - Unicode line (U+2028) and paragraph (U+2029) terminators are considered
 *   invalid and are replaced by spaces
 * - Spaces are used to fill out blank spaces
 *
 * In order to locate a (row,col) pair it is in general necessary to search one
 * character at a time.  To speed things up we cache the length of each row, as
 * well as the offset of the last column searched within each row.
 *
 * If each character in the text storage has length 1 and is not wide, then
 * there is no need to search for a (row, col) pair since it can easily be
 * computed.
 */

#import "MMTextStorage.h"
#import "MacVim.h"
#import "Miscellaneous.h"



// Enable debug log messages for situations that should never occur.
#define MM_TS_PARANOIA_LOG 1



// TODO: What does DRAW_TRANSP flag do?  If the background isn't drawn when
// this flag is set, then sometimes the character after the cursor becomes
// blank.  Everything seems to work fine by just ignoring this flag.
#define DRAW_TRANSP               0x01    /* draw with transparant bg */
#define DRAW_BOLD                 0x02    /* draw bold text */
#define DRAW_UNDERL               0x04    /* draw underline text */
#define DRAW_UNDERC               0x08    /* draw undercurl text */
#define DRAW_ITALIC               0x10    /* draw italic text */
#define DRAW_CURSOR               0x20
#define DRAW_WIDE                 0x40    /* draw wide text */


static NSString *MMWideCharacterAttributeName = @"MMWideChar";




@interface MMTextStorage (Private)
- (void)lazyResize:(BOOL)force;
- (NSRange)charRangeForRow:(int)row column:(int*)col cells:(int*)cells;
- (void)fixInvalidCharactersInRange:(NSRange)range;
@end



@implementation MMTextStorage

- (id)init
{
    if ((self = [super init])) {
        backingStore = [[NSTextStorage alloc] init];
        // NOTE!  It does not matter which font is set here, Vim will set its
        // own font on startup anyway.  Just set some bogus values.
        font = [[NSFont userFixedPitchFontOfSize:0] retain];
        cellSize.height = 16.0;
        cellSize.width = 6.0;
    }

    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

#if MM_USE_ROW_CACHE
    if (rowCache) {
        free(rowCache);
        rowCache = NULL;
    }
#endif
    [emptyRowString release];  emptyRowString = nil;
    [boldItalicFontWide release];  boldItalicFontWide = nil;
    [italicFontWide release];  italicFontWide = nil;
    [boldFontWide release];  boldFontWide = nil;
    [fontWide release];  fontWide = nil;
    [boldItalicFont release];  boldItalicFont = nil;
    [italicFont release];  italicFont = nil;
    [boldFont release];  boldFont = nil;
    [font release];  font = nil;
    [defaultBackgroundColor release];  defaultBackgroundColor = nil;
    [defaultForegroundColor release];  defaultForegroundColor = nil;
    [backingStore release];  backingStore = nil;
    [super dealloc];
}

- (NSString *)string
{
    return [backingStore string];
}

- (NSDictionary *)attributesAtIndex:(NSUInteger)index
                     effectiveRange:(NSRangePointer)range
{
    return [backingStore attributesAtIndex:index effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range
                      withString:(NSString *)string
{
#if MM_TS_PARANOIA_LOG
    ASLogWarn(@"Calling %@ on MMTextStorage is unsupported",
              NSStringFromSelector(_cmd));
#endif
    //[backingStore replaceCharactersInRange:range withString:string];
}

- (void)setAttributes:(NSDictionary *)attributes range:(NSRange)range
{
    // NOTE!  This method must be implemented since the text system calls it
    // constantly to 'fix attributes', apply font substitution, etc.
#if 0
    [backingStore setAttributes:attributes range:range];
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
        if ([backingStore attribute:MMWideCharacterAttributeName
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

        [backingStore setAttributes:newAttr range:range];
    } else {
        [backingStore setAttributes:attributes range:range];
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

- (float)columnspace
{
    return columnspace;
}

- (void)setLinespace:(float)newLinespace
{
    NSLayoutManager *lm = [[self layoutManagers] objectAtIndex:0];
    if (!lm) {
        ASLogWarn(@"No layout manager available");
        return;
    }

    linespace = newLinespace;

    // NOTE: The linespace is added to the cell height in order for a multiline
    // selection not to have white (background color) gaps between lines.  Also
    // this simplifies the code a lot because there is no need to check the
    // linespace when calculating the size of the text view etc.  When the
    // linespace is non-zero the baseline will be adjusted as well; check
    // MMTypesetter.
    cellSize.height = linespace + [lm defaultLineHeightForFont:font];
}

- (void)setColumnspace:(float)newColumnspace
{
    NSLayoutManager *lm = [[self layoutManagers] objectAtIndex:0];
    if (!lm) {
        ASLogWarn(@"No layout manager available");
        return;
    }

    columnspace = newColumnspace;

    float em = [@"m" sizeWithAttributes:
            [NSDictionary dictionaryWithObject:font
                                        forKey:NSFontAttributeName]].width;
    float cellWidthMultiplier = [[NSUserDefaults standardUserDefaults]
            floatForKey:MMCellWidthMultiplierKey];

    cellSize.width = columnspace + ceilf(em * cellWidthMultiplier);
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
    [self lazyResize:NO];

    if (row < 0 || row >= maxRows || col < 0 || col >= maxColumns
            || col+cells > maxColumns || !string || !(fg && bg && sp))
        return;

    BOOL hasControlChars = [string rangeOfCharacterFromSet:
            [NSCharacterSet controlCharacterSet]].location != NSNotFound;
    if (hasControlChars) {
        // HACK! If a string for some reason contains control characters, then
        // draw blanks instead (otherwise charRangeForRow::: fails).
        NSRange subRange = { 0, cells };
        flags &= ~DRAW_WIDE;
        string = [[emptyRowString string] substringWithRange:subRange];
    }

    // Find range of characters in text storage to replace.
    int acol = col;
    int acells = cells;
    NSRange range = [self charRangeForRow:row column:&acol cells:&acells];
    if (NSNotFound == range.location) {
#if MM_TS_PARANOIA_LOG
        ASLogErr(@"INTERNAL ERROR: Out of bounds");
#endif
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
            [NSNumber numberWithInt:0], NSLigatureAttributeName,
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
    // when translating (row,col) pairs to offsets within 'backingStore'.
    if (flags & DRAW_WIDE)
        [attributes setObject:[NSNull null]
                       forKey:MMWideCharacterAttributeName];

    // Replace characters in text storage and apply new attributes.
    NSRange r = NSMakeRange(range.location, [string length]);
    [backingStore replaceCharactersInRange:range withString:string];
    [backingStore setAttributes:attributes range:r];

    NSInteger changeInLength = [string length] - range.length;
    if (acells != cells || acol != col) {
        if (acells == cells + 1) {
            // NOTE: A normal width character replaced a double width
            // character.  To maintain the invariant that each row covers the
            // same amount of cells, we compensate by adding an empty column.
            [backingStore replaceCharactersInRange:NSMakeRange(NSMaxRange(r),0)
                withAttributedString:[emptyRowString
                    attributedSubstringFromRange:NSMakeRange(0,1)]];
            ++changeInLength;
#if 0
        } else if (acol == col - 1) {
            [backingStore replaceCharactersInRange:NSMakeRange(r.location,0)
                withAttributedString:[emptyRowString
                    attributedSubstringFromRange:NSMakeRange(0,1)]];
            ++changeInLength;
        } else if (acol == col + 1) {
            [backingStore replaceCharactersInRange:NSMakeRange(r.location-1,1)
                withAttributedString:[emptyRowString
                    attributedSubstringFromRange:NSMakeRange(0,2)]];
            ++changeInLength;
#endif
        } else {
            // NOTE: It seems that this never gets called.  If it ever does,
            // then there is another case to treat.
#if MM_TS_PARANOIA_LOG
            ASLogWarn(@"row=%d col=%d acol=%d cells=%d acells=%d", row, col,
                      acol, cells, acells);
#endif
        }
    }

    if ((flags & DRAW_WIDE) || [string length] != cells)
        characterEqualsColumn = NO;

    [self fixInvalidCharactersInRange:r];

#if 0
    ASLogDebug(@"length=%d row=%d col=%d cells=%d replaceRange=%@ change=%d",
            [string length], row, col, cells,
            NSStringFromRange(r), changeInLength);
#endif
    [self edited:(NSTextStorageEditedCharacters|NSTextStorageEditedAttributes)
           range:range changeInLength:changeInLength];

#if MM_USE_ROW_CACHE
    rowCache[row].length += changeInLength;
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
    [self lazyResize:NO];

    if (row < 0 || row+count > maxRows || bottom > maxRows || left < 0
            || right > maxColumns)
        return;

    int total = 1 + bottom - row;
    int move = total - count;
    int width = right - left + 1;
    int destRow = row;
    NSRange destRange, srcRange;
    int i;

    for (i = 0; i < move; ++i, ++destRow) {
        int acol = left;
        int acells = width;
        destRange = [self charRangeForRow:destRow column:&acol cells:&acells];
#if MM_TS_PARANOIA_LOG
        if (acells != width || acol != left)
            ASLogErr(@"INTERNAL ERROR");
#endif

        acol = left; acells = width;
        srcRange = [self charRangeForRow:(destRow+count) column:&acol
                                   cells:&acells];
#if MM_TS_PARANOIA_LOG
        if (acells != width || acol != left)
            ASLogErr(@"INTERNAL ERROR");
#endif

        if (NSNotFound == destRange.location || NSNotFound == srcRange.location)
        {
#if MM_TS_PARANOIA_LOG
            ASLogErr(@"INTERNAL ERROR: Out of bounds");
#endif
            return;
        }

        NSAttributedString *srcString = [backingStore
                attributedSubstringFromRange:srcRange];

        [backingStore replaceCharactersInRange:destRange
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
        int acol = left;
        int acells = width;
        destRange = [self charRangeForRow:destRow column:&acol cells:&acells];
#if MM_TS_PARANOIA_LOG
        if (acells != width || acol != left)
            ASLogErr(@"INTERNAL ERROR");
#endif
        if (NSNotFound == destRange.location) {
#if MM_TS_PARANOIA_LOG
            ASLogErr(@"INTERNAL ERROR: Out of bounds");
#endif
            return;
        }

        [backingStore replaceCharactersInRange:destRange
                          withAttributedString:emptyString];
        [backingStore setAttributes:attribs
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
    [self lazyResize:NO];

    if (row < 0 || row+count > maxRows || bottom > maxRows || left < 0
            || right > maxColumns)
        return;

    int total = 1 + bottom - row;
    int move = total - count;
    int width = right - left + 1;
    int destRow = bottom;
    int srcRow = row + move - 1;
    NSRange destRange, srcRange;
    int i;

    for (i = 0; i < move; ++i, --destRow, --srcRow) {
        int acol = left;
        int acells = width;
        destRange = [self charRangeForRow:destRow column:&acol cells:&acells];
#if MM_TS_PARANOIA_LOG
        if (acells != width || acol != left)
            ASLogErr(@"INTERNAL ERROR");
#endif

        acol = left; acells = width;
        srcRange = [self charRangeForRow:srcRow column:&acol cells:&acells];
#if MM_TS_PARANOIA_LOG
        if (acells != width || acol != left)
            ASLogErr(@"INTERNAL ERROR");
#endif
        if (NSNotFound == destRange.location || NSNotFound == srcRange.location)
        {
#if MM_TS_PARANOIA_LOG
            ASLogErr(@"INTERNAL ERROR: Out of bounds");
#endif
            return;
        }

        NSAttributedString *srcString = [backingStore
                attributedSubstringFromRange:srcRange];
        [backingStore replaceCharactersInRange:destRange
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
        int acol = left;
        int acells = width;
        destRange = [self charRangeForRow:destRow column:&acol cells:&acells];
#if MM_TS_PARANOIA_LOG
        if (acells != width || acol != left)
            ASLogErr(@"INTERNAL ERROR");
#endif
        if (NSNotFound == destRange.location) {
#if MM_TS_PARANOIA_LOG
            ASLogErr(@"INTERNAL ERROR: Out of bounds");
#endif
            return;
        }

        [backingStore replaceCharactersInRange:destRange
                          withAttributedString:emptyString];
        [backingStore setAttributes:attribs
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
        int acol = col1;
        int acells = cells;
        range = [self charRangeForRow:r column:&acol cells:&acells];
#if MM_TS_PARANOIA_LOG
        if (acells != cells || acol != col1)
            ASLogErr(@"INTERNAL ERROR");
#endif
        if (NSNotFound == range.location) {
#if MM_TS_PARANOIA_LOG
            ASLogErr(@"INTERNAL ERROR: Out of bounds");
#endif
            return;
        }

        [backingStore replaceCharactersInRange:range
                          withAttributedString:emptyString];
        [backingStore setAttributes:attribs
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
        [boldItalicFont release];  boldItalicFont = nil;
        [italicFont release];  italicFont = nil;
        [boldFont release];  boldFont = nil;
        [font release];  font = nil;

        // NOTE! When setting a new font we make sure that the advancement of
        // each glyph is fixed.

        float em = [@"m" sizeWithAttributes:
                [NSDictionary dictionaryWithObject:newFont
                                            forKey:NSFontAttributeName]].width;
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
        if (lm) {
            cellSize.height = linespace + [lm defaultLineHeightForFont:font];
            cellSize.width = columnspace + ceilf(em * cellWidthMultiplier);
        } else {
            // Should never happen, set some bogus value for cell height.
            ASLogWarn(@"No layout manager available");
            cellSize.height = linespace + 16.0;
        }

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
        [boldItalicFontWide release];  boldItalicFontWide = nil;
        [italicFontWide release];  italicFontWide = nil;
        [boldFontWide release];  boldFontWide = nil;
        [fontWide release];  fontWide = nil;

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

- (NSFont*)fontWide
{
    return fontWide;
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
    NSRect rect = { {0, 0}, {0, 0} };
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
    NSRect rect = { {0, 0}, {0, 0} };
    unsigned start = range.location > maxColumns ? maxColumns : range.location;
    unsigned length = range.length;

    if (start+length > maxColumns)
        length = maxColumns - start;

    rect.origin.x = cellSize.width * start;
    rect.size.width = cellSize.width * length;

    return rect;
}

- (NSUInteger)characterIndexForRow:(int)row column:(int)col
{
    int cells = 1;
    NSRange range = [self charRangeForRow:row column:&col cells:&cells];
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
    int cells = 1;
    NSRange r = [self charRangeForRow:row column:&col cells:&cells];
    if (NSNotFound != r.location
            && [backingStore attribute:MMWideCharacterAttributeName
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
    int cells = 1;
    NSRange range = [self charRangeForRow:row column:&col cells:&cells];
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

    NSRange oldRange = NSMakeRange(0, [backingStore length]);

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

    [backingStore release];
    backingStore = [[NSMutableAttributedString alloc] init];
    for (i=0; i<maxRows; ++i) {
#if MM_USE_ROW_CACHE
        rowCache[i].length = actualColumns + 1;
#endif
        [backingStore appendAttributedString:emptyRowString];
    }

    NSRange fullRange = NSMakeRange(0, [backingStore length]);
    [self edited:(NSTextStorageEditedCharacters|NSTextStorageEditedAttributes)
           range:oldRange changeInLength:fullRange.length-oldRange.length];
}

- (NSRange)charRangeForRow:(int)row column:(int*)pcol cells:(int*)pcells
{
    int col = *pcol;
    int cells = *pcells;

    // If no wide chars are used and if every char has length 1 (no composing
    // characters, no > 16 bit characters), then we can compute the range.
    if (characterEqualsColumn)
        return NSMakeRange(row*(actualColumns+1) + col, cells);

    NSString *string = [backingStore string];
    unsigned stringLen = [string length];
    NSRange r, range = { NSNotFound, 0 };
    unsigned idx;
    int i;

    if (row < 0 || row >= actualRows || col < 0 || col >= actualColumns
            || col+cells > actualColumns) {
#if MM_TS_PARANOIA_LOG
        ASLogErr(@"row=%d col=%d cells=%d is out of range (length=%d)",
                 row, col, cells, stringLen);
#endif
        return range;
    }

#if MM_USE_ROW_CACHE
    // Locate the beginning of the row
    MMRowCacheEntry *cache = rowCache;
    idx = 0;
    for (i = 0; i < row; ++i, ++cache)
        idx += cache->length;

    int rowEnd = idx + cache->length;
#else
    // Locate the beginning of the row by scanning for EOL characters.
    r.location = 0;
    for (i = 0; i < row; ++i) {
        r.length = stringLen - r.location;
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

#if 0  // Backward search seems to be broken...
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
                if (idx >= stringLen)
                    return NSMakeRange(NSNotFound, 0);
                r = [string rangeOfComposedCharacterSequenceAtIndex:idx];

                // Wide chars take up two display cells.
                if ([backingStore attribute:MMWideCharacterAttributeName
                                    atIndex:idx
                             effectiveRange:nil])
                    ++i;

                idx += r.length;
                ++i;
            }
        } else if (col < i) {
            // Backward search
            while (col < i) {
                if (idx-1 >= stringLen)
                    return NSMakeRange(NSNotFound, 0);
                r = [string rangeOfComposedCharacterSequenceAtIndex:idx-1];
                idx -= r.length;
                --i;

                // Wide chars take up two display cells.
                if ([backingStore attribute:MMWideCharacterAttributeName
                                    atIndex:idx
                             effectiveRange:nil])
                    --i;
            }
        }

        *pcol = i;
        cache->col = i;
        cache->colOffset = idx - range.location;
#else
        // Cache miss
        if (col < i) {
            // Search forward from beginning of line.
            i = 0;
        } else {
            // Search forward from cache spot.
            idx += cache->colOffset;
        }

        // Forward search
        while (col > i) {
            if (idx >= stringLen)
                return NSMakeRange(NSNotFound, 0);
            r = [string rangeOfComposedCharacterSequenceAtIndex:idx];

            // Wide chars take up two display cells.
            if ([backingStore attribute:MMWideCharacterAttributeName
                                atIndex:idx
                         effectiveRange:nil])
                ++i;

            idx += r.length;
            ++i;
        }

        *pcol = i;
        cache->col = i;
        cache->colOffset = idx - range.location;
#endif
    }
#else
    idx = r.location;
    for (i = 0; i < col; ++i) {
        if (idx >= stringLen)
            return NSMakeRange(NSNotFound, 0);
        r = [string rangeOfComposedCharacterSequenceAtIndex:idx];

        // Wide chars take up two display cells.
        if ([backingStore attribute:MMWideCharacterAttributeName
                            atIndex:idx
                     effectiveRange:nil])
            ++i;

        idx += r.length;
    }
#endif

    // Count the number of characters that cover the cells.
    range.location = idx;
    for (i = 0; i < cells; ++i) {
        if (idx >= stringLen)
            return NSMakeRange(NSNotFound, 0);
        r = [string rangeOfComposedCharacterSequenceAtIndex:idx];

        // Wide chars take up two display cells.
        if ([backingStore attribute:MMWideCharacterAttributeName
                            atIndex:idx
                     effectiveRange:nil])
            ++i;

        idx += r.length;
        range.length += r.length;
    }

    *pcells = i;

#if MM_TS_PARANOIA_LOG
#if MM_USE_ROW_CACHE
    if (range.location >= rowEnd-1) {
        ASLogErr(@"INTERNAL ERROR: row=%d col=%d cells=%d --> range=%@",
                 row, col, cells, NSStringFromRange(range));
        range.location = rowEnd - 2;
        range.length = 1;
    } else if (NSMaxRange(range) >= rowEnd) {
        ASLogErr(@"INTERNAL ERROR: row=%d col=%d cells=%d --> range=%@",
                 row, col, cells, NSStringFromRange(range));
        range.length = rowEnd - range.location - 1;
    }
#endif

    if (NSMaxRange(range) > stringLen) {
        ASLogErr(@"INTERNAL ERROR: row=%d col=%d cells=%d --> range=%@",
                 row, col, cells, NSStringFromRange(range));
        range.location = NSNotFound;
        range.length = 0;
    }
#endif

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
        invalidRange = [[backingStore string]
            rangeOfCharacterFromSet:invalidCharacterSet
                            options:NSLiteralSearch
                              range:range];
        if (NSNotFound == invalidRange.location)
            break;

        [backingStore replaceCharactersInRange:invalidRange withString:@" "];

        end = NSMaxRange(invalidRange);
        range.length -= end - range.location;
        range.location = end;
    }
}

@end // MMTextStorage (Private)
