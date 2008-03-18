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

@interface MMFullscreenWindow : NSWindow {
    NSWindow    *target;
    MMVimView   *view;
    NSPoint     oldPosition;
    NSString    *oldTabBarStyle;

    // These are only valid in fullscreen mode and store pre-fu vim size 
    int         nonFuRows, nonFuColumns;

    // These store the size vim had right after entering fu mode
    int         startFuRows, startFuColumns;

    // This stores the contents of fuoptions_flags at fu start time
    int         startFuFlags;
}

- (MMFullscreenWindow *)initWithWindow:(NSWindow *)t view:(MMVimView *)v;

- (void)enterFullscreen:(int)fuoptions;
- (void)leaveFullscreen;
- (void)centerView;

- (BOOL)canBecomeKeyWindow;
- (BOOL)canBecomeMainWindow;

@end
