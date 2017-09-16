//
//  FastFindController.h
//  MacVim
//
//  Created by Doug Fales on 3/28/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import <Cocoa/Cocoa.h>

@class MVPProject;

@interface MVPFastFindController : NSWindowController<NSTableViewDataSource, NSTableViewDelegate, NSMetadataQueryDelegate>{
	MVPProject *project;
	IBOutlet NSSearchField *searchField;
	IBOutlet NSTableView *tableView;
    NSMetadataQuery *query;
}

- (NSString *)searchString;
- (void)show;

@property(nonatomic,retain) MVPProject* project;
@property(nonatomic, retain) NSMetadataQuery *query;

@end
