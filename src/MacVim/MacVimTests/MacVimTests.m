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
#import "MMTextView.h"
#import "MMWindowController.h"
#import "MMVimController.h"
#import "MMVimView.h"

// Expose private methods for testing purposes
@interface MMAppController (Private)
+ (NSDictionary*)parseOpenURL:(NSURL*)url;
@end

@interface MMVimController (Private)
- (void)handleMessage:(int)msgid data:(NSData *)data;
@end

// Test harness
@interface MMAppController (Tests)
- (NSMutableArray*)vimControllers;
@end

@implementation MMAppController (Tests)
- (NSMutableArray*)vimControllers {
    return vimControllers;
}
@end

@interface MacVimTests : XCTestCase

@end

@implementation MacVimTests

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

/// Wait for Vim to process all pending messages in its queue.
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
    NSEvent* keyEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                         location:NSMakePoint(50, 50)
                                    modifierFlags:mods
                                        timestamp:100
                                     windowNumber:[[NSApp mainWindow] windowNumber]
                                          context:0
                                       characters:chars
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
    MMAppController *app = MMAppController.sharedInstance;

    // Adding a new window is necessary for the vimtutor menu to show up as it's
    // not part of the global menu
    [app openNewWindow:NewWindowClean activate:YES];
    [self waitForVimOpenAndMessages];

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
    // actually open the copied file.
    [self waitForVimOpen];
    [self waitForVimOpenAndMessages];

    NSString *bufname = [[app keyVimController] evaluateVimExpression:@"bufname()"];
    XCTAssertTrue([bufname containsString:@"tutor"]);

    // Clean up
    [[app keyVimController] sendMessage:VimShouldCloseMsgID data:nil];
    [self waitForVimClose];
    [[app keyVimController] sendMessage:VimShouldCloseMsgID data:nil];
    [self waitForVimClose];

    XCTAssertEqual(0, [app vimControllers].count);
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
    MMAppController *app = MMAppController.sharedInstance;

    [app openNewWindow:NewWindowClean activate:YES];
    [self waitForVimOpenAndMessages];

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

    // Clean up
    [[app keyVimController] sendMessage:VimShouldCloseMsgID data:nil];
    [self waitForVimClose];
}

/// Test that using "-monospace-" for system default monospace font works.
- (void) testGuifontSystemMonospace {
    MMAppController *app = MMAppController.sharedInstance;

    [app openNewWindow:NewWindowClean activate:YES];
    [self waitForVimOpenAndMessages];

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

    [[[app keyVimController] windowController] fontSizeDown:nil];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects([textView font], [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightHeavy]);

    // Clean up
    [[app keyVimController] sendMessage:VimShouldCloseMsgID data:nil];
    [self waitForVimClose];
}

/// Test that document icon is shown in title bar when enabled.
- (void) testTitlebarDocumentIcon {
    MMAppController *app = MMAppController.sharedInstance;

    [app openNewWindow:NewWindowClean activate:YES];
    [self waitForVimOpenAndMessages];

    NSWindow *win = [[[app keyVimController] windowController] window];

    // Untitled documents have no icons
    XCTAssertEqualObjects(@"", win.representedFilename);

    // Test that the document icon is shown when a file (gui_mac.txt) is opened by querying "representedFilename"
    [self sendStringToVim:@":help macvim\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    NSString *gui_mac_path = [[NSBundle mainBundle] pathForResource:@"gui_mac.txt" ofType:nil inDirectory:@"vim/runtime/doc"];
    XCTAssertEqualObjects(gui_mac_path, win.representedFilename);

    // Change setting to hide the document icon
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSDictionary<NSString *, id> *defaults = [ud volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary<NSString *, id> *newDefaults = [defaults mutableCopy];
    newDefaults[MMTitlebarShowsDocumentIconKey] = @NO;
    [ud setVolatileDomain:newDefaults forName:NSArgumentDomain];

    // Test that there is no document icon shown
    [app refreshAllAppearances];
    XCTAssertEqualObjects(@"", win.representedFilename);

    // Change setting back to show the document icon. Test that the path was remembered and icon is shown.
    newDefaults[MMTitlebarShowsDocumentIconKey] = @YES;
    [ud setVolatileDomain:newDefaults forName:NSArgumentDomain];
    [app refreshAllAppearances];
    XCTAssertEqualObjects(gui_mac_path, win.representedFilename);

    // Close the file to go back to untitled document and make sure no icon is shown
    [self sendStringToVim:@":q\n" withMods:0];
    [self waitForEventHandlingAndVimProcess];
    XCTAssertEqualObjects(@"", win.representedFilename);

    // Restore settings to test defaults
    [ud setVolatileDomain:defaults forName:NSArgumentDomain];

    // Clean up
    [[app keyVimController] sendMessage:VimShouldCloseMsgID data:nil];
    [self waitForVimClose];
}

@end
