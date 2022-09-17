//
// MMSparkle2Delegate.h
//
// Delegate class to interface with Sparkle 2
//

#if !DISABLE_SPARKLE && !USE_SPARKLE_1

#import "Sparkle.framework/Headers/Sparkle.h"

@interface MMSparkle2Delegate : NSObject <SPUUpdaterDelegate, SPUStandardUserDriverDelegate>;

// SPUUpdaterDelegate
// Don't implement anything for now.

// SPUStandardUserDriverDelegate
// No need to implement anything for now. Default behaviors work fine.

@end

#endif
