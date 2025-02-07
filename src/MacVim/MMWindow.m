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

#import "CGSInternal/CGSWindow.h"

typedef CGError CGSSetWindowBackgroundBlurRadiusFunction(CGSConnectionID cid, CGSWindowID wid, NSUInteger blur);

static void *GetFunctionByName(NSString *library, char *func) {
    CFBundleRef bundle;
    CFURLRef bundleURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef) library, kCFURLPOSIXPathStyle, true);
    CFStringRef functionName = CFStringCreateWithCString(kCFAllocatorDefault, func, kCFStringEncodingASCII);
    bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL);
    void *f = NULL;
    if (bundle) {
        f = CFBundleGetFunctionPointerForName(bundle, functionName);
        CFRelease(bundle);
    }
    CFRelease(functionName);
    CFRelease(bundleURL);
    return f;
}

static CGSSetWindowBackgroundBlurRadiusFunction* GetCGSSetWindowBackgroundBlurRadiusFunction(void) {
    static BOOL tried = NO;
    static CGSSetWindowBackgroundBlurRadiusFunction *function = NULL;
    if (!tried) {
        function = GetFunctionByName(@"/System/Library/Frameworks/ApplicationServices.framework",
                                      "CGSSetWindowBackgroundBlurRadius");
        tried = YES;
    }
    return function;
}


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

- (BOOL) canBecomeMainWindow {
    return YES;
}

- (BOOL) canBecomeKeyWindow {
    return YES;
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

- (void)setBlurRadius:(int)radius
{
    [MMWindow setBlurRadius:radius onWindow:self];
}

+ (void)setBlurRadius:(int)radius onWindow:(NSWindow *)win
{
    if (radius >= 0) {
        CGSConnectionID con = CGSMainConnectionID();
        if (!con) {
            return;
        }
        CGSSetWindowBackgroundBlurRadiusFunction* function = GetCGSSetWindowBackgroundBlurRadiusFunction();
        if (function) {
            function(con, (int)[win windowNumber], radius);
        }
    }
}

- (void)performClose:(id)sender
{
    id wc = [self windowController];
    if ([wc respondsToSelector:@selector(performClose:)])
        [wc performClose:sender];
    else
        [super performClose:sender];
}

/// Validates whether the menu item should be enabled or not.
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    // This class only really have one action that's bound from Vim
    if ([item action] == @selector(performClose:)) {
        return [item tag];
    }

    // Since this is a subclass of NSWindow, it has a bunch of auto-populated
    // menu from the OS. Just pass it off to the superclass to let it handle it.
    return [super validateMenuItem:item];
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
    // This is an NSWindow method used to enter full-screen since OS X 10.7
    // Lion. We override it so that we can interrupt and pass this on to Vim
    // first, as it is full-screen aware (":set fullscreen") and it's better to
    // only have one path to enter full screen. For non-native full screen this
    // does mean this button will now enter non-native full screen instead of
    // native one.
    // To get to the original method (and enter Lion full-screen) we need to
    // call realToggleFullScreen: defined below.

    // (Use performSelector:: to avoid compilation warning.)
    [[self delegate] performSelector:@selector(invFullScreen:) withObject:nil];
}

- (IBAction)realToggleFullScreen:(id)sender
{
    // See toggleFullScreen: comment above.
    [super toggleFullScreen:sender];
}

- (void)setToolbar:(NSToolbar *)toolbar
{
    if ([[NSUserDefaults standardUserDefaults] 
            boolForKey:MMNoTitleBarWindowKey]) {
        // MacVim can't have toolbar with No title bar setting.
        return;
    }

    [super setToolbar:toolbar];
}

@end // MMWindow
