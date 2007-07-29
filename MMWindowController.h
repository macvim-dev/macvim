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


@interface MMWindowController : NSWindowController
{
    IBOutlet PSMTabBarControl *tabBarControl;
    IBOutlet NSTabView *tabView;
    IBOutlet NSTextField *statusTextField;
    IBOutlet NSBox *statusSeparator;

    MMVimController *vimController;
    BOOL vimTaskSelectedTab;
    NSTimer *statusTimer;
    MMTextView *textView;
    MMTextStorage *textStorage;
    NSMutableArray *scrollbars;
    BOOL setupDone;
}

- (id)initWithVimController:(MMVimController *)controller;
- (MMVimController *)vimController;
- (MMTextView *)textView;
- (MMTextStorage *)textStorage;
- (void)openWindowWithRows:(int)rows columns:(int)cols;
- (void)updateTabsWithData:(NSData *)data;
- (void)selectTabWithIndex:(int)idx;
- (void)setTextDimensionsWithRows:(int)rows columns:(int)cols;
- (void)setStatusText:(NSString *)text;
- (void)flashStatusText:(NSString *)text;
- (void)createScrollbarWithIdentifier:(long)ident type:(int)type;
- (void)destroyScrollbarWithIdentifier:(long)ident;
- (void)showScrollbarWithIdentifier:(long)ident state:(BOOL)visible;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident;
- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(long)ident;

- (IBAction)addNewTab:(id)sender;
- (IBAction)showTabBar:(id)sender;
- (IBAction)hideTabBar:(id)sender;

@end

// vim: set ft=objc:
