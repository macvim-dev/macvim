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


@class MMWindowController;
@class MMVimController;

#if !DISABLE_SPARKLE
#if USE_SPARKLE_1
@class SUUpdater;
#else
@class SPUStandardUpdaterController;
@class MMSparkle2Delegate;
#endif
#endif


@interface MMAppController : NSObject <
    MMAppProtocol,
    NSUserInterfaceItemSearching
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
    , NSMenuItemValidation
#endif
> {
    enum NewWindowMode {
        NewWindowNormal = 0,
        NewWindowClean,
        NewWindowCleanNoDefaults,
    };

    NSConnection        *connection;
    NSMutableArray      *vimControllers;
    NSString            *openSelectionString;
    NSMutableDictionary *pidArguments;

    NSMenu              *defaultMainMenu;
    NSMenu              *currentMainMenu;
    BOOL                mainMenuDirty;

    NSMenuItem          *appMenuItemTemplate;
    NSMenuItem          *recentFilesMenuItem;
    NSMutableArray      *cachedVimControllers;
    int                 preloadPid;
    BOOL                shouldActivateWhenNextWindowOpens;
    int                 numChildProcesses;
    NSMutableDictionary *inputQueues;
    int                 processingFlag;

    BOOL                hasShownWindowBefore;
    BOOL                shouldShowWhatsNewPage;
    
#if !DISABLE_SPARKLE
#if USE_SPARKLE_1
    SUUpdater           *updater;
#else
    SPUStandardUpdaterController *updater;
    MMSparkle2Delegate  *sparkle2delegate; ///< Sparkle 2 delegate which allows us to customize the updater's behavior.
#endif
#endif

    FSEventStreamRef    fsEventStream;
}

+ (MMAppController *)sharedInstance;
- (NSMenu *)defaultMainMenu;
- (NSMenuItem *)appMenuItemTemplate;
- (MMVimController *)keyVimController;
- (void)removeVimController:(id)controller;
- (void)windowControllerWillOpen:(MMWindowController *)windowController;
- (void)setMainMenu:(NSMenu *)mainMenu;
- (void)markMainMenuDirty:(NSMenu *)mainMenu;
- (void)refreshMainMenu;
- (NSArray *)filterOpenFiles:(NSArray *)filenames;
- (BOOL)openFiles:(NSArray *)filenames withArguments:(NSDictionary *)args;

// Refresh functions are used by preference pane to push through settings changes
- (void)refreshAllAppearances;
- (void)refreshAllTabProperties;
- (void)refreshAllFonts;
- (void)refreshAllResizeConstraints;
- (void)refreshAllTextViews;
- (void)refreshAllFullScreenPresentationOptions;

- (void)openNewWindow:(enum NewWindowMode)mode activate:(BOOL)activate extraArgs:(NSArray *)args;
- (void)openNewWindow:(enum NewWindowMode)mode activate:(BOOL)activate;

//
// NSMenuItemValidation
//
- (BOOL)validateMenuItem:(NSMenuItem *)item;

//
// Actions exposed to Vim
//
- (IBAction)newWindow:(id)sender;
- (IBAction)newWindowClean:(id)sender;
- (IBAction)newWindowCleanNoDefaults:(id)sender;
- (IBAction)newWindowAndActivate:(id)sender;
- (IBAction)newWindowCleanAndActivate:(id)sender;
- (IBAction)newWindowCleanNoDefaultsAndActivate:(id)sender;
- (IBAction)fileOpen:(id)sender;
- (IBAction)selectNextWindow:(id)sender;
- (IBAction)selectPreviousWindow:(id)sender;
- (IBAction)orderFrontPreferencePanel:(id)sender;
- (IBAction)openWebsite:(id)sender;
- (IBAction)showWhatsNew:(id)sender;
- (IBAction)showVimHelp:(id)sender withCmd:(NSString *)cmd;
- (IBAction)showVimHelp:(id)sender;
- (IBAction)checkForUpdates:(id)sender;
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_13
- (IBAction)zoomAll:(id)sender;
#endif
- (IBAction)stayInFront:(id)sender;
- (IBAction)stayInBack:(id)sender;
- (IBAction)stayLevelNormal:(id)sender;

//
// NSUserInterfaceItemSearching
//
- (NSArray<NSString *> *)localizedTitlesForItem:(id)item;
- (void)searchForItemsWithSearchString:(NSString *)searchString
                           resultLimit:(NSInteger)resultLimit
                    matchedItemHandler:(void (^)(NSArray *items))handleMatchedItems;
- (void)performActionForItem:(id)item;

@end
