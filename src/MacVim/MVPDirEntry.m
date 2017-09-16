//
//  MVPDirEntry.m
//  MacVim
//
//  Created by Doug Fales on 4/3/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import "MVPDirEntry.h"
#import "MVPProject.h"
#import "MacVim.h"
@implementation MVPDirEntry

@synthesize url, name, relativePath, rootDirectory, parentDirEntry, children, isDirectory, excludePredicate;

- (id)initWithURL:(NSURL *)newUrl andParent:(MVPDirEntry *)aParent andProjectRoot:(NSString *)projectRoot andExcludePredicate:(NSPredicate *)excludePaths {
	if((self = [super init])) {
		self.url = newUrl;
        self.excludePredicate = excludePaths;
		NSNumber *dir = nil;
		[url getResourceValue:&dir forKey:NSURLIsDirectoryKey error:NULL];		
		isDirectory = [dir boolValue]; 
		self.rootDirectory = projectRoot;
        self.name = [url lastPathComponent];
        self.relativePath = [[url path] stringByReplacingOccurrencesOfString:projectRoot withString:@""];
		self.parentDirEntry = aParent;
	}
	return self;
}

- (MVPDirEntry *)refreshAtPath:(NSString *)pathToRefresh{
    MVPDirEntry *entryToRefresh = self;
    NSString *projectRelativePath = [pathToRefresh stringByReplacingOccurrencesOfString:self.rootDirectory withString:@""];
    if(![projectRelativePath isEqualToString:@"/"]){
        NSArray *pathComponents = [projectRelativePath pathComponents];
        for (NSString *pathComponent in pathComponents) {
            for(MVPDirEntry *subDir in [entryToRefresh children] ) {
                if([subDir isDirectory]){
                    if([[subDir filename] isEqualToString:pathComponent]) {
                        entryToRefresh = subDir;
                        break;
                    }
                }
            }
        }
    }
    [entryToRefresh refreshDirectory];
    return entryToRefresh;
}

- (NSArray *)directoryContents
{
    NSArray *keys = [NSArray arrayWithObjects:NSURLIsDirectoryKey, NSURLIsPackageKey, NSURLLocalizedNameKey, nil];
	NSError *error = nil;
	NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.url
													  includingPropertiesForKeys:keys
																		 options:(NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsHiddenFiles)
																		   error:&error];
    return contents;
}

// Refresh only one-level--do not recurse unless a new directory is found. Intended for use with the FSEvents listener.
- (void)refreshDirectory
{
    NSArray *contents = [self directoryContents];
    // First, add new objects.
    for(NSURL *file in contents) {
        NSString *name = [file lastPathComponent];
		if(self.excludePredicate == nil || [self.excludePredicate evaluateWithObject:name] == NO) {
            BOOL unchanged = NO;
            NSNumber *isDir = nil;
			[file getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:NULL];
            for(MVPDirEntry *child in children) {
                if([[child filename] isEqualToString:name] && [child isDirectory] == [isDir boolValue]) {
                    unchanged = YES;
                    break;
                }
            }
            
            if(!unchanged) {
                MVPDirEntry *dirEntry = [[MVPDirEntry alloc] initWithURL:file
                                                               andParent:self
                                                          andProjectRoot:self.rootDirectory
                                                     andExcludePredicate:self.excludePredicate];
                [self addChild:dirEntry];
                if([isDir boolValue]) {
                    [dirEntry buildTree];
                }
            }
		}
	}
    // Locate and remove deleted ones.
    NSMutableArray *deletedFiles = [NSMutableArray array];
    for(MVPDirEntry *child in children) {
        BOOL found = NO;
        for(NSURL *file in contents) {
            if([[file lastPathComponent] isEqualToString:[child filename]]){
                found = YES;
                break;
            }
        }
        if(!found){
            [deletedFiles addObject:child];
        }
    }
    [children removeObjectsInArray:deletedFiles];
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"filename" ascending:YES];
    [children sortUsingDescriptors:[NSArray arrayWithObject:sort]];
}

-(void)buildTree
{
    NSArray *contents = [self directoryContents];
    for(NSURL *file in contents) {
		if(self.excludePredicate == nil || [self.excludePredicate evaluateWithObject:[file lastPathComponent]] == NO) {
			MVPDirEntry *dirEntry = [[MVPDirEntry alloc] initWithURL:file
                                                           andParent:self
                                                      andProjectRoot:self.rootDirectory
                                                 andExcludePredicate:self.excludePredicate];
			[self addChild:dirEntry];
			NSNumber *isDir = nil;
			[file getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:NULL];
			if([isDir boolValue]) {
                [dirEntry buildTree];
			}
		}
	}
}

- (void)addChild:(MVPDirEntry *)childEntry
{
    if(children == nil) {
		self.children = [NSMutableArray arrayWithCapacity:1];
	}
	[children addObject:childEntry];
}

-(id)copyWithZone:(NSZone *)zone {
	MVPDirEntry *copy = [[MVPDirEntry alloc] initWithURL:self.url andParent:self.parentDirEntry andProjectRoot:self.rootDirectory andExcludePredicate:self.excludePredicate];
	return copy;
}

- (void)dealloc {
	[url release]; url = nil;
	[parentDirEntry release]; parentDirEntry = nil;
	[super dealloc];
}

-(NSImage *)icon {
	return [[NSWorkspace sharedWorkspace] iconForFileType:[self.url pathExtension]];
}

- (NSString *)filename {
	return [url lastPathComponent];
}

- (BOOL)isLeaf {
	return ((children == nil) || [children count] == 0);
}
- (NSInteger)childCount {
	if(children == nil) {
		return 0;
	} else {
		return [children count];
	}
}

- (MVPDirEntry *)childAtIndex:(NSInteger)index
{
    if(children == nil || [children count] <= index){
        return nil;
    } else {
        return [children objectAtIndex:index];
    }
}

@end
