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
    "ODBEditMsgID",
    "XcodeModMsgID",
    "LiveResizeMsgID",
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
NSString *MMNoFontSubstitutionKey       = @"MMNoFontSubstitution";
NSString *MMLoginShellKey               = @"MMLoginShell";
NSString *MMAtsuiRendererKey            = @"MMAtsuiRenderer";




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




    NSString *
buildTabDropCommand(NSArray *filenames)
{
    // Create a command line string that will open the specified files in tabs.

    if (!filenames || [filenames count] == 0)
        return [NSString string];

    NSMutableString *cmd = [NSMutableString stringWithString:
            @"<C-\\><C-N>:tab drop"];

    NSEnumerator *e = [filenames objectEnumerator];
    id o;
    while ((o = [e nextObject])) {
        NSString *file = [o stringByEscapingSpecialFilenameCharacters];
        [cmd appendString:@" "];
        [cmd appendString:file];
    }

    [cmd appendString:@"|redr|f<CR>"];

    return cmd;
}

    NSString *
buildSelectRangeCommand(NSRange range)
{
    // Build a command line string that will select the given range of lines.
    // If range.length == 0, then position the cursor on the given line but do
    // not select.

    if (range.location == NSNotFound)
        return [NSString string];

    NSString *cmd;
    if (range.length > 0) {
        cmd = [NSString stringWithFormat:@"<C-\\><C-N>%dGV%dGz.0",
                NSMaxRange(range), range.location];
    } else {
        cmd = [NSString stringWithFormat:@"<C-\\><C-N>%dGz.0", range.location];
    }

    return cmd;
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



@implementation NSIndexSet (MMExtras)

+ (id)indexSetWithVimList:(NSString *)list
{
    NSMutableIndexSet *idxSet = [NSMutableIndexSet indexSet];
    NSArray *array = [list componentsSeparatedByString:@"\n"];
    unsigned i, count = [array count];

    for (i = 0; i < count; ++i) {
        NSString *entry = [array objectAtIndex:i];
        if ([entry intValue] > 0)
            [idxSet addIndex:i];
    }

    return idxSet;
}

@end // NSIndexSet (MMExtras)




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

