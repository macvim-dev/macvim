//
//  NewProjectController.m
//  MacVim
//
//  Created by Doug Fales on 3/27/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import "MVPNewProjectController.h"
#import "MMWindowController.h"
#import "MVPProject.h"

@interface MVPNewProjectController ()

- (NSString *)selectedName;
- (NSString *)selectedRoot;
- (NSString *)selectedIgnorePatterns;
- (void)checkEnableCreateButton;

@end

@implementation MVPNewProjectController

@synthesize windowController;

- (id) init {
	self = [super initWithWindowNibName:@"MVPNewProjectWindow"];
	return self;
}

- (void)dealloc {
	[windowController release]; windowController = nil;
	[super dealloc];
}

- (IBAction)createProject:(id)sender {
	MVPProject *project = [[MVPProject alloc] initWithRoot:[self selectedRoot] andName:[self selectedName] andIgnorePatterns:[self selectedIgnorePatterns]];
	[self.windowController setProject:project];
	[self close];
}

- (IBAction)cancel:(id)sender {
	[self close];
}

- (IBAction)chooseRoot:(id)sender {	
    NSOpenPanel *panel = [NSOpenPanel openPanel];        
    [panel setFloatingPanel:YES];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
	int i = [panel runModalForTypes:nil];
	if(i == NSOKButton){
		NSURL *url = [[panel URLs] objectAtIndex:0];
		[rootPathLabel setStringValue:[url path]];
	}
	[self checkEnableCreateButton];    
}

- (void)checkEnableCreateButton {
	if([[self selectedName] length] > 0 && [[self selectedRoot] length] > 0) {
		[createButton setEnabled:YES];
	} else {
		[createButton setEnabled:NO];
	}
}

- (void)controlTextDidChange:(NSNotification *)aNotification{
	[self checkEnableCreateButton];
}

- (NSString *)selectedName {
	return [[projectNameTextField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (NSString *)selectedRoot {
	NSString *rootPath = [[rootPathLabel stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	return [rootPath stringByReplacingOccurrencesOfString:@"None selected" withString:@""];
}

- (NSString *)selectedIgnorePatterns {
	return [[ignorePatternsTextField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@end
