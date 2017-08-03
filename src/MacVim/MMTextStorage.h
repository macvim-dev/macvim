/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MacVim.h"


#define MM_USE_ROW_CACHE 1


#if MM_USE_ROW_CACHE
typedef struct {
    unsigned    length;     // length of row in unichars
    int         col;        // last column accessed (in this row)
    unsigned    colOffset;  // offset of 'col' from start of row (in unichars)
} MMRowCacheEntry;
#endif



@interface MMTextStorage : NSTextStorage {
    NSTextStorage               *backingStore;
    int                         maxRows, maxColumns;
    int                         actualRows, actualColumns;
    NSAttributedString          *emptyRowString;
    NSFont                      *font;
    NSFont                      *boldFont;
    NSFont                      *italicFont;
    NSFont                      *boldItalicFont;
    NSFont                      *fontWide;
    NSFont                      *boldFontWide;
    NSFont                      *italicFontWide;
    NSFont                      *boldItalicFontWide;
    NSColor                     *defaultBackgroundColor;
    NSColor                     *defaultForegroundColor;
    NSSize                      cellSize;
    float                       linespace;
    float                       columnspace;
#if MM_USE_ROW_CACHE
    MMRowCacheEntry             *rowCache;
#endif
    BOOL                        characterEqualsColumn;
}

- (NSString *)string;
- (NSDictionary *)attributesAtIndex:(NSUInteger)index
                     effectiveRange:(NSRangePointer)aRange;
- (void)replaceCharactersInRange:(NSRange)aRange
                      withString:(NSString *)aString;
- (void)setAttributes:(NSDictionary *)attributes range:(NSRange)aRange;

- (int)maxRows;
- (int)maxColumns;
- (int)actualRows;
- (int)actualColumns;
- (float)linespace;
- (float)columnspace;
- (void)setLinespace:(float)newLinespace;
- (void)setColumnspace:(float)newColumnspace;
- (void)getMaxRows:(int*)rows columns:(int*)cols;
- (void)setMaxRows:(int)rows columns:(int)cols;
- (void)drawString:(NSString *)string atRow:(int)row column:(int)col
             cells:(int)cells withFlags:(int)flags
   foregroundColor:(NSColor *)fg backgroundColor:(NSColor *)bg
      specialColor:(NSColor *)sp;
- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(NSColor *)color;
- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(NSColor *)color;
- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(NSColor *)color;
- (void)clearAll;
- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor;
- (void)setFont:(NSFont *)newFont;
- (void)setWideFont:(NSFont *)newFont;
- (NSFont *)font;
- (NSFont *)fontWide;
- (NSColor *)defaultBackgroundColor;
- (NSColor *)defaultForegroundColor;
- (NSSize)size;
- (NSSize)cellSize;
- (NSRect)rectForRowsInRange:(NSRange)range;
- (NSRect)rectForColumnsInRange:(NSRange)range;
- (NSUInteger)characterIndexForRow:(int)row column:(int)col;
- (BOOL)resizeToFitSize:(NSSize)size;
- (NSSize)fitToSize:(NSSize)size;
- (NSSize)fitToSize:(NSSize)size rows:(int *)rows columns:(int *)columns;
- (NSRect)boundingRectForCharacterAtRow:(int)row column:(int)col;
#if MM_USE_ROW_CACHE
- (MMRowCacheEntry *)rowCache;
#endif

@end
