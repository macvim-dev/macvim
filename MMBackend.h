/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import <Foundation/Foundation.h>
#import "MacVim.h"
#import "vim.h"


// If disabled, all input is dropped if input is already being processed.  (If
// enabled, same thing happens at the moment actually.  So this is pretty
// useless.)
#define MM_USE_INPUT_QUEUE 0




@interface MMBackend : NSObject <MMBackendProtocol, MMVimServerProtocol,
        MMVimClientProtocol> {
    NSMutableArray  *queue;
    NSMutableData   *drawData;
    NSConnection    *connection;
    id              frontendProxy;
    NSDictionary    *colorDict;
    NSDictionary    *sysColorDict;
    BOOL            inputReceived;
    BOOL            tabBarVisible;
    unsigned        backgroundColor;
    unsigned        foregroundColor;
    unsigned        specialColor;
    unsigned        defaultBackgroundColor;
    unsigned        defaultForegroundColor;
    NSDate          *lastFlushDate;
    id              dialogReturn;
    NSTimer         *blinkTimer;
    int             blinkState;
    NSTimeInterval  blinkWaitInterval;
    NSTimeInterval  blinkOnInterval;
    NSTimeInterval  blinkOffInterval;
    BOOL            inProcessInput;
#if MM_USE_INPUT_QUEUE
    NSMutableArray  *inputQueue;
#endif
    NSMutableDictionary *connectionNameDict;
    NSMutableDictionary *clientProxyDict;
    NSMutableDictionary *serverReplyDict;
    NSString            *alternateServerName;
    ATSFontContainerRef fontContainerRef;
}

+ (MMBackend *)sharedInstance;

- (void)setBackgroundColor:(int)color;
- (void)setForegroundColor:(int)color;
- (void)setSpecialColor:(int)color;
- (void)setDefaultColorsBackground:(int)bg foreground:(int)fg;
- (NSConnection *)connection;

- (BOOL)checkin;
- (BOOL)openVimWindow;
- (void)clearAll;
- (void)clearBlockFromRow:(int)row1 column:(int)col1
                    toRow:(int)row2 column:(int)col2;
- (void)deleteLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right;
- (void)replaceString:(char*)s length:(int)len row:(int)row column:(int)col
                flags:(int)flags;
- (void)insertLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right;
- (void)drawCursorAtRow:(int)row column:(int)col shape:(int)shape
               fraction:(int)percent color:(int)color;
- (void)flushQueue:(BOOL)force;
- (BOOL)waitForInput:(int)milliseconds;
- (void)exit;
- (void)selectTab:(int)index;
- (void)updateTabBar;
- (BOOL)tabBarVisible;
- (void)showTabBar:(BOOL)enable;
- (void)setRows:(int)rows columns:(int)cols;
- (void)setWindowTitle:(char *)title;
- (char *)browseForFileInDirectory:(char *)dir title:(char *)title
                            saving:(int)saving;
- (int)presentDialogWithType:(int)type title:(char *)title message:(char *)msg
                     buttons:(char *)btns textField:(char *)txtfield;
- (void)addMenuWithTag:(int)tag parent:(int)parentTag name:(char *)name
               atIndex:(int)index;
- (void)addMenuItemWithTag:(int)tag parent:(int)parentTag name:(char *)name
                       tip:(char *)tip icon:(char *)icon
             keyEquivalent:(int)key modifiers:(int)mods
                    action:(NSString *)action atIndex:(int)index;
- (void)removeMenuItemWithTag:(int)tag;
- (void)enableMenuItemWithTag:(int)tag state:(int)enabled;
- (void)showPopupMenuWithName:(char *)name atMouseLocation:(BOOL)mouse;
- (void)showToolbar:(int)enable flags:(int)flags;
- (void)createScrollbarWithIdentifier:(long)ident type:(int)type;
- (void)destroyScrollbarWithIdentifier:(long)ident;
- (void)showScrollbarWithIdentifier:(long)ident state:(int)visible;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident;
- (void)setScrollbarThumbValue:(long)val size:(long)size max:(long)max
                    identifier:(long)ident;
- (BOOL)setFontWithName:(char *)name;
- (void)executeActionWithName:(NSString *)name;
- (void)setMouseShape:(int)shape;
- (void)setBlinkWait:(int)wait on:(int)on off:(int)off;
- (void)startBlink;
- (void)stopBlink;
- (void)adjustLinespace:(int)linespace;
- (void)activate;

- (int)lookupColorWithKey:(NSString *)key;
- (BOOL)hasSpecialKeyWithValue:(NSString *)value;

- (void)registerServerWithName:(NSString *)name;
- (BOOL)sendToServer:(NSString *)name string:(NSString *)string
               reply:(char_u **)reply port:(int *)port expression:(BOOL)expr
              silent:(BOOL)silent;
- (NSArray *)serverList;
- (NSString *)peekForReplyOnPort:(int)port;
- (NSString *)waitForReplyOnPort:(int)port;
- (BOOL)sendReply:(NSString *)reply toPort:(int)port;

@end
