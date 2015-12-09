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


// TODO: Remove this when the inline IM code has been tested
#define INCLUDE_OLD_IM_CODE

// Use Core Text instead of ATSUI when compiling on 10.5+.
// Note: Core Text was introduced with 10.5, ATSUI was deprecated on 10.6.
#define MM_ENABLE_ATSUI (MAC_OS_X_VERSION_MIN_REQUIRED<MAC_OS_X_VERSION_10_5)


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
extern NSString *MMNoTitleBarWindowKey;
extern NSString *MMLoginShellKey;
extern NSString *MMUntitledWindowKey;
extern NSString *MMTexturedWindowKey;
extern NSString *MMZoomBothKey;
extern NSString *MMCurrentPreferencePaneKey;
extern NSString *MMLoginShellCommandKey;
extern NSString *MMLoginShellArgumentKey;
extern NSString *MMDialogsTrackPwdKey;
extern NSString *MMOpenLayoutKey;
extern NSString *MMVerticalSplitKey;
extern NSString *MMPreloadCacheSizeKey;
extern NSString *MMLastWindowClosedBehaviorKey;
#ifdef INCLUDE_OLD_IM_CODE
extern NSString *MMUseInlineImKey;
#endif // INCLUDE_OLD_IM_CODE
extern NSString *MMSuppressTerminationAlertKey;
extern NSString *MMNativeFullScreenKey;


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



enum {
    // These values are chosen so that the min text view size is not too small
    // with the default font (they only affect resizing with the mouse, you can
    // still use e.g. ":set lines=2" to go below these values).
    MMMinRows = 4,
    MMMinColumns = 30
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
#if (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_6)
// This method is a part of a public API as of Mac OS X 10.6.  Only use this
// hack for earlier versions of Mac OS X.
- (void)setShowsHiddenFiles:(BOOL)show;
#endif
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
- (NSUInteger)indexOfItemWithItemIdentifier:(NSString *)identifier;
- (NSToolbarItem *)itemAtIndex:(NSUInteger)idx;
- (NSToolbarItem *)itemWithItemIdentifier:(NSString *)identifier;
@end


@interface NSTabView (MMExtras)
- (void)removeAllTabViewItems;
@end


@interface NSNumber (MMExtras)
// HACK to allow font size to be changed via menu (bound to Cmd+/Cmd-)
- (NSInteger)tag;
@end



// Create a view with a "show hidden files" button to be used as accessory for
// open/save panels.  This function assumes ownership of the view so do not
// release it.
NSView *showHiddenFilesView();


// Convert filenames (which are in a variant of decomposed form, NFD, on HFS+)
// to normalization form C (NFC).  (This is necessary because Vim does not
// automatically compose NFD.)  For more information see:
//     http://developer.apple.com/technotes/tn/tn1150.html
//     http://developer.apple.com/technotes/tn/tn1150table.html
//     http://developer.apple.com/qa/qa2001/qa1235.html
//     http://www.unicode.org/reports/tr15/
NSString *normalizeFilename(NSString *filename);
NSArray *normalizeFilenames(NSArray *filenames);
