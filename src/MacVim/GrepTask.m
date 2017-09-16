//  GrepTask.m
//  MacVim
//
//  Created by Doug Fales on 1/29/11.
//

#import "GrepTask.h"
#import "SearchResultDataSource.h"

@implementation GrepTask

@synthesize searchResults;

- (id)initWithController:(id <GrepTaskController>)cont andSearchText:(NSString *)text andPath:(NSString *)path
{
    self = [super init];
    controller = cont;
    searchText = [text retain];
	searchPath = [path retain];
    return self;
}

- (void)dealloc
{
    [self stopGrep];
    [searchText release];
	[searchPath release];
    [grepTask release];
	[searchResults release];
    [super dealloc];
}

- (NSArray *)makeArgumentArray {
	return [NSArray arrayWithObjects:@"grep", @"-n", searchText, searchPath, nil];
}

- (void)clearPartialLine {
	[partialLine release]; partialLine = nil;
}

- (void) startGrep
{
	[self clearPartialLine];
	self.searchResults = [[SearchResultDataSource alloc] init];
    [controller grepStarted];	
    grepTask = [[NSTask alloc] init];
	[grepTask setCurrentDirectoryPath:searchPath];
	// Setup a pipe.
    [grepTask setStandardOutput: [NSPipe pipe]];
    [grepTask setStandardError: [grepTask standardOutput]];
	
	// Set the path and the arguments.
    [grepTask setLaunchPath: [controller searchToolPath]];
	NSArray *args = [self makeArgumentArray];
    [grepTask setArguments: args];
	
	// Setup our fetchResults callback for when data is available.
    [[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(fetchResults:) 
												 name: NSFileHandleReadCompletionNotification 
											   object: [[grepTask standardOutput] fileHandleForReading]];
    [[[grepTask standardOutput] fileHandleForReading] readInBackgroundAndNotify];	
    [grepTask launch];    
}

- (void) stopGrep
{
    NSData *data;
	// Stop observing.
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object: [[grepTask standardOutput] fileHandleForReading]];    
	// Kill the task.
    [grepTask terminate];
	
	// Drain the pipe.
	while((data = [[[grepTask standardOutput] fileHandleForReading] availableData]) && [data length])
	{
		[controller appendResults: [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]];
	}
	
	[controller grepFinished:searchResults];
	controller = nil;
}

- (NSString *)prependWithPartialLine:(NSString *)partialRead {
	if(partialLine) {
		return [NSString stringWithFormat:@"%@%@", partialLine, partialRead];
	}
	return partialRead;
}

- (NSString *)saveTrailingCharacters:(NSString *)partialRead{
	int lastChar = [partialRead length] - 1;
	if (lastChar >= 0 && [partialRead characterAtIndex:lastChar] == '\n') {
		[self clearPartialLine];
		return partialRead;
	}
	int i;
	for(i = lastChar; i >= 0; i--) {
		if([partialRead characterAtIndex:i] == '\n') {
			partialLine = [[partialRead substringWithRange:NSMakeRange(i+1, lastChar - i)] retain];
			NSString *res = [partialRead substringWithRange:NSMakeRange(0, i+1)];
			if ([res characterAtIndex:[res length]-1] != '\n') {
				NSLog(@"oh no");
			}
			return res;
		}
	}
	partialLine = [partialRead retain];
	return @"";
}

- (void) fetchResults:(NSNotification *)aNotification
{
    NSData *data = [[aNotification userInfo] objectForKey:NSFileHandleNotificationDataItem];
	// Zero length means the task has completed.
    if ([data length])
    {
		NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSString *bufferedString = [self saveTrailingCharacters:[self prependWithPartialLine:dataString]];
		if ([bufferedString length] > 0) {
			[self parseResults:bufferedString];
		}
    } else {
        [self stopGrep];
    }
    
    [[aNotification object] readInBackgroundAndNotify];  
}

- (void)parseResults:(NSString *)resultString 
{

	if([resultString characterAtIndex:[resultString length]-1] != '\n') {
		NSLog(@"resultString size: %d and last char is %c", [resultString length], [resultString characterAtIndex:[resultString length] - 1]);
	}
    
    if([resultString hasPrefix:@"Binary file "]){
        return;
    }
    
	NSScanner *scanner = [NSScanner scannerWithString:resultString];
	[scanner setCharactersToBeSkipped:[NSCharacterSet whitespaceCharacterSet]];
	while ([scanner isAtEnd] == NO) {
		
		BOOL ret;
		NSString *filename;
		ret = [scanner scanUpToString:@":" intoString:&filename];
		if(ret == NO) {
			NSLog(@"1 no:");
		}
        ret = [scanner scanString:@":" intoString:NULL];
		if(ret == NO) {
			NSLog(@"2 no:");
		}
		
		NSInteger lineNumber;
		ret = [scanner scanInteger:&lineNumber];
		if(ret == NO) {
			NSLog(@"3 no: ");
		}
		ret = [scanner scanString:@":" intoString:NULL];
		if(ret == NO) {
			NSLog(@"4 no: ");
		}
		NSString *matchLine;
		ret = [scanner scanUpToString:@"\n" intoString:&matchLine];
		if(ret == NO) {
			NSLog(@"5 no: ");
		}
		ret = [scanner scanString:@"\n" intoString:NULL];
		if(ret == NO) {
			NSLog(@"6 no:");
		}

	//	NSLog(@"filename: %@\n lineNumber: %d\n matchingLine: %@\n\n", filename, lineNumber, matchLine);
		[searchResults addResult:filename atLine:lineNumber withMatch:matchLine andSearchText:searchText];
		
	}
	[controller appendResults:searchResults];
}

@end
