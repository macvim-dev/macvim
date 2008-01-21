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



@interface MMAtsuiTextView : NSView {
    // From MMTextStorage
    int                         maxRows, maxColumns;
    int                         actualRows, actualColumns;
    NSColor                     *defaultBackgroundColor;
    NSColor                     *defaultForegroundColor;
    NSSize                      cellSize;
    NSFont                      *font;
    float                       linespace;

    // From vim-cocoa
}

- (id)initWithFrame:(NSRect)frame;

//
// MMTextStorage methods
//
- (void)getMaxRows:(int*)rows columns:(int*)cols;
- (void)setMaxRows:(int)rows columns:(int)cols;
- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor;
- (NSSize)size;
- (NSSize)fitToSize:(NSSize)size rows:(int *)rows columns:(int *)columns;
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
- (NSEvent *)lastMouseDownEvent;
- (void)setShouldDrawInsertionPoint:(BOOL)on;
- (void)setPreEditRow:(int)row column:(int)col;
- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                       fraction:(int)percent color:(NSColor *)color;
- (void)hideMarkedTextField;

//
// NSTextView methods
//
- (void)keyDown:(NSEvent *)event;
- (void)insertText:(id)string;
- (void)doCommandBySelector:(SEL)selector;
- (BOOL)performKeyEquivalent:(NSEvent *)event;
- (NSPoint)textContainerOrigin;
- (void)setTextContainerInset:(NSSize)inset;
- (void)setBackgroundColor:(NSColor *)color;

//
// MMAtsuiTextView methods
//
- (void)performBatchDrawWithData:(NSData *)data;

@end
