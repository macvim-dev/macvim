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
extern NSString *MMTextInsetLeftKey;
extern NSString *MMTextInsetRightKey;
extern NSString *MMTextInsetTopKey;
extern NSString *MMTextInsetBottomKey;
extern NSString *MMTerminateAfterLastWindowClosedKey;
extern NSString *MMTypesetterKey;
extern NSString *MMCellWidthMultiplierKey;
extern NSString *MMBaselineOffsetKey;
extern NSString *MMCenterGlyphsKey;


@class MMWindowController;


@interface MMAppController : NSObject <MMAppProtocol> {
    NSMutableArray  *vimControllers;
}

- (void)removeVimController:(id)controller;
- (void)windowControllerWillOpen:(MMWindowController *)windowController;
- (IBAction)newVimWindow:(id)sender;
- (IBAction)selectNextWindow:(id)sender;
- (IBAction)selectPreviousWindow:(id)sender;

@end
