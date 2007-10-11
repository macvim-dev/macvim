/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMFullscreenWindow.h"
#import <PSMTabBarControl.h>
#import "MMVimView.h"
#import "MMTextView.h"
#import "MMWindowController.h"
#import <Carbon/Carbon.h>



@implementation MMFullscreenWindow

- (MMFullscreenWindow *)initWithWindow:(NSWindow *)t view:(MMVimView *)v
{
    NSScreen* screen = [t screen];

    // XXX: what if screen == nil?

    // you can't change the style of an existing window in cocoa. create a new
    // window and move the MMTextView into it.
    // (another way would be to make the existing window large enough that the
    // title bar is off screen. but that doesn't work with multiple screens).  
    self = [super initWithContentRect:[screen frame]
                            styleMask:NSBorderlessWindowMask
                              backing:NSBackingStoreBuffered
                                defer:YES
                               screen:screen];
      
    if (self == nil)
        return nil;

    [self setHasShadow:NO];
    [self setShowsResizeIndicator:NO];
    [self setBackgroundColor:[NSColor blackColor]];
    [self setReleasedWhenClosed:NO];

    target = t;  [target retain];
    view = v;  [view retain];

    return self;
}

- (void)dealloc
{
    [target release];
    [view release];

    [super dealloc];
}

- (void)centerView
{
    NSRect outer = [self frame], inner = [view frame];
    //NSLog(@"%s %@%@", _cmd, NSStringFromRect(outer), NSStringFromRect(inner));
 
    NSPoint origin = NSMakePoint((outer.size.width - inner.size.width)/2,
                                 (outer.size.height - inner.size.height)/2);
    [view setFrameOrigin:origin];
}

- (void)enterFullscreen
{
    // hide menu and dock, both appear on demand
    SetSystemUIMode(kUIModeAllSuppressed, 0); //requires 10.3

    // fade to black
    Boolean didBlend = NO;
    CGDisplayFadeReservationToken token;
    if (CGAcquireDisplayFadeReservation(.5, &token) == kCGErrorSuccess) {
        CGDisplayFade(token, .25, kCGDisplayBlendNormal,
            kCGDisplayBlendSolidColor, .0, .0, .0, true);
        didBlend = YES;
    }
    
    // fool delegate
    id delegate = [target delegate];
    [target setDelegate:nil];
    
    // make target's window controller believe that it's now controlling us
    [target retain];  // NSWindowController will release target once in the
                      // in the next line
    [[target windowController] setWindow:self];


    oldTabBarStyle = [[view tabBarControl] styleName];
    [[view tabBarControl] setStyleNamed:@"Unified"];

    // add text view
    oldPosition = [view frame].origin;

    [[self contentView] addSubview:view];
    [self setInitialFirstResponder:[view textView]];
    
    [self setTitle:[target title]];
    [self setOpaque:[target isOpaque]];

    // make us visible and target invisible
    [target orderOut:self];
    [self makeKeyAndOrderFront:self];

    // don't set this sooner, so we don't get an additional
    // focus gained message  
    [self setDelegate:delegate];

    // update bottom right corner scrollbar (no resize handle in fu mode)
    [[self windowController] placeViews];
    
    // the call above moves the text view in the lower left corner, fix that
    // XXX: still required?
    [self centerView];
    [self display];

    // fade back in
    if (didBlend) {
        CGDisplayFade(token, .25, kCGDisplayBlendSolidColor,
            kCGDisplayBlendNormal, .0, .0, .0, false);
        CGReleaseDisplayFadeReservation(token);
    }
}

- (void)leaveFullscreen
{
    // fade to black
    Boolean didBlend = NO;
    CGDisplayFadeReservationToken token;
    if (CGAcquireDisplayFadeReservation(.5, &token) == kCGErrorSuccess) {
        CGDisplayFade(token, .25, kCGDisplayBlendNormal,
            kCGDisplayBlendSolidColor, .0, .0, .0, true);
        didBlend = YES;
    }

    // fix up target controller
    [self retain];  // NSWindowController releases us once
    [[self windowController] setWindow:target];


    [[view tabBarControl] setStyleNamed:oldTabBarStyle];

    // fix delegate
    id delegate = [self delegate];
    [self setDelegate:nil];
    
    // move text view back to original window, hide fullscreen window,
    // show original window
    // do this _after_ resetting delegate and window controller, so the
    // window controller doesn't get a focus lost message from the fullscreen
    // window.
    [[target contentView] addSubview:view];
    [view setFrameOrigin:oldPosition];
    [self close];
    [target makeKeyAndOrderFront:self];

    // ...but we don't want a focus gained message either, so don't set this
    // sooner
    [target setDelegate:delegate];


    // update bottom right corner scrollbar (resize handle reappears)
    // XXX: Doesn't work?
    [[self windowController] placeViews];
    [view placeScrollbars];


    // fade back in  
    if (didBlend) {
        CGDisplayFade(token, .25, kCGDisplayBlendSolidColor,
            kCGDisplayBlendNormal, .0, .0, .0, false);
        CGReleaseDisplayFadeReservation(token);
    }
    
    // order menu and dock back in
    SetSystemUIMode(kUIModeNormal, 0);
}

// Title-less windows normally don't receive key presses, override this
- (BOOL)canBecomeKeyWindow
{
    return YES;
}

// Title-less windows normally can't become main which means that another
// non-fullscreen window will have the "active" titlebar in expose. Bad, fix it.
- (BOOL)canBecomeMainWindow
{
    return YES;
}


#pragma mark Proxy/Decorator/whatever stuff

// the window controller will send us messages that are meant for the original,
// non-fullscreen window. forward those, and interpret the messages that are
// interesting for us

- (void)setTitle:(NSString *)title
{
    [target setTitle:title];
    [super setTitle:title];
}

// HACK: if the T flag in guioptions is changed in fu mode, the toolbar needs
// to be changed when nofu is set. MMWindowController gets the toolbar object,
// so we need to return a toolbar from this method, even if none is visible for
// the fullscreen window. Seems to work, though.
- (NSToolbar *)toolbar
{
    return [target toolbar];
}

- (void)setFrame:(NSRect)frame display:(BOOL)display
{
    // HACK: if the target window would resize, we have to call our own
    // windowDidResize method so that placeViews in MMWindowController is called
    if (!NSEqualRects(frame, [target frame]))
    {
        [target setFrame:frame display:NO];

        // XXX: send this directly to MMVimView
        if ([[self delegate] respondsToSelector:@selector(windowDidResize:)])
          [[self delegate] windowDidResize:nil];

        [self centerView];
        [self display];
    }
}

/*- (NSRect)frame
{
    return [target frame];  // really? needed by MMWindowController placeViews.
                            //  but mucks up display
}*/

- (NSRect)contentRectForFrameRect:(NSRect)rect
{
    //return [target contentRectForFrameRect:rect];
    
    // EVIL HACK: this is always called with [[self window] frame] as argument
    // from MMWindowController. We can't let frame return the frame of target,
    // so "fix" this here.
    return [target contentRectForFrameRect:[target frame]];
}

- (NSRect)frameRectForContentRect:(NSRect)contentRect
{
    return [target frameRectForContentRect:contentRect];
}

- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen*)screen
{
    return [target constrainFrameRect:frameRect toScreen:screen];
}

- (void)setContentResizeIncrements:(NSSize)size
{
    [target setContentResizeIncrements:size];
}

- (void)setOpaque:(BOOL)isOpaque
{
    // XXX: Do we want transparency even in fullscreen mode?
    [super setOpaque:isOpaque];
    [target setOpaque:isOpaque];
}

@end
