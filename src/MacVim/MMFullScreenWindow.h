/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved            by Bram Moolenaar
 *                              MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import <Cocoa/Cocoa.h>



@class MMVimView;

@interface MMFullScreenWindow : NSWindow {
    NSWindow    *target;
    MMVimView   *view;
    NSPoint     oldPosition;
    NSString    *oldTabBarStyle;
    int         options;
    int         state;

    // These are only valid in full-screen mode and store pre-fu vim size 
    int         nonFuRows, nonFuColumns;

    // These store the size vim had right after entering fu mode
    int         startFuRows, startFuColumns;

    // This stores the contents of fuoptions_flags at fu start time
    int         startFuFlags;
  
    // Controls the speed of the fade in and out.
    double      fadeTime;
    double      fadeReservationTime;
}

- (MMFullScreenWindow *)initWithWindow:(NSWindow *)t view:(MMVimView *)v
                               backgroundColor:(NSColor *)back;
- (void)setOptions:(int)opt;
- (void)enterFullScreen;
- (void)leaveFullScreen;
- (void)centerView;

- (BOOL)canBecomeKeyWindow;
- (BOOL)canBecomeMainWindow;

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification;
@end
