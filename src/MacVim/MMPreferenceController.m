/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMPreferenceController.h"
#import "MacVim.h"



@implementation MMPreferenceController

+ (MMPreferenceController *)sharedPreferenceController
{
    static MMPreferenceController *singleton = nil;
    if (!singleton)
        singleton = [[MMPreferenceController alloc] init];
    return singleton;
}

- (id)init
{
    self = [super initWithWindowNibName:@"Preferences"];
    if (!self) return nil;

    [self setWindowFrameAutosaveName:@"Preferences"];
    return self;
}

- (void)windowDidLoad
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    [loginShellButton setState:[ud boolForKey:MMLoginShellKey]];
    [openFilesInTabsButton setState:[ud boolForKey:MMOpenFilesInTabsKey]];
    [terminateAfterLastWindowClosedButton setState:
            [ud boolForKey:MMTerminateAfterLastWindowClosedKey]];
    [translateCtrlClickButton setState:[ud boolForKey:MMTranslateCtrlClickKey]];

    int tag = [[ud objectForKey:MMUntitledWindowKey] intValue];
    if (tag < 0) tag = 0;
    else if (tag > 3) tag = 3;
    [untitledWindowPopUp selectItemWithTag:tag];
}

- (IBAction)loginShellDidChange:(id)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:[sender state] forKey:MMLoginShellKey];
}

- (IBAction)openFilesInTabsDidChange:(id)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:[sender state] forKey:MMOpenFilesInTabsKey];
}

- (IBAction)terminateAfterLastWindowClosedDidChange:(id)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:[sender state] forKey:MMTerminateAfterLastWindowClosedKey];
}

- (IBAction)translateCtrlClickDidChange:(id)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:[sender state] forKey:MMTranslateCtrlClickKey];
}

- (IBAction)untitledWindowDidChange:(id)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int tag = [[sender selectedItem] tag];
    [ud setInteger:tag forKey:MMUntitledWindowKey];
}

@end
