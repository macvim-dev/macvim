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


@class MMFindBarView;

@protocol MMFindBarViewDelegate <NSObject>
- (void)findBarView:(MMFindBarView *)view findNext:(BOOL)forward;
- (void)findBarView:(MMFindBarView *)view replace:(BOOL)replaceAll;
- (void)findBarViewDidClose:(MMFindBarView *)view;
// Returns the rect (in MMFindBarView's superview coordinates) within which the
// bar may be dragged.  Typically this is the text-view frame, excluding the
// tabline and scrollbars.
- (NSRect)findBarViewDraggableBounds:(MMFindBarView *)view;
@end


@interface MMFindBarView : NSView <NSTextFieldDelegate>

@property (nonatomic, assign) id<MMFindBarViewDelegate> delegate;

- (void)showWithText:(NSString *)text flags:(int)flags;
- (NSString *)findString;
- (NSString *)replaceString;
- (BOOL)ignoreCase;
- (BOOL)matchWord;

@end
