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
 * MacVim.m:  Code shared between Vim and MacVim.
 */

#import "MacVim.h"

char *MessageStrings[] = 
{
    "INVALID MESSAGE ID",
    "OpenWindowMsgID",
    "InsertTextMsgID",
    "KeyDownMsgID",
    "CmdKeyMsgID",
    "BatchDrawMsgID",
    "SelectTabMsgID",
    "CloseTabMsgID",
    "AddNewTabMsgID",
    "DraggedTabMsgID",
    "UpdateTabBarMsgID",
    "ShowTabBarMsgID",
    "HideTabBarMsgID",
    "SetTextRowsMsgID",
    "SetTextColumnsMsgID",
    "SetTextDimensionsMsgID",
    "LiveResizeMsgID",
    "SetTextDimensionsReplyMsgID",
    "SetWindowTitleMsgID",
    "ScrollWheelMsgID",
    "MouseDownMsgID",
    "MouseUpMsgID",
    "MouseDraggedMsgID",
    "FlushQueueMsgID",
    "AddMenuMsgID",
    "AddMenuItemMsgID",
    "RemoveMenuItemMsgID",
    "EnableMenuItemMsgID",
    "ExecuteMenuMsgID",
    "ShowToolbarMsgID",
    "ToggleToolbarMsgID",
    "CreateScrollbarMsgID",
    "DestroyScrollbarMsgID",
    "ShowScrollbarMsgID",
    "SetScrollbarPositionMsgID",
    "SetScrollbarThumbMsgID",
    "ScrollbarEventMsgID",
    "SetFontMsgID",
    "SetWideFontMsgID",
    "VimShouldCloseMsgID",
    "SetDefaultColorsMsgID",
    "ExecuteActionMsgID",
    "DropFilesMsgID",
    "DropStringMsgID",
    "ShowPopupMenuMsgID",
    "GotFocusMsgID",
    "LostFocusMsgID",
    "MouseMovedMsgID",
    "SetMouseShapeMsgID",
    "AdjustLinespaceMsgID",
    "ActivateMsgID",
    "SetServerNameMsgID",
    "EnterFullscreenMsgID",
    "LeaveFullscreenMsgID",
    "BuffersNotModifiedMsgID",
    "BuffersModifiedMsgID",
    "AddInputMsgID",
    "SetPreEditPositionMsgID",
    "TerminateNowMsgID",
    "XcodeModMsgID",
    "EnableAntialiasMsgID",
    "DisableAntialiasMsgID",
    "SetVimStateMsgID",
    "SetDocumentFilenameMsgID",
    "OpenWithArgumentsMsgID",
    "CloseWindowMsgID",
    "SetFullscreenColorMsgID",
    "ShowFindReplaceDialogMsgID",
    "FindReplaceMsgID",
    "ActivateKeyScriptMsgID",
    "DeactivateKeyScriptMsgID",
    "EnableImControlMsgID",
    "DisableImControlMsgID",
    "ActivatedImMsgID",
    "DeactivatedImMsgID",
    "BrowseForFileMsgID",
    "ShowDialogMsgID",
    "END OF MESSAGE IDs"     // NOTE: Must be last!
};




// Argument used to stop MacVim from opening an empty window on startup
// (techincally this is a user default but should not be used as such).
NSString *MMNoWindowKey = @"MMNoWindow";

// Vim pasteboard type (holds motion type + string)
NSString *VimPBoardType = @"VimPBoardType";



// Create a string holding the labels of all messages in message queue for
// debugging purposes (condense some messages since there may typically be LOTS
// of them on a queue).
    NSString *
debugStringForMessageQueue(NSArray *queue)
{
    NSMutableString *s = [NSMutableString new];
    unsigned i, count = [queue count];
    int item = 0, menu = 0, enable = 0;
    for (i = 0; i < count; i += 2) {
        NSData *value = [queue objectAtIndex:i];
        int msgid = *((int*)[value bytes]);
        if (msgid < 1 || msgid >= LastMsgID)
            continue;
        if (msgid == AddMenuItemMsgID) ++item;
        else if (msgid == AddMenuMsgID) ++menu;
        else if (msgid == EnableMenuItemMsgID) ++enable;
        else [s appendFormat:@"%s ", MessageStrings[msgid]];
    }
    if (item > 0) [s appendFormat:@"AddMenuItemMsgID(%d) ", item];
    if (menu > 0) [s appendFormat:@"AddMenuMsgID(%d) ", menu];
    if (enable > 0) [s appendFormat:@"EnableMenuItemMsgID(%d) ", enable];

    return [s autorelease];
}




@implementation NSString (MMExtras)

- (NSString *)stringByEscapingSpecialFilenameCharacters
{
    // NOTE: This code assumes that no characters already have been escaped.
    NSMutableString *string = [self mutableCopy];

    [string replaceOccurrencesOfString:@"\\"
                            withString:@"\\\\"
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];
    [string replaceOccurrencesOfString:@" "
                            withString:@"\\ "
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];
    [string replaceOccurrencesOfString:@"\t"
                            withString:@"\\\t "
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];
    [string replaceOccurrencesOfString:@"%"
                            withString:@"\\%"
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];
    [string replaceOccurrencesOfString:@"#"
                            withString:@"\\#"
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];
    [string replaceOccurrencesOfString:@"|"
                            withString:@"\\|"
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];
    [string replaceOccurrencesOfString:@"\""
                            withString:@"\\\""
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];

    return [string autorelease];
}

@end // NSString (MMExtras)



@implementation NSColor (MMExtras)

+ (NSColor *)colorWithRgbInt:(unsigned)rgb
{
    float r = ((rgb>>16) & 0xff)/255.0f;
    float g = ((rgb>>8) & 0xff)/255.0f;
    float b = (rgb & 0xff)/255.0f;

    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0f];
}

+ (NSColor *)colorWithArgbInt:(unsigned)argb
{
    float a = ((argb>>24) & 0xff)/255.0f;
    float r = ((argb>>16) & 0xff)/255.0f;
    float g = ((argb>>8) & 0xff)/255.0f;
    float b = (argb & 0xff)/255.0f;

    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
}

@end // NSColor (MMExtras)




@implementation NSDictionary (MMExtras)

+ (id)dictionaryWithData:(NSData *)data
{
    id plist = [NSPropertyListSerialization
            propertyListFromData:data
                mutabilityOption:NSPropertyListImmutable
                          format:NULL
                errorDescription:NULL];

    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}

- (NSData *)dictionaryAsData
{
    return [NSPropertyListSerialization dataFromPropertyList:self
            format:NSPropertyListBinaryFormat_v1_0 errorDescription:NULL];
}

@end




@implementation NSMutableDictionary (MMExtras)

+ (id)dictionaryWithData:(NSData *)data
{
    id plist = [NSPropertyListSerialization
            propertyListFromData:data
                mutabilityOption:NSPropertyListMutableContainers
                          format:NULL
                errorDescription:NULL];

    return [plist isKindOfClass:[NSMutableDictionary class]] ? plist : nil;
}

@end
