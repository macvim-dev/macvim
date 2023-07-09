//
// MMWhatsNewWindow.h
//
// Window for displaying a "What's New" page with latest release notes.
//

#import <Cocoa/Cocoa.h>

/// A controller to open a web view showing the latest release notes. This is
/// designed to show what's new since you updated your software and therefore
/// accepts a version range to request.
@interface MMWhatsNewController : NSWindowController<NSWindowDelegate>
{
    IBOutlet NSTextField        *messageTextField;
    IBOutlet NSView             *webViewContainer;
    IBOutlet NSLayoutConstraint *webViewAlignTopConstraint; ///< Constraint to pin the web view to the top of window instead of the message
}

+ (void)openSharedInstance;
+ (BOOL)canOpen;
+ (void)setRequestVersionRange:(NSString*)fromVersion to:(NSString*)latestVersion;

@end
