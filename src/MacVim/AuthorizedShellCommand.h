/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import <Cocoa/Cocoa.h>
#import <Security/Authorization.h>


@interface AuthorizedShellCommand : NSObject {

    NSArray *commands;

    AuthorizationRef authorizationRef;

}

// Pass an array of dictionaries. Each dictionary has to have the following
// keys:
//
//   * MMCommand: The command to execute, an NSString (e.g. @"/usr/bin/rm").
//   * MMArguments: An array of NSStrings, the arguments that are passed to
//                  the command.
//
- (AuthorizedShellCommand *)initWithCommands:(NSArray *)theCommands;

// Runs the command passed in the constructor.
- (OSStatus)run;

// This pops up the permission dialog. Called by run.
- (OSStatus)askUserForPermission;

@end


extern NSString *MMCommand;
extern NSString *MMArguments;

