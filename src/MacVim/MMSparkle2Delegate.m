//
// MMSparkle2Delegate.m
//
// This file contains code to interface with Sparkle 2 and customize it.
//

#if !DISABLE_SPARKLE && !USE_SPARKLE_1

#import "MMSparkle2Delegate.h"

#import "Miscellaneous.h"

#import <Foundation/Foundation.h>

@implementation MMSparkle2Delegate;

/// If the user has opted in, return the pre-release channel to Sparkle so pre-
/// release builds will be available for update as well.
- (nonnull NSSet<NSString *> *)allowedChannelsForUpdater:(nonnull SPUUpdater *)updater
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:MMUpdaterPrereleaseChannelKey]) {
        return [NSSet<NSString *> setWithObject:@"prerelease"];
    }
    return [NSSet<NSString *> set];
}

@end;

#endif
