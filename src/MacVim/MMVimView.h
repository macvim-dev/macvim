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



@class MMTabline;
@class MMTab;
@class MMTextView;
@class MMScroller;
@class MMVimController;


@interface MMVimView : NSView {
    MMTabline           *tabline;
    MMTab               *tabToClose;
    MMVimController     *vimController;
    MMTextView          *textView;
    NSMutableArray      *scrollbars;
}

@property BOOL pendingPlaceScrollbars;
@property BOOL pendingLiveResize;

- (MMVimView *)initWithFrame:(NSRect)frame vimController:(MMVimController *)c;

- (MMTextView *)textView;
- (void)cleanup;

- (NSSize)desiredSize;
- (NSSize)minSize;
- (NSSize)constrainRows:(int *)r columns:(int *)c toSize:(NSSize)size;
- (void)setDesiredRows:(int)r columns:(int)c;

- (MMTabline *)tabline;
- (IBAction)addNewTab:(id)sender;
- (void)updateTabsWithData:(NSData *)data;
- (void)selectTabWithIndex:(int)idx;
- (MMTab *)addNewTab;

- (void)createScrollbarWithIdentifier:(int32_t)ident type:(int)type;
- (BOOL)destroyScrollbarWithIdentifier:(int32_t)ident;
- (BOOL)showScrollbarWithIdentifier:(int32_t)ident state:(BOOL)visible;
- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(int32_t)ident;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(int32_t)ident;
- (void)finishPlaceScrollbars;

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore;

- (void)viewWillStartLiveResize;
- (void)viewDidEndLiveResize;
- (void)setFrameSize:(NSSize)size;
- (void)setFrameSizeKeepGUISize:(NSSize)size;
- (void)setFrame:(NSRect)frame;

@end
