/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMPreferenceController.h"
#import "MacVim.h"

#import "AuthorizedShellCommand.h"

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

@implementation MMPreferenceController

- (void)updateIntegrationPane
{
    // XXX: check validation api.

    // enable/disable buttons

    // can't use this, as it caches the bundle, so uninstallation is not
    // detected
    //NSBundle *inputManager = [NSBundle bundleWithPath:ODBEDITOR_PATH];
    //if (inputManager != nil) {
        //NSString* v =
            //[[inputManager infoDictionary] valueForKey:@"CFBundleVersion"];

    // Check if ODB path exists before calling isFilePackageAtPath: otherwise
    // an error is output to stderr on Tiger.
    BOOL odbIsInstalled =
        [[NSFileManager defaultManager] fileExistsAtPath:ODBEDITOR_PATH]
        && [[NSWorkspace sharedWorkspace] isFilePackageAtPath:ODBEDITOR_PATH];

    if (odbIsInstalled) {
        [installOdbButton setTitle:@"Update"];
        [installOdbButton setEnabled:YES];  //XXX: only if there'a new version
        [uninstallOdbButton setEnabled:YES];
        [editors setEnabled:YES];
    } else {
        [installOdbButton setTitle:@"Install"];
        [installOdbButton setEnabled:YES];
        [uninstallOdbButton setEnabled:NO];
        [editors setEnabled:NO];
    }
}

- (void)awakeFromNib
{
    // reading the defaults of a different app is easier with carbon
    NSString *bundleIdentifier = (NSString*)CFPreferencesCopyAppValue(
            ODB_BUNDLE_IDENTIFIER, ODBEDITOR);
    
    // taken from Cyberduck. Thanks :-)
    supportedOdbEditors = [[NSDictionary alloc] initWithObjectsAndKeys:
        @"com.barebones.bbedit", @"BBEdit",
        @"com.macrabbit.cssedit", @"CSSEdit",
        @"org.vim.MacVim", @"MacVim",
        @"org.smultron.Smultron", @"Smultron",
        @"de.codingmonkeys.SubEthaEdit", @"SubEthaEdit",
        @"com.macromates.textmate", @"TextMate",
        @"com.barebones.textwrangler", @"TextWrangler",
        @"com.hogbaysoftware.WriteRoom", @"WriteRoom",
        @"", @"(None)",
        nil];

    NSString *selectedTitle = @"(None)";

    NSMenu *editorsMenu = [editors menu];
    NSEnumerator *enumerator = [supportedOdbEditors keyEnumerator];
    NSString *key;
    while ((key = [enumerator nextObject]) != nil) {
        NSString *identifier = [supportedOdbEditors objectForKey:key];

        if (bundleIdentifier && [bundleIdentifier isEqualToString:identifier])
            selectedTitle = key;

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:key
                                action:@selector(odbEditorChanged:)
                                keyEquivalent:@""];
        [item setTarget:self];
        if (![identifier isEqualToString:@""]) {
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

    // XXX: if no pref is yet set, set it to MacVim (only if dropdown is
    // active!)
    [editors selectItemWithTitle:selectedTitle];

    [self updateIntegrationPane];

    if (bundleIdentifier)
        CFRelease(bundleIdentifier);
}

- (void)dealloc
{
    [supportedOdbEditors release]; supportedOdbEditors = nil;
    [super dealloc];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    NSString *identifier = [supportedOdbEditors objectForKey:[item title]];
    if (identifier == nil)
        return NO;
    if ([identifier isEqualToString:@""])
        return YES;
    return [[NSWorkspace sharedWorkspace]
        absolutePathForAppBundleWithIdentifier:identifier] != nil;
}

- (void)odbEditorChanged:(id)sender
{
    NSString *name = [sender title];
    NSString *identifier = [supportedOdbEditors objectForKey:name];

    if (![identifier isEqualToString:@""]) {
        CFPreferencesSetAppValue(ODB_BUNDLE_IDENTIFIER, identifier, ODBEDITOR);
        CFPreferencesSetAppValue(ODB_EDITOR_NAME, name, ODBEDITOR);
    } else {
        CFPreferencesSetAppValue(ODB_BUNDLE_IDENTIFIER, NULL, ODBEDITOR);
        CFPreferencesSetAppValue(ODB_EDITOR_NAME, NULL, ODBEDITOR);
    }
    CFPreferencesAppSynchronize(ODBEDITOR);
}

- (IBAction)installOdb:(id)sender
{
    NSString *source = [[[NSBundle mainBundle] resourcePath]
        stringByAppendingString: @"/Edit in ODBEditor"];
    
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
            [NSArray arrayWithObjects: @"-R", //XXX: -p?
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
    [au run];
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
    [au run];
    [au release];

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

@end
