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



@interface MMFindReplaceController : NSWindowController {
    IBOutlet NSTextField    *findBox;
    IBOutlet NSTextField    *replaceBox;
    IBOutlet NSButton       *ignoreCaseButton;
    IBOutlet NSButton       *matchWordButton;
}

+ (MMFindReplaceController *)sharedInstance;

- (void)showWithText:(NSString *)text flags:(int)flags;
- (NSString *)findString;
- (NSString *)replaceString;
- (BOOL)ignoreCase;
- (BOOL)matchWord;
@end
