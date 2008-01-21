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
 * MMFullscreenWindow
 *
 * A window without any decorations which covers an entire screen.
 *
 * When entering full-screen mode the window controller is set to control an
 * instance of this class instead of an MMWindow.  (This seems to work fine
 * even though the Apple docs state that it is generally a better idea to
 * create a separate window controller for each window.)
 *
 * Most of the full-screen logic is currently in this class although it might
 * move to the window controller in the future.
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

    target = [t retain];
    view = [v retain];

    [self setHasShadow:NO];
    [self setShowsResizeIndicator:NO];
    [self setBackgroundColor:[NSColor blackColor]];
    [self setReleasedWhenClosed:NO];

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
    [[target windowController] setWindow:self];

    oldTabBarStyle = [[view tabBarControl] styleName];
    [[view tabBarControl] setStyleNamed:@"Unified"];

    // add text view
    oldPosition = [view frame].origin;

    [view removeFromSuperviewWithoutNeedingDisplay];
    [[self contentView] addSubview:view];
    [self setInitialFirstResponder:[view textView]];
    
    // NOTE: Calling setTitle:nil causes an exception to be raised (and it is
    // possible that 'target' has no title when we get here).
    if ([target title])
        [self setTitle:[target title]];

    [self setOpaque:[target isOpaque]];

    // don't set this sooner, so we don't get an additional
    // focus gained message  
    [self setDelegate:delegate];

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
    [view removeFromSuperviewWithoutNeedingDisplay];
    [[target contentView] addSubview:view];
    [view setFrameOrigin:oldPosition];
    [self close];
    [target makeKeyAndOrderFront:self];

    // ...but we don't want a focus gained message either, so don't set this
    // sooner
    [target setDelegate:delegate];

    // fade back in  
    if (didBlend) {
        CGDisplayFade(token, .25, kCGDisplayBlendSolidColor,
            kCGDisplayBlendNormal, .0, .0, .0, false);
        CGReleaseDisplayFadeReservation(token);
    }
    
    [self revealDockIfAppropriate];

    [self autorelease]; // Balance the above retain
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

- (void)centerView
{
    NSRect outer = [self frame], inner = [view frame];
    //NSLog(@"%s %@%@", _cmd, NSStringFromRect(outer), NSStringFromRect(inner));
 
    NSPoint origin = NSMakePoint((outer.size.width - inner.size.width)/2,
                                 (outer.size.height - inner.size.height)/2);
    [view setFrameOrigin:origin];
}


#pragma mark Proxy/Decorator/whatever stuff

- (void)scrollWheel:(NSEvent *)theEvent
{
    [[view textView] scrollWheel:theEvent];
}

@end // MMFullscreenWindow




@implementation MMFullscreenWindow (Private)

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
