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
    [[self window] setHidesOnDeactivate:NO];

    return self;
}

@end
