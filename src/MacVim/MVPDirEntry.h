//
//  MVPDirEntry.h
//  MacVim
//
//  Created by Doug Fales on 4/3/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import <Cocoa/Cocoa.h>

@class MVPProject;

@interface MVPDirEntry : NSObject<NSCopying> {
	NSURL *url;
	NSString *name;
	NSString *rootDirectory;
	MVPDirEntry *parentDirEntry;
    NSString *relativePath;
	NSMutableArray *children;
	BOOL isDirectory;
    NSPredicate *excludePredicate;
}

@property (assign) double editDistance;
@property (nonatomic, retain) NSURL *url;
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *relativePath;
@property (nonatomic, retain) NSString *rootDirectory;
@property (nonatomic, retain) MVPDirEntry *parentDirEntry;
@property (nonatomic, retain) NSMutableArray *children;
@property (assign, readonly)  BOOL isDirectory;
@property (nonatomic, retain) NSPredicate *excludePredicate;

- (id)initWithURL:(NSURL *)newUrl andParent:(MVPDirEntry *)aParent andProjectRoot:(NSString *)projectRoot andExcludePredicate:(NSPredicate*)excludePaths;

- (NSImage *)icon;
- (NSString *)filename;
- (void)addChild:(MVPDirEntry *)childEntry;
- (MVPDirEntry *)refreshAtPath:(NSString *)pathToRefresh;
- (void)buildTree;
#pragma mark Tree-related 
- (BOOL)isLeaf;
- (NSInteger)childCount;
- (MVPDirEntry *)childAtIndex:(NSInteger)index;

@end
