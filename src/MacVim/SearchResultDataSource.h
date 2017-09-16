//
//  SearchResultDataSource.h
//  MacVim
//
//  Created by Doug Fales on 1/29/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SearchResult;

@interface SearchResultDataSource : NSObject <NSOutlineViewDataSource> {
	NSMutableArray *results;
}
@property(nonatomic,retain) NSMutableArray *results;

- (void)addResult:(NSString *)filename atLine:(NSInteger)lineNumber withMatch:(NSString *)matchLine andSearchText:(NSString *) searchText;

@end
