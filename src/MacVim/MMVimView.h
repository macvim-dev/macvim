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
@class MMScroller;
@class MMVimController;


@interface MMVimView : NSView {
    PSMTabBarControl    *tabBarControl;
    NSTabView           *tabView;

    MMVimController     *vimController;
    BOOL                vimTaskSelectedTab;
    MMTextView          *textView;
    MMTextStorage       *textStorage;
    NSMutableArray      *scrollbars;

    // This is temporary to make the refactoring easier    
    BOOL                shouldUpdateWindowSize;
}

- (MMVimView *)initWithFrame:(NSRect)frame vimController:(MMVimController *) c;

- (MMTextView *)textView;
- (MMTextStorage *)textStorage;
- (NSMutableArray *)scrollbars;
- (BOOL)inLiveResize;
- (void)cleanup;


- (PSMTabBarControl *)tabBarControl;
- (NSTabView *)tabView;
- (IBAction)addNewTab:(id)sender;
- (void)updateTabsWithData:(NSData *)data;
- (void)selectTabWithIndex:(int)idx;
- (int)representedIndexOfTabViewItem:(NSTabViewItem *)tvi;
- (NSTabViewItem *)addNewTabViewItem;

- (BOOL)bottomScrollbarVisible;
- (BOOL)leftScrollbarVisible;
- (BOOL)rightScrollbarVisible;
- (void)placeScrollbars;
- (void)createScrollbarWithIdentifier:(long)ident type:(int)type;
- (void)destroyScrollbarWithIdentifier:(long)ident;
- (void)showScrollbarWithIdentifier:(long)ident state:(BOOL)visible;
- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(long)ident;
- (MMScroller *)scrollbarForIdentifier:(long)ident index:(unsigned *)idx;

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore;

- (BOOL)shouldUpdateWindowSize;
- (NSRect)textViewRectForContentSize:(NSSize)contentSize;
- (void)setShouldUpdateWindowSize:(BOOL)b;


- (NSSize)contentSizeForTextStorageSize:(NSSize)textViewSize;
- (NSSize)textStorageSizeForTextViewSize:(NSSize)textViewSize;
@end

// TODO:  Move!
@interface MMScroller : NSScroller {
    long identifier;
    int type;
    NSRange range;
}
- (id)initWithIdentifier:(long)ident type:(int)type;
- (long)identifier;
- (int)type;
- (NSRange)range;
- (void)setRange:(NSRange)newRange;
@end

