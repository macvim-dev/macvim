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
#import "MMVimController.h"


@interface MMPlugInManager : NSObject {

    NSMutableArray *plugInClasses;
}

- (NSArray *)plugInClasses;

// Find and load any plugins
- (void)loadAllPlugIns;

// release instances of loaded plugins
- (void)unloadAllPlugIns;

// Return singleton instance of MMPluginManager
+ (MMPlugInManager *)sharedManager;

@end
