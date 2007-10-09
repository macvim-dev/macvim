/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import <Cocoa/Cocoa.h>



@class MMVimView;

@interface MMFullscreenWindow : NSWindow {
    NSWindow* target;
    MMVimView* view;
    NSPoint oldPosition;
    NSString *oldTabBarStyle;
}

- (MMFullscreenWindow*)initWithWindow:(NSWindow*)t andView:(MMVimView*)v;

- (void) enterFullscreen;
- (void) leaveFullscreen;

- (BOOL)canBecomeKeyWindow;
- (BOOL)canBecomeMainWindow;

@end
