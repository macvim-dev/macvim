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
    BOOL                isInitialized;
    MMWindowController  *windowController;
    id                  backendProxy;
    BOOL                inProcessCommandQueue;
    NSMutableArray      *sendQueue;
    NSMutableArray      *mainMenuItems;
    NSMutableArray      *popupMenuItems;
    BOOL                shouldUpdateMainMenu;
    NSToolbar           *toolbar;
    NSMutableDictionary *toolbarItemDict;
    int                 pid;
}

- (id)initWithBackend:(id)backend pid:(int)processIdentifier;
- (id)backendProxy;
- (int)pid;
- (MMWindowController *)windowController;
- (void)cleanup;
- (void)sendMessage:(int)msgid data:(NSData *)data wait:(BOOL)wait;

@end

// vim: set ft=objc:
