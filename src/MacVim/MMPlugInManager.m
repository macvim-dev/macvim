/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

/*
 * MMPlugInManager
 *
 * This class is responsible for finding MacVim plugins at startup, loading
 * them, and keeping track of them.
 *
 * Author: Matt Tolton
 */

#import "MacVim.h"

#ifdef MM_ENABLE_PLUGINS

#import "MMPlugInManager.h"
#import "PlugInInterface.h"
#import "PlugInImpl.h"

@implementation MMPlugInManager

static NSString *ext = @"mmplugin";

static NSString *appSupportSubpath = @"Application Support/MacVim/PlugIns";

static MMPlugInManager *plugInManager = nil;

+ (MMPlugInManager*)sharedManager
{
    if (!plugInManager)
        plugInManager = [[MMPlugInManager alloc] init];

    return plugInManager;
}

- (id)init
{
    if ((self = [super init]) == nil) return nil;
    plugInClasses = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [plugInClasses release]; plugInClasses = nil;
    [super dealloc];
}

- (NSArray *)plugInClasses;
{
    return plugInClasses;
}

- (NSMutableArray *)allBundles
{
    NSArray *librarySearchPaths;
    NSEnumerator *searchPathEnum;
    NSString *currPath;
    NSMutableArray *bundleSearchPaths = [NSMutableArray array];
    NSMutableArray *allBundles = [NSMutableArray array];

    librarySearchPaths = NSSearchPathForDirectoriesInDomains(
        NSLibraryDirectory, NSAllDomainsMask - NSSystemDomainMask, YES);

    searchPathEnum = [librarySearchPaths objectEnumerator];
    while(currPath = [searchPathEnum nextObject]) {
        [bundleSearchPaths addObject:
            [currPath stringByAppendingPathComponent:appSupportSubpath]];
    }

    [bundleSearchPaths addObject:
        [[NSBundle mainBundle] builtInPlugInsPath]];

    searchPathEnum = [bundleSearchPaths objectEnumerator];
    while(currPath = [searchPathEnum nextObject]) {
        NSDirectoryEnumerator *bundleEnum;
        NSString *currBundlePath;
        bundleEnum = [[NSFileManager defaultManager]
            enumeratorAtPath:currPath];
        if(bundleEnum) {
            while(currBundlePath = [bundleEnum nextObject]) {
                if([[currBundlePath pathExtension] isEqualToString:ext]) {
                 [allBundles addObject:[currPath
                           stringByAppendingPathComponent:currBundlePath]];
                }
            }
        }
    }

    return allBundles;
}

- (BOOL)plugInClassIsValid:(Class)class
{
    return [class conformsToProtocol:@protocol(PlugInProtocol)];
}

- (void)loadAllPlugIns
{
    NSMutableArray *bundlePaths;
    NSEnumerator *pathEnum;
    NSString *currPath;
    NSBundle *currBundle;
    Class currPrincipalClass;

    bundlePaths = [NSMutableArray array];

    [bundlePaths addObjectsFromArray:[self allBundles]];

    pathEnum = [bundlePaths objectEnumerator];
    while(currPath = [pathEnum nextObject]) {
        currBundle = [NSBundle bundleWithPath:currPath];
        if(currBundle) {
            currPrincipalClass = [currBundle principalClass];
            if(currPrincipalClass && [self plugInClassIsValid:currPrincipalClass]) {
                if ([currPrincipalClass initializePlugIn:
                    [MMPlugInAppMediator sharedAppMediator]]) {
                    ASLogInfo(@"Plug-in initialized: %@", currPath);
                    [plugInClasses addObject:currPrincipalClass];
                } else {
                    ASLogErr(@"Plug-in failed to initialize: %@", currPath);
                }
            } else {
                ASLogErr(@"Plug-in did not conform to protocol: %@", currPath);
            }
        }
    }
}

- (void)unloadAllPlugIns
{
    int i, count = [plugInClasses count];
    for (i = 0; i < count; i++)
        [[plugInClasses objectAtIndex:i] terminatePlugIn];

    [plugInClasses removeAllObjects];
}

@end

#endif
