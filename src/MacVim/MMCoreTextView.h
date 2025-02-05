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

@class MMTextViewHelper;

NS_ASSUME_NONNULL_BEGIN


/// The main text view that manages drawing Vim's content using Core Text, and
/// handles input. We are using this instead of NSTextView because of the
/// custom needs in order to draw Vim's texts, as we don't have access to the
/// full contents of Vim, and works more like a smart terminal to Vim.
///
/// Currently the rendering is done in software via Core Text, but a future
/// extension will add support for Metal rendering which probably will require
/// splitting this class up.
///
/// Since this class implements text rendering/input using a custom view, it
/// implements NSTextInputClient, mostly for the following needs:
/// 1. Text input. This is done via insertText / doCommandBySelector.
/// 2. Input methods (e.g. for CJK). This is done via the marked text and the
///    other APIs like selectedRange/firstRectForCharacterRange/etc.
/// 3. Support native dictionary lookup (quickLookWithEvent:) when the user
///    wants to. This mostly involves implementing the attributeSubstring /
///    firstRectForCharacterRange / characterIndexForPoint APIs.
/// There is an inherent difficulty to implementing NSTextInputClient
/// 'correctly', because it assumes we have an entire text storage with
/// indexable ranges. However, we don't have full access to Vim's internal
/// storage, and we are represening the screen view instead in row-major
/// indexing, but this becomes complicated when we want to implement marked
/// texts. We the relevant parts for comments on how we hack around this.
@interface MMCoreTextView : NSView <
    NSTextInputClient
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
    , NSFontChanging
    , NSMenuItemValidation
#endif
    >
{
    // From MMTextStorage
    int                         maxRows, maxColumns;
    int                         pendingMaxRows, pendingMaxColumns;
    NSColor                     *defaultBackgroundColor;
    NSColor                     *defaultForegroundColor;
    NSSize                      cellSize;
    NSFont                      *font;
    NSFont                      *fontWide;
    float                       linespace;
    float                       columnspace;

    // From NSTextView
    NSSize                      insetSize;

    CGFloat                     fontDescent;
    CGFloat                     fontAscent;
    CGFloat                     fontXHeight;
    BOOL                        antialias;
    BOOL                        ligatures;
    BOOL                        thinStrokes;

    BOOL                        forceRefreshFont; // when true, don't early out of setFont calls.

    MMTextViewHelper            *helper;

    // These are used in MMCoreTextView+ToolTip.m
    id trackingRectOwner_;              // (not retained)
    void *trackingRectUserData_;
    NSTrackingRectTag lastToolTipTag_;
    NSString* toolTip_;
}

@property (nonatomic) NSSize drawRectOffset; ///< A render offset to apply to the draw rects. This is currently only used in specific situations when rendering is blocked.

- (instancetype)initWithFrame:(NSRect)frame;

//
// NSFontChanging methods
//
- (void)changeFont:(nullable id)sender;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel;
#endif

//
// NSMenuItemValidation
//
- (BOOL)validateMenuItem:(NSMenuItem *)item;

//
// Public macaction's
// Note: New items here need to be handled in validateMenuItem: as well.
//
- (IBAction)cut:(id)sender;
- (IBAction)copy:(id)sender;
- (IBAction)paste:(id)sender;
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
- (IBAction)selectAll:(nullable id)sender;

//
// MMTextStorage methods
//
- (int)maxRows;
- (int)maxColumns;
- (void)getMaxRows:(int*)rows columns:(int*)cols;
- (void)setMaxRows:(int)rows columns:(int)cols;
- (int)pendingMaxRows;
- (int)pendingMaxColumns;
- (void)setPendingMaxRows:(int)rows columns:(int)cols;
- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor;
- (NSColor *)defaultBackgroundColor;
- (NSColor *)defaultForegroundColor;
- (NSRect)rectForRowsInRange:(NSRange)range;
- (NSRect)rectForColumnsInRange:(NSRange)range;

- (void)setFont:(NSFont *)newFont;
- (void)setWideFont:(NSFont *)newFont;
- (NSFont *)font;
- (NSFont *)fontWide;
- (NSSize)cellSize;
- (void)setLinespace:(float)newLinespace;

//
// MMTextView methods
//
- (void)deleteSign:(NSString *)signName;
- (void)setShouldDrawInsertionPoint:(BOOL)on;
- (void)setPreEditRow:(int)row column:(int)col;
- (void)setMouseShape:(int)shape;
- (void)setAntialias:(BOOL)state;
- (void)setLigatures:(BOOL)state;
- (void)setThinStrokes:(BOOL)state;
- (void)setImControl:(BOOL)enable;
- (void)activateIm:(BOOL)enable;
- (void)checkImState;
- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column;
- (NSRect)rectForRow:(int)row column:(int)column numRows:(int)nr
          numColumns:(int)nc;
- (void)updateCmdlineRow;
- (void)showDefinitionForCustomString:(NSString *)text row:(int)row col:(int)col;

//
// NSTextView methods
//
- (void)keyDown:(NSEvent *)event;
- (void)quickLookWithEvent:(NSEvent *)event;

//
// NSTextInputClient methods
//
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange;
- (void)doCommandBySelector:(SEL)selector;
- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange;
- (void)unmarkText;
- (NSRange)selectedRange;
- (NSRange)markedRange;
- (BOOL)hasMarkedText;
- (nullable NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange;
- (nonnull NSArray<NSAttributedStringKey> *)validAttributesForMarkedText;
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange;
- (NSUInteger)characterIndexForPoint:(NSPoint)point;

- (CGFloat)baselineDeltaForCharacterAtIndex:(NSUInteger)anIndex;

//
// NSTextContainer methods
//
- (void)setTextContainerInset:(NSSize)inset;

//
// MMCoreTextView methods
//
- (void)performBatchDrawWithData:(NSData *)data;
- (NSSize)desiredSize;
- (NSSize)minSize;
- (NSSize)constrainRows:(int *)rows columns:(int *)cols toSize:(NSSize)size;
@end


//
// This category is defined in MMCoreTextView+ToolTip.m
//
@interface MMCoreTextView (ToolTip)
- (void)setToolTipAtMousePoint:(NSString *)string;
@end

NS_ASSUME_NONNULL_END
