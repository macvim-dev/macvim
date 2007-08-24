/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMTextView.h"
#import "MMTextStorage.h"
#import "MMWindowController.h"
#import "MMVimController.h"
#import "MacVim.h"



// The max/min drag timer interval in seconds
static NSTimeInterval MMDragTimerMaxInterval = .3f;
static NSTimeInterval MMDragTimerMinInterval = .01f;

// The number of pixels in which the drag timer interval changes
static float MMDragAreaSize = 73.0f;



@interface MMTextView (Private)
- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column;
- (NSRect)trackingRect;
- (void)dispatchKeyEvent:(NSEvent *)event;
- (MMVimController *)vimController;
- (void)startDragTimerWithInterval:(NSTimeInterval)t;
- (void)dragTimerFired:(NSTimer *)timer;
@end



@implementation MMTextView

- (void)dealloc
{
    [lastMouseDownEvent release];
    [super dealloc];
}

- (NSEvent *)lastMouseDownEvent
{
    return lastMouseDownEvent;
}

- (BOOL)shouldDrawInsertionPoint
{
    // NOTE: The insertion point is drawn manually in drawRect:.  It would be
    // nice to be able to use the insertion point related methods of
    // NSTextView, but it seems impossible to get them to work properly (search
    // the cocoabuilder archives).
    return NO;
}

- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                          color:(NSColor *)color
{
    // This only stores where to draw the insertion point, the actual drawing
    // is done in drawRect:.
    shouldDrawInsertionPoint = YES;
    insertionPointRow = row;
    insertionPointColumn = col;
    insertionPointShape = shape;

    [self setInsertionPointColor:color];
}

- (void)drawRect:(NSRect)rect
{
    [super drawRect:rect];

    if (shouldDrawInsertionPoint) {
        MMTextStorage *ts = (MMTextStorage*)[self textStorage];
        NSLayoutManager *lm = [self layoutManager];
        NSTextContainer *tc = [self textContainer];

        // Given (row,column), calculate the bounds of the glyph at that spot.
        // We use the layout manager because this gives us exactly the size and
        // location of the glyph so that we can match the insertion point to
        // it.
        unsigned charIdx = [ts characterIndexForRow:insertionPointRow
                                             column:insertionPointColumn];
        NSRange glyphRange =
            [lm glyphRangeForCharacterRange:NSMakeRange(charIdx,1)
                       actualCharacterRange:NULL];
        NSRect glyphRect = [lm boundingRectForGlyphRange:glyphRange
                                         inTextContainer:tc];
        glyphRect.origin.x += [self textContainerOrigin].x;
        glyphRect.origin.y += [self textContainerOrigin].y;

        if (MMInsertionPointHorizontal == insertionPointShape) {
            glyphRect.origin.y += glyphRect.size.height - 1;
            glyphRect.size.height = 2;
        } else if (MMInsertionPointVertical == insertionPointShape) {
            glyphRect.size.width = 2;
        }

        if (MMInsertionPointHollow == insertionPointShape) {
            // This looks very ugly.
            [[self insertionPointColor] set];
            //[NSBezierPath setDefaultLineWidth:2.0];
            //[NSBezierPath setDefaultLineJoinStyle:NSRoundLineJoinStyle];
            [NSBezierPath strokeRect:glyphRect];
        } else {
            NSRectFill(glyphRect);
        }

        // NOTE: We only draw the cursor once and rely on Vim to say when it
        // should be drawn again.
        shouldDrawInsertionPoint = NO;
    }
}

- (void)insertText:(id)string
{
    // NOTE!  This method is called for normal key presses but also for
    // Option-key presses --- even when Ctrl is held as well as Option.  When
    // Ctrl is held, the AppKit translates the character to a Ctrl+key stroke,
    // so 'string' need not be a printable character!  In this case it still
    // works to pass 'string' on to Vim as a printable character (since
    // modifiers are already included and should not be added to the input
    // buffer using CSI, K_MODIFIER).

    NSEvent *event = [NSApp currentEvent];
    //NSLog(@"%s%@ (event=%@)", _cmd, string, event);

    // HACK!  In order to be able to bind to <S-Space> etc. we have to watch
    // for when space was pressed.
    if ([event type] == NSKeyDown
            && [[event charactersIgnoringModifiers] length] > 0
            && [[event charactersIgnoringModifiers] characterAtIndex:0] == ' '
            && [event modifierFlags]
                & (NSShiftKeyMask|NSControlKeyMask|NSAlternateKeyMask))
    {
        [self dispatchKeyEvent:event];
        return;
    }

    [NSCursor setHiddenUntilMouseMoves:YES];

    [[self vimController] sendMessage:InsertTextMsgID
                 data:[string dataUsingEncoding:NSUTF8StringEncoding]
                 wait:NO];
}


- (void)doCommandBySelector:(SEL)selector
{
    // By ignoring the selector we effectively disable the key binding
    // mechanism of Cocoa.  Hopefully this is what the user will expect
    // (pressing Ctrl+P would otherwise result in moveUp: instead of previous
    // match, etc.).
    //
    // We usually end up here if the user pressed Ctrl+key (but not
    // Ctrl+Option+key).

    //NSLog(@"%s%@", _cmd, NSStringFromSelector(selector));
    [self dispatchKeyEvent:[NSApp currentEvent]];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    // Called for Cmd+key keystrokes, function keys, arrow keys, page
    // up/down, home, end.

    if ([event type] != NSKeyDown)
        return NO;

    // HACK!  Let the main menu try to handle any key down event, before
    // passing it on to vim, otherwise key equivalents for menus will
    // effectively be disabled.
    if ([[NSApp mainMenu] performKeyEquivalent:event])
        return YES;

    // HACK!  KeyCode 50 represent the key which switches between windows
    // within an application (like Cmd+Tab is used to switch between
    // applications).  Return NO here, else the window switching does not work.
    //
    // Will this hack work for all languages / keyboard layouts?
    if ([event keyCode] == 50)
        return NO;

    //NSLog(@"%s%@", _cmd, event);

    NSString *string = [event charactersIgnoringModifiers];
    int flags = [event modifierFlags];
    int len = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&flags length:sizeof(int)];
    [data appendBytes:&len length:sizeof(int)];
    [data appendBytes:[string UTF8String] length:len];

    [[self vimController] sendMessage:CmdKeyMsgID data:data wait:NO];

    return YES;
}

- (void)setMarkedText:(id)text selectedRange:(NSRange)range
{
    // TODO: Figure out a way to handle marked text, at the moment the user
    // has no way of knowing what has been added so far in a multi-stroke key.
    // E.g. hitting Option-e and then e will result in an 'e' with acute, but
    // nothing is displayed immediately after hitting Option-e.

    NSLog(@"setMarkedText:'%@' selectedRange:(%d,%d)", text, range.location,
            range.length);
}

- (void)scrollWheel:(NSEvent *)event
{
    if ([event deltaY] == 0)
        return;

    int row, col;
    NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
    if (![self convertPoint:pt toRow:&row column:&col])
        return;

    int flags = [event modifierFlags];
    float dy = [event deltaY];
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&row length:sizeof(int)];
    [data appendBytes:&col length:sizeof(int)];
    [data appendBytes:&flags length:sizeof(int)];
    [data appendBytes:&dy length:sizeof(float)];

    [[self vimController] sendMessage:ScrollWheelMsgID data:data wait:NO];
}

- (void)mouseDown:(NSEvent *)event
{
    int row, col;
    NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
    if (![self convertPoint:pt toRow:&row column:&col])
        return;

    lastMouseDownEvent = [event copy];

    int button = [event buttonNumber];
    int flags = [event modifierFlags];
    int count = [event clickCount];
    NSMutableData *data = [NSMutableData data];

    // If desired, intepret Ctrl-Click as a right mouse click.
    if ([[NSUserDefaults standardUserDefaults]
            boolForKey:MMTranslateCtrlClickKey]
            && button == 0 && flags & NSControlKeyMask) {
        button = 1;
        flags &= ~NSControlKeyMask;
    }

    [data appendBytes:&row length:sizeof(int)];
    [data appendBytes:&col length:sizeof(int)];
    [data appendBytes:&button length:sizeof(int)];
    [data appendBytes:&flags length:sizeof(int)];
    [data appendBytes:&count length:sizeof(int)];

    [[self vimController] sendMessage:MouseDownMsgID data:data wait:NO];
}

- (void)rightMouseDown:(NSEvent *)event
{
    [self mouseDown:event];
}

- (void)otherMouseDown:(NSEvent *)event
{
    [self mouseDown:event];
}

- (void)mouseUp:(NSEvent *)event
{
    int row, col;
    NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
    if (![self convertPoint:pt toRow:&row column:&col])
        return;

    int flags = [event modifierFlags];
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&row length:sizeof(int)];
    [data appendBytes:&col length:sizeof(int)];
    [data appendBytes:&flags length:sizeof(int)];

    [[self vimController] sendMessage:MouseUpMsgID data:data wait:NO];

    isDragging = NO;
}

- (void)rightMouseUp:(NSEvent *)event
{
    [self mouseUp:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
    [self mouseUp:event];
}

- (void)mouseDragged:(NSEvent *)event
{
    int flags = [event modifierFlags];
    int row, col;
    NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
    if (![self convertPoint:pt toRow:&row column:&col])
        return;

    // Autoscrolling is done in dragTimerFired:
    if (!isAutoscrolling) {
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&row length:sizeof(int)];
        [data appendBytes:&col length:sizeof(int)];
        [data appendBytes:&flags length:sizeof(int)];

        [[self vimController] sendMessage:MouseDraggedMsgID data:data wait:NO];
    }

    dragPoint = pt;
    dragRow = row; dragColumn = col; dragFlags = flags;
    if (!isDragging) {
        [self startDragTimerWithInterval:.5];
        isDragging = YES;
    }
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [self mouseDragged:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
    [self mouseDragged:event];
}

- (void)mouseMoved:(NSEvent *)event
{
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    if (!ts) return;

    NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
    int row, col;
    if (![self convertPoint:pt toRow:&row column:&col])
        return;

    // HACK! It seems impossible to get the tracking rects set up before the
    // view is visible, which means that the first mouseEntered: or
    // mouseExited: events are never received.  This forces us to check if the
    // mouseMoved: event really happened over the text.
    int rows, cols;
    [ts getMaxRows:&rows columns:&cols];
    if (row >= 0 && row < rows && col >= 0 && col < cols) {
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&row length:sizeof(int)];
        [data appendBytes:&col length:sizeof(int)];

        [[self vimController] sendMessage:MouseMovedMsgID data:data wait:NO];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    //NSLog(@"%s", _cmd);
    [[self window] setAcceptsMouseMovedEvents:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    //NSLog(@"%s", _cmd);

    int shape = 0;
    NSMutableData *data = [NSMutableData data];

    [[self window] setAcceptsMouseMovedEvents:NO];

    [data appendBytes:&shape length:sizeof(int)];
    [[self vimController] sendMessage:SetMouseShapeMsgID data:data wait:NO];

    if (isDragging) {
    }
}

- (void)setFrame:(NSRect)frame
{
    //NSLog(@"%s", _cmd);

    // When the frame changes we also need to update the tracking rect.
    [super setFrame:frame];
    [self removeTrackingRect:trackingRectTag];
    trackingRectTag = [self addTrackingRect:[self trackingRect] owner:self
                                   userData:NULL assumeInside:YES];
}

- (void)viewDidMoveToWindow
{
    //NSLog(@"%s (window=%@)", _cmd, [self window]);

    // Set a tracking rect which covers the text.
    // NOTE: While the mouse cursor is in this rect the view will receive
    // 'mouseMoved:' events so that Vim can take care of updating the mouse
    // cursor.
    if ([self window]) {
        [[self window] setAcceptsMouseMovedEvents:YES];
        trackingRectTag = [self addTrackingRect:[self trackingRect] owner:self
                                       userData:NULL assumeInside:YES];
    }
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    //NSLog(@"%s%@", _cmd, newWindow);

    // Remove tracking rect if view moves or is removed.
    if ([self window] && trackingRectTag) {
        [self removeTrackingRect:trackingRectTag];
        trackingRectTag = 0;
    }
}

- (NSMenu*)menuForEvent:(NSEvent *)event
{
    // HACK! Return nil to disable NSTextView's popup menus (Vim provides its
    // own).  Called when user Ctrl-clicks in the view (this is already handled
    // in rightMouseDown:).
    return nil;
}

- (NSArray *)acceptableDragTypes
{
    return [NSArray arrayWithObjects:NSFilenamesPboardType,
           NSStringPboardType, nil];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];

    if ([[pboard types] containsObject:NSStringPboardType]) {
        NSString *string = [pboard stringForType:NSStringPboardType];
        [[self vimController] dropString:string];
        return YES;
    } else if ([[pboard types] containsObject:NSFilenamesPboardType]) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        [[self vimController] dropFiles:files];
        return YES;
    }

    return NO;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
    NSPasteboard *pboard = [sender draggingPasteboard];

    if ( [[pboard types] containsObject:NSFilenamesPboardType]
            && (sourceDragMask & NSDragOperationCopy) )
        return NSDragOperationCopy;
    if ( [[pboard types] containsObject:NSStringPboardType]
            && (sourceDragMask & NSDragOperationCopy) )
        return NSDragOperationCopy;

    return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
    NSPasteboard *pboard = [sender draggingPasteboard];

    if ( [[pboard types] containsObject:NSFilenamesPboardType]
            && (sourceDragMask & NSDragOperationCopy) )
        return NSDragOperationCopy;
    if ( [[pboard types] containsObject:NSStringPboardType]
            && (sourceDragMask & NSDragOperationCopy) )
        return NSDragOperationCopy;

    return NSDragOperationNone;
}

- (void)changeFont:(id)sender
{
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    if (!ts) return;

    NSFont *oldFont = [ts font];
    NSFont *newFont = [sender convertFont:oldFont];

    if (newFont) {
        NSString *name = [newFont displayName];
        unsigned len = [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (len > 0) {
            NSMutableData *data = [NSMutableData data];
            float pointSize = [newFont pointSize];

            [data appendBytes:&pointSize length:sizeof(float)];

            ++len;  // include NUL byte
            [data appendBytes:&len length:sizeof(unsigned)];
            [data appendBytes:[name UTF8String] length:len];

            [[self vimController] sendMessage:SetFontMsgID data:data wait:NO];
        }
    }
}

- (void)resetCursorRects
{
    // No need to set up cursor rects...Vim is in control of cursor changes.
}

@end // MMTextView




@implementation MMTextView (Private)

- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column
{
#if 0
    NSLayoutManager *lm = [self layoutManager];
    NSTextContainer *tc = [self textContainer];
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];

    if (!(lm && tc && ts))
        return NO;

    unsigned glyphIdx = [lm glyphIndexForPoint:point inTextContainer:tc];
    unsigned charIdx = [lm characterIndexForGlyphAtIndex:glyphIdx];

    int mod = [ts maxColumns] + 1;

    if (row) *row = (int)(charIdx / mod);
    if (column) *column = (int)(charIdx % mod);

    NSLog(@"convertPoint:%@ toRow:%d column:%d", NSStringFromPoint(point),
            *row, *column);

    return YES;
#else
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    NSSize cellSize = [ts cellSize];
    if (!(cellSize.width > 0 && cellSize.height > 0))
        return NO;
    NSPoint origin = [self textContainerOrigin];

    if (row) *row = floor((point.y-origin.y-1) / cellSize.height);
    if (column) *column = floor((point.x-origin.x-1) / cellSize.width);

    //NSLog(@"convertPoint:%@ toRow:%d column:%d", NSStringFromPoint(point),
    //        *row, *column);

    return YES;
#endif
}

- (NSRect)trackingRect
{
    NSRect rect = [self frame];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int left = [ud integerForKey:MMTextInsetLeftKey];
    int top = [ud integerForKey:MMTextInsetTopKey];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    rect.origin.x = left;
    rect.origin.y = top;
    rect.size.width -= left + right - 1;
    rect.size.height -= top + bot - 1;

    return rect;
}

- (void)keyDown:(NSEvent *)event
{
    // HACK! If a modifier is held, don't pass the event along to
    // interpretKeyEvents: since some keys are bound to multiple commands which
    // means doCommandBySelector: is called several times.
    //
    // TODO: Figure out a way to disable Cocoa key bindings entirely, without
    // affecting input management.

    if ([event modifierFlags] & NSControlKeyMask)
        [self dispatchKeyEvent:event];
    else
        [super keyDown:event];
}

- (void)dispatchKeyEvent:(NSEvent *)event
{
    // Only handle the command if it came from a keyDown event
    if ([event type] != NSKeyDown)
        return;

    NSString *chars = [event characters];
    NSString *imchars = [event charactersIgnoringModifiers];
    unichar c = [chars characterAtIndex:0];
    unichar imc = [imchars characterAtIndex:0];
    int len = 0;
    const char *bytes = 0;

    //NSLog(@"%s chars=0x%x unmodchars=0x%x", _cmd, c, imc);

    if (' ' == imc && 0xa0 != c) {
        // HACK!  The AppKit turns <C-Space> into <C-@> which is not standard
        // Vim behaviour, so bypass this problem.  (0xa0 is <M-Space>, which
        // should be passed on as is.)
        len = [imchars lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        bytes = [imchars UTF8String];
    } else if (imc == c && '2' == c) {
        // HACK!  Translate Ctrl+2 to <C-@>.
        static char ctrl_at = 0;
        len = 1;  bytes = &ctrl_at;
    } else if (imc == c && '6' == c) {
        // HACK!  Translate Ctrl+6 to <C-^>.
        static char ctrl_hat = 0x1e;
        len = 1;  bytes = &ctrl_hat;
    } else if (c == 0x19 && imc == 0x19) {
        // HACK! AppKit turns back tab into Ctrl-Y, so we need to handle it
        // separately (else Ctrl-Y doesn't work).
        static char back_tab[2] = { 'k', 'B' };
        len = 2; bytes = back_tab;
    } else if (c == 0x3 && imc == 0x3) {
        // HACK! AppKit turns enter (not return) into Ctrl-C, so we need to
        // handle it separately (else Ctrl-C doesn't work).
        static char enter[2] = { 'K', 'A' };
        len = 2; bytes = enter;
    } else {
        len = [chars lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        bytes = [chars UTF8String];
    }

    if (len > 0 && bytes) {
        NSMutableData *data = [NSMutableData data];
        int flags = [event modifierFlags];

        [data appendBytes:&flags length:sizeof(int)];
        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:bytes length:len];

        [NSCursor setHiddenUntilMouseMoves:YES];

        //NSLog(@"%s len=%d bytes=0x%x", _cmd, len, bytes[0]);
        [[self vimController] sendMessage:KeyDownMsgID data:data wait:NO];
    }
}

- (MMVimController *)vimController
{
    id windowController = [[self window] windowController];

    // TODO: Make sure 'windowController' is a MMWindowController before type
    // casting.
    return [(MMWindowController*)windowController vimController];
}

- (void)startDragTimerWithInterval:(NSTimeInterval)t
{
    [NSTimer scheduledTimerWithTimeInterval:t target:self
                                   selector:@selector(dragTimerFired:)
                                   userInfo:nil repeats:NO];
}

- (void)dragTimerFired:(NSTimer *)timer
{
    // TODO: Autoscroll in horizontal direction?
    static unsigned tick = 1;
    MMTextStorage *ts = (MMTextStorage *)[self textStorage];

    isAutoscrolling = NO;

    if (isDragging && ts && (dragRow < 0 || dragRow >= [ts maxRows])) {
        // HACK! If the mouse cursor is outside the text area, then send a
        // dragged event.  However, if row&col hasn't changed since the last
        // dragged event, Vim won't do anything (see gui_send_mouse_event()).
        // Thus we fiddle with the column to make sure something happens.
        int col = dragColumn + (dragRow < 0 ? -(tick % 2) : +(tick % 2));
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&dragRow length:sizeof(int)];
        [data appendBytes:&col length:sizeof(int)];
        [data appendBytes:&dragFlags length:sizeof(int)];

        [[self vimController] sendMessage:MouseDraggedMsgID data:data wait:NO];

        isAutoscrolling = YES;
    }

    if (isDragging) {
        // Compute timer interval depending on how far away the mouse cursor is
        // from the text view.
        NSRect rect = [self trackingRect];
        float dy = 0;
        if (dragPoint.y < rect.origin.y) dy = rect.origin.y - dragPoint.y;
        else if (dragPoint.y > NSMaxY(rect)) dy = dragPoint.y - NSMaxY(rect);
        if (dy > MMDragAreaSize) dy = MMDragAreaSize;

        NSTimeInterval t = MMDragTimerMaxInterval -
            dy*(MMDragTimerMaxInterval-MMDragTimerMinInterval)/MMDragAreaSize;

        [self startDragTimerWithInterval:t];
    }

    ++tick;
}

@end // MMTextView (Private)
