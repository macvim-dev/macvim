//
//  NewProjectController.h
//  MacVim
//
//  Created by Doug Fales on 3/27/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import <Cocoa/Cocoa.h>

@class MMWindowController;

@interface MVPNewProjectController : NSWindowController<NSTextFieldDelegate> {
	IBOutlet NSTextField *rootPathLabel;
	IBOutlet NSTextField *projectNameTextField;
	IBOutlet NSTextField *ignorePatternsTextField;
	IBOutlet NSButton *createButton;
	MMWindowController *windowController;
}
@property(nonatomic, retain) MMWindowController *windowController;

- (IBAction)createProject:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)chooseRoot:(id)sender;

@end
