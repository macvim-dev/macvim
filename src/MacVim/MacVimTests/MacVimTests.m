//
// MacVimTests.m
//
// Contains unit tests and end-to-end app tests. Currently everything is in one
// file as we only have a few tests. As we expand test coverage we should split
// them up and refactor to more logical components.
//

#import <XCTest/XCTest.h>

#import <objc/runtime.h>

#import <Cocoa/Cocoa.h>

#import "Miscellaneous.h"
#import "MMAppController.h"
#import "MMApplication.h"
#import "MMFullScreenWindow.h"
#import "MMWindow.h"
#import "MMTabline.h"
#import "MMTextView.h"
#import "MMWindowController.h"
#import "MMVimController.h"
#import "MMVimView.h"

// Expose private methods for testing purposes
@interface MMAppController (Private)
+ (NSDictionary*)parseOpenURL:(NSURL*)url;
- (void)processInputQueues:(id)sender;
@end

@interface MMVimController (Private)
- (void)handleMessage:(int)msgid data:(NSData *)data;
@end

@interface MMVimView (Tests)
- (void)updateTablineColors:(MMTabColorsMode)mode;
@end

// Test harness
@implementation MMAppController (Tests)
- (NSMutableArray*)vimControllers {
    return vimControllers;
}
@end

static BOOL forceInLiveResize = NO;
@implementation MMVimView (testWindowResize)
- (BOOL)inLiveResize {
    // Mock NSView's inLiveResize functionality
    if (forceInLiveResize)
        return YES;
    return [super inLiveResize];
}
@end

@implementation MMWindowController (Tests)
- (BOOL)fullScreenEnabled {
    return fullScreenEnabled;
}
@end

@interface MacVimTests : XCTestCase

@end

@implementation MacVimTests

static NSDictionary<NSString *, id> *cachedAppDefaults;

/// Global test suite set up
+ (void)setUp {
    // We launch test cases with -IgnoreUserDefaults, which populates the
    // volatile domain with default settings to prevent interactions with
    // local defaults on the system. Cache this.
    cachedAppDefaults = [NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain];
}

/// Per-test tear down
- (void)tearDown {
    [self resetDefaults];
}

/// Set a default to be used for this test. It will be reset at end of test.
- (void)setDefault:(NSString *)key toValue:(id)val {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSDictionary<NSString *, id> *curDefaults = [ud volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary<NSString *, id> *newDefaults = [curDefaults mutableCopy];
    newDefaults[key] = val;
    [ud setVolatileDomain:newDefaults
                  forName:NSArgumentDomain];
}

/// Reset test settings to the default values
- (void)resetDefaults {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:cachedAppDefaults
                                                   forName:NSArgumentDomain];
}

/// Create a new clean window for the test that will be torn down afterwards.
/// Most tests will use this for convenience unless they have other needs.
- (void)createTestVimWindow {
    [self createTestVimWindowWithExtraArgs:nil];
}

/// Create a new clean window with extra arguments.
- (void)createTestVimWindowWithExtraArgs:(NSArray *)args {
    [MMAppController.sharedInstance openNewWindow:NewWindowClean activate:YES extraArgs:args];
    [self waitForVimOpenAndMessages];

    __weak __typeof__(self) self_weak = self;
    [self addTeardownBlock:^{
        MMAppController *app = MMAppController.sharedInstance;

        // If we are still in native full screen, make sure to exit it first.
        // Otherwise if we directly close the window there's a period of time
        // macOS will be stuck in the transition animation and if we try to run
        // another native full screen test immediately it will fail.
        if ([app.keyVimController.windowController fullScreenEnabled] &&
                app.keyVimController.windowController.window.styleMask & NSWindowStyleMaskFullScreen) {
            [self_weak sendStringToVim:@":set nofu\n" withMods:0];
            [self_weak waitForFullscreenTransitionIsEnter:NO isNative:YES];
        }

        [[app keyVimController] sendMessage:VimShouldCloseMsgID data:nil];
        [self_weak waitForVimClose];

        XCTAssertEqual(0, [app vimControllers].count);
    }];
}

/// Creates a file URL in a temporary directory. The file itself is not created.
/// The directory will be cleaned up automatically.
- (NSURL *)tempFile:(NSString *)name {
    NSError *error = nil;
    NSURL *tempDir = [NSFileManager.defaultManager URLForDirectory:NSItemReplacementDirectory
                                                          inDomain:NSUserDomainMask
                                                 appropriateForURL:NSFileManager.defaultManager.homeDirectoryForCurrentUser
                                                            create:YES
                                                             error:&error];
    if (tempDir == nil) {
        @throw error;
    }
    [self addTeardownBlock:^{
        [NSFileManager.defaultManager removeItemAtURL:tempDir error:nil];
    }];

    return [tempDir URLByAppendingPathComponent:name];
}

/// Wait for Vim window to open
- (void)waitForVimOpen {
    XCTestExpectation *expectation = [self expectationWithDescription:@"VimOpen"];

    SEL sel = @selector(windowControllerWillOpen:);
    Method method = class_getInstanceMethod([MMAppController class], sel);

    IMP origIMP = method_getImplementation(method);
    IMP newIMP = imp_implementationWithBlock(^(id self, MMWindowController *w) {
        typedef void (*fn)(id,SEL,MMWindowController*);
        ((fn)origIMP)(self, sel, w);
        [expectation fulfill];
    });

    method_setImplementation(method, newIMP);
    [self waitForExpectations:@[expectation] timeout:10];
    method_setImplementation(method, origIMP);
}

/// Wait for Vim window to open and is ready to go
- (void)waitForVimOpenAndMessages {
    [self waitForVimOpen];
    [self waitForEventHandlingAndVimProcess];
}

/// Wait for a Vim window to be closed
- (void)waitForVimClose {
    XCTestExpectation *expectation = [self expectationWithDescription:@"VimClose"];

    SEL sel = @selector(removeVimController:);
    Method method = class_getInstanceMethod([MMAppController class], sel);

    IMP origIMP = method_getImplementation(method);
    IMP newIMP = imp_implementationWithBlock(^(id self, id controller) {
        typedef void (*fn)(id,SEL,id);
        ((fn)origIMP)(self, sel, controller);
        [expectation fulfill];
    });

    method_setImplementation(method, newIMP);
    [self waitForExpectations:@[expectation] timeout:10];
    method_setImplementation(method, origIMP);
}

/// Wait for event handling to be finished at the main loop.
- (void)waitForEventHandling {
    // Inject a custom event. By the time we handle this event all queued events
    // will have been consumed.
    const NSInteger appEventType = 1687648131; // magic number to prevent collisions
    XCTestExpectation *expectation = [self expectationWithDescription:@"EventHandling"];

    SEL sel = @selector(sendEvent:);
    Method method = class_getInstanceMethod([MMApplication class], sel);

    IMP origIMP = method_getImplementation(method);
    IMP newIMP = imp_implementationWithBlock(^(id self, NSEvent *event) {
        typedef void (*fn)(id,SEL,NSEvent*);
        if (event.type == NSEventTypeApplicationDefined && event.data1 == appEventType) {
            [expectation fulfill];
        } else {
            ((fn)origIMP)(self, sel, event);
        }
    });

    NSApplication* app = [NSApplication sharedApplication];
    NSEvent* customEvent = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                              location:NSMakePoint(50, 50)
                                         modifierFlags:0
                                             timestamp:100
                                          windowNumber:[[NSApp mainWindow] windowNumber]
                                               context:0
                                               subtype:0
                                                 data1:appEventType
                                                 data2:0];

    method_setImplementation(method, newIMP);

    [app postEvent:customEvent atStart:NO];
    [self waitForExpectations:@[expectation] timeout:10];

    method_setImplementation(method, origIMP);
}

static BOOL vimProcessInputBlocked = NO;

/// Block / unblock all Vim message handling from happening. This allows tests
/// to run with a strong guarantee of ordering of events without them being
/// subject to timing variations. Any outstanding block will be cleared at the
/// end of the tests during teardown automatically.
- (void)blockVimProcessInput:(BOOL)block {
    SEL sel = @selector(processInputQueues:);
    Method method = class_getInstanceMethod([MMAppController class], sel);

    __weak __typeof__(self) self_weak = self;

    static IMP origIMP = nil;
    static BOOL blockedMethodCalled = NO;
    static BOOL teardownAdded = NO;
    if (block) {
        if (origIMP == nil)
            origIMP = method_getImplementation(method);
        IMP newIMP = imp_implementationWithBlock(^(id self, id sender) {
            blockedMethodCalled = YES;
        });
        method_setImplementation(method, newIMP);
        vimProcessInputBlocked = YES;

        if (!teardownAdded) {
            [self addTeardownBlock:^{
                if (vimProcessInputBlocked) {
                    [self_weak blockVimProcessInput:NO];
                }
                teardownAdded = NO;
            }];
            teardownAdded = YES;
        }
    } else {
        if (origIMP != nil) {
            method_setImplementation(method, origIMP);

            if (blockedMethodCalled) {
                MMAppController *app = MMAppController.sharedInstance;
                [app performSelectorOnMainThread:@selector(processInputQueues:) withObject:nil waitUntilDone:NO];
                blockedMethodCalled = NO;
            }
        }
        vimProcessInputBlocked = NO;
    }
}

/// Wait for a specific message from Vim. Optionally, after receiving the
/// mesasge, block all future Vim message handling until manually unblocked
/// or this method was called again. This is useful for tests that want to
/// test a sequence of events with tight ordering and not be subject to timing
/// issues.
- (void)waitForVimMessage:(int)messageID blockFutureMessages:(BOOL)blockMsgs {
    XCTestExpectation *expectation = [self expectationWithDescription:@"VimMessage"];

    SEL sel = @selector(handleMessage:data:);
    Method method = class_getInstanceMethod([MMVimController class], sel);

    __weak __typeof__(self) self_weak = self;

    IMP origIMP = method_getImplementation(method);
    IMP newIMP = imp_implementationWithBlock(^(id self, int msgid, NSData *data) {
        typedef void (*fn)(id,SEL,int,NSData*);
        ((fn)origIMP)(self, sel, msgid, data);
        if (msgid == messageID) {
            [expectation fulfill];
            if (blockMsgs) {
                [self_weak blockVimProcessInput:YES];
            }
        }
    });

    if (vimProcessInputBlocked) {
        // Make sure unblock message handling first or we will deadlock.
        [self blockVimProcessInput:NO];
    }

    method_setImplementation(method, newIMP);
    [self waitForExpectations:@[expectation] timeout:10];
    method_setImplementation(method, origIMP);
}

/// Wait for Vim to process all pending messages in its queue. In future we
/// should migrate to having tests directly call waitForVimMessage directly.
- (void)waitForVimProcess {
    // Implement this by sending a loopback message (Vim will send the message
    // back to us) as a synchronization mechanism as Vim handles its messages
    // sequentially.
    XCTestExpectation *expectation = [self expectationWithDescription:@"VimLoopBack"];

    SEL sel = @selector(handleMessage:data:);
    Method method = class_getInstanceMethod([MMVimController class], sel);

    IMP origIMP = method_getImplementation(method);
    IMP newIMP = imp_implementationWithBlock(^(id self, int msgid, NSData *data) {
        typedef void (*fn)(id,SEL,int,NSData*);
        if (msgid == LoopBackMsgID) {
            [expectation fulfill];
        } else {
            ((fn)origIMP)(self, sel, msgid, data);
        }
    });

    method_setImplementation(method, newIMP);

    [[MMAppController.sharedInstance keyVimController] sendMessage:LoopBackMsgID data:nil];
    [self waitForExpectations:@[expectation] timeout:10];

    method_setImplementation(method, origIMP);
}

/// Wait for both event handling to be finished at the main loop and for Vim to
/// process all pending messages in its queue.
- (void)waitForEventHandlingAndVimProcess {
    [self waitForEventHandling];
    [self waitForVimProcess];
}

/// Wait for a fixed timeout before fulfilling expectation.
///
/// @note Should only be used for quick iteration / debugging unless we cannot
/// find an alternative way to specify an expectation, as timeouts tend to be
/// fragile and take more time to complete.
- (void)waitTimeout:(double)delaySecs {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Timeout"];
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySecs * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [expectation fulfill];
    });
    [self waitForExpectations:@[expectation] timeout:delaySecs + 10];
}

/// Send a single key to MacVim via event handling system.
- (void)sendKeyToVim:(NSString*)chars withMods:(int)mods {
    NSApplication* app = [NSApplication sharedApplication];

    NSString *modChars = chars;
    if (mods & NSEventModifierFlagControl) {
        unichar ch = [chars characterAtIndex:0] & ~0x60;
        modChars = [NSString stringWithCharacters:&ch length:1];
    }
    NSEvent* keyEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                         location:NSMakePoint(50, 50)
                                    modifierFlags:mods
                                        timestamp:100
                                     windowNumber:[[NSApp mainWindow] windowNumber]
                                          context:0
                                       characters:modChars
                      charactersIgnoringModifiers:chars
                                        isARepeat:NO
                                          keyCode:0];
    [app postEvent:keyEvent atStart:NO];
}

/// Send a string to MacVim via event handling system. Each character will be
/// sent separately as if the user typed it.
- (void)sendStringToVim:(NSString*)chars withMods:(int)mods {
    for (NSUInteger i = 0; i < chars.length; i++) {
        unichar ch = [chars characterAtIndex:i];
        NSString *str = [NSString stringWithCharacters:&ch length:1];
        [self sendKeyToVim:str withMods:mods];
    }
}

#pragma mark Tests

- (void)testCompareSemanticVersions {
    // bogus values evaluate to 0
    XCTAssertEqual(0,  compareSemanticVersions(@"bogus", @""));
    XCTAssertEqual(0,  compareSemanticVersions(@"bogus", @"0"));
    XCTAssertEqual(0,  compareSemanticVersions(@"", @""));

    // single values
    XCTAssertEqual(1,  compareSemanticVersions(@"", @"1"));
    XCTAssertEqual(-1, compareSemanticVersions(@"1", @""));
    XCTAssertEqual(1,  compareSemanticVersions(@"100", @"101"));
    XCTAssertEqual(-1, compareSemanticVersions(@"101", @"100"));

    // multiple semantic values
    XCTAssertEqual(1,  compareSemanticVersions(@"100", @"100.1"));
    XCTAssertEqual(-1, compareSemanticVersions(@"100.1", @"100"));
    XCTAssertEqual(1,  compareSemanticVersions(@"100.2", @"100.3"));
    XCTAssertEqual(-1, compareSemanticVersions(@"100.10", @"100.2")); // double digit after the dot to make sure we are parsing it properly
    XCTAssertEqual(0,  compareSemanticVersions(@"234.5", @"234.5"));
    XCTAssertEqual(-1, compareSemanticVersions(@"234.5.1", @"234.5"));
    XCTAssertEqual(1,  compareSemanticVersions(@"234.5", @"234.5.0"));
}

/// Tests that parseOpenURL complies with the spec. See ":h macvim-url-handler".
- (void)testParseOpenURL {
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?"]], @{});
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo/bar"]], @{@"url": @"file:///foo/bar"});

    // Test that we correctly decode the URL, where special characters like space need to be double encoded.
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo/bar%2520file"]], @{@"url": @"file:///foo/bar%20file"});
    XCTAssertEqualObjects([[NSURL URLWithString:@"file:///foo/bar%20file"] path], @"/foo/bar file");
    // Test opportunistic single-encoding for compatibility with old behaviors and other tools.
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo/bar%20file"]], @{@"url": @"file:///foo/bar%20file"});

    // Test mixed single/double-encoding.
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo/bar%20%2520file%253F"]], @{@"url": @"file:///foo/bar%20%20file%3F"});

    // Test that with certain special characters like "&", you have to encode at least once, as otherwise it will be interpreted as a separator.
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo&bar"]], @{@"url": @"file:///foo"}); // lost the "bar" in the path
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo%26bar"]], @{@"url": @"file:///foo&bar"});
    XCTAssertEqualObjects([[NSURL URLWithString:@"file:///foo&bar"] path], @"/foo&bar");
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo%2526bar"]], @{@"url": @"file:///foo%26bar"});
    XCTAssertEqualObjects([[NSURL URLWithString:@"file:///foo%26bar"] path], @"/foo&bar");

    // Test that '%' in a file name is a special case, where only double-encoding works. The opportunistic single-encoding doesn't work here.
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo%bar"]], @{}); // This should fail at decoding step
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo%25bar"]], @{@"url": @"file:///foo%bar"}); // Not valid file URL
    XCTAssertEqualObjects([[NSURL URLWithString:@"file:///foo%bar"] path], nil); // Invalid decoded file URL leads to nil
    XCTAssertEqualObjects([MMAppController parseOpenURL:[NSURL URLWithString:@"mvim://open?url=file:///foo%2525bar"]], @{@"url": @"file:///foo%25bar"});
    XCTAssertEqualObjects([[NSURL URLWithString:@"file:///foo%25bar"] path], @"/foo%bar");
}

/// Test that the "Vim Tutor" menu item works and can be used to launch the
/// bundled vimtutor. Previously this was silently broken by Vim v8.2.3502
/// and fixed in https://github.com/macvim-dev/macvim/pull/1265.
- (void)testVimTutor {
    // Adding a new window is necessary for the vimtutor menu to show up as it's
    // not part of the global menu
    [self createTestVimWindow];

    MMAppController *app = MMAppController.sharedInstance;

    // Find the vimtutor menu and run it.
    NSMenu *mainMenu = [NSApp mainMenu];
    NSMenu *helpMenu = [mainMenu findHelpMenu];
    NSMenuItem *vimTutorMenu = nil;
    for (NSInteger i = 0; i < helpMenu.numberOfItems; ++i) {
        NSMenuItem *menuItem = [helpMenu itemAtIndex:i];
        if ([menuItem.title isEqualToString:@"Vim Tutor"])
            vimTutorMenu = menuItem;
    }
    XCTAssertNotNil(vimTutorMenu);
    XCTAssertEqual(vimTutorMenu.action, @selector(vimMenuItemAction:));
    [[[app keyVimController] windowController] vimMenuItemAction:vimTutorMenu];

    // Make sure the menu item actually opened a new window and point to a tutor buffer
    // Note that `vimtutor` opens Vim twice. Once to copy the file. Another time to
    // actually open the copied file. The first window closes itself immediately.
    [self waitForVimOpen];
    [self waitForVimOpenAndMessages];

    NSString *bufname = [[app keyVimController] evaluateVimExpression:@"bufname()"];
    XCTAssertTrue([bufname containsString:@"tutor"]);

    // Clean up
    [[app keyVimController] sendMessage:VimShouldCloseMsgID data:nil];
    [self waitForVimClose];
}

/// Test that opening Vim documentation from Help menu works as expected even
/// with odd characters.
- (void)testHelpMenuDocumentationTag {
    MMAppController *app = MMAppController.sharedInstance;
    XCTAssertEqual(0, app.vimControllers.count);

    [NSApp activateIgnoringOtherApps:YES];

    // Test help menu when no window is shown
    [app performActionForItem:@[@"", @"m'"]];
    [self waitForVimOpenAndMessages];
    MMVimController *vim = [app keyVimController];

    XCTAssertEqualObjects(@"help", [vim evaluateVimExpression:@"&buftype"]);
    NSString *curLine = [vim evaluateVimExpression:@"getline('.')"];
    XCTAssertTrue([curLine containsString:@"*m'*"]);
    [vim sendMessage:VimShouldCloseMsgID data:nil];
    vim = nil;
    [self waitForVimClose];

    // Test help menu when there's already a Vim window
    [app openNewWindow:NewWindowClean activate:YES];
    [self waitForVimOpenAndMessages];
    vim = [app keyVimController];

#define ASSERT_HELP_PATTERN(pattern) \
do { \
    [app performActionForItem:@[@"foobar.txt", @pattern]]; \
    [self waitForVimProcess]; \
    XCTAssertEqualObjects(@"help", [vim evaluateVimExpression:@"&buftype"]); \
    curLine = [vim evaluateVimExpression:@"getline('.')"]; \
    XCTAssertTrue([curLine containsString:@("*" pattern "*")]); \
} while(0)

    ASSERT_HELP_PATTERN("macvim-touchbar");
    ASSERT_HELP_PATTERN("++enc");
    ASSERT_HELP_PATTERN("v_CTRL-\\_CTRL-G");
    ASSERT_HELP_PATTERN("/\\%<v");

    // '<' characters need to be concatenated to not be interpreted as keys
    ASSERT_HELP_PATTERN("c_<Down>");
    ASSERT_HELP_PATTERN("c_<C-R>_<C-W>");

    // single-quote characters should be escaped properly when passed to help
    ASSERT_HELP_PATTERN("'display'");
    ASSERT_HELP_PATTERN("m'");

    // Test both single-quote and '<'
    ASSERT_HELP_PATTERN("/\\%<'m");
    ASSERT_HELP_PATTERN("'<");

#undef ASSERT_HELP_PATTERN

    // Clean up
    [vim sendMessage:VimShouldCloseMsgID data:nil];
    [self waitForVimClose];
}

/// Test that cmdline row calculation (used by MMCmdLineAlignBottom) is correct.
/// This is an integration test as the calculation is done in Vim, which has
/// special logic to account for "Press Enter" and "--more--" prompts when showing
/// messages.
- (void) testCmdlineRowCalculation {
    [self createTestVimWindow];

    [self sendStringToVim:@":set lines=10 columns=50\n" withMods:0]; // this test needs a sane window size
    [self waitForEventHandlingAndVimProcess];

    MMAppController *app = MMAppController.sharedInstance;
    MMTextView *textView = [[[[app keyVimController] windowController] vimView] textView];
    const int numLines = [textView maxRows];
    const int numCols = [textView maxColumns];

    // Define convenience macro (don't use functions to preserve line numbers in callstack)
#define ASSERT_NUM_CMDLINES(expected) \
do { \
    const int cmdlineRow = [[[app keyVimController] objectForVimStateKey:@"cmdline_row"] intValue]; \
    const int numBottomLines = numLines - cmdlineRow; \
    XCTAssertEqual(expected, numBottomLines); \
} while(0)

    // Default value
    [self waitForEventHandlingAndVimProcess];
    ASSERT_NUM_CMDLINES(1);

    // Print more lines than we have room for to trigger "Press Enter"
    [self sendStringToVim:@":echo join(repeat(['test line'], 3), \"\\n\")\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    ASSERT_NUM_CMDLINES(1);

    // Test non-1 cmdheight works
    [self sendStringToVim:@":set cmdheight=3\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    ASSERT_NUM_CMDLINES(3);

    // Test typing enough characters to cause cmdheight to grow
    [self sendStringToVim:[@":\"" stringByPaddingToLength:numCols * 3 - 1 withString:@"a" startingAtIndex:0] withMods:0];
    [self waitForEventHandlingAndVimProcess];
    ASSERT_NUM_CMDLINES(3);

    [self sendStringToVim:@"bbbb" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    ASSERT_NUM_CMDLINES(4);

    [self sendStringToVim:@"\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    ASSERT_NUM_CMDLINES(3);

    // Printing just enough lines within cmdheight should not affect anything
    [self sendStringToVim:@":echo join(repeat(['test line'], 3), \"\\n\")\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    ASSERT_NUM_CMDLINES(3);

    // Printing more lines than cmdheight will once again trigger "Press Enter"
    [self sendStringToVim:@":echo join(repeat(['test line'], 4), \"\\n\")\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    ASSERT_NUM_CMDLINES(1);

    // Printing more lines than the screen will trigger "--more--" prompt
    [self sendStringToVim:@":echo join(repeat(['test line'], 2000), \"\\n\")\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    ASSERT_NUM_CMDLINES(1);

#undef ASSERT_NUM_CMDLINES
}

/// Test that using "-monospace-" for system default monospace font works.
- (void) testGuifontSystemMonospace {
    [self createTestVimWindow];

    MMAppController *app = MMAppController.sharedInstance;
    MMTextView *textView = [[[[app keyVimController] windowController] vimView] textView];
    XCTAssertEqualObjects(@"Menlo-Regular", [[textView font] fontName]);

    [self sendStringToVim:@":set guifont=-monospace-\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects([textView font], [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]);

    [self sendStringToVim:@":set guifont=-monospace-Heavy:h12\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects([textView font], [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightHeavy]);

    [[[app keyVimController] windowController] fontSizeUp:nil];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects([textView font], [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightHeavy]);
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"&guifont"], @"-monospace-Heavy:h13");

    [[[app keyVimController] windowController] fontSizeDown:nil];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects([textView font], [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightHeavy]);
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"&guifont"], @"-monospace-Heavy:h12");
}

/// Test that dark mode settings work and the corresponding Vim bindings are functional.
///
/// Note that `v:os_appearance` and OSAppearanceChanged respond to the view's appearance
/// rather than the OS setting. When using manual light/dark or "use background" settings,
/// they do not reflect the current OS dark mode setting.
- (void) testDarkMode {
    [self createTestVimWindow];

    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;

    MMAppController *app = MMAppController.sharedInstance;
    MMVimView *vimView = [[[app keyVimController] windowController] vimView];

    // We just use the system appearance to determine the initial state. Otherwise
    // we have to change the system appearance to light mode first which we don't
    // have permission to do.
    const BOOL systemUsingDarkMode = [[ud stringForKey:@"AppleInterfaceStyle"] isEqualToString:@"Dark"];
    const NSAppearance *systemAppearance = systemUsingDarkMode ?
        [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua] : [NSAppearance appearanceNamed: NSAppearanceNameAqua];

    // Default setting uses system appearance
    XCTAssertEqualObjects(vimView.effectiveAppearance, systemAppearance);
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"v:os_appearance"], systemUsingDarkMode ? @"1" : @"0");

    // Manual Light / Dark mode setting
    [self setDefault:MMAppearanceModeSelectionKey toValue:[NSNumber numberWithInt:MMAppearanceModeSelectionLight]];
    [app refreshAllAppearances];
    [self waitForVimProcess];
    XCTAssertEqualObjects(vimView.effectiveAppearance, [NSAppearance appearanceNamed: NSAppearanceNameAqua]);
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"v:os_appearance"], @"0");

    // Set up a listener for OSAppearanceChanged event to make sure it's called
    // when the view appearance changes.
    [self sendStringToVim:@":let g:os_appearance_changed_called=0\n" withMods:0];
    [self sendStringToVim:@":autocmd OSAppearanceChanged * let g:os_appearance_changed_called+=1\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];

    [self setDefault:MMAppearanceModeSelectionKey toValue:[NSNumber numberWithInt:MMAppearanceModeSelectionDark]];
    [app refreshAllAppearances];
    [self waitForVimProcess];
    XCTAssertEqualObjects(vimView.effectiveAppearance, [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]);
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"v:os_appearance"], @"1");
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"g:os_appearance_changed_called"], @"1");

    // "Use background" setting
    [self sendStringToVim:@":set background=dark\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];

    [self setDefault:MMAppearanceModeSelectionKey toValue:[NSNumber numberWithInt:MMAppearanceModeSelectionBackgroundOption]];
    [app refreshAllAppearances];
    [self waitForVimProcess];
    XCTAssertEqualObjects(vimView.effectiveAppearance, [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]);
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"v:os_appearance"], @"1");
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"g:os_appearance_changed_called"], @"1"); // we stayed in dark mode, so OSAppearnceChanged didn't trigger

    [self sendStringToVim:@":set background=light\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(vimView.effectiveAppearance, [NSAppearance appearanceNamed: NSAppearanceNameAqua]);
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"v:os_appearance"], @"0");
    XCTAssertEqualObjects([[app keyVimController] evaluateVimExpression:@"g:os_appearance_changed_called"], @"2");

    // Restore original settings and make sure it's reset
    [self resetDefaults];
    [app refreshAllAppearances];
    XCTAssertEqualObjects(vimView.effectiveAppearance, systemAppearance);
}

/// Test that document icon is shown in title bar when enabled.
- (void) testTitlebarDocumentIcon {
    [self createTestVimWindow];

    MMAppController *app = MMAppController.sharedInstance;
    NSWindow *win = [[[app keyVimController] windowController] window];

    // Untitled documents have no icons
    XCTAssertEqualObjects(@"", win.representedFilename);

    // Test that the document icon is shown when a file (gui_mac.txt) is opened by querying "representedFilename"
    [self sendStringToVim:@":help macvim\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    NSString *gui_mac_path = [[NSBundle mainBundle] pathForResource:@"gui_mac.txt" ofType:nil inDirectory:@"vim/runtime/doc"];
    XCTAssertEqualObjects(gui_mac_path, win.representedFilename);

    // Change setting to hide the document icon
    [self setDefault:MMTitlebarShowsDocumentIconKey toValue:@NO];

    // Test that there is no document icon shown
    [app refreshAllAppearances];
    XCTAssertEqualObjects(@"", win.representedFilename);

    // Change setting back to show the document icon. Test that the path was remembered and icon is shown.
    [self setDefault:MMTitlebarShowsDocumentIconKey toValue:@YES];
    [app refreshAllAppearances];
    XCTAssertEqualObjects(gui_mac_path, win.representedFilename);

    // Close the file to go back to untitled document and make sure no icon is shown
    [self sendStringToVim:@":q\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(@"", win.representedFilename);
}

/// Test resizing the MacVim window properly resizes Vim
- (void) testWindowResize {
    [self createTestVimWindow];

    MMAppController *app = MMAppController.sharedInstance;
    NSWindow *win = [[[app keyVimController] windowController] window];
    MMVimView *vimView = [[[app keyVimController] windowController] vimView];
    MMTextView *textView = [[[[app keyVimController] windowController] vimView] textView];

    // Set a default 30,80 base size for the entire test
    [self sendStringToVim:@":set lines=30 columns=80\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqual(30, textView.maxRows);
    XCTAssertEqual(80, textView.maxColumns);

    const NSRect winFrame = win.frame;

    {
        // Test basic resizing functionality. Make sure text view is updated properly
        NSRect newFrame = winFrame;
        newFrame.size.width -= textView.cellSize.width;
        newFrame.size.height -= textView.cellSize.height;

        [win setFrame:newFrame display:YES];
        XCTAssertEqual(30, textView.maxRows);
        XCTAssertEqual(80, textView.maxColumns);
        [self waitForVimProcess];
        XCTAssertEqual(29, textView.maxRows);
        XCTAssertEqual(79, textView.maxColumns);

        [win setFrame:winFrame display:YES];
        [self waitForVimProcess];
        XCTAssertEqual(30, textView.maxRows);
        XCTAssertEqual(80, textView.maxColumns);
    }

    {
        // Test rapid resizing where we resize faster than Vim can handle. We
        // should be updating a pending size indicating what we expect Vim's
        // size should be and use that as the cache. Previously we had a bug
        // we we used the outdated size as cache instead leading to rapid
        // resizing sometimes leading to stale sizes.

        // This kind of situation could occur if say Vim is stalled for a bit
        // and we resized the window multiple times. We don't rate limit unlike
        // live resizing since usually it's not needed.
        NSRect newFrame = winFrame;
        newFrame.size.width -= textView.cellSize.width;
        newFrame.size.height -= textView.cellSize.height;

        [win setFrame:newFrame display:YES];
        XCTAssertEqual(30, textView.maxRows);
        XCTAssertEqual(80, textView.maxColumns);
        XCTAssertEqual(29, textView.pendingMaxRows);
        XCTAssertEqual(79, textView.pendingMaxColumns);

        [win setFrame:winFrame display:YES];
        XCTAssertEqual(30, textView.maxRows);
        XCTAssertEqual(80, textView.maxColumns);
        XCTAssertEqual(30, textView.pendingMaxRows);
        XCTAssertEqual(80, textView.pendingMaxColumns);

        [self waitForVimProcess];
        XCTAssertEqual(30, textView.maxRows);
        XCTAssertEqual(80, textView.maxColumns);
    }

    {
        // Test rapid resizing again, but this time we don't resize back to the
        // original size, but instead incremented multiple times. Just to make
        // sure we actually get set to the final size.
        NSRect newFrame = winFrame;
        for (int i = 0; i < 5; i++) {
            newFrame.size.width += textView.cellSize.width;
            newFrame.size.height += textView.cellSize.height;
            [win setFrame:newFrame display:YES];
        }
        XCTAssertEqual(30, textView.maxRows);
        XCTAssertEqual(80, textView.maxColumns);
        XCTAssertEqual(35, textView.pendingMaxRows);
        XCTAssertEqual(85, textView.pendingMaxColumns);

        [self waitForVimProcess];
        XCTAssertEqual(35, textView.maxRows);
        XCTAssertEqual(85, textView.maxColumns);

        [win setFrame:winFrame display:YES]; // reset back to original size
        [self waitForVimProcess];
        XCTAssertEqual(30, textView.maxRows);
        XCTAssertEqual(80, textView.maxColumns);
    }

    {
        // Test live resizing (e.g. when user drags the window edge to resize).
        // We rate limit the number of messages we send to Vim so if there are
        // multiple resize events they will be sequenced to avoid overloading Vim.
        forceInLiveResize = YES; // simulate live resizing which can only be initiated by a user
        [vimView viewWillStartLiveResize];

        NSRect newFrame = winFrame;
        for (int i = 0; i < 5; i++) {
            newFrame.size.width += textView.cellSize.width;
            newFrame.size.height += textView.cellSize.height;
            [win setFrame:newFrame display:YES];
        }

        // The first time Vim processes this it should have only received the first message
        // due to rate limiting.
        XCTAssertEqual(30, textView.maxRows);
        XCTAssertEqual(80, textView.maxColumns);
        XCTAssertEqual(31, textView.pendingMaxRows);
        XCTAssertEqual(81, textView.pendingMaxColumns);

        // After Vim has processed the messages it should now have the final size
        [self waitForVimProcess]; // first wait for Vim to respond it processed the first message, where we send off the second one
        [self waitForVimProcess]; // Vim should now have processed the last message
        XCTAssertEqual(35, textView.maxRows);
        XCTAssertEqual(85, textView.maxColumns);
        XCTAssertEqual(35, textView.pendingMaxRows);
        XCTAssertEqual(85, textView.pendingMaxColumns);

        forceInLiveResize = NO;
        [vimView viewDidEndLiveResize];
        [self waitForVimProcess];
        XCTAssertEqual(35, textView.maxRows);
        XCTAssertEqual(85, textView.maxColumns);

        [win setFrame:winFrame display:YES]; // reset back to original size
        [self waitForEventHandlingAndVimProcess];
        XCTAssertEqual(30, textView.maxRows);
        XCTAssertEqual(80, textView.maxColumns);
    }
}

/// Test resizing the Vim view to match window size (go+=k / full screen) works
/// and produces a stable image.
- (void) testResizeVimView {
    [self createTestVimWindow];

    MMAppController *app = MMAppController.sharedInstance;
    MMWindowController *win = [[app keyVimController] windowController];
    MMTextView *textView = [[[[app keyVimController] windowController] vimView] textView];

    [self sendStringToVim:@":set guioptions+=k guifont=Menlo:h10\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];

    // Set a default 30,80 base size for the entire test
    [self sendStringToVim:@":set lines=30 columns=80\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqual(textView.maxRows, 30);
    XCTAssertEqual(textView.maxColumns, 80);

    // Test that setting a bigger font will trigger a resize of Vim view to
    // smaller grid, but also block intermediary rendering to avoid flicker.
    [self sendStringToVim:@":set guifont=Menlo:h13\n" withMods:0];
    [self waitForVimMessage:SetFontMsgID blockFutureMessages:YES];
    XCTAssertEqual(textView.maxRows, 30);
    XCTAssertEqual(textView.maxColumns, 80);
    XCTAssertLessThan(textView.pendingMaxRows, 30); // confirms that we have an outstanding resize request to make it smaller
    XCTAssertLessThan(textView.pendingMaxColumns, 80);
    XCTAssertTrue(win.isRenderBlocked);
    XCTAssertEqual(textView.drawRectOffset.width, 0);
    XCTAssertEqual(textView.drawRectOffset.height, 0);
    // Vim has responded to the size change. We should now have unblocked rendering.
    [self waitForVimMessage:SetTextDimensionsNoResizeWindowMsgID blockFutureMessages:YES];
    XCTAssertLessThan(textView.maxRows, 30);
    XCTAssertLessThan(textView.maxColumns, 80);
    XCTAssertFalse(win.isRenderBlocked);

    // Make sure if we set it again to the same font, we won't block since we
    // didn't actually resize anything.
    [self sendStringToVim:@":set guifont=Menlo:h13\n" withMods:0];
    [self waitForVimMessage:SetFontMsgID blockFutureMessages:YES];
    XCTAssertFalse(win.isRenderBlocked);

    // Set it back and make sure it went back to the original rows/cols
    [self sendStringToVim:@":set guifont=Menlo:h10\n" withMods:0];
    [self waitForVimMessage:SetTextDimensionsNoResizeWindowMsgID blockFutureMessages:YES];
    XCTAssertEqual(textView.maxRows, 30);
    XCTAssertEqual(textView.maxColumns, 80);

    // Test making a new tab would do the same
    [self sendStringToVim:@":tabnew\n" withMods:0];
    [self waitForVimMessage:ShowTabBarMsgID blockFutureMessages:YES];
    XCTAssertEqual(textView.maxRows, 30);
    XCTAssertLessThan(textView.pendingMaxRows, 30);
    XCTAssertEqual(textView.drawRectOffset.height, MMTablineHeight);
    XCTAssertTrue(win.isRenderBlocked);
    [self waitForVimMessage:SetTextDimensionsNoResizeWindowMsgID blockFutureMessages:YES];
    XCTAssertLessThan(textView.maxRows, 30);
    XCTAssertEqual(textView.drawRectOffset.height, 0);
    XCTAssertFalse(win.isRenderBlocked);
    [self blockVimProcessInput:NO];

    // Repeat the same font size change test in full screen to exercise that
    // code path. In particular, it should act like go+=k even if the option
    // was not explicitly set.
    [self setDefault:MMNativeFullScreenKey toValue:@NO]; // non-native is faster so use that
    [self sendStringToVim:@":set guioptions-=k fullscreen\n" withMods:0];
    [self waitForVimMessage:EnterFullScreenMsgID blockFutureMessages:YES];
    XCTAssertTrue(win.isRenderBlocked);
    [self blockVimProcessInput:NO];
    [self waitForFullscreenTransitionIsEnter:YES isNative:NO];
    XCTAssertFalse(win.isRenderBlocked);
    int fuRows = textView.maxRows;
    int fuCols = textView.maxColumns;
    [self sendStringToVim:@":set guifont=Menlo:h13\n" withMods:0];
    [self waitForVimMessage:SetFontMsgID blockFutureMessages:YES];
    XCTAssertEqual(textView.maxRows, fuRows);
    XCTAssertEqual(textView.maxColumns, fuCols);
    XCTAssertLessThan(textView.pendingMaxRows, fuRows);
    XCTAssertLessThan(textView.pendingMaxColumns, fuCols);
    XCTAssertTrue(win.isRenderBlocked);
    [self waitForVimMessage:SetTextDimensionsNoResizeWindowMsgID blockFutureMessages:YES];
    XCTAssertLessThan(textView.maxRows, fuRows);
    XCTAssertLessThan(textView.maxColumns, fuCols);
    XCTAssertFalse(win.isRenderBlocked);
}

#pragma mark Tabs tests

- (void)testTabColors {
    [self createTestVimWindow];

    MMAppController *app = MMAppController.sharedInstance;
    MMVimView *vimView = [[[app keyVimController] windowController] vimView];
    MMTabline *tabline = [vimView tabline];

    // Test Vim colorscheme mode
    [self setDefault:MMTabColorsModeKey toValue:@(MMTabColorsModeVimColorscheme)];

    [self sendStringToVim:@":hi Normal guifg=#ff0000 guibg=#00ff00\n" withMods:0];
    [self waitForVimProcess];
    [self sendStringToVim:@":hi TabLineSel guifg=#010203 guibg=#040506\n" withMods:0];
    [self sendStringToVim:@":hi clear TabLineFill\n" withMods:0];
    [self sendStringToVim:@":hi TabLine guifg=#111213 guibg=NONE gui=inverse\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];

    // Normal highlight groups
    XCTAssertEqualObjects(tabline.tablineSelBgColor, [NSColor colorWithRgbInt:0x040506]);
    XCTAssertEqualObjects(tabline.tablineSelFgColor, [NSColor colorWithRgbInt:0x010203]);
    // Cleared highlight group should be transparent and fall through to Normal group
    XCTAssertEqualObjects(tabline.tablineFillBgColor, [NSColor colorWithRgbInt:0x00ff00]);
    XCTAssertEqualObjects(tabline.tablineFillFgColor, [NSColor colorWithRgbInt:0xff0000]);
    // One color is transparent, and inversed fg/bg
    XCTAssertEqualObjects(tabline.tablineBgColor, [NSColor colorWithRgbInt:0x111213]);
    XCTAssertEqualObjects(tabline.tablineFgColor, [NSColor colorWithRgbInt:0x00ff00]);

    // Cleared highlight group with inversed fg/bg
    [self sendStringToVim:@":hi TabLineFill gui=inverse\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(tabline.tablineFillBgColor, [NSColor colorWithRgbInt:0xff0000]);
    XCTAssertEqualObjects(tabline.tablineFillFgColor, [NSColor colorWithRgbInt:0x00ff00]);

    // Test automatic colors mode
    // Selected tab should have the exact same background as Normal colors
    [self setDefault:MMTabColorsModeKey toValue:@(MMTabColorsModeAutomatic)];
    [vimView updateTablineColors:MMTabColorsModeAutomatic];
    XCTAssertEqualObjects(tabline.tablineSelBgColor, [NSColor colorWithRgbInt:0x00ff00]);

    // Test default colors mode
    // We just verify that the colors changed, rather than asserting the exact
    // colors to make it easy to update tuning on them in the future.
    [self setDefault:MMTabColorsModeKey toValue:@(MMTabColorsModeDefaultColors)];
    [vimView updateTablineColors:MMTabColorsModeDefaultColors];

    vimView.window.appearance = [NSAppearance appearanceNamed: NSAppearanceNameAqua];
    [self waitForEventHandling];
    XCTAssertEqual(tabline.tablineFillBgColor.colorSpace.colorSpaceModel, NSColorSpaceModelGray);
    XCTAssertGreaterThan(tabline.tablineFillBgColor.whiteComponent, 0.5);

    vimView.window.appearance = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];
    [self waitForEventHandling];
    XCTAssertLessThan(tabline.tablineFillBgColor.whiteComponent, 0.5);
}

#pragma mark Full screen tests

- (void)waitForNativeFullscreenEnter {
    XCTestExpectation *expectation = [self expectationWithDescription:@"NativeFullscreenEnter"];

    SEL sel = @selector(windowDidEnterFullScreen:);
    Method method = class_getInstanceMethod([MMWindowController class], sel);

    IMP origIMP = method_getImplementation(method);
    IMP newIMP = imp_implementationWithBlock(^(id self, id notification) {
        typedef void (*fn)(id,SEL,NSNotification*);
        ((fn)origIMP)(self, sel, notification);
        [expectation fulfill];
    });

    method_setImplementation(method, newIMP);
    [self waitForExpectations:@[expectation] timeout:10];
    method_setImplementation(method, origIMP);
}

- (void)waitForNativeFullscreenExit {
    XCTestExpectation *expectation = [self expectationWithDescription:@"NativeFullscreenExit"];

    SEL sel = @selector(windowDidExitFullScreen:);
    Method method = class_getInstanceMethod([MMWindowController class], sel);

    IMP origIMP = method_getImplementation(method);
    IMP newIMP = imp_implementationWithBlock(^(id self, id notification) {
        typedef void (*fn)(id,SEL,NSNotification*);
        ((fn)origIMP)(self, sel, notification);
        [expectation fulfill];
    });

    method_setImplementation(method, newIMP);
    [self waitForExpectations:@[expectation] timeout:10];
    method_setImplementation(method, origIMP);
}

- (void)waitForFullscreenTransitionIsEnter:(BOOL)enter isNative:(BOOL)native {
    if (native) {
        if (enter) {
            [self waitForNativeFullscreenEnter];
        } else {
            [self waitForNativeFullscreenExit];
        }
    } else {
        [self waitForEventHandlingAndVimProcess];
        [self waitForEventHandlingAndVimProcess]; // wait one more cycle to make sure we finished the transition
    }
}

/// Inject a mouse click at the window border to pretend a user has interacted
/// with the window. Currently macOS 14/15 seems to exhibit a bug (only in VMs)
/// where full screen restore would restore to the last window frame that a
/// user has set manually rather than any programmatically set frames. This bug
/// does not occur in a real MacBook however, makes the issue hard to debug.
/// This workaround allows tests to pass consistently either in CI (run in a
/// VM) or on a developer machine.
/// This issue was filed as FB16348262 with Apple.
- (void)injectFakeUserWindowInteraction:(NSWindow *)window {
    NSTimeInterval timestamp = [[NSProcessInfo processInfo] systemUptime];
    static NSInteger eventNumber = 100000;
    NSApplication* app = [NSApplication sharedApplication];
    for (int i = 0; i < 2; i++) {
        NSEvent *mouseEvent = [NSEvent mouseEventWithType:(i == 0 ? NSEventTypeLeftMouseDown : NSEventTypeLeftMouseUp)
                                                 location:NSMakePoint(0,0)
                                            modifierFlags:0
                                                timestamp:timestamp + i * 0.001
                                             windowNumber:[window windowNumber]
                                                  context:0
                                              eventNumber:eventNumber++
                                               clickCount:1
                                                 pressure:1];
        [app postEvent:mouseEvent atStart:NO];
    }
}

/// Utility to test full screen functionality in both non-native/native full
/// screen.
- (void) fullScreenTestWithNative:(BOOL)native {
    // Change native full screen setting
    [self setDefault:MMNativeFullScreenKey toValue:@(native)];

    // The launch animation interferes with setting the frames in quick sequence
    // and the user action injection below. Disable it.
    [self setDefault:MMDisableLaunchAnimationKey toValue:@YES];

    // In native full screen, non-smooth resize is more of an edge case due to
    // macOS's handling of resize constraints. Set this option to exercise that.
    [self setDefault:MMSmoothResizeKey toValue:@NO];

    [self createTestVimWindow];

    MMAppController *app = MMAppController.sharedInstance;
    MMWindowController *winController = app.keyVimController.windowController;
    MMTextView *textView = [[winController vimView] textView];

    const int numRows = MMMinRows + 10;
    const int numColumns = MMMinColumns + 10;
    [self sendStringToVim:@":set guioptions-=k guifont=Menlo:h10\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    [self sendStringToVim:[NSString stringWithFormat:@":set lines=%d columns=%d\n", numRows, numColumns] withMods:0];
    [self waitForEventHandlingAndVimProcess];

    XCTAssertEqual(textView.maxRows, numRows);
    XCTAssertEqual(textView.maxColumns, numColumns);

    // Intentionally nudge the frame size to be not fixed increment of cell size.
    // This helps to test that we restore the window properly when leaving full
    // screen later.
    NSRect newFrame = winController.window.frame;
    newFrame.size.width += 1;
    newFrame.size.height += 2;
    [winController.window setFrame:newFrame display:YES];
    [self waitForEventHandlingAndVimProcess];

    NSRect origFrame = winController.window.frame;
    NSSize origResizeIncrements = winController.window.contentResizeIncrements;

    XCTAssertEqual(textView.maxRows, numRows);
    XCTAssertEqual(textView.maxColumns, numColumns);

    [self injectFakeUserWindowInteraction:winController.window];

    // 1. Enter full screen. Check that the states are properly changed.
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:native];
    XCTAssertTrue([winController fullScreenEnabled]);
    if (native) {
        XCTAssertTrue([winController.window isKindOfClass:[MMWindow class]]);
    } else {
        XCTAssertTrue([winController.window isKindOfClass:[MMFullScreenWindow class]]);
    }

    // 2. Exit full screen. Confirm state changes and proper window restore.
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:native];

    XCTAssertFalse([winController fullScreenEnabled]);
    XCTAssertTrue([winController.window isKindOfClass:[MMWindow class]]);

    XCTAssertEqual(textView.maxRows, numRows);
    XCTAssertEqual(textView.maxColumns, numColumns);
    XCTAssertTrue(NSEqualRects(origFrame, winController.window.frame),
                  @"Expected frame to be %@, but was %@",
                  NSStringFromRect(origFrame),
                  NSStringFromRect(winController.window.frame));
    XCTAssertTrue(NSEqualSizes(origResizeIncrements, winController.window.contentResizeIncrements),
                  @"Expected resize increments to be %@, but was %@",
                  NSStringFromSize(origResizeIncrements),
                  NSStringFromSize(winController.window.contentResizeIncrements));

    // 3. Enter full screen again
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:native];
    XCTAssertTrue([winController fullScreenEnabled]);

    // 3.1 Test that resizing the vim view does not work when in full screen as we fix the window size instead
    const int fuRows = textView.maxRows;
    const int fuCols = textView.maxColumns;
    XCTAssertNotEqual(10, fuRows); // just some basic assumptions as full screen should have more rows/cols than this
    XCTAssertNotEqual(30, fuCols);
    [self sendStringToVim:@":set lines=10\n" withMods:0];
    [self sendStringToVim:@":set columns=30\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    [self waitForEventHandlingAndVimProcess]; // need to wait twice to allow full screen to force it back
    XCTAssertEqual(fuRows, textView.maxRows);
    XCTAssertEqual(fuCols, textView.maxColumns);

    // 3.2 Set font to larger size to test that on restore we properly fit the
    // content back to the window of same size, but with fewer lines/columns.
    [self sendStringToVim:@":set guifont=Menlo:h13\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];

    // 4. Exit full screen. Confirm the restored window has fewer lines but same size.
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:native];

    XCTAssertLessThan(textView.maxRows, numRows); // fewer lines/columns due to fitting
    XCTAssertLessThan(textView.maxColumns, numColumns);
    XCTAssertTrue(NSEqualRects(winController.window.frame, winController.window.frame),
                  @"Expected frame to be %@, but was %@",
                  NSStringFromRect(origFrame),
                  NSStringFromRect(winController.window.frame));

    // Now, set the rows/columns to minimum allowed by MacVim to test that on
    // restore we will obey that and resize window if necessary.
    [self sendStringToVim:@":set guifont=Menlo:h10\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    [self sendStringToVim:[NSString stringWithFormat:@":set lines=%d columns=%d\n", MMMinRows, MMMinColumns] withMods:0];
    [self waitForEventHandlingAndVimProcess];
    origFrame = winController.window.frame;

    [self injectFakeUserWindowInteraction:winController.window];

    // 5. Enter full screen again.
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:native];

    // 5.1. Set font to larger size. Unlike last time, on restore the window
    // will be larger this time because we will end up with too few
    // lines/columns if we try to fit within the content.
    [self sendStringToVim:@":set guifont=Menlo:h13\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];

    // 6. Exit full screen. Confirm the restored window has same number of
    // lines but a larger size due to the need to fit the min lines/columns.
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:native];

    XCTAssertEqual(MMMinRows, textView.maxRows);
    XCTAssertEqual(MMMinColumns, textView.maxColumns);
    XCTAssertTrue(winController.window.frame.size.width > origFrame.size.width || winController.window.frame.size.height > origFrame.size.height,
                  @"Expected final frame %@ to be larger than %@",
                  NSStringFromSize(winController.window.frame.size),
                  NSStringFromSize(origFrame.size));
}

- (void) testFullScreenNonNative {
    [self fullScreenTestWithNative:NO];
}

- (void) testFullScreenNative {
    [self fullScreenTestWithNative:YES];
}

/// Utility to test delayed full screen scenario where 'fullscreen' was
/// specified in gvimrc which requires the app to delay the full screen
/// process until the Vim window has been presented.
- (void)fullScreenDelayedTestWithNative:(BOOL)native fuoptEmpty:(BOOL)fuoptEmpty {
    // Change native full screen setting
    [self setDefault:MMNativeFullScreenKey toValue:@(native)];

    if (fuoptEmpty)
        XCTAssertFalse(native);

    MMAppController *app = MMAppController.sharedInstance;

    // Override the gvimrc to go full screen right on startup
    NSURL *gvimrcPath = [self tempFile:@"gvimrc"];
    const NSString *gvimContents = fuoptEmpty ? @"set lines=35 columns=45 fuopt= fullscreen" : @"set lines=35 columns=45 fullscreen";
    if (![gvimContents writeToURL:gvimrcPath atomically:NO encoding:NSUTF8StringEncoding error:nil]) {
        XCTFail(@"Failed to write gvimrc file");
    }

    [self createTestVimWindowWithExtraArgs:@[@"-U", gvimrcPath.path]];

    MMWindowController *winController = app.keyVimController.windowController;
    MMTextView *textView = [[winController vimView] textView];
    XCTAssertTrue([winController fullScreenEnabled]);

    [self waitForFullscreenTransitionIsEnter:YES isNative:native];

    const int fuRows = textView.maxRows;
    const int fuCols = textView.maxColumns;
    if (fuoptEmpty) {
        XCTAssertEqual(fuRows, 35);
        XCTAssertEqual(fuCols, 45);
    } else {
        XCTAssertGreaterThan(fuRows, 35);
        XCTAssertGreaterThan(fuCols, 45);
    }

    // Exit full screen
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:native];

    XCTAssertFalse([winController fullScreenEnabled]);
    XCTAssertEqual(textView.maxRows, 35);
    XCTAssertEqual(textView.maxColumns, 45);

    // Enter full screen again. The purpose of this is to check that the behavior and results are the same as entering on startup
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:native];

    XCTAssertTrue([winController fullScreenEnabled]);
    XCTAssertEqual(textView.maxRows, fuRows);
    XCTAssertEqual(textView.maxColumns, fuCols);
}

- (void)testFullScreenDelayedNonNative {
    [self fullScreenDelayedTestWithNative:NO fuoptEmpty:NO];
}

- (void)testFullScreenDelayedNonNativeEmptyFuopt {
    [self fullScreenDelayedTestWithNative:NO fuoptEmpty:YES];
}

- (void)testFullScreenDelayedNative {
    [self fullScreenDelayedTestWithNative:YES fuoptEmpty:NO];
}

/// Test setting 'fuoptions' with non-native full screen.
- (void) testFullScreenNonNativeOptions {
    // Change native full screen setting
    [self setDefault:MMNativeFullScreenKey toValue:@NO];

    [self createTestVimWindow];

    MMAppController *app = MMAppController.sharedInstance;
    MMWindowController *winController = app.keyVimController.windowController;
    MMVimView *vimView = [winController vimView];
    MMTextView *textView = [vimView textView];

    // Test maxvert/maxhorz
    [self sendStringToVim:@":set lines=10\n" withMods:0];
    [self sendStringToVim:@":set columns=30\n" withMods:0];
    [self sendStringToVim:@":set fuoptions=\n" withMods:0];
    [self waitForVimProcess];

    [self injectFakeUserWindowInteraction:winController.window];

    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:NO];
    XCTAssertEqual(textView.maxRows, 10);
    XCTAssertEqual(textView.maxColumns, 30);
    XCTAssertGreaterThan(vimView.frame.origin.x, 0);
    XCTAssertGreaterThan(vimView.frame.origin.y, 0);
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:NO];
    XCTAssertEqual(vimView.frame.origin.x, 0);
    XCTAssertEqual(vimView.frame.origin.y, 0);
    [self sendStringToVim:@":set fuoptions=maxvert\n" withMods:0];
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:NO];
    XCTAssertGreaterThan(textView.maxRows, 10);
    XCTAssertEqual(textView.maxColumns, 30);
    XCTAssertGreaterThan(vimView.frame.origin.x, 0);
    XCTAssertEqual(vimView.frame.origin.y, 0);
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:NO];
    XCTAssertEqual(vimView.frame.origin.x, 0);
    XCTAssertEqual(vimView.frame.origin.y, 0);
    [self sendStringToVim:@":set fuoptions=maxhorz\n" withMods:0];
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:NO];
    XCTAssertEqual(textView.maxRows, 10);
    XCTAssertGreaterThan(textView.maxColumns, 30);
    XCTAssertEqual(vimView.frame.origin.x, 0);
    XCTAssertGreaterThan(vimView.frame.origin.y, 0);
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:NO];
    XCTAssertEqual(vimView.frame.origin.x, 0);
    XCTAssertEqual(vimView.frame.origin.y, 0);
    [self sendStringToVim:@":set fuoptions=maxhorz,maxvert\n" withMods:0];
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:NO];
    XCTAssertGreaterThan(textView.maxRows, 10);
    XCTAssertGreaterThan(textView.maxColumns, 30);
    XCTAssertEqual(vimView.frame.origin.x, 0);
    XCTAssertEqual(vimView.frame.origin.y, 0);

    // Test background color
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithArgbInt:0xff000000]); // default is black

    // Make sure changing colorscheme doesn't override the background color unlike in non-full screen mode
    [self sendStringToVim:@":color desert\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithArgbInt:0xff000000]);

    // Changing fuoptions should update the background color immediately
    [self sendStringToVim:@":set fuoptions=background:Normal\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithArgbInt:0xff333333]);

    // And switching colorscheme should also update the color as well
    [self sendStringToVim:@":color blue\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithArgbInt:0xff000087]);

    // Test parsing manual colors in both 8-digit mode (alpha is ignored) and 6-digit mode
    [self sendStringToVim:@":set fuoptions=background:#11234567\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithArgbInt:0xff234567]);
    [self sendStringToVim:@":set fuoptions=background:#abcdef\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithArgbInt:0xffabcdef]);

    // Test setting transparency while in full screen. We always set the alpha of the background color to 0.001 when transparency is set.
    [self sendStringToVim:@":set fuoptions=background:#ffff00\n:set transparency=50\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithRed:1 green:1 blue:0 alpha:0.001]);

    [self sendStringToVim:@":set fuoptions=background:#00ff00\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithRed:0 green:1 blue:0 alpha:0.001]);

    [self sendStringToVim:@":set transparency=0\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithRed:0 green:1 blue:0 alpha:1]);

    // Test setting transparency outside of full screen and make sure it still works
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:NO];
    [self sendStringToVim:@":set transparency=50 fuoptions=background:#0000ff\n" withMods:0];
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:NO];
    XCTAssertEqualObjects(winController.window.backgroundColor, [NSColor colorWithRed:0 green:0 blue:1 alpha:0.001]);
}

/// Test that non-native full screen can handle multiple screens. This test
/// will only run when the machine has 2 monitors and will therefore be skipped
/// in CI.
- (void) testFullScreenNonNativeMultiScreen {
    XCTSkipIf(NSScreen.screens.count <= 1);

    // Change native full screen setting
    [self setDefault:MMNativeFullScreenKey toValue:@NO];

    [self createTestVimWindow];
    [self sendStringToVim:@":set lines=45 columns=65\n" withMods:0];
    [self waitForVimProcess];

    MMAppController *app = MMAppController.sharedInstance;
    MMWindowController *winController = app.keyVimController.windowController;
    MMVimView *vimView = [winController vimView];
    MMTextView *textView = [vimView textView];

    // Test that window restore properly moves the original window to the new screen
    [winController.window setFrameOrigin:NSScreen.screens[0].frame.origin];
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:NO];
    [winController.window setFrameOrigin:NSScreen.screens[1].frame.origin];
    [self waitForEventHandling];
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:NO];
    XCTAssertTrue(NSPointInRect(winController.window.frame.origin, NSScreen.screens[1].frame));
    XCTAssertEqual(textView.maxRows, 45);
    XCTAssertEqual(textView.maxColumns, 65);
    [self sendStringToVim:@":set fu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:YES isNative:NO];
    [winController.window setFrameOrigin:NSScreen.screens[0].frame.origin];
    [self waitForEventHandling];
    [self sendStringToVim:@":set nofu\n" withMods:0];
    [self waitForFullscreenTransitionIsEnter:NO isNative:NO];
    XCTAssertTrue(NSPointInRect(winController.window.frame.origin, NSScreen.screens[0].frame));
}

#pragma mark Vim IPC

/// Test the selected text related IPC APIs
- (void)testIPCSelectedText {
    [self createTestVimWindow];
    [self sendStringToVim:@":call setline(1,['abcd','efgh','ijkl'])\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];

    MMAppController *app = MMAppController.sharedInstance;
    MMVimController *vc = app.keyVimController;

    // Set up register
    [self sendStringToVim:@"ggyy" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    NSString *regcontents = [vc evaluateVimExpression:@"getreg()"];
    XCTAssertEqualObjects(regcontents, @"abcd\n");

    // Get selected texts in visual mode
    XCTAssertFalse([vc hasSelectedText]);
    XCTAssertNil([vc selectedText]);
    [self sendStringToVim:@"lvjl" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertTrue([vc hasSelectedText]);
    XCTAssertEqualObjects([vc selectedText], @"bcd\nefg");

    // Get selected texts in visual line mode
    [self sendStringToVim:@"V" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertTrue([vc hasSelectedText]);
    XCTAssertEqualObjects([vc selectedText], @"abcd\nefgh\n");

    // Get selected texts in visual block mode
    [self sendKeyToVim:@"v" withMods:NSEventModifierFlagControl];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertTrue([vc hasSelectedText]);
    XCTAssertEqualObjects([vc selectedText], @"bc\nfg");

    // Set selected texts in visual block mode
    NSString *changedtick = [vc evaluateVimExpression:@"b:changedtick"];
    [vc replaceSelectedText:@"xyz\n1234"];
    NSString *changedtick2 = [vc evaluateVimExpression:@"b:changedtick"];
    XCTAssertEqualObjects([vc evaluateVimExpression:@"getline(1)"], @"axyz d");
    XCTAssertEqualObjects([vc evaluateVimExpression:@"getline(2)"], @"e1234h");
    XCTAssertEqualObjects([vc evaluateVimExpression:@"getline(3)"], @"ijkl");
    XCTAssertNotEqualObjects(changedtick, changedtick2);

    // Make sure replacing texts when nothing is selected won't set anything
    [vc replaceSelectedText:@"foobar"];
    NSString *changedtick3 = [vc evaluateVimExpression:@"b:changedtick"];
    XCTAssertEqualObjects(changedtick2, changedtick3);

    // Select in visual block again but send a different number of lines, make sure we intentionaly won't treat it as block text
    [self sendStringToVim:@"ggjjvll" withMods:0];
    [self sendKeyToVim:@"v" withMods:NSEventModifierFlagControl];
    [self waitForEventHandlingAndVimProcess];
    [vc replaceSelectedText:@"xyz\n1234\n"]; // ending in newline means it gets interpreted as line-wise
    XCTAssertEqualObjects([vc evaluateVimExpression:@"getline(1)"], @"axyz d");
    XCTAssertEqualObjects([vc evaluateVimExpression:@"getline(2)"], @"e1234h");
    XCTAssertEqualObjects([vc evaluateVimExpression:@"getline(3)"], @"xyz");
    XCTAssertEqualObjects([vc evaluateVimExpression:@"getline(4)"], @"1234");
    XCTAssertEqualObjects([vc evaluateVimExpression:@"getline(5)"], @"l");

    // Make sure registers didn't get stomped (internally the implementation uses register and manually restores it)
    regcontents = [[app keyVimController] evaluateVimExpression:@"getreg()"];
    XCTAssertEqualObjects(regcontents, @"abcd\n");

    [self sendStringToVim:@":set nomodified\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
}

@end
