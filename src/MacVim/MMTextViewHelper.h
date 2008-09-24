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


enum {
    // These values are chosen so that the min text view size is not too small
    // with the default font (they only affect resizing with the mouse, you can
    // still use e.g. ":set lines=2" to go below these values).
    MMMinRows = 4,
    MMMinColumns = 30
};


@interface MMTextViewHelper : NSObject {
    id                  textView;
    BOOL                isDragging;
    int                 dragRow;
    int                 dragColumn;
    int                 dragFlags;
    NSPoint             dragPoint;
    BOOL                isAutoscrolling;
    int                 mouseShape;
    NSTrackingRectTag   trackingRectTag;
    NSColor             *insertionPointColor;

    // Input Manager
    NSRange             imRange;
    NSRange             markedRange;
    NSDictionary        *markedTextAttributes;
    NSMutableAttributedString  *markedText;
    int                 preEditRow;
    int                 preEditColumn;
}

- (void)setTextView:(id)view;
- (void)setInsertionPointColor:(NSColor *)color;
- (NSColor *)insertionPointColor;

- (void)keyDown:(NSEvent *)event;
- (void)insertText:(id)string;
- (void)doCommandBySelector:(SEL)selector;
- (BOOL)performKeyEquivalent:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;
- (void)mouseDown:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (void)mouseEntered:(NSEvent *)event;
- (void)mouseExited:(NSEvent *)event;
- (void)setFrame:(NSRect)frame;
- (void)viewDidMoveToWindow;
- (void)viewWillMoveToWindow:(NSWindow *)newWindow;
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender;
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender;
- (void)setMouseShape:(int)shape;

// Input Manager
- (BOOL)hasMarkedText;
- (NSRange)markedRange;
- (NSDictionary *)markedTextAttributes;
- (void)setMarkedTextAttributes:(NSDictionary *)attr;
- (void)setMarkedText:(id)text selectedRange:(NSRange)range;
- (void)unmarkText;
- (NSMutableAttributedString *)markedText;
- (void)setPreEditRow:(int)row column:(int)col;
- (int)preEditRow;
- (int)preEditColumn;
- (void)setImRange:(NSRange)range;
- (NSRange)imRange;
- (void)setMarkedRange:(NSRange)range;
- (NSRect)firstRectForCharacterRange:(NSRange)range;

@end
