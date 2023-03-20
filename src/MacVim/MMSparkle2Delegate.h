//
// MMSparkle2Delegate.h
//
// Delegate class to interface with Sparkle 2
//

#if !DISABLE_SPARKLE && !USE_SPARKLE_1

#import "Sparkle.framework/Headers/Sparkle.h"

NS_ASSUME_NONNULL_BEGIN

@interface MMSparkle2Delegate : NSObject <SPUUpdaterDelegate, SPUStandardUserDriverDelegate, SUVersionDisplay>;

// SPUUpdaterDelegate
- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)updater;

// SPUStandardUserDriverDelegate
- (_Nullable id <SUVersionDisplay>)standardUserDriverRequestsVersionDisplayer;

// SUVersionDisplay
- (NSString *)formatUpdateDisplayVersionFromUpdate:(SUAppcastItem *)update andBundleDisplayVersion:(NSString * _Nonnull __autoreleasing * _Nonnull)inOutBundleDisplayVersion withBundleVersion:(NSString *)bundleVersion;

- (NSString *)formatBundleDisplayVersion:(NSString *)bundleDisplayVersion withBundleVersion:(NSString *)bundleVersion matchingUpdate:(SUAppcastItem * _Nullable)matchingUpdate;

@end

NS_ASSUME_NONNULL_END

#endif
