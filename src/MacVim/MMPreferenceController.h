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
#import "DBPrefsWindowController.h"

@interface MMPreferenceController : DBPrefsWindowController {
    IBOutlet NSView *generalPreferences;
    IBOutlet NSView *appearancePreferences;
    IBOutlet NSView *advancedPreferences;

    // General pane
    IBOutlet NSPopUpButton *layoutPopUpButton;
    IBOutlet NSButton *autoInstallUpdateButton;
    IBOutlet NSView *sparkleUpdaterPane;
}

// General pane
- (IBAction)showWindow:(id)sender;
- (IBAction)openInCurrentWindowSelectionChanged:(id)sender;
- (IBAction)checkForUpdatesChanged:(id)sender;
- (IBAction)appearanceChanged:(id)sender;
@end
