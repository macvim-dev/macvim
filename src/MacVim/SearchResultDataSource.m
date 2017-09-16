//
//  SearchResultDataSource.m
//  MacVim
//
//  Created by Doug Fales on 1/29/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "SearchResultDataSource.h"
#import "SearchResult.h"

@implementation SearchResultDataSource
@synthesize results;


- (id)init 
{
	if((self = [super init])) 
	{
		results = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc 
{
	[results release];
	[super dealloc];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(SearchResult *)item {
	if(item == nil) {
		return [results objectAtIndex:index];	
	}
	return [item.children objectAtIndex:index];
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(SearchResult *)item 
{
	if (item == nil) {
		return YES;	
	}
	return [item.children count] > 0;
	
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(SearchResult *)item {
	if (item == nil) {
		return [results count];
	}
	return [item.children count];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(SearchResult *)item
{
	return [item displayName];
}

- (void)addResult:(NSString *)filename atLine:(NSInteger)lineNumber withMatch:(NSString *)matchLine andSearchText:(NSString *)searchText {
	SearchResult *newResult = [[SearchResult alloc] initWithFile:filename andLine:lineNumber andMatch:matchLine andSearchText:searchText];
	if ([results count] >= 1) {
		SearchResult *previousResult = [results	objectAtIndex:[results count] - 1];
		if([previousResult.name isEqualToString:newResult.name]) {
			[previousResult.children addObject:newResult];
			return;
		}
	} 
	[results addObject:newResult];
	SearchResult *newChild = [[SearchResult alloc] initWithFile:filename andLine:lineNumber andMatch:matchLine andSearchText:searchText];
	[newResult.children addObject:newChild];
	
}



@end
