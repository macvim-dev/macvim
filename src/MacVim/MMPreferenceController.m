/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved            by Bram Moolenaar
 *                              MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "AuthorizedShellCommand.h"
#import "MMPreferenceController.h"
#import "Miscellaneous.h"

// On Leopard, we want to use the images provided by the OS for some of the
// toolbar images (NSImageNamePreferencesGeneral and friends). We need to jump
// through some hoops to do that in a way that MacVim still _compiles_ on Tiger
// (life would be easier if we'd require Leopard for building). See
// http://developer.apple.com/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/WeakLinking.html
// and http://developer.apple.com/technotes/tn2002/tn2064.html
// for how you'd do it with a Leopard build system, and see
// http://lists.cairographics.org/archives/cairo-bugs/2007-December/001818.html
// for why this doesn't work here.
// Using the system images gives us resolution independence and consistency
// with other apps.

#import <dlfcn.h>

NSString* nsImageNamePreferencesGeneral = nil;
NSString* nsImageNamePreferencesAdvanced = nil;

static void loadSymbols()
{
    // use dlfcn() instead of the deprecated NSModule api.
    void *ptr;
    if ((ptr = dlsym(RTLD_DEFAULT, "NSImageNamePreferencesGeneral")) != NULL)
        nsImageNamePreferencesGeneral = *(NSString**)ptr;
    if ((ptr = dlsym(RTLD_DEFAULT, "NSImageNamePreferencesAdvanced")) != NULL)
        nsImageNamePreferencesAdvanced = *(NSString**)ptr;
}


static CFStringRef ODBEDITOR = CFSTR("org.slashpunt.edit_in_odbeditor");
static CFStringRef ODB_BUNDLE_IDENTIFIER = CFSTR("ODBEditorBundleIdentifier");
static CFStringRef ODB_EDITOR_NAME = CFSTR("ODBEditorName");
static NSString *ODBEDITOR_DIR = 
    @"/Library/InputManagers/Edit in ODBEditor";
static NSString *ODBEDITOR_PATH =
    @"/Library/InputManagers/Edit in ODBEditor/Edit in ODBEditor.bundle";


NSString *kOdbEditorNameNone = @"(None)";
NSString *kOdbEditorIdentifierNone = @"";

NSString *kOdbEditorNameBBEdit = @"BBEdit";
NSString *kOdbEditorIdentifierBBEdit = @"com.barebones.bbedit";

NSString *kOdbEditorNameCSSEdit = @"CSSEdit";
NSString *kOdbEditorIdentifierCSSEdit = @"com.macrabbit.cssedit";

NSString *kOdbEditorNameMacVim = @"MacVim";
NSString *kOdbEditorIdentifierMacVim = @"org.vim.MacVim";

NSString *kOdbEditorNameSmultron = @"Smultron";
NSString *kOdbEditorIdentifierSmultron = @"org.smultron.Smultron";

NSString *kOdbEditorNameSubEthaEdit = @"SubEthaEdit";
NSString *kOdbEditorIdentifierSubEthaEdit = @"de.codingmonkeys.SubEthaEdit";

NSString *kOdbEditorNameTextMate = @"TextMate";
NSString *kOdbEditorIdentifierTextMate = @"com.macromates.textmate";

NSString *kOdbEditorNameTextWrangler = @"TextWrangler";
NSString *kOdbEditorIdentifierTextWrangler = @"com.barebones.textwrangler";

NSString *kOdbEditorNameWriteRoom = @"WriteRoom";
NSString *kOdbEditorIdentifierWriteRoom = @"com.hogbaysoftware.WriteRoom";


@interface MMPreferenceController (Private)
// Integration pane
- (void)updateIntegrationPane;
- (void)setOdbEditorByName:(NSString *)name;
- (NSString *)odbEditorBundleIdentifier;
- (NSString *)odbBundleSourceDir;
- (NSString *)versionOfBundle:(NSString *)bundlePath;
- (NSString *)odbBundleInstalledVersion;
- (NSString *)odbBundleInstallVersion;
@end

@implementation MMPreferenceController

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self == nil)
        return nil;
    // taken from Cyberduck. Thanks :-)
    supportedOdbEditors = [[NSDictionary alloc] initWithObjectsAndKeys:
        kOdbEditorIdentifierNone, kOdbEditorNameNone,
        kOdbEditorIdentifierBBEdit, kOdbEditorNameBBEdit,
        kOdbEditorIdentifierCSSEdit, kOdbEditorNameCSSEdit,
        kOdbEditorIdentifierMacVim, kOdbEditorNameMacVim,
        kOdbEditorIdentifierSmultron, kOdbEditorNameSmultron,
        kOdbEditorIdentifierSubEthaEdit, kOdbEditorNameSubEthaEdit,
        kOdbEditorIdentifierTextMate, kOdbEditorNameTextMate,
        kOdbEditorIdentifierTextWrangler, kOdbEditorNameTextWrangler,
        kOdbEditorIdentifierWriteRoom, kOdbEditorNameWriteRoom,
        nil];
    return self;
}

- (void)dealloc
{
    [supportedOdbEditors release]; supportedOdbEditors = nil;
    [super dealloc];
}

- (void)awakeFromNib
{
    // fill list of editors in integration pane
    NSArray *keys = [[supportedOdbEditors allKeys]
        sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMenu *editorsMenu = [editors menu];
    NSEnumerator *enumerator = [keys objectEnumerator];
    NSString *key;
    while ((key = [enumerator nextObject]) != nil) {
        NSString *identifier = [supportedOdbEditors objectForKey:key];

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:key
                                action:@selector(odbEditorChanged:)
                                keyEquivalent:@""];
        [item setTarget:self];
        if (![identifier isEqualToString:kOdbEditorIdentifierNone]) {
            NSString *appPath = [[NSWorkspace sharedWorkspace]
                absolutePathForAppBundleWithIdentifier:identifier];
            [item setEnabled:appPath != nil];
            if (appPath != nil) {
                NSImage *icon = [[NSWorkspace sharedWorkspace]
                    iconForFile:appPath];
                [icon setSize:NSMakeSize(16, 16)];  // XXX: make res independent
                [item setImage:icon];
            }
        }
        [editorsMenu addItem:item];
        [item release];
    }

    [self updateIntegrationPane];
}

- (void)setupToolbar
{
    loadSymbols();

    if (nsImageNamePreferencesGeneral != NULL) {
        [self addView:generalPreferences
                label:@"General"
                image:[NSImage imageNamed:nsImageNamePreferencesGeneral]];
    } else {
        [self addView:generalPreferences label:@"General"];
    }

    [self addView:integrationPreferences label:@"Integration"];
}


- (NSString *)currentPaneIdentifier
{
    // We override this to persist the current pane.
    return [[NSUserDefaults standardUserDefaults]
        stringForKey:MMCurrentPreferencePaneKey];
}

- (void)setCurrentPaneIdentifier:(NSString *)identifier
{
    // We override this to persist the current pane.
    [[NSUserDefaults standardUserDefaults]
        setObject:identifier forKey:MMCurrentPreferencePaneKey];
}


- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(odbEditorChanged:)) {
        NSString *identifier = [supportedOdbEditors objectForKey:[item title]];
        if (identifier == nil)
            return NO;
        if ([identifier isEqualToString:kOdbEditorIdentifierNone])
            return YES;
        return [[NSWorkspace sharedWorkspace]
            absolutePathForAppBundleWithIdentifier:identifier] != nil;
    }
    return YES;
}

- (IBAction)openInCurrentWindowSelectionChanged:(id)sender
{
    BOOL openInCurrentWindowSelected = ([[sender selectedCell] tag] != 0);
    BOOL useWindowsLayout =
            ([[layoutPopUpButton selectedItem] tag] == MMLayoutWindows);
    if (openInCurrentWindowSelected && useWindowsLayout)
        [layoutPopUpButton selectItemWithTag:MMLayoutTabs];
}

#pragma mark -
#pragma mark Integration pane

- (void)updateIntegrationPane
{
    // XXX: check validation api.
    // XXX: call this each time the dialog becomes active (so that if the
    // user changes settings in terminal, the changes are reflected in the
    // dialog)

    NSString *versionString;

    // Check if ODB path exists before calling isFilePackageAtPath: otherwise
    // an error is output to stderr on Tiger.
    BOOL odbIsInstalled =
        [[NSFileManager defaultManager] fileExistsAtPath:ODBEDITOR_PATH]
        && [[NSWorkspace sharedWorkspace] isFilePackageAtPath:ODBEDITOR_PATH];

    // enable/disable buttons
    [installOdbButton setTitle:@"Install"];
    if (odbIsInstalled) {
        [uninstallOdbButton setEnabled:YES];
        [editors setEnabled:YES];

        NSString *installVersion = [self odbBundleInstallVersion];
        NSString *installedVersion = [self odbBundleInstalledVersion];
        switch ([installedVersion compare:installVersion
                                  options:NSNumericSearch]) {
        case NSOrderedAscending:
            versionString = [NSString stringWithFormat:
                @"Latest version is %@, you have %@.",
                installVersion, installedVersion];
            [installOdbButton setTitle:@"Update"];
            [installOdbButton setEnabled:YES];
            break;
        case NSOrderedSame:
            versionString = [NSString stringWithFormat:
                @"Latest version is %@. You have the latest version.",
                installVersion];
            [installOdbButton setEnabled:NO];
            break;
        case NSOrderedDescending:
            versionString = [NSString stringWithFormat:
                @"Latest version is %@, you have %@.",
                installVersion, installedVersion];
            [installOdbButton setEnabled:NO];
            break;
        }
    } else {
        [installOdbButton setEnabled:YES];
        [uninstallOdbButton setEnabled:NO];
        [editors setEnabled:NO];

        versionString = [NSString
            stringWithFormat:@"Latest version is %@. It is not installed.",
                      [self odbBundleInstallVersion]];
    }

    [obdBundleVersionLabel setStringValue:versionString];

    // make sure the right editor is selected on the popup button
    NSString *selectedTitle = kOdbEditorNameNone;
    NSArray* keys = [supportedOdbEditors
        allKeysForObject:[self odbEditorBundleIdentifier]];
    if ([keys count] > 0)
        selectedTitle = [keys objectAtIndex:0];
    [editors selectItemWithTitle:selectedTitle];
}

- (void)setOdbEditorByName:(NSString *)name
{
    NSString *identifier = [supportedOdbEditors objectForKey:name];
    if (identifier != kOdbEditorIdentifierNone) {
        CFPreferencesSetAppValue(ODB_BUNDLE_IDENTIFIER, identifier, ODBEDITOR);
        CFPreferencesSetAppValue(ODB_EDITOR_NAME, name, ODBEDITOR);
    } else {
        CFPreferencesSetAppValue(ODB_BUNDLE_IDENTIFIER, NULL, ODBEDITOR);
        CFPreferencesSetAppValue(ODB_EDITOR_NAME, NULL, ODBEDITOR);
    }
    CFPreferencesAppSynchronize(ODBEDITOR);
}

// Note that you can't compare the result of this function with ==, you have
// to use isStringEqual: (since this returns a new copy of the string).
- (NSString *)odbEditorBundleIdentifier
{
    // reading the defaults of a different app is easier with carbon
    NSString *bundleIdentifier = (NSString*)CFPreferencesCopyAppValue(
            ODB_BUNDLE_IDENTIFIER, ODBEDITOR);
    if (bundleIdentifier == nil)
        return kOdbEditorIdentifierNone;
    return [bundleIdentifier autorelease];
}

- (void)odbEditorChanged:(id)sender
{
    [self setOdbEditorByName:[sender title]];
}

- (NSString *)odbBundleSourceDir
{
    return [[[NSBundle mainBundle] resourcePath]
        stringByAppendingString:@"/Edit in ODBEditor"];
}

// Returns the CFBundleVersion of a bundle. This assumes a bundle exists
// at bundlePath.
- (NSString *)versionOfBundle:(NSString *)bundlePath
{
    // -[NSBundle initWithPath:] caches a bundle, so if the bundle is replaced
    // with a new bundle on disk, we get the old version. So we can't use it :-(

    NSString *infoPath = [bundlePath
        stringByAppendingString:@"/Contents/Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    return [info objectForKey:@"CFBundleVersion"];
}

- (NSString *)odbBundleInstalledVersion
{
    return [self versionOfBundle:ODBEDITOR_PATH];
}

- (NSString *)odbBundleInstallVersion
{
    return [self versionOfBundle:[[self odbBundleSourceDir]
         stringByAppendingString:@"/Edit in ODBEditor.bundle"]];
}

- (IBAction)installOdb:(id)sender
{
    NSString *source = [self odbBundleSourceDir];

    // It doesn't hurt to rm -rf the InputManager even if it's not there,
    // the code is simpler that way.
    NSArray *cmd = [NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"/bin/rm", MMCommand,
            [NSArray arrayWithObjects:@"-rf", ODBEDITOR_DIR, nil], MMArguments,
            nil],
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"/bin/mkdir", MMCommand,
            [NSArray arrayWithObjects:@"-p", ODBEDITOR_DIR, nil], MMArguments,
            nil],
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"/bin/cp", MMCommand,
            [NSArray arrayWithObjects: @"-R",
                source, @"/Library/InputManagers", nil], MMArguments,
            nil],
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"/usr/sbin/chown", MMCommand,
            [NSArray arrayWithObjects: @"-R",
                @"root:admin", @"/Library/InputManagers", nil], MMArguments,
            nil],
        nil
        ];

    AuthorizedShellCommand *au = [[AuthorizedShellCommand alloc]
        initWithCommands:cmd];
    OSStatus err = [au run];
    if (err == errAuthorizationSuccess) {
        // If the user just installed the input manager and no editor was
        // selected before, chances are he wants to use MacVim as editor
        if ([[self odbEditorBundleIdentifier]
                isEqualToString:kOdbEditorIdentifierNone]) {
            [self setOdbEditorByName:kOdbEditorNameMacVim];
        }
    } else {
        NSLog(@"Failed to install input manager, error is %d", err);
    }
    [au release];

    [self updateIntegrationPane];
}

- (IBAction)uninstallOdb:(id)sender
{
    NSArray *cmd = [NSArray arrayWithObject:
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"/bin/rm", MMCommand,
            [NSArray arrayWithObjects: @"-rf", ODBEDITOR_DIR, nil], MMArguments,
            nil]];

    AuthorizedShellCommand *au = [[AuthorizedShellCommand alloc]
        initWithCommands:cmd];
    OSStatus err = [au run];
    if (err != errAuthorizationSuccess)
        NSLog(@"Failed to uninstall input manager, error is %d", err);
    [au release];

    [self updateIntegrationPane];
}

@end
