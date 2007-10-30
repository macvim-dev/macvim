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

    // This is temporary to make the refactoring easier  (XXX)
    BOOL                shouldUpdateWindowSize;
}

- (MMVimView *)initWithFrame:(NSRect)frame vimController:(MMVimController *) c;

- (MMTextView *)textView;
- (MMTextStorage *)textStorage;
- (NSMutableArray *)scrollbars;
- (BOOL)inLiveResize;
- (void)cleanup;

- (NSSize)desiredSizeForActualRowsAndColumns;
- (NSSize)getDesiredRows:(int *)r columns:(int *)c forSize:(NSSize)size;
- (void)getActualRows:(int *)r columns:(int *)c;
- (void)setActualRows:(int)r columns:(int)c;

- (PSMTabBarControl *)tabBarControl;
- (IBAction)addNewTab:(id)sender;
- (void)updateTabsWithData:(NSData *)data;
- (void)selectTabWithIndex:(int)idx;
- (NSTabViewItem *)addNewTabViewItem;

- (void)createScrollbarWithIdentifier:(long)ident type:(int)type;
- (void)destroyScrollbarWithIdentifier:(long)ident;
- (void)showScrollbarWithIdentifier:(long)ident state:(BOOL)visible;
- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(long)ident;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident;

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore;

- (BOOL)shouldUpdateWindowSize;
- (NSRect)textViewRectForContentSize:(NSSize)contentSize;
- (void)setShouldUpdateWindowSize:(BOOL)b;

- (void)placeViews;  // XXX: this should probably not be public

@end
