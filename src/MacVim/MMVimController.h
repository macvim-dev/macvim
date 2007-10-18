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


// If sendMessage: fails, store the message and resend after a delay.
#define MM_RESEND_LAST_FAILURE 0


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
    NSString            *serverName;
#ifdef MM_RESEND_LAST_FAILURE
    NSTimer             *resendTimer;
    int                 resendMsgid;
    NSData              *resendData;
#endif
    NSMenu              *lastMenuSearched;
}

- (id)initWithBackend:(id)backend pid:(int)processIdentifier;
- (id)backendProxy;
- (int)pid;
- (void)setServerName:(NSString *)name;
- (NSString *)serverName;
- (MMWindowController *)windowController;
- (void)cleanup;
- (void)dropFiles:(NSArray *)filenames;
- (void)dropString:(NSString *)string;
- (void)sendMessage:(int)msgid data:(NSData *)data;
- (BOOL)sendMessageNow:(int)msgid data:(NSData *)data
               timeout:(NSTimeInterval)timeout;

@end

// vim: set ft=objc:
