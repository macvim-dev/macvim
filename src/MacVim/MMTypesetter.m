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
#import "MacVim.h"


// The 'linerange' functions count U+2028 and U+2029 as line end characters,
// which causes rendering to be screwed up because Vim does not count them as
// line end characters.
#define MM_USE_LINERANGE 0


#if 0
@interface MMTypesetter (Private)
- (NSCharacterSet *)hiddenCharSet;
@end
#endif



@implementation MMTypesetter

//
// Layout glyphs so that each line fragment has a fixed size.
//
// It is assumed that the font for each character has been chosen so that every
// glyph has the right advancement (either 2*cellSize.width or half that,
// depending on whether it is a wide character or not).  This is taken care of
// by MMTextStorage in setAttributes:range: and in setFont:.  All that is left
// for the typesetter to do is to make sure each line fragment has the same
// height and that unwanted glyphs are hidden.
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
    NSSize cellSize = [ts cellSize];
    // NOTE: With non-zero linespace the baseline is adjusted so that the text
    // is centered within a line.
    float baseline = [font descender] - floor(.5*[ts linespace]);

    if (!(lm && ts && tv && tc && font && text && textLen
                && [lm isValidGlyphIndex:startGlyphIdx]))
        return;

    float baselineOffset = [[NSUserDefaults standardUserDefaults]
            floatForKey:MMBaselineOffsetKey];

    baseline += baselineOffset;

    unsigned startCharIdx = [lm characterIndexForGlyphAtIndex:startGlyphIdx];
    unsigned i, numberOfLines = 0, firstLine = 0;
    NSRange firstLineRange = { 0, 0 };

#if MM_USE_LINERANGE
    // Find the first line and its range, and count the number of lines.  (This
    // info could also be gleaned from MMTextStorage, but we do it here anyway
    // to make absolutely sure everything is right.)
    for (i = 0; i < textLen; numberOfLines++) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(i, 0)];
        if (NSLocationInRange(startCharIdx, lineRange)) {
            firstLine = numberOfLines;
            firstLineRange = lineRange;
        }

        i = NSMaxRange(lineRange);
    }
#else
    unsigned stride = 1 + [ts actualColumns];
    numberOfLines = [ts actualRows];
    firstLine = (unsigned)(startCharIdx/stride);
    firstLineRange.location =  firstLine * stride;
    unsigned len = [text length] - firstLineRange.location;
    firstLineRange.length = len < stride ? len : stride;
#endif

    // Perform line fragment generation one line at a time.
    NSRange lineRange = firstLineRange;
    unsigned endGlyphIdx = startGlyphIdx;
    for (i = 0; i < maxNumLines && lineRange.length; ++i) {
        NSRange glyphRange = [lm glyphRangeForCharacterRange:lineRange
                                        actualCharacterRange:nil];
        NSRect lineRect = { 0, (firstLine+i)*cellSize.height,
                cellSize.width*(lineRange.length-1), cellSize.height };
        unsigned endLineIdx = NSMaxRange(lineRange);
        NSPoint glyphPt = { 0, cellSize.height+baseline };
        unsigned j;

        endGlyphIdx = NSMaxRange(glyphRange);

        [lm setTextContainer:tc forGlyphRange:glyphRange];
        [lm setLineFragmentRect:lineRect forGlyphRange:glyphRange
                       usedRect:lineRect];
        [lm setLocation:glyphPt forStartOfGlyphRange:glyphRange];

        // Hide end-of-line and non-zero space characters (there is one after
        // every wide character).
        for (j = lineRange.location; j < endLineIdx; ++j) {
            unichar ch = [text characterAtIndex:j];
            if (ch == 0x200b || ch == '\n') {
                NSRange range = { j, 1 };
                range = [lm glyphRangeForCharacterRange:range
                                   actualCharacterRange:nil];
                [lm setNotShownAttribute:YES forGlyphAtIndex:range.location];
            }
        }

#if MM_USE_LINERANGE
        lineRange = [text lineRangeForRange:NSMakeRange(endLineIdx, 0)];
#else
        lineRange.location = endLineIdx;
        len = [text length] - lineRange.location;
        if (len < lineRange.length)
            lineRange.length = len;
#endif
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
