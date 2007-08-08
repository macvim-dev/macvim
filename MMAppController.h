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
#import "MacVim.h"


// NSUserDefaults keys
extern NSString *MMNoWindowKey;
extern NSString *MMTabMinWidthKey;
extern NSString *MMTabMaxWidthKey;
extern NSString *MMTabOptimumWidthKey;
extern NSString *MMStatuslineOffKey;
extern NSString *MMTextInsetLeft;
extern NSString *MMTextInsetRight;
extern NSString *MMTextInsetTop;
extern NSString *MMTextInsetBottom;
extern NSString *MMTerminateAfterLastWindowClosed;



@interface MMAppController : NSObject <MMAppProtocol>
{
    NSMutableArray  *vimControllers;
}

- (void)removeVimController:(id)controller;
- (IBAction)newVimWindow:(id)sender;
- (IBAction)selectNextWindow:(id)sender;
- (IBAction)selectPreviousWindow:(id)sender;

@end
