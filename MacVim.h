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


#define MM_USE_DO 1



#if MM_USE_DO

@protocol MMBackendProtocol
- (oneway void)processInput:(int)msgid data:(in NSData *)data;
- (BOOL)checkForModifiedBuffers;
@end

@protocol MMFrontendProtocol
- (oneway void)processCommandQueue:(in NSArray *)queue;
@end

@protocol MMAppProtocol
- (byref id <MMFrontendProtocol>)connectBackend:
    (byref in id <MMBackendProtocol>)backend;
@end

#endif



enum {
    CheckinMsgID = 1,
    ConnectedMsgID,
    KillTaskMsgID,
    TaskExitedMsgID,
    OpenVimWindowMsgID,
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
    BrowseForFileMsgID,
    BrowseForFileReplyMsgID,
    FlushQueueMsgID,
    UpdateInsertionPointMsgID,
    AddMenuMsgID,
    AddMenuItemMsgID,
    RemoveMenuItemMsgID,
    EnableMenuItemMsgID,
    ExecuteMenuMsgID,
    ShowToolbarMsgID,
#if !MM_USE_DO
    TaskShouldTerminateMsgID,
    TerminateReplyYesMsgID,
    TerminateReplyNoMsgID,
#endif
    CreateScrollbarMsgID,
    DestroyScrollbarMsgID,
    ShowScrollbarMsgID,
    SetScrollbarPositionMsgID,
    SetScrollbarThumbMsgID,
    ScrollbarEventMsgID,
    SetFontMsgID,
    VimShouldCloseMsgID,
    SetDefaultColorsMsgID,
};


enum {
    ClearAllDrawType = 1,
    ClearBlockDrawType,
    DeleteLinesDrawType,
    ReplaceStringDrawType,
    InsertLinesDrawType
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


@interface NSPortMessage (MacVim)

+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        receivePort:(NSPort *)receivePort components:(NSArray *)components
               wait:(BOOL)wait;
+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        receivePort:(NSPort *)receivePort data:(NSData *)data wait:(BOOL)wait;
+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        receivePort:(NSPort *)receivePort wait:(BOOL)wait;
+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        components:(NSArray *)components wait:(BOOL)wait;
+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort
        data:(NSData *)data wait:(BOOL)wait;
+ (BOOL)sendMessage:(int)msgid withSendPort:(NSPort *)sendPort wait:(BOOL)wait;

@end

// vim: set ft=objc:
