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




@interface MMBackend : NSObject <MMBackendProtocol, MMVimServerProtocol,
        MMVimClientProtocol> {
    NSMutableArray      *outputQueue;
    NSMutableArray      *inputQueue;
    NSMutableData       *drawData;
    NSConnection        *connection;
    id                  frontendProxy;
    NSDictionary        *colorDict;
    NSDictionary        *sysColorDict;
    NSDictionary        *actionDict;
    BOOL                tabBarVisible;
    unsigned            backgroundColor;
    unsigned            foregroundColor;
    unsigned            specialColor;
    unsigned            defaultBackgroundColor;
    unsigned            defaultForegroundColor;
    NSDate              *lastFlushDate;
    id                  dialogReturn;
    NSTimer             *blinkTimer;
    int                 blinkState;
    NSTimeInterval      blinkWaitInterval;
    NSTimeInterval      blinkOnInterval;
    NSTimeInterval      blinkOffInterval;
    NSMutableDictionary *connectionNameDict;
    NSMutableDictionary *clientProxyDict;
    NSMutableDictionary *serverReplyDict;
    NSString            *alternateServerName;
    ATSFontContainerRef fontContainerRef;
    NSFont              *oldWideFont;
    BOOL                isTerminating;
    BOOL                waitForAck;
    int                 initialWindowLayout;
    BOOL                flushDisabled;
}

+ (MMBackend *)sharedInstance;

- (void)setBackgroundColor:(int)color;
- (void)setForegroundColor:(int)color;
- (void)setSpecialColor:(int)color;
- (void)setDefaultColorsBackground:(int)bg foreground:(int)fg;
- (NSConnection *)connection;
- (NSDictionary *)actionDict;
- (int)initialWindowLayout;

- (void)queueMessage:(int)msgid properties:(NSDictionary *)props;
- (BOOL)checkin;
- (BOOL)openGUIWindow;
- (void)clearAll;
- (void)clearBlockFromRow:(int)row1 column:(int)col1
                    toRow:(int)row2 column:(int)col2;
- (void)deleteLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right;
- (void)drawString:(char*)s length:(int)len row:(int)row column:(int)col
             cells:(int)cells flags:(int)flags;
- (void)insertLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right;
- (void)drawCursorAtRow:(int)row column:(int)col shape:(int)shape
               fraction:(int)percent color:(int)color;
- (void)drawInvertedRectAtRow:(int)row column:(int)col numRows:(int)nr
                   numColumns:(int)nc invert:(int)invert;
- (void)update;
- (void)flushQueue:(BOOL)force;
- (BOOL)waitForInput:(int)milliseconds;
- (void)exit;
- (void)selectTab:(int)index;
- (void)updateTabBar;
- (BOOL)tabBarVisible;
- (void)showTabBar:(BOOL)enable;
- (void)setRows:(int)rows columns:(int)cols;
- (void)setWindowTitle:(char *)title;
- (void)setDocumentFilename:(char *)filename;
- (char *)browseForFileWithAttributes:(NSDictionary *)attr;
- (int)showDialogWithAttributes:(NSDictionary *)attr textField:(char *)txtfield;
- (void)showToolbar:(int)enable flags:(int)flags;
- (void)createScrollbarWithIdentifier:(long)ident type:(int)type;
- (void)destroyScrollbarWithIdentifier:(long)ident;
- (void)showScrollbarWithIdentifier:(long)ident state:(int)visible;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident;
- (void)setScrollbarThumbValue:(long)val size:(long)size max:(long)max
                    identifier:(long)ident;
- (void)setFont:(NSFont *)font;
- (void)setWideFont:(NSFont *)font;
- (void)executeActionWithName:(NSString *)name;
- (void)setMouseShape:(int)shape;
- (void)setBlinkWait:(int)wait on:(int)on off:(int)off;
- (void)startBlink;
- (void)stopBlink;
- (void)adjustLinespace:(int)linespace;
- (void)activate;
- (void)setPreEditRow:(int)row column:(int)col;

- (int)lookupColorWithKey:(NSString *)key;
- (BOOL)hasSpecialKeyWithValue:(NSString *)value;

- (void)enterFullscreen:(int)fuoptions background:(int)bg;
- (void)leaveFullscreen;

- (void)setAntialias:(BOOL)antialias;

- (void)updateModifiedFlag;

- (void)registerServerWithName:(NSString *)name;
- (BOOL)sendToServer:(NSString *)name string:(NSString *)string
               reply:(char_u **)reply port:(int *)port expression:(BOOL)expr
              silent:(BOOL)silent;
- (NSArray *)serverList;
- (NSString *)peekForReplyOnPort:(int)port;
- (NSString *)waitForReplyOnPort:(int)port;
- (BOOL)sendReply:(NSString *)reply toPort:(int)port;

- (BOOL)waitForAck;
- (void)setWaitForAck:(BOOL)yn;
- (void)waitForConnectionAcknowledgement;

@end



@interface NSString (VimStrings)
+ (id)stringWithVimString:(char_u *)s;
- (char_u *)vimStringSave;
@end
