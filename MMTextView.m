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
#import "MacVim.h"
#import "MMWindowController.h"



@interface MMTextView (Private)
- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column;
- (void)dispatchKeyEvent:(NSEvent *)event;
@end



@implementation MMTextView

- (id)initWithPort:(NSPort *)port frame:(NSRect)frame
     textContainer:(NSTextContainer *)tc
{
    if ((self = [super initWithFrame:frame textContainer:tc])) {
        sendPort = [port retain];
    }

    return self;
}

- (MMTextView *)initWithFrame:(NSRect)frame port:(NSPort *)port
{
    MMTextStorage *ts = [[MMTextStorage alloc] init];
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    NSTextContainer *tc = [[NSTextContainer alloc] initWithContainerSize:
            NSMakeSize(1.0e7,1.0e7)];

    [tc setWidthTracksTextView:NO];
    [tc setHeightTracksTextView:NO];
    [tc setLineFragmentPadding:0];

    [ts addLayoutManager:lm];
    [lm addTextContainer:tc];

    [tc release];
    [lm release];

    // HACK! Where should i get these values from?
    // TODO: get values from frame
    [ts setMaxRows:24 columns:80];

    if ((self = [super initWithFrame:frame textContainer:tc])) {
        ownsTextStorage = YES;
        //[self setRichText:NO];
        sendPort = [port retain];
    } else {
        ownsTextStorage = NO;
        [ts release];
    }

    return self;
}


- (void)dealloc
{
    // BUG!  The reference count of the text view will never reach 0 unless
    // release is explicitly called on the text storage;  so this code is
    // meaningless.
    if (ownsTextStorage) {
        [[self textContainer] setTextView:nil];
        [[self textStorage] release];
        ownsTextStorage = NO;
    }

    [sendPort release];

    [super dealloc];
}

- (void)setShouldDrawInsertionPoint:(BOOL)enable
{
    shouldDrawInsertionPoint = enable;
}

- (BOOL)shouldDrawInsertionPoint
{
    return shouldDrawInsertionPoint;
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

    //NSLog(@"%s%@ (%x)", _cmd, string, [string characterAtIndex:0]);

    NSEvent *event = [NSApp currentEvent];
    if ([event type] == NSKeyDown) {
        unsigned mods = [event modifierFlags];
        unichar c = [[event charactersIgnoringModifiers] characterAtIndex:0];

        if (mods & (NSShiftKeyMask|NSControlKeyMask|NSAlternateKeyMask)
                && ' ' == c) {
            // HACK!  In order to be able to bind to <S-Space> etc. we have to
            // watch for when space was pressed.
            [self dispatchKeyEvent:event];
            return;
        }
    }

    [NSCursor setHiddenUntilMouseMoves:YES];

    [NSPortMessage sendMessage:InsertTextMsgID withSendPort:sendPort
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

    NSMutableData *data = [NSMutableData data];
    NSString *string = [event charactersIgnoringModifiers];
    int flags = [event modifierFlags];
    int len = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    [data appendBytes:&flags length:sizeof(int)];
    [data appendBytes:&len length:sizeof(int)];
    [data appendBytes:[string UTF8String] length:len];

    [NSPortMessage sendMessage:CmdKeyMsgID withSendPort:sendPort data:data
                          wait:NO];

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

#if 0
- (IBAction)copy:(id)sender
{
}

- (IBAction)paste:(id)sender
{
}
#endif

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

    [NSPortMessage sendMessage:ScrollWheelMsgID withSendPort:sendPort
                          data:data wait:NO];
}

- (void)mouseDown:(NSEvent *)event
{
    int row, col;
    NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
    if (![self convertPoint:pt toRow:&row column:&col])
        return;

    int button = [event buttonNumber];
    int flags = [event modifierFlags];
    int count = [event clickCount];
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&row length:sizeof(int)];
    [data appendBytes:&col length:sizeof(int)];
    [data appendBytes:&button length:sizeof(int)];
    [data appendBytes:&flags length:sizeof(int)];
    [data appendBytes:&count length:sizeof(int)];

    [NSPortMessage sendMessage:MouseDownMsgID withSendPort:sendPort
                          data:data wait:NO];
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

    [NSPortMessage sendMessage:MouseUpMsgID withSendPort:sendPort
                          data:data wait:NO];
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
    int row, col;
    NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
    if (![self convertPoint:pt toRow:&row column:&col])
        return;

    int flags = [event modifierFlags];
    NSMutableData *data = [NSMutableData data];

    [data appendBytes:&row length:sizeof(int)];
    [data appendBytes:&col length:sizeof(int)];
    [data appendBytes:&flags length:sizeof(int)];

    [NSPortMessage sendMessage:MouseDraggedMsgID withSendPort:sendPort
                          data:data wait:NO];
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [self mouseDragged:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
    [self mouseDragged:event];
}

#if 0
- (void)menuForEvent:(NSEvent *)event
{
    // TODO:  Enabling this causes a crash at the moment.  Why?
    //
    // Called when user Ctrl-clicks in the view
    [self mouseDown:event];
}
#endif

@end // MMTextView




@implementation MMTextView (Private)

- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column
{
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

    return YES;
}

- (void)dispatchKeyEvent:(NSEvent *)event
{
    // Only handle the command if it came from a keyDown event
    if ([event type] != NSKeyDown)
        return;

    //NSLog(@"%s%@", _cmd, event);

    NSString *chars = [event characters];
    NSString *imchars = [event charactersIgnoringModifiers];
    unichar c = [chars characterAtIndex:0];
    unichar imc = [imchars characterAtIndex:0];
    int len = 0;
    const char *bytes = 0;

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

        [NSPortMessage sendMessage:KeyDownMsgID withSendPort:sendPort data:data
                              wait:NO];
    }
}

@end // MMTextView (Private)
