//
//  ProjectDrawerController.m
//  MacVim
//
//  Created by Doug Fales on 3/4/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import "MVPProjectDrawerController.h"
#import "MVPProjectDrawerCell.h"
#import "MMAppController.h"
#import "MMVimController.h"
#import "MMWindowController.h"
#import "MMTextViewHelper.h"
#import "MVPProject.h"

#define COLUMNID_NAME			@"Project"	// the single column name in our outline view

#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5)
static void
fsEventCallback(ConstFSEventStreamRef streamRef,
                void *clientCallBackInfo,
                size_t numEvents,
                void *eventPaths,
                const FSEventStreamEventFlags eventFlags[],
                const FSEventStreamEventId eventIds[])
{
    MVPProjectDrawerController *drawerController = (MVPProjectDrawerController *)clientCallBackInfo;    
    size_t i;
    for(i=0; i < numEvents; i++){
        [drawerController refreshPath:[(NSArray *)eventPaths objectAtIndex:i]];
    }
}
#endif

@implementation MVPProjectDrawerController
@synthesize projectDrawer;
@synthesize projectOutlineView;
@synthesize scrollView;
@synthesize project;
@synthesize rootEntry;
@synthesize lastClickedEntry;

-(void)dealloc{
    [super dealloc];
    [self stopWatchingProjectForChanges];
}

-(void)addToWindow:(MMWindow *)window {	
	NSSize contentSize = NSMakeSize(100, 100);
	projectDrawer = [[NSDrawer alloc] initWithContentSize:contentSize preferredEdge:NSMinXEdge];
	[projectDrawer setParentWindow:window];
	[projectDrawer setMinContentSize:contentSize];	
	[projectDrawer setMaxContentSize:NSMakeSize(400, 100)];	
	[projectDrawer setContentView:self.view];	
}

- (void)show {
	[projectDrawer openOnEdge:NSMinXEdge];	
} 

- (void)toggle {
    [projectDrawer toggle:self];	
}

- (void)hide {
	[projectDrawer close];
}

- (void)awakeFromNib {
	folderImage = [[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)] retain];
	[folderImage setSize:NSMakeSize(16,16)];
	
	// apply our custom ImageAndTextCell for rendering the first column's cells
	NSTableColumn *tableColumn = [projectOutlineView tableColumnWithIdentifier:COLUMNID_NAME];
	MVPProjectDrawerCell *imageAndTextCell = [[[MVPProjectDrawerCell alloc] init] autorelease];
	[imageAndTextCell setEditable:YES];
	[tableColumn setDataCell:imageAndTextCell];
    [projectOutlineView setTarget:self];
    [projectOutlineView setDoubleAction:@selector(openInNewTab:)];
}

- (void)setProject:(MVPProject *)newProject {
	if(newProject != project) {
		[newProject retain];
		[project release];
		project = newProject;
		self.rootEntry = project.rootDirEntry;
		NSTableColumn *tableColumn = [projectOutlineView tableColumnWithIdentifier:COLUMNID_NAME];
		[[tableColumn headerCell] setStringValue:[NSString stringWithFormat:@"%@ Project", project.name]];
        [projectOutlineView reloadData];
        [self startWatchingProjectForChanges];
	}
}

- (void)refreshPath:(NSString *)path
{
    ASLogErr(@"path: %@", path);
    MVPDirEntry * entry = [rootEntry refreshAtPath:path];
    [projectOutlineView reloadData];
}

- (void)startWatchingProjectForChanges
{
#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5)
    if (fsEventStream)
        return;
    if (NULL == FSEventStreamStart)
        return; // FSEvent functions are weakly linked
    
    FSEventStreamContext context = {0, (void*)self, NULL, NULL, NULL};
    NSArray *pathsToWatch = [NSArray arrayWithObject:[project pathToRoot]];
    fsEventStream = FSEventStreamCreate(NULL, &fsEventCallback, &context,
                                        (CFArrayRef)pathsToWatch, kFSEventStreamEventIdSinceNow,
                                        0.1, kFSEventStreamCreateFlagUseCFTypes);
    
    FSEventStreamScheduleWithRunLoop(fsEventStream,
                                     [[NSRunLoop currentRunLoop] getCFRunLoop],
                                     kCFRunLoopDefaultMode);
    
    FSEventStreamStart(fsEventStream);
    ASLogDebug(@"Started FS event stream to watch project dir: %@", [project pathToRoot]);
#endif
    
}

- (void)stopWatchingProjectForChanges
{
#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5)
    if (NULL == FSEventStreamStop)
        return; // FSEvent functions are weakly linked
    
    if (fsEventStream) {
        FSEventStreamStop(fsEventStream);
        FSEventStreamInvalidate(fsEventStream);
        FSEventStreamRelease(fsEventStream);
        fsEventStream = NULL;
        ASLogDebug(@"Stopped FS event stream on project dir: %@", [project pathToRoot]);
    }
#endif
}

#pragma mark Context Menu

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = [item action];
    if(action == @selector(openInNewTab:) ||
       action == @selector(openInVerticalSplit:) ||
       action == @selector(openInHorizontalSplit:) ||
       action == @selector(showInFinder:) ||
       action == @selector(renameFile:) ||
       action == @selector(deleteItem:)) {
           return YES;
    }
    MVPDirEntry * entry = [projectOutlineView itemAtRow:[projectOutlineView clickedRow]];

    if(action == @selector(viewOnGithub:)) {
        if([project isGitProject] && [entry isLeaf]){
            return YES;
        }
    }
    return NO; // for now.

}

- (void)showInFinder:(id)sender {
    MVPDirEntry * entry = [projectOutlineView itemAtRow:[projectOutlineView clickedRow]];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:[NSArray arrayWithObject:[entry url]]];
}

- (IBAction)openInNewTab:(id)sender {
    MVPDirEntry *dirEntry = (MVPDirEntry *) [projectOutlineView itemAtRow:[projectOutlineView clickedRow]];
    MMVimController *vc = [[MMAppController sharedInstance] topmostVimController];
    [vc dropFiles:[NSArray arrayWithObject:[[dirEntry url] path]] forceOpen:YES];
}

- (void)splitOpenWithVertical:(BOOL)vertical
{
    MVPDirEntry *dirEntry = (MVPDirEntry *) [projectOutlineView itemAtRow:[projectOutlineView clickedRow]];
	MMVimController *vc = [[MMAppController sharedInstance] topmostVimController];
	NSString *filePath = [[[dirEntry url] path] stringByEscapingSpecialFilenameCharacters];
	NSString *cmd = [NSString stringWithFormat:@"%@ %@<CR>", (vertical ? @":vsp" : @":sp"), filePath];
	[vc addVimInput:cmd];
}

- (MVPDirEntry *)clickedDirEntry
{
    NSInteger clickedRowIndex = [projectOutlineView clickedRow];
    if(clickedRowIndex >= 0) {
        return [projectOutlineView itemAtRow:clickedRowIndex];
    }
    return nil;
}

- (IBAction)viewLineOnGithub:(id)sender
{
   NSLog(@"N OWAYASDASDFASDFASFASDFAS asdfasdf asdfas asdf");
    
    MMVimController *vc = [[MMAppController sharedInstance] topmostVimController];
    int range = [[[[[vc windowController] vimView] textView] helper] preEditRow];
    NSLog(@"row is: %d", range);
}

- (IBAction)viewOnGithub:(id)sender
{
    self.lastClickedEntry = [projectOutlineView itemAtRow:[projectOutlineView clickedRow]];

    
    NSTask *objectHashTask = [[NSTask alloc] init];
	[objectHashTask setCurrentDirectoryPath:[project pathToRoot]];
    [objectHashTask setStandardOutput: [NSPipe pipe]];
    [objectHashTask setStandardError: [objectHashTask standardOutput]];
	
    [objectHashTask setLaunchPath:[MVPProject pathToGit]];
    
	NSArray *args = [NSArray arrayWithObjects:@"log", @"-n", @"1", @"--pretty=format:%H", [self.project pathToRoot], nil];
    [objectHashTask setArguments: args];
    [[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(launchGitBrowser:)
												 name: NSFileHandleReadCompletionNotification
											   object: [[objectHashTask standardOutput] fileHandleForReading]];
    [[[objectHashTask standardOutput] fileHandleForReading] readInBackgroundAndNotify];
    [objectHashTask launch];
    
    
    
}

- (void)launchGitBrowser:(NSNotification *)note
{
    NSData *data = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
	// Zero length means the task has completed.
    if ([data length])
    {
		NSString *blob = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        NSURL *url = [self.project githubUrlForEntry:self.lastClickedEntry atBlob:blob];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (IBAction)openInVerticalSplit:(id)sender {
    [self splitOpenWithVertical:YES];
}

- (IBAction)openInHorizontalSplit:(id)sender {
    [self splitOpenWithVertical:NO];
}

- (IBAction)renameFile:(id)sender {
    NSInteger editingRow = [projectOutlineView clickedRow];
    self.lastClickedEntry = [projectOutlineView itemAtRow:editingRow];
    [self.projectOutlineView editColumn:0
                                    row:editingRow
                              withEvent:nil
                                 select:YES];
}

- (IBAction)deleteItem:(id)sender {
    
    MVPDirEntry *clickedEntry = [self clickedDirEntry];
    if(clickedEntry == nil) {
        // Error message?
        return;
    }
    
    NSString *path = [[clickedEntry url] path];
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert addButtonWithTitle:NSLocalizedString(@"Move to Trash", @"Dialog button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Dialog button")];
    [alert setMessageText:NSLocalizedString(@"Move item to trash?",
                                            @"Move to Trash dialog, title")];
    NSString *info = nil;
    info = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to move %@ to the Trash?",
                                                        @"Move file or directory to trash, text"),
                                                        [path lastPathComponent]];
    [alert setInformativeText:info];
    if ([alert runModal] == NSAlertFirstButtonReturn){
        [[NSWorkspace sharedWorkspace] recycleURLs:[NSArray arrayWithObject:[clickedEntry url]] completionHandler:nil];
    }
    [alert release];
}


#pragma mark NSOutlineView DataSource 

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return (item == nil) ? 1 : [item childCount];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return (item == nil) ? YES : ![item isLeaf];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return (item == nil) ? rootEntry : [item childAtIndex:index];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    NSString *result = (item == nil) ? @"/" : (id)[item name];
    return result;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    
    self.lastClickedEntry = item;
    return YES;
}

- (BOOL)control:(NSControl *)control textShouldBeginEditing:(NSText *)fieldEditor{
    return YES;
}
- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor{
    NSString *newName = [fieldEditor string];
    NSString *srcPath = [[self.lastClickedEntry url] path];
    NSString *dstPath = [[[[self.lastClickedEntry url] path] stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
    NSError *error = nil;
    [[NSFileManager defaultManager] moveItemAtPath:srcPath toPath:dstPath error:&error];
    if(error){
        [[NSAlert alertWithError:error] runModal];
    }
    return YES;
}



- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
	MVPDirEntry *dirEntry = (MVPDirEntry *) [projectOutlineView itemAtRow:[projectOutlineView selectedRow]];
    if(dirEntry){
        NSLog(@"hi");
    }
//	if([dirEntry isLeaf]) {
//		//	[[MMAppController sharedInstance] application:NSApp openFiles:[NSArray arrayWithObject:[fsItem fullPath]]];
//		MMVimController *vc = [[MMAppController sharedInstance] topmostVimController];
//		[vc dropFiles:[NSArray arrayWithObject:[[dirEntry url] path]] forceOpen:YES];		
//	}
}

- (void)outlineView:(NSOutlineView *)olv willDisplayCell:(NSCell*)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	MVPDirEntry *dirEntry = (MVPDirEntry *)item;
	if ([[tableColumn identifier] isEqualToString:COLUMNID_NAME]){
		// we are displaying the single and only column
		if ([cell isKindOfClass:[MVPProjectDrawerCell class]]){
			if (dirEntry){
				if ([dirEntry isLeaf]){
					[(MVPProjectDrawerCell*)cell setImage:[[NSWorkspace sharedWorkspace] iconForFileType:[[dirEntry url] pathExtension]]];
				} else {
					[(MVPProjectDrawerCell*)cell setImage:folderImage];
				}
			}
		}
	}
}



@end
