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

#if (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
// Need Carbon for TIS...() functions
#import <Carbon/Carbon.h>
#endif


#define BLUE(argb)      ((argb & 0xff)/255.0f)
#define GREEN(argb)     (((argb>>8) & 0xff)/255.0f)
#define RED(argb)       (((argb>>16) & 0xff)/255.0f)
#define ALPHA(argb)     (((argb>>24) & 0xff)/255.0f)


@interface MMTextViewHelper : NSObject {
    id                  textView;
    BOOL                isDragging;
    int                 dragRow;
    int                 dragColumn;
    int                 dragFlags;
    NSPoint             dragPoint;
    BOOL                isAutoscrolling;
    int                 mouseShape;
    NSColor             *insertionPointColor;
    BOOL                interpretKeyEventsSwallowedKey;
    NSEvent             *currentEvent;
    NSMutableDictionary *signImages;

    // Input Manager
    NSRange             imRange;
    NSRange             markedRange;
    NSDictionary        *markedTextAttributes;
    NSMutableAttributedString   *markedText;
    int                 preEditRow;
    int                 preEditColumn;
    BOOL                imControl;
    BOOL                imState;
#if (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
    TISInputSourceRef   lastImSource;
    TISInputSourceRef   asciiImSource;
#endif
}

- (id)init;
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
#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6)
- (void)swipeWithEvent:(NSEvent *)event;
#endif
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
- (void)setImControl:(BOOL)enable;
- (void)activateIm:(BOOL)enable;
- (BOOL)useInlineIm;
#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5)
- (void)checkImState;
#endif

@end
