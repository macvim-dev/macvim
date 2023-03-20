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

- (_Nullable id <SUVersionDisplay>)standardUserDriverRequestsVersionDisplayer
{
    return self;
}

/// MacVim has a non-standard way of using "bundle version" and "display version",
/// where the display version is the upstream Vim version, and the bundle version
/// is the release number of MacVim itself. The release number is more useful to
/// know when updating MacVim, but both should be displayed. Format them nicely so
/// it's clear to the user which is which. By default Sparkle would only show display
/// version which is problematic as that wouldn't show the release number which we
/// care about.
NSString* formatVersionString(NSString* bundleVersion, NSString* displayVersion)
{
    return [NSString stringWithFormat:@"r%@ (Vim %@)", bundleVersion, displayVersion];
}

- (NSString *)formatUpdateDisplayVersionFromUpdate:(SUAppcastItem *)update andBundleDisplayVersion:(NSString * _Nonnull __autoreleasing * _Nonnull)inOutBundleDisplayVersion withBundleVersion:(NSString *)bundleVersion
{
    *inOutBundleDisplayVersion = formatVersionString(bundleVersion, *inOutBundleDisplayVersion);
    return formatVersionString(update.versionString, update.displayVersionString);
}

- (NSString *)formatBundleDisplayVersion:(NSString *)bundleDisplayVersion withBundleVersion:(NSString *)bundleVersion matchingUpdate:(SUAppcastItem * _Nullable)matchingUpdate
{
    return formatVersionString(bundleVersion, bundleDisplayVersion);
}


@end;

#endif
