/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

// This header file should include everything that a plug-in will need so that
// it is all we need to distribute for plug-in developers.

/*
 * PlugInAppMediator
 *
 * The interface that the plugin may use to interact with the MacVim
 * application.
 *
 * PlugInInstanceMediator
 *
 * The interface that a plugin may use to interact with a specific vim instance
 * within MacVim.
 *
 * PlugInProtocol
 *
 * The protocol which the principal class of the plugin must conform to.
 *
 * Author: Matt Tolton
 *
 */

@protocol PlugInAppMediator

- (void)addPlugInMenuItem:(NSMenuItem *)menuItem;

// Returns the plugin instance of the specified class associated with the key vim window.
// If a vim window is not the key window, returns nil.
// If there are no instances with the specified class, returns nil.
- (id)keyPlugInInstanceWithClass:(Class)class;

@end

@protocol PlugInInstanceMediator

// vim values are converted into NSNumber, NSString, NSArray, and NSDictionary
- (id)evaluateVimExpression:(NSString *)vimExpression;
- (void)addVimInput:(NSString *)input;
- (void)openFiles:(NSArray *)fileNames;
- (void)addPlugInView:(NSView *)view withTitle:(NSString *)title;

@end

@protocol PlugInProtocol
// The mediator should not be retained.  It will exist until terminatePlugIn is
// called.
+ (BOOL)initializePlugIn:(id<PlugInAppMediator>)mediator;
+ (void)terminatePlugIn;
@end

@interface NSObject (PlugInProtocol)
// The mediator should not be retained.  It will exist until it releases this
// plugin instance, and is not valid after that.
- (id)initWithMediator:(id<PlugInInstanceMediator>)mediator;
@end

