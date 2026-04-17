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
 * MMFindBarView - inline find/replace bar
 *
 * An NSView overlay anchored to the top-right corner of MMVimView that
 * provides the same find/replace functionality as the floating
 * MMFindReplaceController panel, but without leaving the editor window.
 * The UI is built programmatically (no xib).
 *
 * Activation: controlled by the MMFindBarInlineKey user default.
 * When enabled, ShowFindReplaceDialogMsgID routes here instead of to
 * MMFindReplaceController.
 */

#import "MMFindBarView.h"
#import "MMTabline/MMHoverButton.h"


// FRD flag bits (must match FRD_ defines in Vim's gui.h)
enum {
    MMFRDForward   = 0,
    MMFRDBackward  = 0x100,
    MMFRDReplace   = 0x03,
    MMFRDReplaceAll= 0x04,
    MMFRDMatchWord = 0x08,
    MMFRDExactMatch= 0x10,   // no ignore-case when set
};

static const CGFloat kBarWidth  = 490;
static const CGFloat kBarHeight = 148;   // 2*kMargin + 4*kFieldH + 3*kRowGap
static const CGFloat kMargin    = 12;    // ~3 mm outer padding on all four sides
static const CGFloat kLabelW    = 90;
static const CGFloat kFieldH    = 22;
static const CGFloat kRowH      = 34;    // kFieldH + kMargin, keeps row gap ~3 mm


@implementation MMFindBarView {
    NSTextField  *_findBox;
    NSTextField  *_replaceBox;
    NSButton     *_ignoreCaseButton;
    NSButton     *_matchWordButton;
    NSButton     *_replaceButton;
    NSButton     *_replaceAllButton;
    NSButton     *_prevButton;
    NSButton     *_nextButton;
    NSButton     *_closeButton;  // MMHoverButton
    NSPoint       _dragOffset;   // mouse-down offset for dragging
}

- (instancetype)init {
    self = [super initWithFrame:NSMakeRect(0, 0, kBarWidth, kBarHeight)];
    if (!self) return nil;
    [self _buildUI];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [self _buildUI];
    return self;
}

- (void)_buildUI {
    self.wantsLayer = YES;
    // Access [self layer] to force layer creation before configuring properties;
    // simply setting wantsLayer=YES does not guarantee self.layer is non-nil yet.
    CALayer *layer = [self layer];
    layer.zPosition = 100;
    layer.borderWidth = 1;
    layer.borderColor = [NSColor separatorColor].CGColor;
    layer.cornerRadius = 4;

    // ── Step 1: Pre-create buttons and measure uniform width ─────────────────
    // Must happen first so we can derive the right-alignment edge for fields.
    _replaceAllButton = [NSButton buttonWithTitle:@"Replace All" target:self action:@selector(_replaceAll:)];
    _replaceButton    = [NSButton buttonWithTitle:@"Replace"     target:self action:@selector(_replace:)];
    _prevButton       = [NSButton buttonWithTitle:@"Previous"    target:self action:@selector(_findPrevious:)];
    _nextButton       = [NSButton buttonWithTitle:@"Next"        target:self action:@selector(_findNext:)];

    NSArray *actionButtons = @[_replaceAllButton, _replaceButton, _prevButton, _nextButton];
    CGFloat maxBtnW = 0;
    for (NSButton *btn in actionButtons) {
        [btn sizeToFit];
        maxBtnW = MAX(maxBtnW, btn.frame.size.width);
    }
    maxBtnW += 8;

    // Right edge of the button row (4 buttons + 3 gaps, starting at kMargin)
    CGFloat buttonsRight = kMargin + 4 * maxBtnW + 3 * 4;

    // ── Step 2: Field geometry — right edge aligned to buttonsRight ──────────
    CGFloat fieldX = kMargin + kLabelW + 4;
    CGFloat fieldW = buttonsRight - fieldX - 6;  // both fields share this width

    // ── Close button: MMHoverButton (tab-style × with circular hover bg) ─────
    // Positioned at bar's top-right corner with a tighter 6pt margin so it
    // sits closer to the corner than the content rows (margin = 12pt).
    MMHoverButton *closeBtn = [MMHoverButton new];
    closeBtn.imageTemplate = [MMHoverButton imageFromType:MMHoverButtonImageCloseTab];
    closeBtn.target = self;
    closeBtn.action = @selector(_close:);
    closeBtn.bordered = NO;
    CGFloat closeSize = 15;
    closeBtn.frame = NSMakeRect(
        kBarWidth - 6 - closeSize,
        kBarHeight - 6 - closeSize,
        closeSize, closeSize);
    _closeButton = closeBtn;

    // ── Row 1: Find ──────────────────────────────────────────────────────────
    CGFloat y = kBarHeight - kMargin - kFieldH;

    NSTextField *findLabel = [NSTextField labelWithString:@"Find:"];
    findLabel.alignment = NSTextAlignmentRight;
    findLabel.frame = NSMakeRect(kMargin, y, kLabelW, kFieldH);
    [self addSubview:findLabel];

    _findBox = [[NSTextField alloc] initWithFrame:
        NSMakeRect(fieldX, y, fieldW, kFieldH)];
    _findBox.placeholderString = @"Search";
    _findBox.delegate = self;
    _findBox.target = self;
    _findBox.action = @selector(_findNext:);
    [self addSubview:_findBox];
    // Close button floats above the find field
    [self addSubview:_closeButton positioned:NSWindowAbove relativeTo:_findBox];

    // ── Row 2: Replace with ──────────────────────────────────────────────────
    y -= kRowH;
    NSTextField *replaceLabel = [NSTextField labelWithString:@"Replace with:"];
    replaceLabel.alignment = NSTextAlignmentRight;
    replaceLabel.frame = NSMakeRect(kMargin, y, kLabelW, kFieldH);
    [self addSubview:replaceLabel];

    _replaceBox = [[NSTextField alloc] initWithFrame:
        NSMakeRect(fieldX, y, fieldW, kFieldH)];
    _replaceBox.placeholderString = @"Replace";
    _replaceBox.delegate = self;
    [self addSubview:_replaceBox];

    // ── Row 3: Checkboxes ────────────────────────────────────────────────────
    y -= kRowH;
    _ignoreCaseButton = [NSButton checkboxWithTitle:@"Ignore case"
                                             target:nil action:nil];
    _ignoreCaseButton.frame = NSMakeRect(fieldX, y, 110, kFieldH);
    [self addSubview:_ignoreCaseButton];

    _matchWordButton = [NSButton checkboxWithTitle:@"Match whole word only"
                                            target:nil action:nil];
    _matchWordButton.frame = NSMakeRect(fieldX + 114, y, 170, kFieldH);
    [self addSubview:_matchWordButton];

    // ── Row 4: Action buttons ────────────────────────────────────────────────
    y -= kRowH;
    CGFloat bx = kMargin;
    for (NSButton *btn in actionButtons) {
        btn.frame = NSMakeRect(bx, y, maxBtnW, kFieldH);
        [self addSubview:btn];
        bx += maxBtnW + 4;
    }
}

// ── Public API ───────────────────────────────────────────────────────────────

- (void)showWithText:(NSString *)text flags:(int)flags {
    if (text && text.length > 0)
        _findBox.stringValue = text;

    // Restore checkbox state from flags
    _ignoreCaseButton.state = (flags & MMFRDExactMatch) ? NSControlStateValueOff
                                                        : NSControlStateValueOn;
    _matchWordButton.state  = (flags & MMFRDMatchWord)  ? NSControlStateValueOn
                                                        : NSControlStateValueOff;

    self.hidden = NO;
    [[self window] makeFirstResponder:_findBox];
}

- (NSString *)findString    { return _findBox.stringValue; }
- (NSString *)replaceString { return _replaceBox.stringValue; }
- (BOOL)ignoreCase          { return _ignoreCaseButton.state == NSControlStateValueOn; }
- (BOOL)matchWord           { return _matchWordButton.state  == NSControlStateValueOn; }

// ── Background ───────────────────────────────────────────────────────────────

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

- (void)updateLayer {
    self.layer.borderColor = [NSColor separatorColor].CGColor;
}

// ── Button actions ───────────────────────────────────────────────────────────

- (void)_findNext:(id)sender {
    [_delegate findBarView:self findNext:YES];
}

- (void)_findPrevious:(id)sender {
    [_delegate findBarView:self findNext:NO];
}

- (void)_replace:(id)sender {
    [_delegate findBarView:self replace:NO];
}

- (void)_replaceAll:(id)sender {
    [_delegate findBarView:self replace:YES];
}

- (void)_close:(id)sender {
    self.hidden = YES;
    [_delegate findBarViewDidClose:self];
}

// ── Dragging ──────────────────────────────────────────────────────────────────
// Allow the bar to be dragged anywhere within the text-editing area.
// The delegate supplies the allowed rect; if unavailable we fall back to the
// superview bounds so the bar can never leave the window.

- (void)mouseDown:(NSEvent *)event {
    // Record where inside the bar the user clicked so we can keep that point
    // under the cursor during the drag.
    NSPoint locInSelf = [self convertPoint:event.locationInWindow fromView:nil];
    _dragOffset = locInSelf;
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint locInSuper = [self.superview convertPoint:event.locationInWindow
                                             fromView:nil];
    NSRect bounds = [_delegate findBarViewDraggableBounds:self];
    NSSize barSize = self.frame.size;

    CGFloat newX = locInSuper.x - _dragOffset.x;
    CGFloat newY = locInSuper.y - _dragOffset.y;

    // Clamp so the bar stays fully inside the draggable bounds.
    newX = MAX(NSMinX(bounds), MIN(newX, NSMaxX(bounds) - barSize.width));
    newY = MAX(NSMinY(bounds), MIN(newY, NSMaxY(bounds) - barSize.height));

    [self setFrameOrigin:NSMakePoint(newX, newY)];
}

// ── NSControlTextEditingDelegate ─────────────────────────────────────────────
// Called by the field editor for each key command while a text field is active.
// This is the reliable way to intercept Escape and Return from NSTextField —
// overriding cancelOperation:/keyDown: on the text field itself is unreliable
// because the field editor (an NSTextView) is the actual first responder during
// editing and handles those events before the control sees them.

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)cmd
{
    if (cmd == @selector(cancelOperation:)) {
        // Escape → close the find bar
        [self _close:nil];
        return YES;
    }
    if (cmd == @selector(insertNewline:)) {
        // Return / Shift+Return → find next / previous
        NSUInteger mods = [NSApp currentEvent].modifierFlags
                          & NSEventModifierFlagDeviceIndependentFlagsMask;
        if (mods & NSEventModifierFlagShift)
            [self _findPrevious:control];
        else
            [self _findNext:control];
        return YES;
    }
    if (cmd == @selector(insertTab:)) {
        // Tab → move focus: find → replace → find → …
        NSTextField *next = (control == _findBox) ? _replaceBox : _findBox;
        [[self window] makeFirstResponder:next];
        return YES;
    }
    if (cmd == @selector(insertBacktab:)) {
        // Shift+Tab → move focus in reverse
        NSTextField *prev = (control == _replaceBox) ? _findBox : _replaceBox;
        [[self window] makeFirstResponder:prev];
        return YES;
    }
    return NO;
}

@end
