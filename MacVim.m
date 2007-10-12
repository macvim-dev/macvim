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

char *MessageStrings[] = 
{
    "INVALID MESSAGE ID",
    "OpenVimWindowMsgID",
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
    "SetTextDimensionsMsgID",
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
};




// NSUserDefaults keys
NSString *MMNoWindowKey                 = @"MMNoWindow";
NSString *MMTabMinWidthKey              = @"MMTabMinWidth";
NSString *MMTabMaxWidthKey              = @"MMTabMaxWidth";
NSString *MMTabOptimumWidthKey          = @"MMTabOptimumWidth";
NSString *MMTextInsetLeftKey            = @"MMTextInsetLeft";
NSString *MMTextInsetRightKey           = @"MMTextInsetRight";
NSString *MMTextInsetTopKey             = @"MMTextInsetTop";
NSString *MMTextInsetBottomKey          = @"MMTextInsetBottom";
NSString *MMTerminateAfterLastWindowClosedKey
                                        = @"MMTerminateAfterLastWindowClosed";
NSString *MMTypesetterKey               = @"MMTypesetter";
NSString *MMCellWidthMultiplierKey      = @"MMCellWidthMultiplier";
NSString *MMBaselineOffsetKey           = @"MMBaselineOffset";
NSString *MMTranslateCtrlClickKey       = @"MMTranslateCtrlClick";
NSString *MMTopLeftPointKey             = @"MMTopLeftPoint";
NSString *MMOpenFilesInTabsKey          = @"MMOpenFilesInTabs";




    ATSFontContainerRef
loadFonts()
{
    // This loads all fonts from the Resources folder.  The fonts are only
    // available to the process which loaded them, so loading has to be done
    // once for MacVim and an additional time for each Vim process.  The
    // returned container ref should be used to deactiave the font.
    //
    // (Code taken from cocoadev.com)
    ATSFontContainerRef fontContainerRef = 0;
    NSString *fontsFolder = [[NSBundle mainBundle] resourcePath];    
    if (fontsFolder) {
        NSURL *fontsURL = [NSURL fileURLWithPath:fontsFolder];
        if (fontsURL) {
            FSRef fsRef;
            FSSpec fsSpec;
            CFURLGetFSRef((CFURLRef)fontsURL, &fsRef);

            if (FSGetCatalogInfo(&fsRef, kFSCatInfoNone, NULL, NULL, &fsSpec,
                        NULL) == noErr) {
                ATSFontActivateFromFileSpecification(&fsSpec,
                        kATSFontContextLocal, kATSFontFormatUnspecified, NULL,
                        kATSOptionFlagsDefault, &fontContainerRef);
            }
        }
    }

    return fontContainerRef;
}




@implementation NSString (MMExtras)

- (NSString *)stringByEscapingPercent
{
    NSMutableString *string = [self mutableCopy];

    // Some '%' may already be escaped, so un-escape first...
    [string replaceOccurrencesOfString:@"\\%"
                            withString:@"%"
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];
    // ...then escape all '%'
    [string replaceOccurrencesOfString:@"%"
                            withString:@"\\%"
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];

    return [string autorelease];
}

- (NSString *)stringByEscapingSpace
{
    NSMutableString *string = [self mutableCopy];

    // Some space chars may already be escaped, so un-escape first...
    [string replaceOccurrencesOfString:@"\\ "
                            withString:@" "
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];
    // ...then escape all space chars
    [string replaceOccurrencesOfString:@" "
                            withString:@"\\ "
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [string length])];

    return [string autorelease];
}

- (NSString *)stringByEscapingInvalidFilenameCharacters
{
    return [[self stringByEscapingSpace] stringByEscapingPercent];
}


@end // NSString (MMExtras)
