//
//  SearchResult.m
//  MacVim
//
//  Created by Doug Fales on 1/29/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "SearchResult.h"


@implementation SearchResult

- (id)initWithFile:(NSString *)file andLine:(NSInteger)lineNo andMatch:(NSString *)match andSearchText:(NSString *)search
{
	if((self = [super init])) {
		self.children = [NSMutableArray new];
		self.name = file;
		self.matchLine = match;
		self.lineNumber = lineNo;
		NSRange lastFileSeparator = [self.name rangeOfString:@"/" options:NSBackwardsSearch];
		if(lastFileSeparator.location == NSNotFound) {
			self.basename = self.name;
		} else {
			self.basename = [self.name substringFromIndex:lastFileSeparator.location + 1];
		}

		self.searchText = search;
		
	}	
	return self;
}

- (void)dealloc 
{
	[children release];
	[name release];
	[matchLine release];
	[searchText release];
	[super dealloc];
}

- (NSAttributedString *)displayName
{
	if([self.children count] == 0) {
		NSString *fullString = [NSString stringWithFormat:@"\t%d: %@", self.lineNumber, self.matchLine];
		NSRange searchTextLocation = [fullString rangeOfString:self.searchText];
		NSDictionary *matchLineAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor grayColor], NSForegroundColorAttributeName, [NSFont systemFontOfSize:11], NSFontAttributeName, nil];
		NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:fullString attributes:matchLineAttributes]; 
		[str addAttribute:NSForegroundColorAttributeName value:[NSColor blackColor] range:searchTextLocation];	
		[str addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:11] range:searchTextLocation];
		return str;
	} else {
		return [NSString stringWithFormat:@"%@ -- %@", self.basename, self.name];
	}
}

@synthesize children;
@synthesize name;
@synthesize basename;
@synthesize matchLine;
@synthesize lineNumber;
@synthesize	searchText;

@end
