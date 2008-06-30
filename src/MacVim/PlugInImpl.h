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
#import "PlugInInterface.h"

@interface MMPlugInAppMediator : NSObject <PlugInAppMediator> {
    NSMenu *plugInMenu;
}

+ (MMPlugInAppMediator *)sharedAppMediator;

@end


@class MMVimController;

// One of these per vim controller object.  It manages all of the plugin
// instances for a given controller.
@interface MMPlugInInstanceMediator : NSObject <PlugInInstanceMediator> {
    // NB: this is a weak reference to the vim controller
    MMVimController *vimController;
    NSMutableArray *instances;
    NSDrawer *drawer;
    NSMutableArray *plugInViews ;
}

- (id)initWithVimController:(MMVimController *)controller;

@end
