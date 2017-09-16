//
//  Project.m
//  MacVim
//
//  Created by Doug Fales on 3/27/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//
#define kSearchMax 1000
#import "MVPProject.h"

#define kProjectName @"name"
#define kProjectRootPath @"root"
#define kProjectExcludePatterns @"excludePatterns"
#define kProjectRecentProjects @"RecentProjects"

@interface MVPProject ()
+ (void)persistToDisk:(MVPProject *)project atRoot:(NSString *)rootPath;
- (void)initializeFileTree;
-(void)initializeExcludePredicate;
@end

static NSString *_pathToGit;

@implementation MVPProject

@synthesize pathToRoot;
@synthesize name;
@synthesize excludePatterns;
@synthesize rootDirEntry;
@synthesize excludePredicate;
@synthesize originUrl;


+ (NSString *)pathToGit
{
    if(_pathToGit == nil) {
        @synchronized(self){
            if(_pathToGit == nil) {
                NSMutableArray *possibleGits = [NSMutableArray arrayWithObjects:@"/opt/local/bin/git",
                                                @"/sw/bin/git",
                                                @"/opt/git/bin/git",
                                                @"/usr/bin/git",
                                                @"/usr/local/bin/git",
                                                @"/usr/local/git/bin/git",
                                                nil];
                [possibleGits addObject:[@"~/bin/git" stringByExpandingTildeInPath]];
                
                for(NSString *possibleGit in possibleGits)
                {
                    if([[NSFileManager defaultManager] fileExistsAtPath:possibleGit]) {
                        _pathToGit = [possibleGit retain];
                        break;
                    }
                    _pathToGit = nil;
                }
   
            }
        }
    }
    return _pathToGit;
}

- (id)initWithRoot:(NSString *)root andName:(NSString *)newName andIgnorePatterns:(NSString *)patterns {
	if((self = [super init])) {
		self.pathToRoot = root;
		self.name = newName;
		self.excludePatterns = patterns;
		[self initializeExcludePredicate];
	}
	return self;
}

- (void)load {
	[self initializeFileTree];
    [self initializeRepoConfig];
}

- (void)save {
	[MVPProject persistToDisk:self atRoot:self.pathToRoot];
}

- (void)dealloc {
	[pathToRoot release]; pathToRoot = nil;
	[name release]; name = nil;
	[excludePatterns release]; excludePatterns = nil;
	[super dealloc];
}

#pragma mark NSCoding
- (id)initWithCoder:(NSCoder *)aDecoder {
	if((self = [super init])) {
		self.name = [aDecoder decodeObjectForKey:kProjectName];
		self.pathToRoot = [aDecoder decodeObjectForKey:kProjectRootPath];
		self.excludePatterns = [aDecoder decodeObjectForKey:kProjectExcludePatterns];
		[self initializeExcludePredicate];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	[coder encodeObject:name forKey:kProjectName];
	[coder encodeObject:pathToRoot forKey:kProjectRootPath];
	[coder encodeObject:excludePatterns forKey:kProjectExcludePatterns];
}

- (BOOL)isGitProject
{
    NSString *gitDir = [[self pathToRoot] stringByAppendingPathComponent:@".git"];
    return [[NSFileManager defaultManager] fileExistsAtPath:gitDir];
}

#pragma mark Git

- (void)initializeRepoConfig
{
    NSTask *gitConfigTask = [[NSTask alloc] init];
    
	[gitConfigTask setCurrentDirectoryPath:[self pathToRoot]];
    [gitConfigTask setStandardOutput: [NSPipe pipe]];
    [gitConfigTask setStandardError: [gitConfigTask standardOutput]];
	
    [gitConfigTask setLaunchPath:[MVPProject pathToGit]];
    [gitConfigTask setArguments:[NSArray arrayWithObjects:@"config", @"--get", @"remote.origin.url", nil]];
	
    [[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(storeRepoConfig:)
												 name: NSFileHandleReadCompletionNotification
											   object: [[gitConfigTask standardOutput] fileHandleForReading]];
    [[[gitConfigTask standardOutput] fileHandleForReading] readInBackgroundAndNotify];
    [gitConfigTask launch];
}

- (void)storeRepoConfig:(NSNotification *)note
{
    NSData *data = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([data length])
    {
		self.originUrl = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSLog(@"originUrl: %@", originUrl);
    }
}




#pragma mark Project File Tree
- (void)initializeFileTree {
	NSURL *directoryURL = [NSURL URLWithString:self.pathToRoot];
	self.rootDirEntry = [[MVPDirEntry alloc] initWithURL:directoryURL andParent:nil andProjectRoot:self.pathToRoot andExcludePredicate:self.excludePredicate];
    [self.rootDirEntry buildTree];
}

-(void)initializeExcludePredicate {
	NSArray *excludePatternStrings = [self.excludePatterns componentsSeparatedByString:@","];
	if(excludePatterns && [excludePatternStrings count] > 0) {
		NSMutableArray *predicateArray = [NSMutableArray arrayWithCapacity:[excludePatternStrings count]];
		for(NSString *pattern in excludePatternStrings) {
			[predicateArray addObject:[NSPredicate predicateWithFormat:@"SELF LIKE %@", [pattern stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]]];
		}
		self.excludePredicate = [NSCompoundPredicate orPredicateWithSubpredicates:predicateArray];
	} else {
		self.excludePredicate = nil;	
	}
}

- (NSURL *)githubUrlForEntry:(MVPDirEntry *)entry atBlob:(NSString *)blob
{
    NSString *repoPath = nil;
    
    NSArray *githubAndRepo = [originUrl componentsSeparatedByString:@":"];
    if([githubAndRepo count] == 2) {
        repoPath = [NSString stringWithFormat:@"/%@", [githubAndRepo objectAtIndex:1]];
        NSInteger dotGit = [repoPath length] - 5;
        repoPath = [repoPath substringToIndex:dotGit];
    }
    repoPath = [repoPath stringByAppendingFormat:@"/blob/%@/%@", [blob substringToIndex:7], [entry relativePath] ];
    NSURL *url = [[NSURL alloc] initWithScheme:@"https" host:@"github.com" path:repoPath];
    return url;
}

#pragma mark Saving and Creating
+ (NSString *)projectMetaPath:(NSString *)rootPath forProjectName:(NSString *)projName {
	return [rootPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mvp", projName]];
}

+ (void)persistToDisk:(MVPProject *)project atRoot:(NSString *)rootPath {	
	[NSKeyedArchiver archiveRootObject:project toFile:[self projectMetaPath:rootPath forProjectName:project.name]];
}

+ (MVPProject *)loadFromDisk:(NSString *)pathToProjectFile {
	MVPProject *p = [NSKeyedUnarchiver unarchiveObjectWithFile:pathToProjectFile];
	return p;
}





@end
