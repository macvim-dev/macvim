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
    IBOutlet NSView *inputPreferences;
    IBOutlet NSView *advancedPreferences;

    // General pane
    IBOutlet NSPopUpButton *layoutPopUpButton;
    IBOutlet NSButton *autoInstallUpdateButton;
    IBOutlet NSView *sparkleUpdaterPane;

    // Input pane
    IBOutlet NSButton *allowForceClickLookUpButton;

    // Advanced pane
    IBOutlet NSView *sparklePrereleaseButton;
    IBOutlet NSView *sparklePrereleaseDesc;
}

// General pane
- (IBAction)showWindow:(id)sender;
- (IBAction)openInCurrentWindowSelectionChanged:(id)sender;
- (IBAction)checkForUpdatesChanged:(id)sender;
- (IBAction)appearanceChanged:(id)sender;
- (IBAction)smoothResizeChanged:(id)sender;

// Appearance pane
- (IBAction)fontPropertiesChanged:(id)sender;
- (IBAction)tabsPropertiesChanged:(id)sender;
- (IBAction)nonNativeFullScreenShowMenuChanged:(id)sender;

@end
