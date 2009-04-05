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


//
// Enable support for MacVim plugins (not to be confused with Vim plugins!).
//
#define MM_ENABLE_PLUGINS



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
- (oneway void)processInput:(int)msgid data:(in bycopy NSData *)data;
- (oneway void)setDialogReturn:(in bycopy id)obj;
- (NSString *)evaluateExpression:(in bycopy NSString *)expr;
- (id)evaluateExpressionCocoa:(in bycopy NSString *)expr
                  errorString:(out bycopy NSString **)errstr;
- (BOOL)starRegisterToPasteboard:(byref NSPasteboard *)pboard;
- (oneway void)acknowledgeConnection;
@end


//
// This is the protocol MMAppController implements.
//
// It handles connections between MacVim and Vim and communication from Vim to
// MacVim.
//
@protocol MMAppProtocol
- (unsigned)connectBackend:(byref in id <MMBackendProtocol>)backend
                       pid:(int)pid;
- (oneway void)processInput:(in bycopy NSArray *)queue
              forIdentifier:(unsigned)identifier;
- (NSArray *)serverList;
@end


@protocol MMVimServerProtocol;

//
// The Vim client protocol (implemented by MMBackend).
//
// The client needs to keep track of server replies.  Take a look at MMBackend
// if you want to implement this protocol in another program.
//
@protocol MMVimClientProtocol
- (oneway void)addReply:(in bycopy NSString *)reply
                 server:(in byref id <MMVimServerProtocol>)server;
@end


//
// The Vim server protocol (implemented by MMBackend).
//
// Note that addInput:client: is not asynchronous, because otherwise Vim might
// quit before the message has been passed (e.g. if --remote was used on the
// command line).
//
@protocol MMVimServerProtocol
- (void)addInput:(in bycopy NSString *)input
                 client:(in byref id <MMVimClientProtocol>)client;
- (NSString *)evaluateExpression:(in bycopy NSString *)expr
                 client:(in byref id <MMVimClientProtocol>)client;
@end



//
// The following enum lists all messages that are passed between MacVim and
// Vim.  These can be sent in processInput:data: and in processCommandQueue:.
//

// NOTE! This array must be updated whenever the enum below changes!
extern char *MessageStrings[];

enum {
    OpenWindowMsgID = 1,
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
    SetTextRowsMsgID,
    SetTextColumnsMsgID,
    SetTextDimensionsMsgID,
    LiveResizeMsgID,
    SetTextDimensionsReplyMsgID,
    SetWindowTitleMsgID,
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
    SetWideFontMsgID,
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
    ActivateMsgID,
    SetServerNameMsgID,
    EnterFullscreenMsgID,
    LeaveFullscreenMsgID,
    BuffersNotModifiedMsgID,
    BuffersModifiedMsgID,
    AddInputMsgID,
    SetPreEditPositionMsgID,
    TerminateNowMsgID,
    XcodeModMsgID,
    EnableAntialiasMsgID,
    DisableAntialiasMsgID,
    SetVimStateMsgID,
    SetDocumentFilenameMsgID,
    OpenWithArgumentsMsgID,
    CloseWindowMsgID,
    SetFullscreenColorMsgID,
    ShowFindReplaceDialogMsgID,
    FindReplaceMsgID,
    ActivateKeyScriptID,
    DeactivateKeyScriptID,
    BrowseForFileMsgID,
    ShowDialogMsgID,
};


#define DRAW_WIDE   0x40    /* draw wide text */

enum {
    ClearAllDrawType = 1,
    ClearBlockDrawType,
    DeleteLinesDrawType,
    DrawStringDrawType,
    InsertLinesDrawType,
    DrawCursorDrawType,
    SetCursorPosDrawType,
    DrawInvertedRectDrawType,
};

enum {
    MMInsertionPointBlock,
    MMInsertionPointHorizontal,
    MMInsertionPointVertical,
    MMInsertionPointHollow,
    MMInsertionPointVerticalRight,
};


enum {
    ToolbarLabelFlag = 1,
    ToolbarIconFlag = 2,
    ToolbarSizeRegularFlag = 4
};


enum {
    MMTabLabel = 0,
    MMTabToolTip,
    MMTabInfoCount
};

// Argument used to stop MacVim from opening an empty window on startup
// (techincally this is a user default but should not be used as such).
extern NSString *MMNoWindowKey;

// Vim pasteboard type (holds motion type + string)
extern NSString *VimPBoardType;




@interface NSString (MMExtras)
- (NSString *)stringByEscapingSpecialFilenameCharacters;
@end


@interface NSColor (MMExtras)
+ (NSColor *)colorWithRgbInt:(unsigned)rgb;
+ (NSColor *)colorWithArgbInt:(unsigned)argb;
@end


@interface NSDictionary (MMExtras)
+ (id)dictionaryWithData:(NSData *)data;
- (NSData *)dictionaryAsData;
@end

@interface NSMutableDictionary (MMExtras)
+ (id)dictionaryWithData:(NSData *)data;
@end




// ODB Editor Suite Constants (taken from ODBEditorSuite.h)
#define	keyFileSender		'FSnd'
#define	keyFileSenderToken	'FTok'
#define	keyFileCustomPath	'Burl'
#define	kODBEditorSuite		'R*ch'
#define	kAEModifiedFile		'FMod'
#define	keyNewLocation		'New?'
#define	kAEClosedFile		'FCls'
#define	keySenderToken		'Tokn'


// MacVim Apple Event Constants
#define keyMMUntitledWindow       'MMuw'




#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
// NSInteger was introduced in 10.5
# if __LP64__ || NS_BUILD_32_LIKE_64
typedef long NSInteger;
typedef unsigned long NSUInteger;
# else
typedef int NSInteger;
typedef unsigned int NSUInteger;
# endif
#endif
