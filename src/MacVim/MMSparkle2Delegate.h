//
// MMSparkle2Delegate.h
//
// Delegate class to interface with Sparkle 2
//

#if !DISABLE_SPARKLE && !USE_SPARKLE_1

#import "Sparkle.framework/Headers/Sparkle.h"

@interface MMSparkle2Delegate : NSObject <SPUUpdaterDelegate, SPUStandardUserDriverDelegate>;

// SPUUpdaterDelegate
- (nonnull NSSet<NSString *> *)allowedChannelsForUpdater:(nonnull SPUUpdater *)updater;

// SPUStandardUserDriverDelegate
// No need to implement anything for now. Default behaviors work fine.

@end

#endif
