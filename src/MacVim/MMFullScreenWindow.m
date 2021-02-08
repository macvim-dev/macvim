/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved            by Bram Moolenaar
 *                              MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * MMFullScreenWindow
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

#import "MMFullScreenWindow.h"
#import "MMTextView.h"
#import "MMVimController.h"
#import "MMVimView.h"
#import "MMWindowController.h"
#import "Miscellaneous.h"
#import <PSMTabBarControl/PSMTabBarControl.h>

// These have to be the same as in option.h
#define FUOPT_MAXVERT         0x001
#define FUOPT_MAXHORZ         0x002
#define FUOPT_BGCOLOR_HLGROUP 0x004

// Used for 'state' variable
enum {
    BeforeFullScreen = 0,
    InFullScreen,
    LeftFullScreen
};


@interface MMFullScreenWindow (Private)
- (BOOL)isOnPrimaryScreen;
- (BOOL)screenHasDockAndMenu;
- (void)windowDidBecomeMain:(NSNotification *)notification;
- (void)windowDidResignMain:(NSNotification *)notification;
- (void)windowDidMove:(NSNotification *)notification;
@end

@implementation MMFullScreenWindow

- (MMFullScreenWindow *)initWithWindow:(NSWindow *)t view:(MMVimView *)v 
                               backgroundColor:(NSColor *)back
{
    NSScreen* screen = [t screen];

    // XXX: what if screen == nil?

    // you can't change the style of an existing window in cocoa. create a new
    // window and move the MMTextView into it.
    // (another way would be to make the existing window large enough that the
    // title bar is off screen. but that doesn't work with multiple screens).
    self = [super initWithContentRect:[screen frame]
                            styleMask:NSWindowStyleMaskBorderless
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
    [self setBackgroundColor:back];
    [self setReleasedWhenClosed:NO];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(windowDidBecomeMain:)
               name:NSWindowDidBecomeMainNotification
             object:self];

    [nc addObserver:self
           selector:@selector(windowDidResignMain:)
               name:NSWindowDidResignMainNotification
             object:self];

    [nc addObserver:self
           selector:@selector(windowDidMove:)
               name:NSWindowDidMoveNotification
             object:self];

    // NOTE: Vim needs to process mouse moved events, so enable them here.
    [self setAcceptsMouseMovedEvents:YES];
  
    fadeTime = [[NSUserDefaults standardUserDefaults] doubleForKey:MMFullScreenFadeTimeKey];

    // Each fade goes in and then out, so the fade hardware must be reserved accordingly and the
    // actual fade time can't exceed half the allowable reservation time... plus some slack to
    // prevent visual artifacts caused by defaulting on the fade hardware lease.
    fadeTime = MIN(fadeTime, 0.5 * (kCGMaxDisplayReservationInterval - 1));
    fadeReservationTime = 2.0 * fadeTime + 1;
    
    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [target release];  target = nil;
    [view release];  view = nil;

    [super dealloc];
}

- (void)setOptions:(int)opt
{
    options = opt;
}

- (void)enterFullScreen
{
    ASLogDebug(@"Enter full-screen now");

    // Hide Dock and menu bar when going to full screen. Only do so if the current screen
    // has a menu bar and dock.
    if ([self screenHasDockAndMenu]) {
        const bool showMenu = [[NSUserDefaults standardUserDefaults]
                               boolForKey:MMNonNativeFullScreenShowMenuKey];

        [NSApplication sharedApplication].presentationOptions = showMenu ?
            NSApplicationPresentationAutoHideDock :
            NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar;
    }

    // fade to black
    Boolean didBlend = NO;
    CGDisplayFadeReservationToken token;
    if (fadeTime > 0) {
        if (CGAcquireDisplayFadeReservation(fadeReservationTime, &token) == kCGErrorSuccess) {
            CGDisplayFade(token, fadeTime, kCGDisplayBlendNormal,
                kCGDisplayBlendSolidColor, .0, .0, .0, true);
            didBlend = YES;
        }
    }

    // NOTE: The window may have moved to another screen in between init.. and
    // this call so set the frame again just in case.
    [self setFrame:[[target screen] frame] display:NO];

    // fool delegate
    id delegate = [target delegate];
    [target setDelegate:nil];
    
    // make target's window controller believe that it's now controlling us
    [[target windowController] setWindow:self];

    oldTabBarStyle = [[view tabBarControl] styleName];

    NSString *style =
        shouldUseYosemiteTabBarStyle() ? (shouldUseMojaveTabBarStyle() ? @"Mojave" : @"Yosemite") : @"Unified";
    [[view tabBarControl] setStyleNamed:style];

    // add text view
    oldPosition = [view frame].origin;

    [view removeFromSuperviewWithoutNeedingDisplay];
    [[self contentView] addSubview:view];
    [self setInitialFirstResponder:[view textView]];
    
    // NOTE: Calling setTitle:nil causes an exception to be raised (and it is
    // possible that 'target' has no title when we get here).
    if ([target title]) {
        [self setTitle:[target title]];

        // NOTE: Cocoa does not add borderless windows to the "Window" menu so
        // we have to do it manually.
        [NSApp changeWindowsItem:self title:[target title] filename:NO];
    }
    
    [self setAppearance:target.appearance];

    [self setOpaque:[target isOpaque]];

    // don't set this sooner, so we don't get an additional
    // focus gained message  
    [self setDelegate:delegate];

    // Store view dimension used before entering full-screen, then resize the
    // view to match 'fuopt'.
    [[view textView] getMaxRows:&nonFuRows columns:&nonFuColumns];
    nonFuVimViewSize = view.frame.size;

    // Store options used when entering full-screen so that we can restore
    // dimensions when exiting full-screen.
    startFuFlags = options;

    // HACK! Put window on all Spaces to avoid Spaces (available on OS X 10.5
    // and later) from moving the full-screen window to a separate Space from
    // the one the decorated window is occupying.  The collection behavior is
    // restored further down.
    NSWindowCollectionBehavior wcb = [self collectionBehavior];
    [self setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];

    // make us visible and target invisible
    [target orderOut:self];
    [self makeKeyAndOrderFront:self];

    // Restore collection behavior (see hack above).
    [self setCollectionBehavior:wcb];

    // fade back in
    if (didBlend) {
        [NSAnimationContext currentContext].completionHandler = ^{
            CGDisplayFade(token, fadeTime, kCGDisplayBlendSolidColor,
                          kCGDisplayBlendNormal, .0, .0, .0, false);
            CGReleaseDisplayFadeReservation(token);
        };
    }

    state = InFullScreen;
}

- (void)leaveFullScreen
{
    // fade to black
    Boolean didBlend = NO;
    CGDisplayFadeReservationToken token;
    if (fadeTime > 0) {
        if (CGAcquireDisplayFadeReservation(fadeReservationTime, &token) == kCGErrorSuccess) {
            CGDisplayFade(token, fadeTime, kCGDisplayBlendNormal,
                kCGDisplayBlendSolidColor, .0, .0, .0, true);
            didBlend = YES;
        }
    }

    // restore old vim view size
    int currRows, currColumns;
    [[view textView] getMaxRows:&currRows columns:&currColumns];
    int newRows = nonFuRows, newColumns = nonFuColumns;

    // resize vim if necessary
    if (currRows != newRows || currColumns != newColumns) {
        int newSize[2] = { newRows, newColumns };
        NSData *data = [NSData dataWithBytes:newSize length:2*sizeof(int)];
        MMVimController *vimController =
            [[self windowController] vimController];

        [vimController sendMessage:SetTextDimensionsMsgID data:data];
        [[view textView] setMaxRows:newRows columns:newColumns];
    }

    // fix up target controller
    [self retain];  // NSWindowController releases us once
    [[self windowController] setWindow:target];

    [[view tabBarControl] setStyleNamed:oldTabBarStyle];

    // fix delegate
    id delegate = [self delegate];
    [self setDelegate:nil];
    
    // move text view back to original window, hide fullScreen window,
    // show original window
    // do this _after_ resetting delegate and window controller, so the
    // window controller doesn't get a focus lost message from the fullScreen
    // window.
    [view removeFromSuperviewWithoutNeedingDisplay];
    [[target contentView] addSubview:view];

    [view setFrameOrigin:oldPosition];
    [self close];

    // Set the text view to initial first responder, otherwise the 'plus'
    // button on the tabline steals the first responder status.
    [target setInitialFirstResponder:[view textView]];

    // HACK! Put decorated window on all Spaces (available on OS X 10.5 and
    // later) so that the decorated window stays on the same Space as the full
    // screen window (they may occupy different Spaces e.g. if the full-screen
    // window was dragged to another Space).  The collection behavior is
    // restored further down.
    NSWindowCollectionBehavior wcb = [target collectionBehavior];
    [target setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];

#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)
    // HACK! On Mac OS X 10.7 windows animate when makeKeyAndOrderFront: is
    // called.  This is distracting here, so disable the animation and restore
    // animation behavior after calling makeKeyAndOrderFront:.
    NSWindowAnimationBehavior a = NSWindowAnimationBehaviorNone;
    if ([target respondsToSelector:@selector(animationBehavior)]) {
        a = [target animationBehavior];
        [target setAnimationBehavior:NSWindowAnimationBehaviorNone];
    }
#endif

    [target makeKeyAndOrderFront:self];

#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)
    // HACK! Restore animation behavior.
    if (NSWindowAnimationBehaviorNone != a)
        [target setAnimationBehavior:a];
#endif

    // Restore collection behavior (see hack above).
    [target setCollectionBehavior:wcb];

    // ...but we don't want a focus gained message either, so don't set this
    // sooner
    [target setDelegate:delegate];

    // fade back in  
    if (didBlend) {
        CGDisplayFade(token, fadeTime, kCGDisplayBlendSolidColor,
            kCGDisplayBlendNormal, .0, .0, .0, false);
        CGReleaseDisplayFadeReservation(token);
    }
    
    [self autorelease]; // Balance the above retain

    state = LeftFullScreen;
    ASLogDebug(@"Left full-screen");
}

// Title-less windows normally don't receive key presses, override this
- (BOOL)canBecomeKeyWindow
{
    return YES;
}

// Title-less windows normally can't become main which means that another
// non-full-screen window will have the "active" titlebar in expose. Bad, fix
// it.
- (BOOL)canBecomeMainWindow
{
    return YES;
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification
{
    if (state != InFullScreen)
        return;

    // This notification is sent when screen resolution may have changed (e.g.
    // due to a monitor being unplugged or the resolution being changed
    // manually) but it also seems to get called when the Dock is
    // hidden/displayed.
    ASLogDebug(@"Screen unplugged / resolution changed");

    NSScreen *screen = [target screen];
    if (!screen) {
        // Paranoia: if window we originally used for full-screen is gone, try
        // screen window is on now, and failing that (not sure this can happen)
        // use main screen.
        screen = [self screen];
        if (!screen)
            screen = [NSScreen mainScreen];
    }

    // Ensure the full-screen window is still covering the entire screen and
    // then resize view according to 'fuopt'.
    [self setFrame:[screen frame] display:NO];
}

/// Get the view vertical offset to allow us space to show the menu bar and what not.
- (CGFloat) viewOffset {
    if ([[NSUserDefaults standardUserDefaults]
          boolForKey:MMNonNativeFullScreenShowMenuKey]) {
        return [[[NSApplication sharedApplication] mainMenu] menuBarHeight]-1;
    } else {
        return 0;
    }
}

/// Returns the desired frame of the Vim view, which takes fuopts into account
/// by centering the view in the middle of the full-screen frame. If using the
/// default of having both maxvert/maxhorz set, this will simply return
/// desiredFrameSize back.
///
/// @return Desired frame, including size and offset.
- (NSRect)getDesiredFrame;
{
    NSRect windowFrame = [self frame];
    NSSize desiredFrameSize = windowFrame.size;
    desiredFrameSize.height -= [self viewOffset];

    if (!(options & FUOPT_MAXVERT))
        desiredFrameSize.height = MIN(desiredFrameSize.height, nonFuVimViewSize.height);
    if (!(options & FUOPT_MAXHORZ))
        desiredFrameSize.width = MIN(desiredFrameSize.width, nonFuVimViewSize.width);

    NSPoint origin = { floor((windowFrame.size.width - desiredFrameSize.width)/2),
                       floor((windowFrame.size.height - desiredFrameSize.height)/2 - [self viewOffset] / 2) };

    return NSMakeRect(origin.x, origin.y, desiredFrameSize.width, desiredFrameSize.height);
}

- (void)scrollWheel:(NSEvent *)theEvent
{
    [[view textView] scrollWheel:theEvent];
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

@end // MMFullScreenWindow




@implementation MMFullScreenWindow (Private)

- (BOOL)isOnPrimaryScreen
{
    // The primary screen is the screen the menu bar is on. This is different
    // from [NSScreen mainScreen] (which returns the screen containing the
    // key window).
    NSArray *screens = [NSScreen screens];
    if (screens == nil || [screens count] < 1)
        return NO;

    NSScreen* primaryScreen = [screens objectAtIndex:0];

    // We cannot compare the NSScreen pointers directly because they are not
    // guaranteed to match. Instead use the screen number as a more canonical
    // way to compare them.
    NSNumber* primaryScreenNum = primaryScreen.deviceDescription[@"NSScreenNumber"];
    NSNumber* selfScreenNum = [self screen].deviceDescription[@"NSScreenNumber"];
    return selfScreenNum == primaryScreenNum;
}

- (BOOL)screenHasDockAndMenu
{
    return NSScreen.screensHaveSeparateSpaces || [self isOnPrimaryScreen];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    // Hide menu and dock when this window gets focus.
    if ([self screenHasDockAndMenu]) {
        const bool showMenu = [[NSUserDefaults standardUserDefaults]
                               boolForKey:MMNonNativeFullScreenShowMenuKey];

        [NSApplication sharedApplication].presentationOptions = showMenu ?
            NSApplicationPresentationAutoHideDock :
            NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar;
    }
}


- (void)windowDidResignMain:(NSNotification *)notification
{
    // Un-hide menu/dock when we lose focus. This makes sure if we have multiple
    // windows opened, when the non-fullscreen windows get focus they will have the
    // dock and menu showing (since presentationOptions is per-app, not per-window).
    if ([self screenHasDockAndMenu]) {
        [NSApplication sharedApplication].presentationOptions = NSApplicationPresentationDefault;
    }
}

- (void)windowDidMove:(NSNotification *)notification
{
    if (state != InFullScreen)
        return;

    // Window may move as a result of being dragged between Spaces.
    ASLogDebug(@"Full-screen window moved, ensuring it covers the screen...");

    // Ensure the full-screen window is still covering the entire screen and
    // then resize view according to 'fuopt'.
    [self setFrame:[[self screen] frame] display:NO];
}

@end // MMFullScreenWindow (Private)
