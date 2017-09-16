//
//  ProjectDrawerController.h
//  MacVim
//
//  Created by Doug Fales on 3/4/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import <Cocoa/Cocoa.h>

#import "MMWindow.h"

@class MVPProject;
@class MVPDirEntry;

@interface MVPProjectDrawerController : NSViewController <NSOutlineViewDelegate, NSOutlineViewDataSource, NSMenuDelegate> {
	IBOutlet NSOutlineView *projectOutlineView;
	IBOutlet NSScrollView *scrollView;
	NSDrawer *projectDrawer;
	NSImage *folderImage;
	MVPProject *project;
	MVPDirEntry *rootEntry;
    MVPDirEntry *lastClickedEntry;
#if (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
    FSEventStreamRef    fsEventStream;
#endif
}
@property (nonatomic,retain) NSDrawer *projectDrawer;
@property (nonatomic,retain) NSOutlineView *projectOutlineView;
@property (nonatomic,retain) NSScrollView *scrollView;
@property (nonatomic,retain) MVPProject *project;
@property (nonatomic,retain) MVPDirEntry *rootEntry;
@property (nonatomic,retain) MVPDirEntry *lastClickedEntry;

-(void)addToWindow:(MMWindow *)window;
-(void)show;
-(void)hide;
- (void)toggle;
- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
- (void)refreshPath:(NSString *)path;
- (void)startWatchingProjectForChanges;
- (void)stopWatchingProjectForChanges;
#pragma mark Context Menu
- (MVPDirEntry *)clickedDirEntry;
- (IBAction)showInFinder:(id)sender;
- (IBAction)openInNewTab:(id)sender;
- (IBAction)openInVerticalSplit:(id)sender;
- (IBAction)openInHorizontalSplit:(id)sender;
- (IBAction)viewOnGithub:(id)sender;
- (IBAction)viewLineOnGithub:(id)sender;
- (IBAction)renameFile:(id)sender;
@end

