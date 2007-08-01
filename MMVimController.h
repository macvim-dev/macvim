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



@interface MMVimController : NSObject
#if MM_USE_DO
    <MMFrontendProtocol>
#endif
{
    MMWindowController  *windowController;
#if MM_USE_DO
    id                  backendProxy;
# if MM_DELAY_SEND_IN_PROCESS_CMD_QUEUE
    BOOL                inProcessCommandQueue;
    NSMutableArray      *sendQueue;
# endif
#else
    NSPort              *sendPort;
    NSPort              *receivePort;
#endif
    NSMutableArray      *mainMenuItems;
    BOOL                shouldUpdateMainMenu;
    //NSMutableArray      *popupMenus;
    NSToolbar           *toolbar;
    NSMutableDictionary *toolbarItemDict;
}

#if MM_USE_DO
- (id)initWithBackend:(id)backend;
- (id)backendProxy;
#else
- (id)initWithPort:(NSPort *)port;
- (NSPort *)sendPort;
#endif
- (MMWindowController *)windowController;
- (void)windowWillClose:(NSNotification *)notification;
- (void)sendMessage:(int)msgid data:(NSData *)data wait:(BOOL)wait;

@end

// vim: set ft=objc:
