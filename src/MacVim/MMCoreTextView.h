/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import <Cocoa/Cocoa.h>
#import "Miscellaneous.h" // Defines MM_ENABLE_ATSUI

#if !MM_ENABLE_ATSUI

@class MMTextViewHelper;


@interface MMCoreTextView : NSView <NSTextInput> {
    // From MMTextStorage
    int                         maxRows, maxColumns;
    NSColor                     *defaultBackgroundColor;
    NSColor                     *defaultForegroundColor;
    NSSize                      cellSize;
    NSFont                      *font;
    float                       linespace;

    // From NSTextView
    NSSize                      insetSize;

    float                       fontDescent;
    BOOL                        antialias;
    NSMutableArray              *drawData;

    MMTextViewHelper            *helper;

    unsigned                    maxlen;
    CGGlyph                     *glyphs;
    CGSize                      *advances;

    NSRect                      lastClearRect;
}

- (id)initWithFrame:(NSRect)frame;

//
// MMTextStorage methods
//
- (int)maxRows;
- (int)maxColumns;
- (void)getMaxRows:(int*)rows columns:(int*)cols;
- (void)setMaxRows:(int)rows columns:(int)cols;
- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor;
- (NSColor *)defaultBackgroundColor;
- (NSColor *)defaultForegroundColor;
- (NSRect)rectForRowsInRange:(NSRange)range;
- (NSRect)rectForColumnsInRange:(NSRange)range;

- (void)setFont:(NSFont *)newFont;
- (void)setWideFont:(NSFont *)newFont;
- (NSFont *)font;
- (NSFont *)fontWide;
- (NSSize)cellSize;
- (void)setLinespace:(float)newLinespace;

//
// MMTextView methods
//
- (void)setShouldDrawInsertionPoint:(BOOL)on;
- (void)setPreEditRow:(int)row column:(int)col;
- (void)setMouseShape:(int)shape;
- (void)setAntialias:(BOOL)state;
- (void)setImControl:(BOOL)enable;
- (void)activateIm:(BOOL)enable;
- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column;

//
// NSTextView methods
//
- (void)keyDown:(NSEvent *)event;
- (void)insertText:(id)string;
- (void)doCommandBySelector:(SEL)selector;
- (BOOL)performKeyEquivalent:(NSEvent *)event;

//
// NSTextContainer methods
//
- (void)setTextContainerInset:(NSSize)inset;

//
// MMCoreTextView methods
//
- (void)performBatchDrawWithData:(NSData *)data;
- (NSSize)desiredSize;
- (NSSize)minSize;
- (NSSize)constrainRows:(int *)rows columns:(int *)cols toSize:(NSSize)size;

@end

#endif // !MM_ENABLE_ATSUI
