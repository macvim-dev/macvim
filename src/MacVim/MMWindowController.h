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



@class MMWindow;
@class MMFullscreenWindow;
@class MMVimController;
@class MMVimView;

@interface MMWindowController : NSWindowController {
    MMVimController     *vimController;
    MMVimView           *vimView;
    BOOL                setupDone;
    BOOL                shouldResizeVimView;
    int                 shouldUpdateToolbar;
    BOOL                keepOnScreen;
    BOOL                fullscreenEnabled;
    NSString            *windowAutosaveKey;
    MMFullscreenWindow  *fullscreenWindow;
    MMWindow            *decoratedWindow;
    NSString            *lastSetTitle;
}

- (id)initWithVimController:(MMVimController *)controller;
- (MMVimController *)vimController;
- (MMVimView *)vimView;
- (NSString *)windowAutosaveKey;
- (void)setWindowAutosaveKey:(NSString *)key;
- (void)cleanup;
- (void)openWindow;
- (void)showWindow;
- (void)updateTabsWithData:(NSData *)data;
- (void)selectTabWithIndex:(int)idx;
- (void)setTextDimensionsWithRows:(int)rows columns:(int)cols isLive:(BOOL)live
                          isReply:(BOOL)reply;
- (void)setTitle:(NSString *)title;
- (void)setDocumentFilename:(NSString *)filename;
- (void)setToolbar:(NSToolbar *)toolbar;
- (void)createScrollbarWithIdentifier:(long)ident type:(int)type;
- (BOOL)destroyScrollbarWithIdentifier:(long)ident;
- (BOOL)showScrollbarWithIdentifier:(long)ident state:(BOOL)visible;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident;
- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(long)ident;
- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore;
- (void)setFont:(NSFont *)font;
- (void)setWideFont:(NSFont *)font;
- (void)processCommandQueueDidFinish;
- (void)showTabBar:(BOOL)on;
- (void)showToolbar:(BOOL)on size:(int)size mode:(int)mode;
- (void)setMouseShape:(int)shape;
- (void)adjustLinespace:(int)linespace;
- (void)liveResizeWillStart;
- (void)liveResizeDidEnd;

- (void)enterFullscreen:(int)fuoptions backgroundColor:(NSColor *)back;
- (void)leaveFullscreen;
- (void)setFullscreenBackgroundColor:(NSColor *)back;

- (void)setBuffersModified:(BOOL)mod;

- (IBAction)addNewTab:(id)sender;
- (IBAction)toggleToolbar:(id)sender;
- (IBAction)performClose:(id)sender;
- (IBAction)findNext:(id)sender;
- (IBAction)findPrevious:(id)sender;
- (IBAction)vimMenuItemAction:(id)sender;
- (IBAction)vimToolbarItemAction:(id)sender;
- (IBAction)fontSizeUp:(id)sender;
- (IBAction)fontSizeDown:(id)sender;
- (IBAction)findAndReplace:(id)sender;

@end
