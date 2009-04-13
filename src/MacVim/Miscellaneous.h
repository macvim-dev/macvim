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
#import "MacVim.h"

#define MM_LOG_DEALLOCATIONS 0


#if MM_LOG_DEALLOCATIONS
# define LOG_DEALLOC NSLog(@"%s %@", _cmd, [self className]);
#else
# define LOG_DEALLOC
#endif


// NSUserDefaults keys
extern NSString *MMTabMinWidthKey;
extern NSString *MMTabMaxWidthKey;
extern NSString *MMTabOptimumWidthKey;
extern NSString *MMShowAddTabButtonKey;
extern NSString *MMTextInsetLeftKey;
extern NSString *MMTextInsetRightKey;
extern NSString *MMTextInsetTopKey;
extern NSString *MMTextInsetBottomKey;
extern NSString *MMTypesetterKey;
extern NSString *MMCellWidthMultiplierKey;
extern NSString *MMBaselineOffsetKey;
extern NSString *MMTranslateCtrlClickKey;
extern NSString *MMTopLeftPointKey;
extern NSString *MMOpenInCurrentWindowKey;
extern NSString *MMNoFontSubstitutionKey;
extern NSString *MMLoginShellKey;
extern NSString *MMAtsuiRendererKey;
extern NSString *MMUntitledWindowKey;
extern NSString *MMTexturedWindowKey;
extern NSString *MMZoomBothKey;
extern NSString *MMCurrentPreferencePaneKey;
extern NSString *MMLoginShellCommandKey;
extern NSString *MMLoginShellArgumentKey;
extern NSString *MMDialogsTrackPwdKey;
#ifdef MM_ENABLE_PLUGINS
extern NSString *MMShowLeftPlugInContainerKey;
#endif
extern NSString *MMOpenLayoutKey;
extern NSString *MMVerticalSplitKey;
extern NSString *MMPreloadCacheSizeKey;
extern NSString *MMLastWindowClosedBehaviorKey;
extern NSString *MMLoadDefaultFontKey;


// Enum for MMUntitledWindowKey
enum {
    MMUntitledWindowNever = 0,
    MMUntitledWindowOnOpen = 1,
    MMUntitledWindowOnReopen = 2,
    MMUntitledWindowAlways = 3
};

// Enum for MMOpenLayoutKey (first 4 must match WIN_* defines in main.c)
enum {
    MMLayoutArglist = 0,
    MMLayoutHorizontalSplit = 1,
    MMLayoutVerticalSplit = 2,
    MMLayoutTabs = 3,
    MMLayoutWindows = 4,
};

// Enum for MMLastWindowClosedBehaviorKey
enum {
    MMDoNothingWhenLastWindowClosed = 0,
    MMHideWhenLastWindowClosed = 1,
    MMTerminateWhenLastWindowClosed = 2,
};




@interface NSIndexSet (MMExtras)
+ (id)indexSetWithVimList:(NSString *)list;
@end


@interface NSDocumentController (MMExtras)
- (void)noteNewRecentFilePath:(NSString *)path;
- (void)noteNewRecentFilePaths:(NSArray *)paths;
@end


@interface NSSavePanel (MMExtras)
- (void)hiddenFilesButtonToggled:(id)sender;
- (void)setShowsHiddenFiles:(BOOL)show;
@end


@interface NSMenu (MMExtras)
- (int)indexOfItemWithAction:(SEL)action;
- (NSMenuItem *)itemWithAction:(SEL)action;
- (NSMenu *)findMenuContainingItemWithAction:(SEL)action;
- (NSMenu *)findWindowsMenu;
- (NSMenu *)findApplicationMenu;
- (NSMenu *)findServicesMenu;
- (NSMenu *)findFileMenu;
@end


@interface NSToolbar (MMExtras)
- (int)indexOfItemWithItemIdentifier:(NSString *)identifier;
- (NSToolbarItem *)itemAtIndex:(int)idx;
- (NSToolbarItem *)itemWithItemIdentifier:(NSString *)identifier;
@end


@interface NSTabView (MMExtras)
- (void)removeAllTabViewItems;
@end


@interface NSNumber (MMExtras)
- (int)tag;
@end



// Create a view with a "show hidden files" button to be used as accessory for
// open/save panels.  This function assumes ownership of the view so do not
// release it.
NSView *showHiddenFilesView();

