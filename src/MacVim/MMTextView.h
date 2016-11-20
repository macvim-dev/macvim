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

@class MMTextViewHelper;


@interface MMTextView : NSTextView {
    BOOL                shouldDrawInsertionPoint;
    int                 insertionPointRow;
    int                 insertionPointColumn;
    int                 insertionPointShape;
    int                 insertionPointFraction;
    BOOL                antialias;
    BOOL                ligatures;
    BOOL                thinStrokes;
    NSRect              *invertRects;
    int                 numInvertRects;

    MMTextViewHelper    *helper;
}

- (id)initWithFrame:(NSRect)frame;

- (void)setPreEditRow:(int)row column:(int)col;
- (void)performBatchDrawWithData:(NSData *)data;
- (void)setMouseShape:(int)shape;
- (void)setAntialias:(BOOL)antialias;
- (void)setLigatures:(BOOL)ligatures;
- (void)setThinStrokes:(BOOL)thinStrokes;
- (void)setImControl:(BOOL)enable;
- (void)activateIm:(BOOL)enable;
- (void)checkImState;

//
// MMTextStorage methods
//
- (NSFont *)font;
- (void)setFont:(NSFont *)newFont;
- (NSFont *)fontWide;
- (void)setWideFont:(NSFont *)newFont;
- (NSSize)cellSize;
- (void)setLinespace:(float)newLinespace;
- (int)maxRows;
- (int)maxColumns;
- (void)getMaxRows:(int*)rows columns:(int*)cols;
- (void)setMaxRows:(int)rows columns:(int)cols;
- (NSRect)rectForRowsInRange:(NSRange)range;
- (NSRect)rectForColumnsInRange:(NSRange)range;
- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor;
- (NSColor *)defaultBackgroundColor;
- (NSColor *)defaultForegroundColor;

- (NSSize)constrainRows:(int *)rows columns:(int *)cols toSize:(NSSize)size;
- (NSSize)desiredSize;
- (NSSize)minSize;

- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column;
- (NSPoint)pointForRow:(int)row column:(int)col;
- (NSRect)rectForRow:(int)row column:(int)col numRows:(int)nr
          numColumns:(int)nc;

// NOT IMPLEMENTED (only in Core Text renderer)
- (void)deleteSign:(NSString *)signName;
- (void)setToolTipAtMousePoint:(NSString *)string;
- (void)setCGLayerEnabled:(BOOL)enabled;
@end
