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
 * MMAtsuiTextView
 *
 * Dispatches keyboard and mouse input to the backend.  Handles drag-n-drop of
 * files onto window.
 */

#import "MMAtsuiTextView.h"
#import "MMVimController.h"
#import "MacVim.h"



static char MMKeypadEnter[2] = { 'K', 'A' };
static NSString *MMKeypadEnterString = @"KA";



@interface MMAtsuiTextView (Private)
- (void)dispatchKeyEvent:(NSEvent *)event;
- (void)sendKeyDown:(const char *)chars length:(int)len modifiers:(int)flags;
- (MMVimController *)vimController;
@end

@interface MMAtsuiTextView (Drawing)
- (void)beginDrawing;
- (void)endDrawing;
- (void)drawString:(UniChar *)string length:(UniCharCount)length
             atRow:(int)row column:(int)col cells:(int)cells
         withFlags:(int)flags foregroundColor:(NSColor *)fg
   backgroundColor:(NSColor *)bg specialColor:(NSColor *)sp;
- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(NSColor *)color;
- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(NSColor *)color;
- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(NSColor *)color;
- (void)clearAll;
@end


@implementation MMAtsuiTextView

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        // NOTE!  It does not matter which font is set here, Vim will set its
        // own font on startup anyway.  Just set some bogus values.
        font = [[NSFont userFixedPitchFontOfSize:0] retain];
        cellSize.width = cellSize.height = 1;
    }

    return self;
}

- (void)dealloc
{
    [font release];  font = nil;
    [defaultBackgroundColor release];  defaultBackgroundColor = nil;
    [defaultForegroundColor release];  defaultForegroundColor = nil;

    [super dealloc];
}

- (void)getMaxRows:(int*)rows columns:(int*)cols
{
    if (rows) *rows = maxRows;
    if (cols) *cols = maxColumns;
}

- (void)setMaxRows:(int)rows columns:(int)cols
{
    // NOTE: Just remember the new values, the actual resizing is done lazily.
    maxRows = rows;
    maxColumns = cols;
}

- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor
{
    if (defaultBackgroundColor != bgColor) {
        [defaultBackgroundColor release];
        defaultBackgroundColor = bgColor ? [bgColor retain] : nil;
    }

    // NOTE: The default foreground color isn't actually used for anything, but
    // other class instances might want to be able to access it so it is stored
    // here.
    if (defaultForegroundColor != fgColor) {
        [defaultForegroundColor release];
        defaultForegroundColor = fgColor ? [fgColor retain] : nil;
    }
}

- (NSSize)size
{
    return NSMakeSize(maxColumns*cellSize.width, maxRows*cellSize.height);
}

- (NSSize)fitToSize:(NSSize)size rows:(int *)rows columns:(int *)columns
{
    NSSize curSize = [self size];
    NSSize fitSize = curSize;
    int fitRows = maxRows;
    int fitCols = maxColumns;

    if (size.height < curSize.height) {
        // Remove lines until the height of the text storage fits inside
        // 'size'.  However, always make sure there are at least 3 lines in the
        // text storage.  (Why 3? It seem Vim never allows less than 3 lines.)
        //
        // TODO: No need to search since line height is fixed, just calculate
        // the new height.
        int rowCount = maxRows;
        int rowsToRemove;
        for (rowsToRemove = 0; rowsToRemove < maxRows-3; ++rowsToRemove) {
            float height = cellSize.height*rowCount;

            if (height <= size.height) {
                fitSize.height = height;
                break;
            }

            --rowCount;
        }

        fitRows -= rowsToRemove;
    } else if (size.height > curSize.height) {
        float fh = cellSize.height;
        if (fh < 1.0f) fh = 1.0f;

        fitRows = floor(size.height/fh);
        fitSize.height = fh*fitRows;
    }

    if (size.width != curSize.width) {
        float fw = cellSize.width;
        if (fw < 1.0f) fw = 1.0f;

        fitCols = floor(size.width/fw);
        fitSize.width = fw*fitCols;
    }

    if (rows) *rows = fitRows;
    if (columns) *columns = fitCols;

    return fitSize;
}

- (NSRect)rectForRowsInRange:(NSRange)range
{
    NSRect rect = { 0, 0, 0, 0 };
    unsigned start = range.location > maxRows ? maxRows : range.location;
    unsigned length = range.length;

    if (start+length > maxRows)
        length = maxRows - start;

    rect.origin.y = cellSize.height * start;
    rect.size.height = cellSize.height * length;

    return rect;
}

- (NSRect)rectForColumnsInRange:(NSRange)range
{
    NSRect rect = { 0, 0, 0, 0 };
    unsigned start = range.location > maxColumns ? maxColumns : range.location;
    unsigned length = range.length;

    if (start+length > maxColumns)
        length = maxColumns - start;

    rect.origin.x = cellSize.width * start;
    rect.size.width = cellSize.width * length;

    return rect;
}


- (void)setFont:(NSFont *)newFont
{
    if (newFont && font != newFont) {
        [font release];
        font = [newFont retain];

        float em = [newFont widthOfString:@"m"];
        float cellWidthMultiplier = [[NSUserDefaults standardUserDefaults]
                floatForKey:MMCellWidthMultiplierKey];

        // NOTE! Even though NSFontFixedAdvanceAttribute is a float, it will
        // only render at integer sizes.  Hence, we restrict the cell width to
        // an integer here, otherwise the window width and the actual text
        // width will not match.
        cellSize.width = ceilf(em * cellWidthMultiplier);
        cellSize.height = linespace + [newFont defaultLineHeightForFont];
    }
}

- (void)setWideFont:(NSFont *)newFont
{
}

- (NSFont *)font
{
    return font;
}

- (NSSize)cellSize
{
    return cellSize;
}

- (void)setLinespace:(float)newLinespace
{
    linespace = newLinespace;

    // NOTE: The linespace is added to the cell height in order for a multiline
    // selection not to have white (background color) gaps between lines.  Also
    // this simplifies the code a lot because there is no need to check the
    // linespace when calculating the size of the text view etc.  When the
    // linespace is non-zero the baseline will be adjusted as well; check
    // MMTypesetter.
    cellSize.height = linespace + [font defaultLineHeightForFont];
}




- (NSEvent *)lastMouseDownEvent
{
    return nil;
}

- (void)setShouldDrawInsertionPoint:(BOOL)on
{
}

- (void)setPreEditRow:(int)row column:(int)col
{
}

- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                       fraction:(int)percent color:(NSColor *)color
{
}

- (void)hideMarkedTextField
{
}




- (void)keyDown:(NSEvent *)event
{
    //NSLog(@"%s %@", _cmd, event);
    // HACK! If control modifier is held, don't pass the event along to
    // interpretKeyEvents: since some keys are bound to multiple commands which
    // means doCommandBySelector: is called several times.
    //
    // TODO: Figure out a way to disable Cocoa key bindings entirely, without
    // affecting input management.
    if ([event modifierFlags] & NSControlKeyMask) {
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
        [super keyDown:event];
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

    // HACK!  On Leopard Ctrl-key events end up here instead of keyDown:.
    if (flags & NSControlKeyMask) {
        [self keyDown:event];
        return YES;
    }

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

- (NSPoint)textContainerOrigin
{
    return NSZeroPoint;
}

- (void)setTextContainerInset:(NSSize)inset
{
}

- (void)setBackgroundColor:(NSColor *)color
{
}




- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)rect
{
    NSColor *color = defaultBackgroundColor ? defaultBackgroundColor
                                            : [NSColor lightGrayColor];
    [color set];
    [NSBezierPath fillRect:rect];
}




#define MM_DEBUG_DRAWING 0

- (void)performBatchDrawWithData:(NSData *)data
{
    const void *bytes = [data bytes];
    const void *end = bytes + [data length];

#if MM_DEBUG_DRAWING
    NSLog(@"====> BEGIN %s", _cmd);
#endif
    [self beginDrawing];

    // TODO: Sanity check input

    while (bytes < end) {
        int type = *((int*)bytes);  bytes += sizeof(int);

        if (ClearAllDrawType == type) {
#if MM_DEBUG_DRAWING
            NSLog(@"   Clear all");
#endif
            [self clearAll];
        } else if (ClearBlockDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row1 = *((int*)bytes);  bytes += sizeof(int);
            int col1 = *((int*)bytes);  bytes += sizeof(int);
            int row2 = *((int*)bytes);  bytes += sizeof(int);
            int col2 = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            NSLog(@"   Clear block (%d,%d) -> (%d,%d)", row1, col1,
                    row2,col2);
#endif
            [self clearBlockFromRow:row1 column:col1
                    toRow:row2 column:col2
                    color:[NSColor colorWithArgbInt:color]];
        } else if (DeleteLinesDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            NSLog(@"   Delete %d line(s) from %d", count, row);
#endif
            [self deleteLinesFromRow:row lineCount:count
                    scrollBottom:bot left:left right:right
                           color:[NSColor colorWithArgbInt:color]];
        } else if (DrawStringDrawType == type) {
            int bg = *((int*)bytes);  bytes += sizeof(int);
            int fg = *((int*)bytes);  bytes += sizeof(int);
            int sp = *((int*)bytes);  bytes += sizeof(int);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int cells = *((int*)bytes);  bytes += sizeof(int);
            int flags = *((int*)bytes);  bytes += sizeof(int);
            int len = *((int*)bytes);  bytes += sizeof(int);
            UniChar *string = (UniChar*)bytes;  bytes += len;

#if MM_DEBUG_DRAWING
            NSLog(@"   Draw string at (%d,%d) length=%d flags=%d fg=0x%x "
                    "bg=0x%x sp=0x%x", row, col, len, flags, fg, bg, sp);
#endif
            [self drawString:string length:len atRow:row column:col
                       cells:cells withFlags:flags
                    foregroundColor:[NSColor colorWithRgbInt:fg]
                    backgroundColor:[NSColor colorWithArgbInt:bg]
                       specialColor:[NSColor colorWithRgbInt:sp]];
        } else if (InsertLinesDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int count = *((int*)bytes);  bytes += sizeof(int);
            int bot = *((int*)bytes);  bytes += sizeof(int);
            int left = *((int*)bytes);  bytes += sizeof(int);
            int right = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            NSLog(@"   Insert %d line(s) at row %d", count, row);
#endif
            [self insertLinesAtRow:row lineCount:count
                             scrollBottom:bot left:left right:right
                                    color:[NSColor colorWithArgbInt:color]];
        } else if (DrawCursorDrawType == type) {
            unsigned color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            int row = *((int*)bytes);  bytes += sizeof(int);
            int col = *((int*)bytes);  bytes += sizeof(int);
            int shape = *((int*)bytes);  bytes += sizeof(int);
            int percent = *((int*)bytes);  bytes += sizeof(int);

#if MM_DEBUG_DRAWING
            NSLog(@"   Draw cursor at (%d,%d)", row, col);
#endif
            [self drawInsertionPointAtRow:row column:col shape:shape
                                     fraction:percent
                                        color:[NSColor colorWithRgbInt:color]];
        } else {
            NSLog(@"WARNING: Unknown draw type (type=%d)", type);
        }
    }

    [self endDrawing];

    // NOTE: During resizing, Cocoa only sends draw messages before Vim's rows
    // and columns are changed (due to ipc delays). Force a redraw here.
    [self displayIfNeeded];

#if MM_DEBUG_DRAWING
    NSLog(@"<==== END   %s", _cmd);
#endif
}

@end // MMAtsuiTextView




@implementation MMAtsuiTextView (Private)

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

        // TODO: Support 'mousehide' (check p_mh)
        [NSCursor setHiddenUntilMouseMoves:YES];

        //NSLog(@"%s len=%d chars=0x%x", _cmd, len, chars[0]);
        [[self vimController] sendMessage:KeyDownMsgID data:data];
    }
}

- (MMVimController *)vimController
{
    id windowController = [[self window] windowController];

    // TODO: Make sure 'windowController' is a MMWindowController before type
    // casting.
    return [(MMWindowController*)windowController vimController];
}

@end // MMAtsuiTextView (Private)




@implementation MMAtsuiTextView (Drawing)

- (void)beginDrawing
{
}

- (void)endDrawing
{
}

- (void)drawString:(UniChar *)string length:(UniCharCount)length
             atRow:(int)row column:(int)col cells:(int)cells
         withFlags:(int)flags foregroundColor:(NSColor *)fg
   backgroundColor:(NSColor *)bg specialColor:(NSColor *)sp
{
    // 'string' consists of 'length' utf-16 code pairs and should cover 'cells'
    // display cells (a normal character takes up one display cell, a wide
    // character takes up two)
}

- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(NSColor *)color
{
}

- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(NSColor *)color
{
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(NSColor *)color
{
}

- (void)clearAll
{
}

@end // MMAtsuiTextView (Drawing)
