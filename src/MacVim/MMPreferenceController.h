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
#import <DBPrefsWindowController.h>

@interface MMPreferenceController : DBPrefsWindowController {

    IBOutlet NSView *generalPreferences;
    IBOutlet NSView *integrationPreferences;


    // Integration pane
    NSDictionary *supportedOdbEditors;
    IBOutlet NSPopUpButton *editors;
    IBOutlet NSButton *installOdbButton;
    IBOutlet NSButton *uninstallOdbButton;

}

// Integration pane
- (IBAction)installOdb:(id)sender;
- (IBAction)uninstallOdb:(id)sender;

@end
