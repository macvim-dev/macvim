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

@class MMWindowController;



@interface MMVimController : NSObject {
    MMWindowController  *windowController;
    NSPort              *sendPort;
    NSPort              *receivePort;
    NSMutableArray      *mainMenuItems;
    BOOL                shouldUpdateMainMenu;
    //NSMutableArray      *popupMenus;
    NSToolbar           *toolbar;
    NSMutableDictionary *toolbarItemDict;
}

- (id)initWithPort:(NSPort *)port;
- (void)windowWillClose:(NSNotification *)notification;
- (NSPort *)sendPort;

@end

// vim: set ft=objc:
