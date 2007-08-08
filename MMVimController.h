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
#import "MacVim.h"

@class MMWindowController;



@interface MMVimController : NSObject <MMFrontendProtocol>
{
    MMWindowController  *windowController;
    id                  backendProxy;
    BOOL                inProcessCommandQueue;
    NSMutableArray      *sendQueue;
    NSMutableArray      *mainMenuItems;
    BOOL                shouldUpdateMainMenu;
    //NSMutableArray      *popupMenus;
    NSToolbar           *toolbar;
    NSMutableDictionary *toolbarItemDict;
}

- (id)initWithBackend:(id)backend;
- (id)backendProxy;
- (MMWindowController *)windowController;
- (void)windowWillClose:(NSNotification *)notification;
- (void)sendMessage:(int)msgid data:(NSData *)data wait:(BOOL)wait;

@end

// vim: set ft=objc:
