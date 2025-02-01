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
    /// The tab that has been requested to be closed and waiting on Vim to respond
    NSInteger           pendingCloseTabID;
    MMTabline           *tabline;
    MMVimController     *vimController;
    MMTextView          *textView;
    NSMutableArray      *scrollbars;
}

@property BOOL pendingPlaceScrollbars;
@property BOOL pendingLiveResize; ///< An ongoing live resizing message to Vim is active
@property BOOL pendingLiveResizeQueued; ///< A new size has been queued while an ongoing live resize is already active

- (MMVimView *)initWithFrame:(NSRect)frame vimController:(MMVimController *)c;

- (MMTextView *)textView;
- (void)cleanup;

- (NSSize)desiredSize;
- (NSSize)minSize;
- (NSSize)constrainRows:(int *)r columns:(int *)c toSize:(NSSize)size;
- (void)setDesiredRows:(int)r columns:(int)c;

- (MMTabline *)tabline;
- (IBAction)addNewTab:(id)sender;
- (IBAction)scrollToCurrentTab:(id)sender;
- (IBAction)scrollBackwardOneTab:(id)sender;
- (IBAction)scrollForwardOneTab:(id)sender;
- (void)showTabline:(BOOL)on;
- (void)updateTabsWithData:(NSData *)data;
- (void)refreshTabProperties;

- (void)createScrollbarWithIdentifier:(int32_t)ident type:(int)type;
- (BOOL)destroyScrollbarWithIdentifier:(int32_t)ident;
- (BOOL)showScrollbarWithIdentifier:(int32_t)ident state:(BOOL)visible;
- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(int32_t)ident;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(int32_t)ident;
- (void)finishPlaceScrollbars;

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore;
- (void)setTablineColorsTabBg:(NSColor *)tabBg tabFg:(NSColor *)tabFg
                       fillBg:(NSColor *)fillBg fillFg:(NSColor *)fillFg
                        selBg:(NSColor *)selBg selFg:(NSColor *)selFg;

- (void)viewWillStartLiveResize;
- (void)viewDidEndLiveResize;
- (void)setFrameSize:(NSSize)size;
- (void)setFrameSizeKeepGUISize:(NSSize)size;
- (void)setFrame:(NSRect)frame;

@end
