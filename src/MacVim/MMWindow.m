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
 * MMWindow
 *
 * A normal window with a (possibly hidden) tabline separator at the top of the
 * content view.
 *
 * The main point of this class is for the window controller to be able to call
 * contentRectForFrameRect: without having to worry about whether the separator
 * is visible or not.
 *
 * This is a bit of a hack, it would be nicer to be able to leave the content
 * view alone, but as it is the tabline separator is a subview of the content
 * view.  Since we want to pretend that the content view does not contain the
 * separator this leads to some dangerous situations.  For instance, calling
 * [window setContentMinSize:size] when the separator is visible results in
 * size != [window contentMinSize], since the latter is one pixel higher than
 * 'size'.
 */

#import "MMWindow.h"
#import "Miscellaneous.h"




@implementation MMWindow

- (id)initWithContentRect:(NSRect)rect
                styleMask:(NSUInteger)style
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag
{
    self = [super initWithContentRect:rect
                            styleMask:style
                              backing:bufferingType
                                defer:flag];
    if (!self) return nil;

    [self setReleasedWhenClosed:NO];

    NSRect tabSepRect = { {0, rect.size.height - 1}, {rect.size.width, 1} };
    tablineSeparator = [[NSBox alloc] initWithFrame:tabSepRect];
    
    [tablineSeparator setBoxType:NSBoxSeparator];
    [tablineSeparator setHidden:YES];
    [tablineSeparator setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];

    NSView *contentView = [self contentView];
    [contentView setAutoresizesSubviews:YES];
    [contentView addSubview:tablineSeparator];

    // NOTE: Vim needs to process mouse moved events, so enable them here.
    [self setAcceptsMouseMovedEvents:YES];

    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    // TODO: Is there any reason why we would want the following call?
    //[tablineSeparator removeFromSuperviewWithoutNeedingDisplay];
    [tablineSeparator release];  tablineSeparator = nil;
    [super dealloc];
}

- (BOOL)hideTablineSeparator:(BOOL)hide
{
    BOOL isHidden = [tablineSeparator isHidden];
    [tablineSeparator setHidden:hide];

    // Return YES if visibility state was toggled, NO if it was unchanged.
    return isHidden != hide;
}

- (NSRect)contentRectForFrameRect:(NSRect)frame
{
    NSRect rect = [super contentRectForFrameRect:frame];
    if (![tablineSeparator isHidden])
        --rect.size.height;

    return rect;
}

- (NSRect)frameRectForContentRect:(NSRect)rect
{
    NSRect frame = [super frameRectForContentRect:rect];
    if (![tablineSeparator isHidden])
        ++frame.size.height;

    return frame;
}

- (void)setContentMinSize:(NSSize)size
{
    if (![tablineSeparator isHidden])
        ++size.height;

    [super setContentMinSize:size];
}

- (void)setContentMaxSize:(NSSize)size
{
    if (![tablineSeparator isHidden])
        ++size.height;

    [super setContentMaxSize:size];
}

- (void)setContentSize:(NSSize)size
{
    if (![tablineSeparator isHidden])
        ++size.height;

    [super setContentSize:size];
}

- (void)performClose:(id)sender
{
    id wc = [self windowController];
    if ([wc respondsToSelector:@selector(performClose:)])
        [wc performClose:sender];
    else
        [super performClose:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(vimMenuItemAction:)
            || [item action] == @selector(performClose:))
        return [item tag];

    return YES;
}

- (IBAction)zoom:(id)sender
{
    // NOTE: We shortcut the usual zooming behavior and provide custom zooming
    // in the window controller.

    // (Use performSelector:: to avoid compilation warning.)
    [[self delegate] performSelector:@selector(zoom:) withObject:sender];
}

- (IBAction)toggleFullScreen:(id)sender
{
    // HACK! This is an NSWindow method used to enter full-screen on OS X 10.7.
    // We override it so that we can interrupt and pass this on to Vim first.
    // An alternative hack would be to reroute the action message sent by the
    // full-screen button in the top right corner of a window, but there could
    // be other places where this action message is sent from.
    // To get to the original method (and enter Lion full-screen) we need to
    // call realToggleFullScreen: defined below.

    // (Use performSelector:: to avoid compilation warning.)
    [[self delegate] performSelector:@selector(invFullScreen:) withObject:nil];
}

- (IBAction)realToggleFullScreen:(id)sender
{
#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)
    // HACK! See toggleFullScreen: comment above.
    if ([NSWindow instancesRespondToSelector:@selector(toggleFullScreen:)])
        [super toggleFullScreen:sender];
#endif
}

@end // MMWindow
