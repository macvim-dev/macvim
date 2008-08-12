/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * MMTextViewHelper
 *
 * Contains code shared between the different text renderers.  Unfortunately it
 * is not possible to let the text renderers inherit from this class since
 * MMTextView needs to inherit from NSTextView whereas MMAtsuiTextView needs to
 * inherit from NSView.
 */

#import "MMTextView.h"
#import "MMTextViewHelper.h"
#import "MMVimController.h"
#import "MMWindowController.h"
#import "Miscellaneous.h"


static char MMKeypadEnter[2] = { 'K', 'A' };
static NSString *MMKeypadEnterString = @"KA";

// The max/min drag timer interval in seconds
static NSTimeInterval MMDragTimerMaxInterval = .3f;
static NSTimeInterval MMDragTimerMinInterval = .01f;

// The number of pixels in which the drag timer interval changes
static float MMDragAreaSize = 73.0f;


@interface MMTextViewHelper (Private)
- (MMWindowController *)windowController;
- (MMVimController *)vimController;
- (void)dispatchKeyEvent:(NSEvent *)event;
- (void)sendKeyDown:(const char *)chars length:(int)len modifiers:(int)flags;
- (void)hideMouseCursor;
- (void)startDragTimerWithInterval:(NSTimeInterval)t;
- (void)dragTimerFired:(NSTimer *)timer;
- (void)setCursor;
- (NSRect)trackingRect;
@end


@implementation MMTextViewHelper

- (void)setTextView:(id)view
{
    // Only keep a weak reference to owning text view.
    textView = view;
}

- (void)keyDown:(NSEvent *)event
{
    //NSLog(@"%s %@", _cmd, event);
    // HACK! If control modifier is held, don't pass the event along to
    // interpretKeyEvents: since some keys are bound to multiple commands which
    // means doCommandBySelector: is called several times.  Do the same for
    // Alt+Function key presses (Alt+Up and Alt+Down are bound to two
    // commands).  This hack may break input management, but unless we can
    // figure out a way to disable key bindings there seems little else to do.
    //
    // TODO: Figure out a way to disable Cocoa key bindings entirely, without
    // affecting input management.

    // When the Input Method is activated, some special key inputs
    // should be treated as key inputs for Input Method.
    if ([textView hasMarkedText]) {
        [textView interpretKeyEvents:[NSArray arrayWithObject:event]];
        [textView setNeedsDisplay:YES];
        return;
    }

    int flags = [event modifierFlags];
    if ((flags & NSControlKeyMask) ||
            ((flags & NSAlternateKeyMask) && (flags & NSFunctionKeyMask))) {
        NSString *unmod = [event charactersIgnoringModifiers];
        if ([unmod length] == 1 && [unmod characterAtIndex:0] <= 0x7f
                                && [unmod characterAtIndex:0] >= 0x60) {
            // HACK! Send Ctrl-letter keys (and C-@, C-[, C-\, C-], C-^, C-_)
            // as normal text to be added to the Vim input buffer.  This must
            // be done in order for the backend to be able to separate e.g.
            // Ctrl-i and Ctrl-tab.
            [self insertText:[event characters]];
        } else {
            [self dispatchKeyEvent:event];
        }
    } else {
        [textView interpretKeyEvents:[NSArray arrayWithObject:event]];
    }
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

    if ([textView hasMarkedText]) {
        [textView unmarkText];
    }

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

    [self hideMouseCursor];

    // NOTE: 'string' is either an NSString or an NSAttributedString.  Since we
    // do not support attributes, simply pass the corresponding NSString in the
    // latter case.
    if ([string isKindOfClass:[NSAttributedString class]])
        string = [string string];

    //NSLog(@"send InsertTextMsgID: %@", string);

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

    // HACK!  KeyCode 50 represent the key which switches between windows
    // within an application (like Cmd+Tab is used to switch between
    // applications).  Return NO here, else the window switching does not work.
    if ([event keyCode] == 50)
        return NO;

    // HACK!  Let the main menu try to handle any key down event, before
    // passing it on to vim, otherwise key equivalents for menus will
    // effectively be disabled.
    if ([[NSApp mainMenu] performKeyEquivalent:event])
        return YES;

    // HACK!  On Leopard Ctrl-key events end up here instead of keyDown:.
    if (flags & NSControlKeyMask) {
        [self keyDown:event];
        return YES;
    }

    // HACK!  Don't handle Cmd-? or the "Help" menu does not work on Leopard.
    NSString *unmodchars = [event charactersIgnoringModifiers];
    if ([unmodchars isEqual:@"?"])
        return NO;

    //NSLog(@"%s%@", _cmd, event);

    NSString *chars = [event characters];
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

- (void)scrollWheel:(NSEvent *)event
{
    if ([event deltaY] == 0)
        return;

    int row, col;
    NSPoint pt = [textView convertPoint:[event locationInWindow] fromView:nil];
    if (![textView convertPoint:pt toRow:&row column:&col])
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
    NSPoint pt = [textView convertPoint:[event locationInWindow] fromView:nil];
    if (![textView convertPoint:pt toRow:&row column:&col])
        return;

    int button = [event buttonNumber];
    int flags = [event modifierFlags];
    int count = [event clickCount];
    NSMutableData *data = [NSMutableData data];

    // If desired, intepret Ctrl-Click as a right mouse click.
    BOOL translateCtrlClick = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMTranslateCtrlClickKey];
    flags = flags & NSDeviceIndependentModifierFlagsMask;
    if (translateCtrlClick && button == 0 &&
            (flags == NSControlKeyMask ||
             flags == (NSControlKeyMask|NSAlphaShiftKeyMask))) {
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

- (void)mouseUp:(NSEvent *)event
{
    int row, col;
    NSPoint pt = [textView convertPoint:[event locationInWindow] fromView:nil];
    if (![textView convertPoint:pt toRow:&row column:&col])
        return;

    int flags = [event modifierFlags];
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&row length:sizeof(int)];
    [data appendBytes:&col length:sizeof(int)];
    [data appendBytes:&flags length:sizeof(int)];

    [[self vimController] sendMessage:MouseUpMsgID data:data];

    isDragging = NO;
}

- (void)mouseDragged:(NSEvent *)event
{
    int flags = [event modifierFlags];
    int row, col;
    NSPoint pt = [textView convertPoint:[event locationInWindow] fromView:nil];
    if (![textView convertPoint:pt toRow:&row column:&col])
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
    dragRow = row;
    dragColumn = col;
    dragFlags = flags;

    if (!isDragging) {
        [self startDragTimerWithInterval:.5];
        isDragging = YES;
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    // HACK! NSTextView has a nasty habit of resetting the cursor to the
    // default I-beam cursor at random moments.  The only reliable way we know
    // of to work around this is to set the cursor each time the mouse moves.
    [self setCursor];

    NSPoint pt = [textView convertPoint:[event locationInWindow] fromView:nil];
    int row, col;
    if (![textView convertPoint:pt toRow:&row column:&col])
        return;

    // HACK! It seems impossible to get the tracking rects set up before the
    // view is visible, which means that the first mouseEntered: or
    // mouseExited: events are never received.  This forces us to check if the
    // mouseMoved: event really happened over the text.
    int rows, cols;
    [textView getMaxRows:&rows columns:&cols];
    if (row >= 0 && row < rows && col >= 0 && col < cols) {
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&row length:sizeof(int)];
        [data appendBytes:&col length:sizeof(int)];

        [[self vimController] sendMessage:MouseMovedMsgID data:data];

        //NSLog(@"Moved %d %d\n", col, row);
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    //NSLog(@"%s", _cmd);

    // NOTE: This event is received even when the window is not key; thus we
    // have to take care not to enable mouse moved events unless our window is
    // key.
    if ([[textView window] isKeyWindow]) {
        [[textView window] setAcceptsMouseMovedEvents:YES];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    //NSLog(@"%s", _cmd);

    [[textView window] setAcceptsMouseMovedEvents:NO];

    // NOTE: This event is received even when the window is not key; if the
    // mouse shape is set when our window is not key, the hollow (unfocused)
    // cursor will become a block (focused) cursor.
    if ([[textView window] isKeyWindow]) {
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
    [textView removeTrackingRect:trackingRectTag];
    trackingRectTag = [textView addTrackingRect:[self trackingRect]
                                          owner:textView
                                       userData:NULL
                                   assumeInside:YES];
}

- (void)viewDidMoveToWindow
{
    //NSLog(@"%s (window=%@)", _cmd, [self window]);

    // Set a tracking rect which covers the text.
    // NOTE: While the mouse cursor is in this rect the view will receive
    // 'mouseMoved:' events so that Vim can take care of updating the mouse
    // cursor.
    if ([textView window]) {
        [[textView window] setAcceptsMouseMovedEvents:YES];
        trackingRectTag = [textView addTrackingRect:[self trackingRect]
                                              owner:textView
                                           userData:NULL
                                       assumeInside:YES];
    }
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    //NSLog(@"%s%@", _cmd, newWindow);

    // Remove tracking rect if view moves or is removed.
    if ([textView window] && trackingRectTag) {
        [textView removeTrackingRect:trackingRectTag];
        trackingRectTag = 0;
    }
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
        [[self vimController] dropFiles:files forceOpen:NO];
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

- (void)setMouseShape:(int)shape
{
    mouseShape = shape;
    [self setCursor];
}

@end // MMTextViewHelper




@implementation MMTextViewHelper (Private)

- (MMWindowController *)windowController
{
    id windowController = [[textView window] windowController];
    if ([windowController isKindOfClass:[MMWindowController class]])
        return (MMWindowController*)windowController;
    return nil;
}

- (MMVimController *)vimController
{
    return [[self windowController] vimController];
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

- (void)sendKeyDown:(const char *)chars length:(int)len modifiers:(int)flags
{
    if (chars && len > 0) {
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&flags length:sizeof(int)];
        [data appendBytes:&len length:sizeof(int)];
        [data appendBytes:chars length:len];

        [self hideMouseCursor];

        //NSLog(@"%s len=%d chars=0x%x", _cmd, len, chars[0]);
        [[self vimController] sendMessage:KeyDownMsgID data:data];
    }
}

- (void)hideMouseCursor
{
    // Check 'mousehide' option
    id mh = [[[self vimController] vimState] objectForKey:@"p_mh"];
    if (mh && ![mh boolValue])
        [NSCursor setHiddenUntilMouseMoves:NO];
    else
        [NSCursor setHiddenUntilMouseMoves:YES];
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

    isAutoscrolling = NO;

    if (isDragging && (dragRow < 0 || dragRow >= [textView maxRows])) {
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

- (void)setCursor
{
    static NSCursor *customIbeamCursor = nil;

    if (!customIbeamCursor) {
        // Use a custom Ibeam cursor that has better contrast against dark
        // backgrounds.
        // TODO: Is the hotspot ok?
        NSImage *ibeamImage = [NSImage imageNamed:@"ibeam"];
        if (ibeamImage) {
            NSSize size = [ibeamImage size];
            NSPoint hotSpot = { size.width*.5f, size.height*.5f };

            customIbeamCursor = [[NSCursor alloc]
                    initWithImage:ibeamImage hotSpot:hotSpot];
        }
        if (!customIbeamCursor) {
            NSLog(@"WARNING: Failed to load custom Ibeam cursor");
            customIbeamCursor = [NSCursor IBeamCursor];
        }
    }

    // This switch should match mshape_names[] in misc2.c.
    //
    // TODO: Add missing cursor shapes.
    switch (mouseShape) {
        case 2: [customIbeamCursor set]; break;
        case 3: case 4: [[NSCursor resizeUpDownCursor] set]; break;
        case 5: case 6: [[NSCursor resizeLeftRightCursor] set]; break;
        case 9: [[NSCursor crosshairCursor] set]; break;
        case 10: [[NSCursor pointingHandCursor] set]; break;
        case 11: [[NSCursor openHandCursor] set]; break;
        default:
            [[NSCursor arrowCursor] set]; break;
    }

    // Shape 1 indicates that the mouse cursor should be hidden.
    if (1 == mouseShape)
        [NSCursor setHiddenUntilMouseMoves:YES];
}

- (NSRect)trackingRect
{
    NSRect rect = [textView frame];
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

@end // MMTextViewHelper (Private)
