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



@class PSMTabBarControl;
@class MMTextView;
@class MMTextStorage;
@class MMVimController;


@interface MMWindowController : NSWindowController {
    PSMTabBarControl    *tabBarControl;
    NSTabView           *tabView;
    NSBox               *tablineSeparator;

    MMVimController     *vimController;
    BOOL                vimTaskSelectedTab;
    MMTextView          *textView;
    MMTextStorage       *textStorage;
    NSMutableArray      *scrollbars;
    BOOL                setupDone;
    BOOL                shouldUpdateWindowSize;
    NSString            *windowAutosaveKey;
}

- (id)initWithVimController:(MMVimController *)controller;
- (MMVimController *)vimController;
- (MMTextView *)textView;
- (MMTextStorage *)textStorage;
- (NSString *)windowAutosaveKey;
- (void)setWindowAutosaveKey:(NSString *)key;
- (void)cleanup;
- (void)openWindow;
- (void)updateTabsWithData:(NSData *)data;
- (void)selectTabWithIndex:(int)idx;
- (void)setTextDimensionsWithRows:(int)rows columns:(int)cols;
- (void)createScrollbarWithIdentifier:(long)ident type:(int)type;
- (void)destroyScrollbarWithIdentifier:(long)ident;
- (void)showScrollbarWithIdentifier:(long)ident state:(BOOL)visible;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident;
- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(long)ident;
- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore;
- (void)setFont:(NSFont *)font;
- (void)processCommandQueueDidFinish;
- (void)popupMenu:(NSMenu *)menu atRow:(int)row column:(int)col;
- (void)showTabBar:(BOOL)on;
- (void)showToolbar:(BOOL)on size:(int)size mode:(int)mode;
- (void)setMouseShape:(int)shape;
- (void)adjustLinespace:(int)linespace;

- (IBAction)addNewTab:(id)sender;
- (IBAction)toggleToolbar:(id)sender;

@end

// vim: set ft=objc:
