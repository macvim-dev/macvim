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

@interface MMPreferenceController : NSWindowController {
    IBOutlet id loginShellButton;
    IBOutlet id openFilesInTabsButton;
    IBOutlet id terminateAfterLastWindowClosedButton;
    IBOutlet id translateCtrlClickButton;
    IBOutlet id untitledWindowPopUp;
}

+ (MMPreferenceController *)sharedPreferenceController;

- (IBAction)loginShellDidChange:(id)sender;
- (IBAction)openFilesInTabsDidChange:(id)sender;
- (IBAction)terminateAfterLastWindowClosedDidChange:(id)sender;
- (IBAction)translateCtrlClickDidChange:(id)sender;
- (IBAction)untitledWindowDidChange:(id)sender;

@end
