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
@class SUUpdater;
#endif


@interface MMAppController : NSObject <MMAppProtocol, NSUserInterfaceItemSearching> {
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
    
#if !DISABLE_SPARKLE
    SUUpdater           *updater;
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

- (void)refreshAllAppearances;
- (void)refreshAllFonts;

- (IBAction)newWindow:(id)sender;
- (IBAction)newWindowAndActivate:(id)sender;
- (IBAction)fileOpen:(id)sender;
- (IBAction)selectNextWindow:(id)sender;
- (IBAction)selectPreviousWindow:(id)sender;
- (IBAction)orderFrontPreferencePanel:(id)sender;
- (IBAction)openWebsite:(id)sender;
- (IBAction)showVimHelp:(id)sender withCmd:(NSString *)cmd;
- (IBAction)showVimHelp:(id)sender;
- (IBAction)checkForUpdates:(id)sender;
- (IBAction)zoomAll:(id)sender;
- (IBAction)stayInFront:(id)sender;
- (IBAction)stayInBack:(id)sender;
- (IBAction)stayLevelNormal:(id)sender;

- (NSArray<NSString *> *)localizedTitlesForItem:(id)item;
- (void)searchForItemsWithSearchString:(NSString *)searchString
                           resultLimit:(NSInteger)resultLimit
                    matchedItemHandler:(void (^)(NSArray *items))handleMatchedItems;
- (void)performActionForItem:(id)item;

@end
