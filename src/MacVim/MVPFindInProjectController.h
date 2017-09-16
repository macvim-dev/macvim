//
//  MVPFindInProjectController.h
//  MacVim
//
//  Created by Doug Fales on 1/29/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GrepTask.h"

@class MVPProject;


@interface MVPFindInProjectController  : NSWindowController <NSOutlineViewDelegate, GrepTaskController> {
	IBOutlet NSOutlineView *resultsOutlineView;
	IBOutlet NSScrollView *scrollView;
	IBOutlet NSTextField *searchText;
	IBOutlet NSButton *searchButton;
	IBOutlet NSProgressIndicator *searchingIndicator;
	MVPProject *project;
	SearchResultDataSource *searchResults;
    NSString        *gitLocation;
    NSString        *grepLocation;
}

@property (nonatomic,retain) MVPProject *project;
@property (nonatomic,retain) SearchResultDataSource *searchResults;
@property (nonatomic,retain) NSString *gitLocation;
@property (nonatomic,retain) NSString *grepLocation;

- (void)show;
- (IBAction)search:(id)sender;
- (NSString *)searchToolPath;

@end
