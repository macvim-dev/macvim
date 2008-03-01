/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * AuthorizedCommand
 *
 * Runs a set of shell commands which may require authorization. Displays a
 * gui dialog to ask the user for authorized access.
 */

#import "AuthorizedShellCommand.h"

#import <Security/AuthorizationTags.h>

@implementation AuthorizedShellCommand

- (AuthorizedShellCommand *)initWithCommands:(NSArray *)theCommands
{
    if (![super init])
        return nil;

    commands = [theCommands retain];
    return self;
}

- (void)dealloc
{
    [super dealloc];
    [commands release]; 
}

- (OSStatus)run
{
    OSStatus err;
    int i;
    const char** arguments = NULL;
    AuthorizationFlags flags = kAuthorizationFlagDefaults;

    err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
            flags, &authorizationRef);
    if (err != errAuthorizationSuccess)
        return err;

    if ((err = [self askUserForPermission]) != errAuthorizationSuccess) {
        goto cleanup;
    }

    NSEnumerator* myIterator = [commands objectEnumerator];
    NSDictionary* currCommand;

    while (currCommand = [myIterator nextObject])
    {
        /* do something useful with currCommand */
        FILE *ioPipe = NULL;
        char junk[256];

        const char* toolPath = [[currCommand objectForKey:MMCommand] UTF8String];
        NSArray* argumentStrings = [currCommand objectForKey:MMArguments];
        arguments = (const char**)malloc(
                ([argumentStrings count] + 1) * sizeof(char*));

        for (i = 0; i < [argumentStrings count]; ++i) {
            arguments[i] = [[argumentStrings objectAtIndex:i] UTF8String];
        }
        arguments[i] = NULL;

        err = AuthorizationExecuteWithPrivileges (authorizationRef, toolPath,
                kAuthorizationFlagDefaults, arguments, &ioPipe);
        if (err != errAuthorizationSuccess)
            goto cleanup;

#if 0
        // We use the pipe to signal us when the command has completed
        char *p;
        do {
            p = fgets(junk, sizeof(junk), ioPipe);
        } while (p);
#else
        for(;;)
        {
            int bytesRead = read (fileno (ioPipe),
                    junk, sizeof (junk));
            if (bytesRead < 1) break;
            write (fileno (stdout), junk, bytesRead);
        }
#endif

        if (arguments != NULL) {
            free(arguments);
            arguments = NULL;
        }
        fclose(ioPipe);
    }



cleanup:
    AuthorizationFree(authorizationRef, kAuthorizationFlagDefaults);
    authorizationRef = 0;

    if (arguments != NULL)
        free(arguments);

    return err;
}

- (OSStatus)askUserForPermission
{
    int i;

    assert(authorizationRef != 0);

    // The documentation for AuthorizationItem says that `value` should be
    // the path to the full posix path for kAuthorizationRightExecute. But
    // the installer sample "Calling a Privileged Installer" sets it to NULL.
    // Gotta love Apple's documentation.
    //
    // If you don't set `value` correctly, you'll get an
    // `errAuthorizationToolEnvironmentError` when you try to execute the
    // command.
    AuthorizationItem* authItems =
        malloc([commands count] * sizeof(AuthorizationItem));
    for (i = 0; i < [commands count]; ++i) {
        authItems[i].name = kAuthorizationRightExecute;
        authItems[i].value = (void*)
            [[[commands objectAtIndex:i] objectForKey:MMCommand] UTF8String];
        authItems[i].valueLength = strlen(authItems[i].value);
        authItems[i].flags = 0;
    }

    AuthorizationRights rights = {
        [commands count], authItems
    };
    
    OSStatus err = AuthorizationCopyRights(authorizationRef, &rights, NULL,
            kAuthorizationFlagInteractionAllowed |
            kAuthorizationFlagPreAuthorize |
            kAuthorizationFlagExtendRights
            , NULL);

    free(authItems);

    return err;
}

@end

NSString *MMCommand   = @"MMCommand";
NSString *MMArguments = @"MMArguments";

