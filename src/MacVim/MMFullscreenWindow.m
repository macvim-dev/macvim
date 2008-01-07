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
 * MMFullscreen
 *
 * Support for full-screen editing.
 *
 * Author: Nico Weber
 */

#import "MMFullscreenWindow.h"
#import <PSMTabBarControl.h>
#import "MMVimView.h"
#import "MMTextView.h"
#import "MMWindowController.h"
#import <Carbon/Carbon.h>


static int numFullscreenWindows = 0;

@interface MMFullscreenWindow (Private)
- (void)centerView;
- (BOOL)isOnPrimaryScreen;
- (void)hideDockIfAppropriate;
- (void)revealDockIfAppropriate;
@end

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
                               // since we're passing [screen frame] above,
                               // we want the content rect to be relative to
                               // the main screen (ie, pass nil for screen).
                               screen:nil];
      
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

- (void)enterFullscreen
{
    [self hideDockIfAppropriate];

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

    // don't set this sooner, so we don't get an additional
    // focus gained message  
    [self setDelegate:delegate];

    // update bottom right corner scrollbar (no resize handle in fu mode)
    [view placeViews];

    // move vim view to the window's center
    [self centerView];

    // make us visible and target invisible
    [target orderOut:self];
    [self makeKeyAndOrderFront:self];

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
    [view placeViews];

    // fade back in  
    if (didBlend) {
        CGDisplayFade(token, .25, kCGDisplayBlendSolidColor,
            kCGDisplayBlendNormal, .0, .0, .0, false);
        CGReleaseDisplayFadeReservation(token);
    }
    
    [self revealDockIfAppropriate];
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

- (void)scrollWheel:(NSEvent *)theEvent
{
    [[view textView] scrollWheel:theEvent];
}

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
    
    // EVIL HACK: if this is always called with [[self window] frame] as
    // argument from MMWindowController, we can't let frame return the frame
    // of target so "fix" this here.
    if (NSEqualRects([self frame], rect)) {
        return [target contentRectForFrameRect:[target frame]];
    } else {
        return [target contentRectForFrameRect:rect];
    }
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

@end // MMFullscreenWindow




@implementation MMFullscreenWindow (Private)

- (void)centerView
{
    NSRect outer = [self frame], inner = [view frame];
    //NSLog(@"%s %@%@", _cmd, NSStringFromRect(outer), NSStringFromRect(inner));
 
    NSPoint origin = NSMakePoint((outer.size.width - inner.size.width)/2,
                                 (outer.size.height - inner.size.height)/2);
    [view setFrameOrigin:origin];
}

- (BOOL)isOnPrimaryScreen
{
    // The primary screen is the screen the menu bar is on. This is different
    // from [NSScreen mainScreen] (which returns the screen containing the
    // key window).
    NSArray *screens = [NSScreen screens];
    if (screens == nil || [screens count] < 1)
        return NO;

    return [self screen] == [screens objectAtIndex:0];
}

- (void)hideDockIfAppropriate
{
    // Hide menu and dock, both appear on demand.
    //
    // Don't hide the dock if going fullscreen on a non-primary screen. Also,
    // if there are several fullscreen windows on the primary screen, only
    // hide dock and friends for the first fullscreen window (and display
    // them again after the last fullscreen window has been closed).
    //
    // Another way to deal with several fullscreen windows would be to hide/
    // reveal the dock each time a fullscreen window gets/loses focus, but
    // this way it's less distracting.

    // XXX: If you have a fullscreen window on a secondary monitor and unplug
    // the monitor, this will probably not work right.

    if ([self isOnPrimaryScreen]) {
        if (numFullscreenWindows == 0) {
            SetSystemUIMode(kUIModeAllSuppressed, 0); //requires 10.3
        }
        ++numFullscreenWindows;
    }
}

- (void)revealDockIfAppropriate
{
     // order menu and dock back in
    if ([self isOnPrimaryScreen]) {
        --numFullscreenWindows;
        if (numFullscreenWindows == 0) {
            SetSystemUIMode(kUIModeNormal, 0);
        }
    }
}

@end // MMFullscreenWindow (Private)
