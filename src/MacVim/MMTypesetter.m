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
 * MMTypesetter
 *
 * Ensures that each line has a fixed height and deals with some baseline
 * issues.
 */

#import "MMTextStorage.h"
#import "MMTypesetter.h"
#import "Miscellaneous.h"




@implementation MMTypesetter

- (void)willSetLineFragmentRect:(NSRectPointer)lineRect
                  forGlyphRange:(NSRange)glyphRange
                       usedRect:(NSRectPointer)usedRect
                 baselineOffset:(CGFloat *)baselineOffset
{
    MMTextStorage *ts = (MMTextStorage*)[[self layoutManager] textStorage];
    float h = [ts cellSize].height;

    // HACK! Force each line fragment rect to have a fixed height.  By also
    // forcing the 'usedRect' to the same height we also ensure that the cursor
    // is as high as the line itself.
    lineRect->size.height = h;
    usedRect->size.height = h;

    // See [MMTextStorage setLinespace:] for info on how 'linespace' support
    // works.
    *baselineOffset += floor(.5*[ts linespace]);
}

#if 0
- (void)setNotShownAttribute:(BOOL)flag forGlyphRange:(NSRange)glyphRange
{
    if (1 != glyphRange.length)
        return;

    NSLayoutManager *lm = [self layoutManager];
    unsigned charIdx = [lm characterIndexForGlyphAtIndex:glyphRange.location];

    if ('\n' == [[[lm textStorage] string] characterAtIndex:charIdx])
        [lm setNotShownAttribute:flag forGlyphAtIndex:glyphRange.location];
}
#endif

#if 0
- (NSTypesetterControlCharacterAction)
    actionForControlCharacterAtIndex:(unsigned)charIndex
{
    /*NSTextStorage *ts = [[self layoutManager] textStorage];

    if ('\n' == [[ts string] characterAtIndex:charIndex])
        return NSTypesetterLineBreakAction;*/

    return NSTypesetterWhitespaceAction;
}
#endif

#if 0
- (void)setLocation:(NSPoint)location
        withAdvancements:(const float *)advancements
    forStartOfGlyphRange:(NSRange)glyphRange
{
    ASLogDebug(@"setLocation:%@ withAdvancements:%f forStartOfGlyphRange:%@",
               NSStringFromPoint(location), advancements ? *advancements : 0,
               NSStringFromRange(glyphRange));
    [super setLocation:location withAdvancements:advancements
            forStartOfGlyphRange:glyphRange];
}
#endif


@end // MMTypesetter




#if MM_USE_ROW_CACHE

@implementation MMTypesetter2

//
// Layout glyphs so that each line fragment has a fixed size.
//
// It is assumed that the font for each character has been chosen so that every
// glyph has the right advancement (either 2*cellSize.width or half that,
// depending on whether it is a wide character or not).  This is taken care of
// by MMTextStorage in setAttributes:range: and in setFont:.  All that is left
// for the typesetter to do is to make sure each line fragment has the same
// height and that EOL glyphs are hidden.
//
- (void)layoutGlyphsInLayoutManager:(NSLayoutManager *)lm
               startingAtGlyphIndex:(NSUInteger)startGlyphIdx
           maxNumberOfLineFragments:(NSUInteger)maxNumLines
                     nextGlyphIndex:(NSUInteger *)nextGlyph
{
    // TODO: Check that it really is an MMTextStorage?
    MMTextStorage *ts = (MMTextStorage*)[lm textStorage];
    NSTextContainer *tc = [[lm firstTextView] textContainer];
    NSFont *font = [ts font];
    NSString *text = [ts string];

    if (!(lm && ts && tc && font && text
                && [lm isValidGlyphIndex:startGlyphIdx]))
        return;

    // Note that we always start laying out lines from the beginning of a line,
    // even if 'startCharIdx' may be somewhere in the middle.
    unsigned startCharIdx = [lm characterIndexForGlyphAtIndex:startGlyphIdx];
    if (startCharIdx >= [text length])
        return;

    [lm setTextContainer:tc forGlyphRange:
            [lm glyphRangeForCharacterRange:NSMakeRange(0, [text length])
                       actualCharacterRange:nil]];

    //
    // STEP 1: Locate the line containing 'startCharIdx'.
    //
    MMRowCacheEntry *cache = [ts rowCache];
    unsigned lineIdx = 0, nextLineIdx = 0;
    int actualRows = [ts actualRows];
    int line = 0;

    for (; line < actualRows; ++line, ++cache) {
        lineIdx = nextLineIdx;
        nextLineIdx += cache->length;
        if (startCharIdx < nextLineIdx)
            break;
    }

    //
    // STEP 2: Generate line fragment rects one line at a time until there are
    // no more lines in the text storage, or until 'maxNumLines' have been
    // exhausted.  (There is no point in just laying out one line, the layout
    // manager will keep calling this method until there are no more lines in
    // the text storage.)
    //

    // NOTE: With non-zero linespace the baseline is adjusted so that the text
    // is centered within a line.
    float baseline = [font descender] - floor(.5*[ts linespace])
        + [[NSUserDefaults standardUserDefaults]
                floatForKey:MMBaselineOffsetKey];
    NSSize cellSize = [ts cellSize];
    NSPoint glyphPt = { 0, cellSize.height+baseline };

    NSRange lineRange = { lineIdx, 0 };
    NSRange glyphRange = { startGlyphIdx, 0 };
    NSRect lineRect = { {0, line*cellSize.height},
                        {[ts actualColumns]*cellSize.width, cellSize.height} };
    int endLine = line + maxNumLines;
    if (endLine > actualRows)
        endLine = actualRows;

    for (; line < endLine; ++line, ++cache) {
        lineRange.length = cache->length;

        glyphRange = [lm glyphRangeForCharacterRange:lineRange
                                actualCharacterRange:nil];

        [lm setLineFragmentRect:lineRect forGlyphRange:glyphRange
                       usedRect:lineRect];
        [lm setLocation:glyphPt forStartOfGlyphRange:glyphRange];

        lineRange.location += lineRange.length;
        lineRect.origin.y += cellSize.height;

        // Hide EOL character (otherwise a square will be rendered).
        [lm setNotShownAttribute:YES forGlyphAtIndex:lineRange.location-1];
    }

    if (nextGlyph)
        *nextGlyph = NSMaxRange(glyphRange);
}

@end // MMTypesetter2

#endif // MM_USE_ROW_CACHE

