//
//  SearchResult.h
//  MacVim
//
//  Created by Doug Fales on 1/29/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface SearchResult : NSObject {
	NSMutableArray *children;
	NSString *name;
	NSString *matchLine;
	NSString *basename;
	NSString *searchText;
	NSInteger lineNumber;

}
@property(nonatomic,retain) NSMutableArray *children;
@property(nonatomic,retain) NSString *name;
@property(nonatomic,retain) NSString *basename;
@property(nonatomic,retain) NSString *matchLine;
@property(nonatomic,retain) NSString *searchText;
@property(nonatomic,assign) NSInteger lineNumber;


- (id)initWithFile:(NSString *)file andLine:(NSInteger)lineNo andMatch:(NSString *)match andSearchText:(NSString *)searchText;
- (NSAttributedString *)displayName;

@end
