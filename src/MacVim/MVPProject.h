//
//  Project.h
//  MacVim
//
//  Created by Doug Fales on 3/27/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import <Cocoa/Cocoa.h>

#import "MVPDirEntry.h"

@interface MVPProject : NSObject <NSCoding> {

	NSString *pathToRoot;
	NSString *name;
	NSString *excludePatterns;
	MVPDirEntry *rootDirEntry;
	NSMutableData *indexObject;
	NSPredicate *excludePredicate;
    NSString *originUrl;
}

//- (FSItem *)rootDirectory;

@property(nonatomic,retain) NSString *pathToRoot;
@property(nonatomic,retain) NSString *name;
@property(nonatomic,retain) NSString *excludePatterns;
@property(nonatomic,retain) NSPredicate *excludePredicate;
@property(nonatomic,retain) MVPDirEntry *rootDirEntry;
@property(nonatomic,retain) NSString *originUrl;


- (id)initWithRoot:(NSString *)root andName:(NSString *)name andIgnorePatterns:(NSString *)patterns;
- (void)load;
- (void)save;
- (BOOL)isGitProject;
- (NSURL *)githubUrlForEntry:(MVPDirEntry *)entry atBlob:(NSString *)blob;

+ (MVPProject *)loadFromDisk:(NSString *)pathToProjectFile;
+ (NSString *)pathToGit;

@end
