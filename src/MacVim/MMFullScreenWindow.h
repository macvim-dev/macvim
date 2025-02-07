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
    int         options;
    int         state;

    /// The non-full-screen size of the Vim view. Used for non-maxvert/maxhorz options.
    NSSize      nonFuVimViewSize;

    // This stores the contents of fuoptions_flags at fu start time
    int         startFuFlags;
  
    // Controls the speed of the fade in and out.
    // This feature is deprecated and off by default.
    double      fadeTime;
    double      fadeReservationTime;
}

- (MMFullScreenWindow *)initWithWindow:(NSWindow *)t view:(MMVimView *)v
                               backgroundColor:(NSColor *)back;
- (void)setOptions:(int)opt;
- (void)updatePresentationOptions;
- (void)enterFullScreen;
- (void)leaveFullScreen;
- (NSRect)getDesiredFrame;

- (BOOL)canBecomeKeyWindow;
- (BOOL)canBecomeMainWindow;

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification;

// Public macaction's.
// Note: New items here need to be handled in validateMenuItem: as well.
- (void)performClose:(id)sender;

@end
