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



@interface MMBackend : NSObject
#if MM_USE_DO
    <MMBackendProtocol>
#endif
{
    NSMutableArray  *queue;
    NSMutableData   *drawData;
#if MM_USE_DO
    NSConnection    *connection;
    id              frontendProxy;
    NSString        *browseForFileString;
#else
    NSPort          *sendPort;
    NSPort          *receivePort;
    NSData          *replyData;
#endif
    NSDictionary    *colorDict;
    BOOL            inputReceived;
    BOOL            receivedKillTaskMsg;
    BOOL            tabBarVisible;
    int             backgroundColor;
    int             foregroundColor;
    int             defaultBackgroundColor;
    int             defaultForegroundColor;
}

+ (MMBackend *)sharedInstance;

- (void)setBackgroundColor:(int)color;
- (void)setForegroundColor:(int)color;
- (void)setDefaultColorsBackground:(int)bg foreground:(int)fg;

- (BOOL)checkin;
- (BOOL)openVimWindowWithRows:(int)rows columns:(int)cols;
- (void)clearAll;
- (void)clearBlockFromRow:(int)row1 column:(int)col1
                    toRow:(int)row2 column:(int)col2;
- (void)deleteLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right;
- (void)replaceString:(char*)s length:(int)len row:(int)row column:(int)col
                flags:(int)flags;
- (void)insertLinesFromRow:(int)row count:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right;
- (void)flush;
- (void)flushQueue;
- (BOOL)waitForInput:(int)milliseconds;
- (void)exit;
- (void)selectTab:(int)index;
- (void)updateTabBar;
- (BOOL)tabBarVisible;
- (void)showTabBar:(BOOL)enable;
- (void)setRows:(int)rows columns:(int)cols;
- (void)setVimWindowTitle:(char *)title;
- (char *)browseForFileInDirectory:(char *)dir title:(char *)title
                            saving:(int)saving;
- (void)updateInsertionPoint;
- (void)addMenuWithTag:(int)tag parent:(int)parentTag name:(char *)name
               atIndex:(int)index;
- (void)addMenuItemWithTag:(int)tag parent:(int)parentTag name:(char *)name
                       tip:(char *)tip icon:(char *)icon atIndex:(int)index;
- (void)removeMenuItemWithTag:(int)tag;
- (void)enableMenuItemWithTag:(int)tag state:(int)enabled;
- (void)showToolbar:(int)enable flags:(int)flags;
- (void)createScrollbarWithIdentifier:(long)ident type:(int)type;
- (void)destroyScrollbarWithIdentifier:(long)ident;
- (void)showScrollbarWithIdentifier:(long)ident state:(int)visible;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident;
- (void)setScrollbarThumbValue:(long)val size:(long)size max:(long)max
                    identifier:(long)ident;
- (BOOL)setFontWithName:(char *)name;

- (int)lookupColorWithKey:(NSString *)key;

@end


// vim: set ft=objc:
