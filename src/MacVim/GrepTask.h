//
//  GrepTask.h
//  MacVim
//
//  Created by Doug Fales on 1/29/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SearchResultDataSource;

@protocol GrepTaskController
- (void)appendResults:(SearchResultDataSource *)results;
- (void)grepStarted;
- (void)grepFinished:(SearchResultDataSource *)results;;
@end

@interface GrepTask : NSObject {
    NSTask          *grepTask;
    id              <GrepTaskController>controller;
    NSString        *searchText;
	NSString		*searchPath;
	SearchResultDataSource *searchResults;
	NSString		*partialLine;
}

@property(nonatomic, retain) SearchResultDataSource *searchResults;

- (id)initWithController:(id <GrepTaskController>)controller andSearchText:(NSString *)searchText andPath:(NSString *)path;
- (void) startGrep;
- (void) stopGrep;

@end
