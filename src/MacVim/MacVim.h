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
#import <asl.h>


// Taken from /usr/include/AvailabilityMacros.h
#ifndef MAC_OS_X_VERSION_10_4
# define MAC_OS_X_VERSION_10_4 1040
#endif
#ifndef MAC_OS_X_VERSION_10_5
# define MAC_OS_X_VERSION_10_5 1050
#endif
#ifndef MAC_OS_X_VERSION_10_6
# define MAC_OS_X_VERSION_10_6 1060
#endif
#ifndef MAC_OS_X_VERSION_10_7
# define MAC_OS_X_VERSION_10_7 1070
#endif


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
// Do not add methods to this interface without a _very_ good reason (if
// possible, instead add a new message to the *MsgID enum below and pass it via
// processInput:forIdentifier).  Methods should not modify the state directly
// but should instead delay any potential modifications (see
// connectBackend:pid: and processInput:forIdentifier:).
//
@protocol MMAppProtocol
- (unsigned)connectBackend:(byref in id <MMBackendProtocol>)proxy pid:(int)pid;
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
    OpenWindowMsgID = 1,    // NOTE: FIRST IN ENUM MUST BE 1
    KeyDownMsgID,
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
    EnterFullScreenMsgID,
    LeaveFullScreenMsgID,
    SetBuffersModifiedMsgID,
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
    SetFullScreenColorMsgID,
    ShowFindReplaceDialogMsgID,
    FindReplaceMsgID,
    ActivateKeyScriptMsgID,
    DeactivateKeyScriptMsgID,
    EnableImControlMsgID,
    DisableImControlMsgID,
    ActivatedImMsgID,
    DeactivatedImMsgID,
    BrowseForFileMsgID,
    ShowDialogMsgID,
    NetBeansMsgID,
    SetMarkedTextMsgID,
    ZoomMsgID,
    SetWindowPositionMsgID,
    DeleteSignMsgID,
    SetTooltipMsgID,
    SetTooltipDelayMsgID,
    GestureMsgID,
    AddToMRUMsgID,
    BackingPropertiesChangedMsgID,
    LastMsgID   // NOTE: MUST BE LAST MESSAGE IN ENUM!
};


enum {
    ClearAllDrawType = 1,
    ClearBlockDrawType,
    DeleteLinesDrawType,
    DrawStringDrawType,
    InsertLinesDrawType,
    DrawCursorDrawType,
    SetCursorPosDrawType,
    DrawInvertedRectDrawType,
    DrawSignDrawType,
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

enum {
    MMGestureSwipeLeft,
    MMGestureSwipeRight,
    MMGestureSwipeUp,
    MMGestureSwipeDown,
};


// Create a string holding the labels of all messages in message queue for
// debugging purposes (condense some messages since there may typically be LOTS
// of them on a queue).
NSString *debugStringForMessageQueue(NSArray *queue);


// Shared user defaults (most user defaults are in Miscellaneous.h).
// Contrary to the user defaults in Miscellaneous.h these defaults are not
// intitialized to any default values.  That is, unless the user sets them
// these keys will not be present in the user default database.
extern NSString *MMLogLevelKey;
extern NSString *MMLogToStdErrKey;

// Argument used to stop MacVim from opening an empty window on startup
// (techincally this is a user default but should not be used as such).
extern NSString *MMNoWindowKey;

extern NSString *MMAutosaveRowsKey;
extern NSString *MMAutosaveColumnsKey;
extern NSString *MMRendererKey;

enum {
    MMRendererDefault = 0,
    MMRendererATSUI,
    MMRendererCoreText
};


extern NSString *VimFindPboardType;




@interface NSString (MMExtras)
- (NSString *)stringByEscapingSpecialFilenameCharacters;
- (NSString *)stringByRemovingFindPatterns;
- (NSString *)stringBySanitizingSpotlightSearch;
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




#ifndef NSINTEGER_DEFINED
// NSInteger was introduced in 10.5
# if __LP64__ || NS_BUILD_32_LIKE_64
typedef long NSInteger;
typedef unsigned long NSUInteger;
# else
typedef int NSInteger;
typedef unsigned int NSUInteger;
# endif
# define NSINTEGER_DEFINED 1
#endif

#ifndef NSAppKitVersionNumber10_4  // Needed for pre-10.5 SDK
# define NSAppKitVersionNumber10_4 824
#endif

#ifndef CGFLOAT_DEFINED
    // On Leopard, CGFloat is float on 32bit and double on 64bit. On Tiger,
    // we can't use this anyways, so it's just here to keep the compiler happy.
    // However, when we're compiling for Tiger and running on Leopard, we
    // might need the correct typedef, so this piece is copied from ATSTypes.h
# ifdef __LP64__
    typedef double CGFloat;
# else
    typedef float CGFloat;
# endif
#endif


// Logging related functions and macros.
//
// This is a very simplistic logging facility built on top of ASL.  Two user
// defaults allow for changing the local log filter level (MMLogLevel) and
// whether logs should be sent to stderr (MMLogToStdErr).  (These user defaults
// are only checked during startup.)  The default is to block level 6 (info)
// and 7 (debug) logs and _not_ to send logs to stderr.  Apart from this
// "syslog" (see "man syslog") can be used to modify the ASL filters (it is
// currently not possible to change the local filter at runtime).  For example:
//   Enable all logs to reach the ASL database (by default 'debug' and 'info'
//   are filtered out, see "man syslogd"):
//     $ sudo syslog -c syslogd -d
//   Reset the ASL database filter:
//     $ sudo syslog -c syslogd off
//   Change the master filter to block logs less severe than errors:
//     $ sudo syslog -c 0 -e
//   Change per-process filter for running MacVim process to block logs less
//   severe than warnings:
//     $ syslog -c MacVim -w
//
// Note that there are four ASL filters:
//   1) The ASL database filter (syslog -c syslogd ...)
//   2) The master filter (syslog -c 0 ...)
//   3) The per-process filter (syslog -c PID ...)
//   4) The local filter (MMLogLevel)
//
// To view the logs, either use "Console.app" or the "syslog" command:
//   $ syslog -w | grep Vim
// To get the logs to show up in Xcode enable the MMLogToStdErr user default.

extern int ASLogLevel;

void ASLInit();

#define ASLog(level, fmt, ...) \
    if (level <= ASLogLevel) { \
        asl_log(NULL, NULL, level, "%s@%d: %s", \
            __PRETTY_FUNCTION__, __LINE__, \
            [[NSString stringWithFormat:fmt, ##__VA_ARGS__] UTF8String]); \
    }

// Note: These macros are used like ASLogErr(@"text num=%d", 42).  Objective-C
// style specifiers (%@) are supported.
#define ASLogCrit(fmt, ...)   ASLog(ASL_LEVEL_CRIT,    fmt, ##__VA_ARGS__)
#define ASLogErr(fmt, ...)    ASLog(ASL_LEVEL_ERR,     fmt, ##__VA_ARGS__)
#define ASLogWarn(fmt, ...)   ASLog(ASL_LEVEL_WARNING, fmt, ##__VA_ARGS__)
#define ASLogNotice(fmt, ...) ASLog(ASL_LEVEL_NOTICE,  fmt, ##__VA_ARGS__)
#define ASLogInfo(fmt, ...)   ASLog(ASL_LEVEL_INFO,    fmt, ##__VA_ARGS__)
#define ASLogDebug(fmt, ...)  ASLog(ASL_LEVEL_DEBUG,   fmt, ##__VA_ARGS__)
#define ASLogTmp(fmt, ...)    ASLog(ASL_LEVEL_NOTICE,  fmt, ##__VA_ARGS__)
