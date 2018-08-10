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


#ifdef FEAT_BEVAL
// Seconds to delay balloon evaluation after mouse event (subtracted from
// p_bdlay).
extern NSTimeInterval MMBalloonEvalInternalDelay;
#endif


@interface MMBackend : NSObject <MMBackendProtocol, MMVimServerProtocol,
        MMVimClientProtocol> {
    NSMutableArray      *outputQueue;
    NSMutableArray      *inputQueue;
    NSMutableData       *drawData;
    NSConnection        *connection;
    NSConnection        *vimServerConnection;
    id                  appProxy;
    unsigned            identifier;
    NSDictionary        *colorDict;
    NSDictionary        *sysColorDict;
    NSDictionary        *actionDict;
    BOOL                tabBarVisible;
    unsigned            backgroundColor;
    unsigned            foregroundColor;
    unsigned            specialColor;
    unsigned            defaultBackgroundColor;
    unsigned            defaultForegroundColor;
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
    GuiFont             oldWideFont;
    BOOL                isTerminating;
    BOOL                waitForAck;
    int                 initialWindowLayout;
    BOOL                flushDisabled;
    unsigned            numWholeLineChanges;
    unsigned            offsetForDrawDataPrune;
    BOOL                imState;
    int                 winposX;
    int                 winposY;
#ifdef FEAT_BEVAL
    NSString            *lastToolTip;
#endif
}

+ (MMBackend *)sharedInstance;

- (void)setBackgroundColor:(int)color;
- (void)setForegroundColor:(int)color;
- (void)setSpecialColor:(int)color;
- (void)setDefaultColorsBackground:(int)bg foreground:(int)fg;
- (NSConnection *)connection;
- (NSDictionary *)actionDict;
- (int)initialWindowLayout;
- (void)getWindowPositionX:(int*)x Y:(int*)y;
- (void)setWindowPositionX:(int)x Y:(int)y;

- (void)queueMessage:(int)msgid properties:(NSDictionary *)props;
- (BOOL)checkin;
- (BOOL)openGUIWindow;
- (void)clearAll;
- (void)clearBlockFromRow:(int)row1 column:(int)col1
                    toRow:(int)row2 column:(int)col2;
- (void)deleteLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right;
- (void)drawString:(char_u*)s length:(int)len row:(int)row
            column:(int)col cells:(int)cells flags:(int)flags;
- (void)insertLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right;
- (void)drawCursorAtRow:(int)row column:(int)col shape:(int)shape
               fraction:(int)percent color:(int)color;
- (void)drawInvertedRectAtRow:(int)row column:(int)col numRows:(int)nr
                   numColumns:(int)nc invert:(int)invert;
- (void)drawSign:(NSString *)imgName
           atRow:(int)row
          column:(int)col
           width:(int)width
          height:(int)height;
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
- (void)createScrollbarWithIdentifier:(int32_t)ident type:(int)type;
- (void)destroyScrollbarWithIdentifier:(int32_t)ident;
- (void)showScrollbarWithIdentifier:(int32_t)ident state:(int)visible;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(int32_t)ident;
- (void)setScrollbarThumbValue:(long)val size:(long)size max:(long)max
                    identifier:(int32_t)ident;
- (void)setFont:(GuiFont)font wide:(BOOL)wide;
- (void)executeActionWithName:(NSString *)name;
- (void)setMouseShape:(int)shape;
- (void)setBlinkWait:(int)wait on:(int)on off:(int)off;
- (void)startBlink;
- (void)stopBlink:(BOOL)updateCursor;
- (void)adjustLinespace:(int)linespace;
- (void)adjustColumnspace:(int)columnspace;
- (void)activate;
- (void)setPreEditRow:(int)row column:(int)col;

- (int)lookupColorWithKey:(NSString *)key;
- (BOOL)hasSpecialKeyWithValue:(char_u *)value;

- (void)enterFullScreen:(int)fuoptions background:(int)bg;
- (void)leaveFullScreen;
- (void)setFullScreenBackgroundColor:(int)color;

- (void)setAntialias:(BOOL)antialias;
- (void)setLigatures:(BOOL)ligatures;
- (void)setThinStrokes:(BOOL)thinStrokes;
- (void)setBlurRadius:(int)radius;

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

- (BOOL)imState;
- (void)setImState:(BOOL)activated;

#ifdef FEAT_BEVAL
- (void)setLastToolTip:(NSString *)toolTip;
#endif

- (void)addToMRU:(NSArray *)filenames;

@end



@interface NSString (VimStrings)
+ (id)stringWithVimString:(char_u *)s;
- (char_u *)vimStringSave;
@end
