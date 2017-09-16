//
//  MVPFindInProjectController.m
//  MacVim
//
//  Created by Doug Fales on 1/29/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "MVPFindInProjectController.h"
#import "MMVimController.h"
#import "MMAppController.h"
#import "MVPProject.h"
#import "SearchResultDataSource.h"

@interface MVPFindInProjectController()
    - (void)locateSearchTools;
@end

@implementation MVPFindInProjectController

@synthesize project;
@synthesize searchResults;
@synthesize gitLocation;
@synthesize grepLocation;

- (id) init {
	self = [super initWithWindowNibName:@"MVPFindInProject"];
    [self locateSearchTools];
	return self;
}

//i-(void)awakeFromNib {
//
//}

- (IBAction)search:(id)sender
{
	GrepTask *task = [[GrepTask alloc] initWithController:self andSearchText:[searchText stringValue] andPath:[project pathToRoot]];
	[task startGrep];
}

- (void)show {	
	[self.window makeKeyAndOrderFront:self];
	[self.window makeFirstResponder:searchText];
}

/* GrepTaskController */
- (void)appendResults:(SearchResultDataSource *)results {
	self.searchResults = results;
	[resultsOutlineView setDataSource:results];
	[resultsOutlineView reloadData];
	[resultsOutlineView expandItem:nil expandChildren:YES];
}

- (void)grepStarted {
	NSLog(@"Search started!");
}

- (void)grepFinished:(SearchResultDataSource *)results {
	NSLog(@"Grep finished!");
	self.searchResults = results;
	[resultsOutlineView setDataSource:results];
	[resultsOutlineView reloadData];
	[resultsOutlineView expandItem:nil expandChildren:YES];
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(NSTextField *)cell forTableColumn:(NSTableColumn *)tableColumn item:(SearchResult *)item {
	[cell setAttributedStringValue:[item displayName]];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(SearchResult *)item 
{
	NSString *filename = [item name];	
	MMVimController *vc = [[MMAppController sharedInstance] topmostVimController];	
	// Open split...
	//	NSString *cmd = [NSString stringWithFormat:@":vsp %@<CR>", filename];
	NSString *cmd;
	if([item lineNumber] >= 0) {
		NSInteger startPoint = [item lineNumber] - 1;
		startPoint = (startPoint < 0 ? 0 : startPoint);
		cmd = [NSString stringWithFormat:@":tabedit +%d %@ | /%@<CR>", startPoint, filename, [item searchText]];
	} else {
		cmd = [NSString stringWithFormat:@":tabedit %@ | /%@<CR>", filename, [item searchText]];
	}
	[vc addVimInput:cmd];
	[[[vc windowController] window] makeKeyAndOrderFront:self];
	return NO;
}

- (void)locateSearchTools
{
    self.gitLocation = [MVPProject pathToGit];
        
    NSMutableArray *possibleGreps = [NSMutableArray arrayWithObjects:@"/usr/bin/grep",
                                     @"/usr/bin/egrep",
                                     @"/usr/local/bin/grep",
                                     @"/usr/local/bin/egrep", nil];
    
    for(NSString *possibleGrep in possibleGreps)
    {
        if([[NSFileManager defaultManager] fileExistsAtPath:possibleGrep]) {
            self.grepLocation    = possibleGrep;
            break;
        }
        self.grepLocation = nil;
    }
}

-(NSString *)searchToolPath
{
    if([project isGitProject] && gitLocation) {
        return gitLocation;
    } else {
        return grepLocation;
    }
}

@end
