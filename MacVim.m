/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MacVim.h"


@implementation NSPortMessage (MacVim)

+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        receivePort:(NSPort *)receivePort components:(NSArray *)components
               wait:(BOOL)wait
{
    NSPortMessage *msg = [[NSPortMessage alloc]
            initWithSendPort:sendPort
                 receivePort:receivePort
                  components:components];
    [msg setMsgid:msgid];

    // HACK!  How long should this wait before time out?
    NSDate *date = wait ? [NSDate dateWithTimeIntervalSinceNow:1]
                        : [NSDate date];
    BOOL ok = [msg sendBeforeDate:date];

    [msg release];

    return ok;
}

+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        receivePort:(NSPort *)receivePort data:(NSData *)data wait:(BOOL)wait
{
    return [NSPortMessage sendMessage:msgid
                         withSendPort:sendPort
                          receivePort:receivePort
                           components:[NSArray arrayWithObject:data]
                                 wait:wait];
}

+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        receivePort:(NSPort *)receivePort wait:(BOOL)wait
{
    return [NSPortMessage sendMessage:msgid
                         withSendPort:sendPort
                          receivePort:receivePort
                           components:nil
                                 wait:wait];
}

+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        components:(NSArray *)components wait:(BOOL)wait
{
    return [NSPortMessage sendMessage:msgid
                         withSendPort:sendPort
                          receivePort:nil
                           components:components
                                 wait:wait];
}

+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        data:(NSData *)data wait:(BOOL)wait
{
    return [NSPortMessage sendMessage:msgid
                         withSendPort:sendPort
                          receivePort:nil
                           components:[NSArray arrayWithObject:data]
                                 wait:wait];
}

+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort wait:(BOOL)wait
{
    return [NSPortMessage sendMessage:msgid
                         withSendPort:sendPort
                          receivePort:nil
                           components:nil
                                 wait:wait];
}


@end
