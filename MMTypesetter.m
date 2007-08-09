/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMTypesetter.h"
#import "MMTextStorage.h"
#import "MMAppController.h"



#if 0
@interface MMTypesetter (Private)
- (NSCharacterSet *)hiddenCharSet;
@end
#endif



@implementation MMTypesetter

//
// Layout glyphs so that each glyph takes up exactly one cell.
//
// The width of a cell is determined by [MMTextStorage cellWidth] (which
// typically sets one cell to equal the width of 'W' in the current font), and
// the height of a cell is given by the default line height for the current
// font.
//
// It is assumed that the text storage is set up so that each wide character is
// followed by a 'zero-width space' character (Unicode 0x200b); these are not
// rendered.  If a wide character is not followed by a zero-width space, then
// the next character will render on top of it.
//
- (void)layoutGlyphsInLayoutManager:(NSLayoutManager *)lm
               startingAtGlyphIndex:(unsigned)startGlyphIdx
           maxNumberOfLineFragments:(unsigned)maxNumLines
                     nextGlyphIndex:(unsigned *)nextGlyph
{
    // TODO: Check that it really is an MMTextStorage.
    MMTextStorage *ts = (MMTextStorage*)[lm textStorage];
    NSTextView *tv = [lm firstTextView];
    NSTextContainer *tc = [tv textContainer];
    NSFont *font = [ts font];
    NSString *text = [ts string];
    unsigned textLen = [text length];
    float cellWidth = [ts cellWidth];
    float cellHeight = [lm defaultLineHeightForFont:font];
    float baseline = [font descender];

    if (!(ts && tv && tc && font && text && textLen))
        return;

    float baselineOffset = [[NSUserDefaults standardUserDefaults]
            floatForKey:MMBaselineOffsetKey];

    baseline += baselineOffset;

    unsigned startCharIdx = [lm characterIndexForGlyphAtIndex:startGlyphIdx];
    unsigned i, numberOfLines = 0, firstLine = 0;
    NSRange firstLineRange = { 0, 0 };

    // Find first line and its range, and count the number of lines.
    for (i = 0; i < textLen; numberOfLines++) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(i, 0)];
        if (NSLocationInRange(startCharIdx, lineRange)) {
            firstLine = numberOfLines;
            firstLineRange = lineRange;
        }

        i = NSMaxRange(lineRange);
    }

    // Perform line fragment generation one line at a time.
    NSRange lineRange = firstLineRange;
    unsigned endGlyphIdx = startGlyphIdx;
    for (i = 0; i < maxNumLines && lineRange.length; ++i) {
        NSRange glyphRange = [lm glyphRangeForCharacterRange:lineRange
                                        actualCharacterRange:nil];
        NSRect lineRect = { 0, (firstLine+i)*cellHeight,
                cellWidth*(lineRange.length-1), cellHeight };
        unsigned endLineIdx = NSMaxRange(lineRange);
        NSPoint glyphPt = { 0, cellHeight+baseline };
        unsigned j;

        endGlyphIdx = NSMaxRange(glyphRange);

        [lm setTextContainer:tc forGlyphRange:glyphRange];
        [lm setLineFragmentRect:lineRect forGlyphRange:glyphRange
                       usedRect:lineRect];
        //[lm setLocation:glyphPt forStartOfGlyphRange:glyphRange];

        // Position each glyph individually to ensure they take up exactly one
        // cell.
        for (j = glyphRange.location; j < endGlyphIdx; ++j) {
            [lm setLocation:glyphPt forStartOfGlyphRange:NSMakeRange(j, 1)];
            glyphPt.x += cellWidth;
        }

        // Hide non-zero space characters (there is one after every wide
        // character).
        for (j = lineRange.location; j < endLineIdx; ++j) {
            if ([text characterAtIndex:j] == 0x200b) {
                NSRange range = { j, 1 };
                range = [lm glyphRangeForCharacterRange:range
                                   actualCharacterRange:nil];
                [lm setNotShownAttribute:YES forGlyphAtIndex:range.location];
            }
        }

        lineRange = [text lineRangeForRange:NSMakeRange(endLineIdx, 0)];
    }

    if (nextGlyph)
        *nextGlyph = endGlyphIdx;
}

@end // MMTypesetter




#if 0
@implementation MMTypesetter (Private)

- (NSCharacterSet *)hiddenCharSet
{
    static NSCharacterSet *hiddenCharSet = nil;

    if (!hiddenCharSet) {
        NSString *string = [NSString stringWithFormat:@"%C\n", 0x200b];
        hiddenCharSet = [NSCharacterSet
                characterSetWithCharactersInString:string];
        [hiddenCharSet retain];
    }

    return hiddenCharSet;
}

@end // MMTypesetter (Private)
#endif
