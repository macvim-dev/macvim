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


// Enable to use experimental 'enc' support.
#define MM_ENABLE_CONV 0



//
// This is the protocol MMBackend implements.
//
// Only processInput:data: is allowed to cause state changes in Vim; all other
// messages should only read the Vim state.  (Note that setDialogReturn: is an
// exception to this rule; there really is no other way to deal with dialogs
// since they work with callbacks, so we cannot wait for them to return.)
//
// Be careful with messages with return type other than 'oneway void' -- there
// is a reply timeout set in MMAppController, if a message fails to get a
// response within the given timeout an exception will be thrown.  Use
// @try/@catch/@finally to deal with timeouts.
//
@protocol MMBackendProtocol
- (oneway void)processInput:(int)msgid data:(in NSData *)data;
- (oneway void)processInputAndData:(in NSArray *)messages;
- (BOOL)checkForModifiedBuffers;
- (oneway void)setDialogReturn:(in bycopy id)obj;
- (BOOL)starRegisterToPasteboard:(byref NSPasteboard *)pboard;
@end


//
// This is the protocol MMVimController implements.
//
@protocol MMFrontendProtocol
- (oneway void)processCommandQueue:(in NSArray *)queue;
- (oneway void)showSavePanelForDirectory:(in bycopy NSString *)dir
                                   title:(in bycopy NSString *)title
                                  saving:(int)saving;
- (oneway void)presentDialogWithStyle:(int)style
                              message:(in bycopy NSString *)message
                      informativeText:(in bycopy NSString *)text
                         buttonTitles:(in bycopy NSArray *)buttonTitles
                      textFieldString:(in bycopy NSString *)textFieldString;
@end


//
// This is the protocol MMAppController implements.
//
// It handles connections between MacVim and Vim.
//
@protocol MMAppProtocol
- (byref id <MMFrontendProtocol>)connectBackend:
    (byref in id <MMBackendProtocol>)backend pid:(int)pid;
@end



//
// The following enum lists all messages that are passed between MacVim and
// Vim.  These can be sent in processInput:data: and in processCommandQueue:.
//

// NOTE! This array must be updated whenever the enum below changes!
extern char *MessageStrings[];

enum {
    OpenVimWindowMsgID = 1,
    InsertTextMsgID,
    KeyDownMsgID,
    CmdKeyMsgID,
    BatchDrawMsgID,
    SelectTabMsgID,
    CloseTabMsgID,
    AddNewTabMsgID,
    DraggedTabMsgID,
    UpdateTabBarMsgID,
    ShowTabBarMsgID,
    HideTabBarMsgID,
    SetTextDimensionsMsgID,
    SetVimWindowTitleMsgID,
    ScrollWheelMsgID,
    MouseDownMsgID,
    MouseUpMsgID,
    MouseDraggedMsgID,
    FlushQueueMsgID,
    AddMenuMsgID,
    AddMenuItemMsgID,
    RemoveMenuItemMsgID,
    EnableMenuItemMsgID,
    ExecuteMenuMsgID,
    ShowToolbarMsgID,
    ToggleToolbarMsgID,
    CreateScrollbarMsgID,
    DestroyScrollbarMsgID,
    ShowScrollbarMsgID,
    SetScrollbarPositionMsgID,
    SetScrollbarThumbMsgID,
    ScrollbarEventMsgID,
    SetFontMsgID,
    VimShouldCloseMsgID,
    SetDefaultColorsMsgID,
    ExecuteActionMsgID,
    DropFilesMsgID,
    DropStringMsgID,
    ShowPopupMenuMsgID,
    GotFocusMsgID,
    LostFocusMsgID,
    MouseMovedMsgID,
    SetMouseShapeMsgID,
    AdjustLinespaceMsgID,
};


enum {
    ClearAllDrawType = 1,
    ClearBlockDrawType,
    DeleteLinesDrawType,
    ReplaceStringDrawType,
    InsertLinesDrawType,
    DrawCursorDrawType
};

enum {
    MMInsertionPointBlock,
    MMInsertionPointHorizontal,
    MMInsertionPointVertical,
    MMInsertionPointHollow,
};


// NOTE!  These values must be close to zero, or the 'add menu' message might
// fail to distinguish type from tag.
enum {
    MenuMenubarType = 0,
    MenuPopupType,
    MenuToolbarType
};


enum {
    ToolbarLabelFlag = 1,
    ToolbarIconFlag = 2,
    ToolbarSizeRegularFlag = 4
};


// NSUserDefaults keys
extern NSString *MMNoWindowKey;
extern NSString *MMTabMinWidthKey;
extern NSString *MMTabMaxWidthKey;
extern NSString *MMTabOptimumWidthKey;
extern NSString *MMTextInsetLeftKey;
extern NSString *MMTextInsetRightKey;
extern NSString *MMTextInsetTopKey;
extern NSString *MMTextInsetBottomKey;
extern NSString *MMTerminateAfterLastWindowClosedKey;
extern NSString *MMTypesetterKey;
extern NSString *MMCellWidthMultiplierKey;
extern NSString *MMBaselineOffsetKey;
extern NSString *MMTranslateCtrlClickKey;
extern NSString *MMTopLeftPointKey;
extern NSString *MMOpenFilesInTabsKey;




// vim: set ft=objc:
