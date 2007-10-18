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

static char MMKeypadEnter[2] = { 'K', 'A' };
static NSString *MMKeypadEnterString = @"KA";



@interface MMTextView (Private)
- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column;
- (BOOL)convertRow:(int)row column:(int)column toPoint:(NSPoint *)point;
- (NSRect)trackingRect;
- (void)dispatchKeyEvent:(NSEvent *)event;
- (MMVimController *)vimController;
- (void)startDragTimerWithInterval:(NSTimeInterval)t;
- (void)dragTimerFired:(NSTimer *)timer;
- (void)sendKeyDown:(const char *)chars length:(int)len modifiers:(int)flags;
@end



@implementation MMTextView

- (void)dealloc
{
    if (markedTextField) {
        [[markedTextField window] autorelease];
        [markedTextField release];
        markedTextField = nil;
    }

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

- (void)setShouldDrawInsertionPoint:(BOOL)on
{
    shouldDrawInsertionPoint = on;
}

- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                       fraction:(int)percent color:(NSColor *)color
{
    //NSLog(@"drawInsertionPointAtRow:%d column:%d shape:%d color:%@",
    //        row, col, shape, color);

    // This only stores where to draw the insertion point, the actual drawing
    // is done in drawRect:.
    shouldDrawInsertionPoint = YES;
    insertionPointRow = row;
    insertionPointColumn = col;
    insertionPointShape = shape;
    insertionPointFraction = percent;

    [self setInsertionPointColor:color];
}

- (void)hideMarkedTextField
{
    if (markedTextField) {
        NSWindow *win = [markedTextField window];
        [win close];
        [markedTextField setStringValue:@""];
    }
}

- (BOOL)isOpaque
{
    return NO;
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
        NSRect ipRect = [lm boundingRectForGlyphRange:glyphRange
                                      inTextContainer:tc];
        ipRect.origin.x += [self textContainerOrigin].x;
        ipRect.origin.y += [self textContainerOrigin].y;

        if (MMInsertionPointHorizontal == insertionPointShape) {
            int frac = ([ts cellSize].height * insertionPointFraction + 99)/100;
            ipRect.origin.y += ipRect.size.height - frac;
            ipRect.size.height = frac;
        } else if (MMInsertionPointVertical == insertionPointShape) {
            int frac = ([ts cellSize].width* insertionPointFraction + 99)/100;
            ipRect.size.width = frac;
        }

        [[self insertionPointColor] set];
        if (MMInsertionPointHollow == insertionPointShape) {
            NSFrameRect(ipRect);
        } else {
            NSRectFill(ipRect);
        }

        // NOTE: We only draw the cursor once and rely on Vim to say when it
        // should be drawn again.
        shouldDrawInsertionPoint = NO;

        //NSLog(@"%s draw insertion point %@ shape=%d color=%@", _cmd,
        //        NSStringFromRect(ipRect), insertionPointShape,
        //        [self insertionPointColor]);
    }
#if 0
    // this code invalidates the shadow, so we don't 
    // get shifting ghost text on scroll and resize
    // but makes speed unusable
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    if ([ts defaultBackgroundAlpha] < 1.0f) {
        if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_1)
        {
            [[self window] setHasShadow:NO];
            [[self window] setHasShadow:YES];
        }
        else
            [[self window] invalidateShadow];

    }
#endif
}

- (void)keyDown:(NSEvent *)event
{
    //NSLog(@"%s %@", _cmd, event);
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

- (void)insertText:(id)string
{
    //NSLog(@"%s %@", _cmd, string);
    // NOTE!  This method is called for normal key presses but also for
    // Option-key presses --- even when Ctrl is held as well as Option.  When
    // Ctrl is held, the AppKit translates the character to a Ctrl+key stroke,
    // so 'string' need not be a printable character!  In this case it still
    // works to pass 'string' on to Vim as a printable character (since
    // modifiers are already included and should not be added to the input
    // buffer using CSI, K_MODIFIER).

    [self hideMarkedTextField];

    NSEvent *event = [NSApp currentEvent];

    // HACK!  In order to be able to bind to <S-Space>, <S-M-Tab>, etc. we have
    // to watch for them here.
    if ([event type] == NSKeyDown
            && [[event charactersIgnoringModifiers] length] > 0
            && [event modifierFlags]
                & (NSShiftKeyMask|NSControlKeyMask|NSAlternateKeyMask)) {
        unichar c = [[event charactersIgnoringModifiers] characterAtIndex:0];

        // <S-M-Tab> translates to 0x19 
        if (' ' == c || 0x19 == c) {
            [self dispatchKeyEvent:event];
            return;
        }
    }

    // TODO: Support 'mousehide' (check p_mh)
    [NSCursor setHiddenUntilMouseMoves:YES];

    // NOTE: 'string' is either an NSString or an NSAttributedString.  Since we
    // do not support attributes, simply pass the corresponding NSString in the
    // latter case.
    if ([string isKindOfClass:[NSAttributedString class]])
        string = [string string];

    [[self vimController] sendMessage:InsertTextMsgID
                 data:[string dataUsingEncoding:NSUTF8StringEncoding]];
}


- (void)doCommandBySelector:(SEL)selector
{
    //NSLog(@"%s %@", _cmd, NSStringFromSelector(selector));
    // By ignoring the selector we effectively disable the key binding
    // mechanism of Cocoa.  Hopefully this is what the user will expect
    // (pressing Ctrl+P would otherwise result in moveUp: instead of previous
    // match, etc.).
    //
    // We usually end up here if the user pressed Ctrl+key (but not
    // Ctrl+Option+key).

    NSEvent *event = [NSApp currentEvent];

    if (selector == @selector(cancelOperation:)
            || selector == @selector(insertNewline:)) {
        // HACK! If there was marked text which got abandoned as a result of
        // hitting escape or enter, then 'insertText:' is called with the
        // abandoned text but '[event characters]' includes the abandoned text
        // as well.  Since 'dispatchKeyEvent:' looks at '[event characters]' we
        // must intercept these keys here or the abandonded text gets inserted
        // twice.
        NSString *key = [event charactersIgnoringModifiers];
        const char *chars = [key UTF8String];
        int len = [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (0x3 == chars[0]) {
            // HACK! AppKit turns enter (not return) into Ctrl-C, so we need to
            // handle it separately (else Ctrl-C doesn't work).
            len = sizeof(MMKeypadEnter)/sizeof(MMKeypadEnter[0]);
            chars = MMKeypadEnter;
        }

        [self sendKeyDown:chars length:len modifiers:[event modifierFlags]];
    } else {
        [self dispatchKeyEvent:event];
    }
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    //NSLog(@"%s %@", _cmd, event);
    // Called for Cmd+key keystrokes, function keys, arrow keys, page
    // up/down, home, end.
    //
    // NOTE: This message cannot be ignored since Cmd+letter keys never are
    // passed to keyDown:.  It seems as if the main menu consumes Cmd-key
    // strokes, unless the key is a function key.

    // NOTE: If the event that triggered this method represents a function key
    // down then we do nothing, otherwise the input method never gets the key
    // stroke (some input methods use e.g. arrow keys).  The function key down
    // event will still reach Vim though (via keyDown:).  The exceptions to
    // this rule are: PageUp/PageDown (keycode 116/121).
    int flags = [event modifierFlags];
    if ([event type] != NSKeyDown || flags & NSFunctionKeyMask
            && !(116 == [event keyCode] || 121 == [event keyCode]))
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

    NSString *chars = [event characters];
    NSString *unmodchars = [event charactersIgnoringModifiers];
    int len = [unmodchars lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *data = [NSMutableData data];

    if (len <= 0)
        return NO;

    // If 'chars' and 'unmodchars' differs when shift flag is present, then we
    // can clear the shift flag as it is already included in 'unmodchars'.
    // Failing to clear the shift flag means <D-Bar> turns into <S-D-Bar> (on
    // an English keyboard).
    if (flags & NSShiftKeyMask && ![chars isEqual:unmodchars])
        flags &= ~NSShiftKeyMask;

    if (0x3 == [unmodchars characterAtIndex:0]) {
        // HACK! AppKit turns enter (not return) into Ctrl-C, so we need to
        // handle it separately (else Cmd-enter turns into Ctrl-C).
        unmodchars = MMKeypadEnterString;
        len = [unmodchars lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    }

    [data appendBytes:&flags length:sizeof(int)];
    [data appendBytes:&len length:sizeof(int)];
    [data appendBytes:[unmodchars UTF8String] length:len];

    [[self vimController] sendMessage:CmdKeyMsgID data:data];

    return YES;
}

- (BOOL)hasMarkedText
{
    //NSLog(@"%s", _cmd);
    return markedTextField && [[markedTextField stringValue] length] > 0;
}

- (NSRange)markedRange
{
    //NSLog(@"%s", _cmd);
    // HACK! If a valid range is returned, then NSTextView changes the
    // background color of the returned range.  Since marked text is displayed
    // in a separate popup window this behaviour is not wanted.  By setting the
    // location of the returned range to NSNotFound NSTextView does nothing.
    // This hack is continued in 'firstRectForCharacterRange:'.
    return NSMakeRange(NSNotFound, 0);
}

- (void)setMarkedText:(id)text selectedRange:(NSRange)range
{
    //NSLog(@"setMarkedText:'%@' selectedRange:%@", text,
    //        NSStringFromRange(range));

    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    if (!ts) return;

    if (!markedTextField) {
        // Create a text field and put it inside a floating panel.  This field
        // is used to display marked text.
        NSSize cellSize = [ts cellSize];
        NSRect cellRect = { 0, 0, cellSize.width, cellSize.height };

        markedTextField = [[NSTextField alloc] initWithFrame:cellRect];
        [markedTextField setEditable:NO];
        [markedTextField setSelectable:NO];
        [markedTextField setBezeled:NO];
        [markedTextField setBordered:YES];

        NSPanel *panel = [[NSPanel alloc]
            initWithContentRect:cellRect
                      styleMask:NSBorderlessWindowMask|NSUtilityWindowMask
                        backing:NSBackingStoreBuffered
                          defer:YES];

        //[panel setHidesOnDeactivate:NO];
        [panel setFloatingPanel:YES];
        [panel setBecomesKeyOnlyIfNeeded:YES];
        [panel setContentView:markedTextField];
    }

    if (text && [text length] > 0) {
        [markedTextField setFont:[ts font]];
        if ([text isKindOfClass:[NSAttributedString class]])
            [markedTextField setAttributedStringValue:text];
        else
            [markedTextField setStringValue:text];

        [markedTextField sizeToFit];
        NSSize size = [markedTextField frame].size;

        // Convert coordinates (row,col) -> view -> window base -> screen
        NSPoint origin;
        if (![self convertRow:insertionPointRow+1 column:insertionPointColumn
                     toPoint:&origin])
            return;
        origin = [self convertPoint:origin toView:nil];
        origin = [[self window] convertBaseToScreen:origin];

        NSWindow *win = [markedTextField window];
        [win setContentSize:size];
        [win setFrameOrigin:origin];
        [win orderFront:nil];
    } else {
        [self hideMarkedTextField];
    }
}

- (void)unmarkText
{
    //NSLog(@"%s", _cmd);
    [self hideMarkedTextField];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
{
    //NSLog(@"%s%@", _cmd, NSStringFromRange(range));

    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    NSLayoutManager *lm = [self layoutManager];
    NSTextContainer *tc = [self textContainer];

    // HACK! Since we always return marked text to have location NSNotFound,
    // this method will be called with 'range.location == NSNotFound' whenever
    // the input manager tries to position a popup window near the insertion
    // point.  For this reason we compute where the insertion point is and
    // return a rect which contains it.
    if (!(ts && lm && tc) || NSNotFound != range.location)
        return [super firstRectForCharacterRange:range];

    unsigned charIdx = [ts characterIndexForRow:insertionPointRow
                                         column:insertionPointColumn];
    NSRange glyphRange =
        [lm glyphRangeForCharacterRange:NSMakeRange(charIdx,1)
                   actualCharacterRange:NULL];
    NSRect ipRect = [lm boundingRectForGlyphRange:glyphRange
                                  inTextContainer:tc];
    ipRect.origin.x += [self textContainerOrigin].x;
    ipRect.origin.y += [self textContainerOrigin].y + [ts cellSize].height;

    ipRect.origin = [self convertPoint:ipRect.origin toView:nil];
    ipRect.origin = [[self window] convertBaseToScreen:ipRect.origin];

    return ipRect;
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

    [[self vimController] sendMessage:ScrollWheelMsgID data:data];
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

    [[self vimController] sendMessage:MouseDownMsgID data:data];
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

    [[self vimController] sendMessage:MouseUpMsgID data:data];

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

        [[self vimController] sendMessage:MouseDraggedMsgID data:data];
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

        [[self vimController] sendMessage:MouseMovedMsgID data:data];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    //NSLog(@"%s", _cmd);

    // NOTE: This event is received even when the window is not key; thus we
    // have to take care not to enable mouse moved events unless our window is
    // key.
    if ([[self window] isKeyWindow])
        [[self window] setAcceptsMouseMovedEvents:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    //NSLog(@"%s", _cmd);

    [[self window] setAcceptsMouseMovedEvents:NO];

    // NOTE: This event is received even when the window is not key; if the
    // mouse shape is set when our window is not key, the hollow (unfocused)
    // cursor will become a block (focused) cursor.
    if ([[self window] isKeyWindow]) {
        int shape = 0;
        NSMutableData *data = [NSMutableData data];
        [data appendBytes:&shape length:sizeof(int)];
        [[self vimController] sendMessage:SetMouseShapeMsgID data:data];
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

            [[self vimController] sendMessage:SetFontMsgID data:data];
        }
    }
}

- (void)resetCursorRects
{
    // No need to set up cursor rects since Vim handles cursor changes.
}

- (void)updateFontPanel
{
    // The font panel is updated whenever the font is set.
}

- (void)viewDidEndLiveResize
{
    id windowController = [[self window] windowController];
    [windowController liveResizeDidEnd];
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

- (BOOL)convertRow:(int)row column:(int)column toPoint:(NSPoint *)point
{
    MMTextStorage *ts = (MMTextStorage*)[self textStorage];
    NSSize cellSize = [ts cellSize];
    if (!(point && cellSize.width > 0 && cellSize.height > 0))
        return NO;

    *point = [self textContainerOrigin];
    point->x += column * cellSize.width;
    point->y += row * cellSize.height;

    return YES;
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

- (void)dispatchKeyEvent:(NSEvent *)event
{
    // Only handle the command if it came from a keyDown event
    if ([event type] != NSKeyDown)
        return;

    NSString *chars = [event characters];
    NSString *unmodchars = [event charactersIgnoringModifiers];
    unichar c = [chars characterAtIndex:0];
    unichar imc = [unmodchars characterAtIndex:0];
    int len = 0;
    const char *bytes = 0;
    int mods = [event modifierFlags];

    //NSLog(@"%s chars[0]=0x%x unmodchars[0]=0x%x (chars=%@ unmodchars=%@)",
    //        _cmd, c, imc, chars, unmodchars);

    if (' ' == imc && 0xa0 != c) {
        // HACK!  The AppKit turns <C-Space> into <C-@> which is not standard
        // Vim behaviour, so bypass this problem.  (0xa0 is <M-Space>, which
        // should be passed on as is.)
        len = [unmodchars lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        bytes = [unmodchars UTF8String];
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
        static char tab = 0x9;
        len = 1;  bytes = &tab;  mods |= NSShiftKeyMask;
    } else {
        len = [chars lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        bytes = [chars UTF8String];
    }

    [self sendKeyDown:bytes length:len modifiers:mods];
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

        [[self vimController] sendMessage:MouseDraggedMsgID data:data];

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

- (void)sendKeyDown:(const char *)chars length:(int)len modifiers:(int)flags
{
    if (chars && len > 0) {
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&flags length:sizeof(int)];
        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:chars length:len];

        // TODO: Support 'mousehide' (check p_mh)
        [NSCursor setHiddenUntilMouseMoves:YES];

        //NSLog(@"%s len=%d chars=0x%x", _cmd, len, chars[0]);
        [[self vimController] sendMessage:KeyDownMsgID data:data];
    }
}

@end // MMTextView (Private)
