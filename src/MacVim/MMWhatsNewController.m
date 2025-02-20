//
// MMWhatsNewWindow.m
//
// Window for displaying a "What's New" page with latest release notes.
//

#import "MMWhatsNewController.h"

#import "MacVim.h"

#import <WebKit/WebKit.h>

@interface MMWhatsNewController () <WKNavigationDelegate>

@property WKWebView* webView;
@property NSURL *whatsNewURL;

- (id)init;
- (void)dealloc;
@end

@implementation MMWhatsNewController

static MMWhatsNewController *singleton = nil;
static NSString *_fromVersion;
static NSString *_latestVersion;

+ (void)openSharedInstance
{
    if (![MMWhatsNewController canOpen]) {
        return;
    }

    if (!singleton) {
        singleton = [[MMWhatsNewController alloc] init];
    }
    NSWindow *window = [singleton window];
    [window makeKeyAndOrderFront:self];
    [window setDelegate:singleton];

    return;
}

/// Whether this feature is supported on this OS.
+ (BOOL)canOpen
{
    // While macOS 10.10 added WKWebView, 10.10-10.11 have issues with expired
    // certs which means they can't easily access macvim.org. Just disable this
    // feature to avoid confusing certifate errors when we pop up a blank page.
    if (AVAILABLE_MAC_OS(10, 12))
    {
        return YES;
    }
    return NO;
}

/// Sets a requested version range for displaying What's New. Useful for when
/// we have updated across multiple versions and we can show a list of them.
+ (void)setRequestVersionRange:(NSString *)fromVersion to:(NSString *)latestVersion
{
    // These will leak as we never release, but it's ok. We intentionally remember
    // the values so that even if the user dismissed the initial window they can
    // open this again and it will be remembered as long as MacVim is open. This
    // results in a better UX than only seeing the info once.
    _fromVersion = [fromVersion retain];
    _latestVersion = [latestVersion retain];
}

- (id)init
{
    self = [super initWithWindowNibName:@"WhatsNew"];
    [self setWindowFrameAutosaveName:@"WhatsNew"];

    NSString *whatsNewURLStr = [[NSBundle mainBundle]
                                objectForInfoDictionaryKey:@"MMWhatsNewURL"];

    if (_fromVersion != nil && _latestVersion != nil) {
        // We just updated to a new version. Show a message to user and also
        // requests specifically these new versions for the welcome message
        whatsNewURLStr = [NSString stringWithFormat:@"%@?from=%@&to=%@",
                          whatsNewURLStr,
                          _fromVersion,
                          _latestVersion];
    }
    else {
        // Just show the current version MacVim has
        NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

        whatsNewURLStr = [NSString stringWithFormat:@"%@?version=%@",
                          whatsNewURLStr,
                          currentVersion];
    }
    _whatsNewURL = [[NSURL URLWithString:whatsNewURLStr] retain];

    return self;
}

- (void)dealloc
{
    webViewContainer = nil;
    [_webView release]; _webView = nil;
    [_whatsNewURL release]; _whatsNewURL = nil;

    [super dealloc];
}

- (void)windowDidLoad
{
    if (_fromVersion != nil && _latestVersion != nil) {
        messageTextField.stringValue = [NSString stringWithFormat:
                                        NSLocalizedString(@"MacVim has been updated to a new version (from r%@ to r%@)! See below for what's new.", @"New version prompt"),
                                        _fromVersion, _latestVersion];
    }
    else {
        // This will pin the web view to the top, on top of the message box
        [webViewAlignTopConstraint setPriority:999];

        messageTextField.stringValue = @"";
    }

    // Construct a web view at runtime instead of relying on using the xib because this is
    // more backwards compatible as we can use runtime checks and compiler defines.
    _webView = [[WKWebView alloc] initWithFrame:NSZeroRect
                                  configuration:[[[WKWebViewConfiguration alloc] init] autorelease]];

    [webViewContainer addSubview:_webView];
    _webView.frame = webViewContainer.bounds;
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _webView.navigationDelegate = self;

    [_webView loadRequest:[NSURLRequest requestWithURL:_whatsNewURL]];
}

// NSWindowDelegate methods

- (void)windowWillClose:(NSNotification *)notification
{
    [singleton release]; singleton = nil;
    return;
}

// Font size delegates for menu items

#if defined(MAC_OS_VERSION_11_0) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_11_0
- (IBAction)fontSizeUp:(id)sender
{
    if (@available(macos 11.0, *)) {
        CGFloat pageZoom = _webView.pageZoom + 0.25;
        _webView.pageZoom = pageZoom > 3.0 ? 3.0 : pageZoom;
    }
}

- (IBAction)fontSizeDown:(id)sender
{
    if (@available(macos 11.0, *)) {
        CGFloat pageZoom = _webView.pageZoom - 0.25;
        _webView.pageZoom = pageZoom < 0.25 ? 0.25 : pageZoom;
    }
}
#endif

// WKNavigationDelegate methods

/// Tells web view how to handle links and navigation. Current behavior is
/// anything that is not the release notes will be opened by system web browser.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURLRequest *request = navigationAction.request;
    NSURL *requestURL = request.URL;

    if ([requestURL.scheme isEqual:_whatsNewURL.scheme] &&
        [requestURL.host isEqual:_whatsNewURL.host] &&
        requestURL.port.integerValue == _whatsNewURL.port.integerValue &&
        [requestURL.path isEqual:_whatsNewURL.path] &&
        [requestURL.query isEqual:_whatsNewURL.query])
    {
        // Only allow if everything except for fragment is the same (which
        // we allow so that table of contents anchor links would work).
        decisionHandler(WKNavigationActionPolicyAllow);
    }
    else {
        // We want to open any links in the release notes with a browser instead.
        decisionHandler(WKNavigationActionPolicyCancel);

        if ([requestURL.scheme isEqualToString:@"https"]) {
            // Just try to be sane and only open https:// urls. There should be
            // no reason why the release notes should contain other schemes and it
            // would be an indication something is wrong or malicious (e.g. file:
            // URLs).
            [[NSWorkspace sharedWorkspace] openURL: requestURL];
        }
    }
}
@end
