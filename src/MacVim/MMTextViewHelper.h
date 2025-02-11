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

// Need Carbon for TIS...() functions
#import <Carbon/Carbon.h>


#define BLUE(argb)      ((argb & 0xff)/255.0f)
#define GREEN(argb)     (((argb>>8) & 0xff)/255.0f)
#define RED(argb)       (((argb>>16) & 0xff)/255.0f)
#define ALPHA(argb)     (((argb>>24) & 0xff)/255.0f)
#define COMPONENTS(argb) ((CGFloat[]){RED(argb), GREEN(argb), BLUE(argb), ALPHA(argb)})


@interface MMTextViewHelper : NSObject {
    enum ScrollingDirection {
        ScrollingDirectionUnknown = 0,
        ScrollingDirectionVertical,
        ScrollingDirectionHorizontal,
    };

    id                  textView;
    BOOL                isDragging;
    int                 dragRow;
    int                 dragColumn;
    unsigned            dragFlags;
    NSPoint             dragPoint;
    BOOL                isAutoscrolling;
    int                 mouseShape;
    NSColor             *insertionPointColor;
    BOOL                interpretKeyEventsSwallowedKey;
    NSEvent             *currentEvent;
    NSMutableDictionary *signImages;
    BOOL                useMouseTime;
    NSDate              *mouseDownTime;
    CGFloat             scrollingDeltaX;
    CGFloat             scrollingDeltaY;
    enum ScrollingDirection scrollingDirection; ///< The fixed scrolling direction when using track pad (if configured to use it)

    // Input Manager
    NSRange             imRange;
    NSRange             markedRange;
    NSDictionary        *markedTextAttributes;
    NSMutableAttributedString   *markedText;
    int                 preEditRow; ///< The cursor's row. Note that this gets set no matter what. Doesn't matter if we are in pre-edit or not.
    int                 preEditColumn; ///< The cursor's column.
    BOOL                imControl;
    BOOL                imState;
    TISInputSourceRef   lastImSource;
    TISInputSourceRef   asciiImSource;
}

- (id)init;
- (void)setTextView:(id)view;
- (void)setInsertionPointColor:(NSColor *)color;
- (NSColor *)insertionPointColor;

- (void)keyDown:(NSEvent *)event;
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange;
- (void)doCommandBySelector:(SEL)selector;
- (void)scrollWheel:(NSEvent *)event;
- (void)mouseDown:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (void)swipeWithEvent:(NSEvent *)event;
- (void)pressureChangeWithEvent:(NSEvent *)event;
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender;
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender;
- (void)setMouseShape:(int)shape;
- (void)changeFont:(id)sender;
- (NSImage *)signImageForName:(NSString *)imgName;
- (void)deleteImage:(NSString *)imgName;

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
- (NSRect)firstRectForCharacterRange:(int)row column:(int)col length:(int)length;
- (void)setImControl:(BOOL)enable;
- (void)activateIm:(BOOL)enable;
- (BOOL)useInlineIm;
- (void)checkImState;

@end
