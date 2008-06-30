//
//  RBSplitView.h version 1.1.4
//  RBSplitView
//
//  Created by Rainer Brockerhoff on 24/09/2004.
//  Copyright 2004-2006 Rainer Brockerhoff.
//	Some Rights Reserved under the Creative Commons Attribution License, version 2.5, and/or the MIT License.
//

#import "RBSplitSubview.h"

// These values are used to handle the various cursor types.
typedef enum {
	RBSVHorizontalCursor=0,		// appears over horizontal dividers
	RBSVVerticalCursor,			// appears over vertical dividers
	RBSV2WayCursor,				// appears over two-way thumbs
	RBSVDragCursor,				// appears while dragging
	RBSVCursorTypeCount
} RBSVCursorType;

@interface RBSplitView : RBSplitSubview {
// Subclasses normally should use setter methods instead of changing instance variables by assignment.
// Most getter methods simply return the corresponding instance variable, so with some care, subclasses
// could reference them directly.
	IBOutlet id delegate;		// The delegate (may be nil).
	NSString* autosaveName;		// This name is used for storing subview proportions in user defaults.
	NSColor* background;		// The color used to paint the view's background (may be nil).
	NSImage* divider;			// The image used for the divider "dimple".
	NSRect* dividers;			// A C array of NSRects, one for each divider.
	float dividerThickness;		// Actual divider width; should be an integer and at least 1.0.
	BOOL mustAdjust;			// Set internally if the subviews need to be adjusted.
	BOOL mustClearFractions;	// Set internally if fractions should be cleared before adjusting.
	BOOL isHorizontal;			// The divider's orientation; default is vertical.
	BOOL canSaveState;			// Set internally to allow saving subview state.
	BOOL isCoupled;				// If YES, take some parameters from the containing RBSplitView, if any.
	BOOL isAdjusting;			// Set internally while the subviews are being adjusted.
	BOOL isDragging;			// Set internally while in a drag loop.
	BOOL isInScrollView;		// Set internally if directly contained in an NSScrollView.
}

// These class methods get and set the cursor used for each type.
// Pass in nil to reset to the default cursor for that type.
+ (NSCursor*)cursor:(RBSVCursorType)type;
+ (void)setCursor:(RBSVCursorType)type toCursor:(NSCursor*)cursor;

// This class method clears the saved state for a given autosave name from the defaults.
+ (void)removeStateUsingName:(NSString*)name;

// This class method returns the actual key used to store autosave data in the defaults.
+ (NSString*)defaultsKeyForName:(NSString*)name isHorizontal:(BOOL)orientation;

// Sets and gets the autosaveName; this will be the key used to store the subviews' proportions
// in the user defaults. Default is @"", which doesn't save anything. Set flag to YES to set
// unique names for nested subviews. You are responsible for avoiding duplicates.
- (void)setAutosaveName:(NSString*)aString recursively:(BOOL)flag;
- (NSString*)autosaveName;

// Saves the current state of the subviews if there's a valid autosave name set. If the argument
// is YES, it's then also called recursively for nested RBSplitViews. Returns YES if successful.
- (BOOL)saveState:(BOOL)recurse;

// Restores the saved state of the subviews if there's a valid autosave name set. If the argument
// is YES, it's first called recursively for nested RBSplitViews. Returns YES if successful.
// You need to call adjustSubviews after calling this.
- (BOOL)restoreState:(BOOL)recurse;

// Returns a string encoding the current state of all direct subviews. Does not check for nesting.
- (NSString*)stringWithSavedState;

// Readjusts all direct subviews according to the encoded string parameter. The number of subviews
// must match. Returns YES if successful. Does not check for nesting.
- (BOOL)setStateFromString:(NSString*)aString;

// Returns an array with complete state information for the receiver and all subviews, taking
// nesting into account. Don't store this array in a file, as its format might change in the
// future; this is for taking a state snapshot and later restoring it with setStatesFromArray.
- (NSArray*)arrayWithStates;

// Restores the state of the receiver and all subviews. The array must have been produced by a
// previous call to arrayWithStates. Returns YES if successful. This will fail if you have
// added or removed subviews in the meantime!
// You need to call adjustSubviews after calling this.
- (BOOL)setStatesFromArray:(NSArray*)array;

// This is the designated initializer for creating RBSplitViews programmatically.
- (id)initWithFrame:(NSRect)frame;

// This convenience initializer adds any number of subviews and adjusts them proportionally.
- (id)initWithFrame:(NSRect)frame andSubviews:(unsigned)count;

// Sets and gets the delegate. (Delegates aren't retained.) See further down for delegate methods.
- (void)setDelegate:(id)anObject;
- (id)delegate;

// Returns a subview which has a certain identifier string, or nil if there's none
- (RBSplitSubview*)subviewWithIdentifier:(NSString*)anIdentifier;

// Returns the subview at a certain position. Returns nil if the position is invalid.
- (RBSplitSubview*)subviewAtPosition:(unsigned)position;

// Adds a subview at a certain position.
- (void)addSubview:(NSView*)aView atPosition:(unsigned)position;

// Sets and gets the divider thickness, which should be a positive integer or zero.
// Setting the divider image also resets this automatically, so you would call this
// only if you want the divider to be larger or smaller than the image. Zero means that
// the image dimensions will be used.
- (void)setDividerThickness:(float)thickness;
- (float)dividerThickness;

// Sets and gets the divider image. The default image can also be set in Interface Builder, so usually
// there's no need to call this. Passing in nil means that the default divider thickness will be zero,
// and no mouse events will be processed, so that the dividers can be moved only programmatically.
- (void)setDivider:(NSImage*)image;
- (NSImage*)divider;

// Sets and gets the view background. The default is nil, meaning no background is
// drawn and the view and its subviews are considered transparent.
- (void)setBackground:(NSColor*)color;
- (NSColor*)background;

// Sets and gets the orientation. This uses the same convention as NSSplitView: vertical means the
// dividers are vertical, but the subviews are in a horizontal row. Sort of counter-intuitive, yes.
- (void)setVertical:(BOOL)flag;
- (BOOL)isVertical;
- (BOOL)isHorizontal;

// Call this to force adjusting the subviews before display. Called automatically if anything
// relevant is changed.
- (void)setMustAdjust;

// Returns YES if there's a pending adjustment.
- (BOOL)mustAdjust;

// Returns YES if we're in a dragging loop.
- (BOOL)isDragging;

// Returns YES if the view is directly contained in an NSScrollView.
- (BOOL)isInScrollView;

// Call this to recalculate all subview dimensions. Normally this is done automatically whenever
// something relevant is changed, so you rarely will need to call this explicitly.
- (void)adjustSubviews;

// This method should be called only from within the splitView:wasResizedFrom:to: delegate method
// to keep some specific subview the same size.
- (void)adjustSubviewsExcepting:(RBSplitSubview*)excepting;

// This method draws dividers. You should never call it directly but you can override it when
// subclassing, if you need custom dividers.
- (void)drawDivider:(NSImage*)anImage inRect:(NSRect)rect betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing;

@end

// The following methods are optionally implemented by the delegate.

@interface NSObject(RBSplitViewDelegate)

// The delegate can override a subview's ability to collapse by implementing this method.
// Return YES to allow collapsing. If this is implemented, the subviews' built-in
// 'collapsed' flags are ignored.
- (BOOL)splitView:(RBSplitView*)sender canCollapse:(RBSplitSubview*)subview;

// The delegate can alter the divider's appearance by implementing this method.
// Before calling this, the divider is filled with the background, and afterwards
// the divider image is drawn into the returned rect. If imageRect is empty, no
// divider image will be drawn, because there are nested RBSplitViews. Return
// NSZeroRect to suppress the divider image. Return imageRect to use the default
// location for the image, or change its origin to place the image elsewhere.
// You could also draw the divider yourself at this point and return NSZeroRect.
- (NSRect)splitView:(RBSplitView*)sender willDrawDividerInRect:(NSRect)dividerRect betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing withProposedRect:(NSRect)imageRect;

// These methods are called after a subview is completely collapsed or expanded. adjustSubviews may or may not
// have been called, however.
- (void)splitView:(RBSplitView*)sender didCollapse:(RBSplitSubview*)subview;
- (void)splitView:(RBSplitView*)sender didExpand:(RBSplitSubview*)subview;

// These methods are called just before and after adjusting subviews.
- (void)willAdjustSubviews:(RBSplitView*)sender;
- (void)didAdjustSubviews:(RBSplitView*)sender;

// This method will be called after a RBSplitView is resized with setFrameSize: but before
// adjustSubviews is called on it.
- (void)splitView:(RBSplitView*)sender wasResizedFrom:(float)oldDimension to:(float)newDimension;

// This method will be called when a divider is double-clicked and both leading and trailing
// subviews can be collapsed. Return either of the parameters to collapse that subview, or nil
// to collapse neither. If not implemented, the smaller subview will be collapsed.
- (RBSplitSubview*)splitView:(RBSplitView*)sender collapseLeading:(RBSplitSubview*)leading orTrailing:(RBSplitSubview*)trailing;

// This method will be called when a cursor rect is being set (inside resetCursorRects). The
// proposed rect is passed in. Return the actual rect, or NSZeroRect to suppress cursor setting
// for this divider. This won't be called for two-axis thumbs, however. The rects are in
// sender's local coordinates.
- (NSRect)splitView:(RBSplitView*)sender cursorRect:(NSRect)rect forDivider:(unsigned int)divider;

// This method will be called whenever a mouse-down event is received in a divider. Return YES to have
// the event handled by the split view, NO if you wish to ignore it or handle it in the delegate.
- (BOOL)splitView:(RBSplitView*)sender shouldHandleEvent:(NSEvent*)theEvent inDivider:(unsigned int)divider betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing;

// This method will be called just before a subview will be collapsed or expanded with animation.
// Return the approximate time the animation should take, or 0.0 to disallow animation.
// If not implemented, it will use the default of 0.2 seconds per 150 pixels.
- (NSTimeInterval)splitView:(RBSplitView*)sender willAnimateSubview:(RBSplitSubview*)subview withDimension:(float)dimension;

// This method will be called whenever a subview's frame is changed, usually from inside adjustSubviews' final loop.
// You'd normally use this to move some auxiliary view to keep it aligned with the subview.
- (void)splitView:(RBSplitView*)sender changedFrameOfSubview:(RBSplitSubview*)subview from:(NSRect)fromRect to:(NSRect)toRect;

// This method is called whenever the event handlers want to check if some point within the RBSplitSubview
// should act as an alternate drag view. Usually, the delegate will check the point (which is in sender's
// local coordinates) against the frame of one or several auxiliary views, and return a valid divider number.
// Returning NSNotFound means the point is not valid.
- (unsigned int)splitView:(RBSplitView*)sender dividerForPoint:(NSPoint)point inSubview:(RBSplitSubview*)subview;

// This method is called continuously while a divider is dragged, just before the leading subview is resized.
// Return NO to resize the trailing view by the same amount, YES to resize the containing window by the same amount.
- (BOOL)splitView:(RBSplitView*)sender shouldResizeWindowForDivider:(unsigned int)divider betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing willGrow:(BOOL)grow;

// This method is called by each subview's drawRect: method, just after filling it with the background color but
// before the contained subviews are drawn. Usually you would use this to draw a frame inside the subview.
- (void)splitView:(RBSplitView*)sender willDrawSubview:(RBSplitSubview*)subview inRect:(NSRect)rect;

@end

