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


enum { MMMaxCellsPerChar = 2 };

@class MMTextViewHelper;


@interface MMAtsuiTextView : NSView {
    // From MMTextStorage
    int                         maxRows, maxColumns;
    NSColor                     *defaultBackgroundColor;
    NSColor                     *defaultForegroundColor;
    NSSize                      cellSize;
    NSFont                      *font;
    float                       linespace;

    // From NSTextView
    NSSize                      insetSize;

    // From vim-cocoa
    NSImage                     *contentImage;
    NSSize                      imageSize;
    ATSUStyle                   atsuStyles[MMMaxCellsPerChar];
    BOOL                        antialias;

    MMTextViewHelper            *helper;
}

- (id)initWithFrame:(NSRect)frame;

//
// MMTextStorage methods
//
- (int)maxRows;
- (void)getMaxRows:(int*)rows columns:(int*)cols;
- (void)setMaxRows:(int)rows columns:(int)cols;
- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor;
- (NSRect)rectForRowsInRange:(NSRange)range;
- (NSRect)rectForColumnsInRange:(NSRange)range;

- (void)setFont:(NSFont *)newFont;
- (void)setWideFont:(NSFont *)newFont;
- (NSFont *)font;
- (NSSize)cellSize;
- (void)setLinespace:(float)newLinespace;

//
// MMTextView methods
//
- (void)setShouldDrawInsertionPoint:(BOOL)on;
- (void)setPreEditRow:(int)row column:(int)col;
- (void)hideMarkedTextField;
- (void)setMouseShape:(int)shape;
- (void)setAntialias:(BOOL)state;
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
// MMAtsuiTextView methods
//
- (void)performBatchDrawWithData:(NSData *)data;
- (NSSize)desiredSize;
- (NSSize)minSize;
- (NSSize)constrainRows:(int *)rows columns:(int *)cols toSize:(NSSize)size;

@end
