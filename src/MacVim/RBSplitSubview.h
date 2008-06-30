//
//  RBSplitSubview.h version 1.1.4
//  RBSplitView
//
//  Created by Rainer Brockerhoff on 19/11/2004.
//  Copyright 2004-2006 Rainer Brockerhoff.
//	Some Rights Reserved under the Creative Commons Attribution License, version 2.5, and/or the MIT License.
//

#import <Cocoa/Cocoa.h>

@class RBSplitView;

// These values are used to inquire about the status of a subview.
typedef enum {
	RBSSubviewExpanding=-2,
	RBSSubviewCollapsing=-1,
	RBSSubviewNormal=0,
	RBSSubviewCollapsed=1
} RBSSubviewStatus;

@interface RBSplitSubview : NSView {
// Subclasses normally should use setter methods instead of changing instance variables by assignment.
// Most getter methods simply return the corresponding instance variable, so with some care, subclasses
// could reference them directly.
	NSString* identifier;			// An identifier string for the subview, default is @"".
	int tag;						// A tag integer for the subview, default is 0.
	float minDimension;				// The minimum dimension. Must be 1.0 or any larger integer.
	float maxDimension;				// The maximum dimension. Must be at least equal to the minDimension.
									// Set to a large number if there's no maximum.
	double fraction;				// A fractional part of the dimension, used for proportional resizing.
									// Normally varies between -0.999... and 0.999...
									// When collapsed, holds the proportion of the RBSplitView's dimension
									// the view was occupying before collapsing.
	NSRect previous;				// Holds the frame rect for the last delegate notification.
	NSSize savedSize;				// This holds the size the subview had before it was resized beyond
									// its minimum or maximum limits. Valid if notInLimits is YES.
	unsigned int actDivider;		// This is set temporarily while an alternate drag view is being dragged.
	BOOL canDragWindow;				// This is set temporarily during a mouseDown on a non-opaque subview.
	BOOL canCollapse;				// YES if the subview can be collapsed.
	BOOL notInLimits;				// YES if the subview's dimensions are outside the set limits.
}

// This class method returns YES if some RBSplitSubview is being animated.
+ (BOOL)animating;

// This is the designated initializer for creating extra subviews programmatically.
- (id)initWithFrame:(NSRect)frame;

// Returns the immediately containing RBSplitView, or nil if there is none.
// couplingSplitView returns nil if we're a non-coupled RBSplitView.
// outermostSplitView returns the outermost RBSplitView.
- (RBSplitView*)splitView;
- (RBSplitView*)couplingSplitView;
- (RBSplitView*)outermostSplitView;

// Returns self if we're a RBSplitView, nil otherwise. Convenient for testing or calling methods.
// coupledSplitView returns nil if we're a non-coupled RBSplitView.
- (RBSplitView*)asSplitView;
- (RBSplitView*)coupledSplitView;

// Sets and gets the coupling between the view and its containing RBSplitView (if any). Coupled
// RBSplitViews take some parameters, such as divider images, from the containing view. The default
// for RBSplitView is YES. However, calling setCoupled: on a RBSplitSubview will have no effect,
// and isCoupled will always return false.
- (void)setCoupled:(BOOL)flag;
- (BOOL)isCoupled;

// Returns YES if the containing RBSplitView is horizontal.
- (BOOL)splitViewIsHorizontal;

// Returns the number of subviews. Just a convenience method.
- (unsigned)numberOfSubviews;

// Sets and gets the tag.
- (void)setTag:(int)theTag;
- (int)tag;

// Sets and gets the identifier string. Will never be nil.
- (void)setIdentifier:(NSString*)aString;
- (NSString*)identifier;

// Position means the subview's position within the RBSplitView - counts from zero left to right
// or top to bottom. Setting it will move the subview to another position without changing its size,
// status or attributes. Set position to 0 to move it to the start, or to some large number to move it
// to the end of the RBSplitView.
- (unsigned)position;
- (void)setPosition:(unsigned)newPosition;

// Returns YES if the subview is collapsed. Collapsed subviews are squashed down to zero but never
// made smaller than the minimum dimension as far as their own subviews are concerned. If the
// subview is being animated this will return NO.
- (BOOL)isCollapsed;

// This will return the current status of the subview. Negative values mean the subview is
// being animated.
- (RBSSubviewStatus)status;

// Sets and gets the ability to collapse the subview. However, this can be overridden by the delegate.
- (BOOL)canCollapse;
- (void)setCanCollapse:(BOOL)flag;

// Tests whether the subview can shrink or expand further.
- (BOOL)canShrink;
- (BOOL)canExpand;	

// Sets and gets the minimum and maximum dimensions. They're set at the same time to make sure values
// are consistent. Despite being floats, they'll always have integer values. The minimum value for the
// minimum is 1.0. Pass 0.0 for the maximum to set it to some huge number.
- (float)minDimension;
- (float)maxDimension;
- (void)setMinDimension:(float)newMinDimension andMaxDimension:(float)newMaxDimension;

// Call this to expand a subview programmatically. It will return the subview's dimension after
// expansion.
- (float)expand;

// Call this to collapse a subview programmatically. It will return the negative
// of the subview's dimension _before_ collapsing, or 0.0 if the subview can't be collapsed.
- (float)collapse;

// These calls collapse and expand subviews with animation. They return YES if animation
// startup was successful.
- (BOOL)collapseWithAnimation;
- (BOOL)expandWithAnimation;

// These methods collapse and expand subviews with animation, depending on the parameters.
// They return YES if animation startup was successful. If resize is NO, the subview is
// collapsed/expanded without resizing it during animation.
- (BOOL)collapseWithAnimation:(BOOL)animate withResize:(BOOL)resize;
- (BOOL)expandWithAnimation:(BOOL)animate withResize:(BOOL)resize;

// Returns the current dimension of the subview.
- (float)dimension;

// Sets the current dimension of the subview, subject to the current maximum and minimum.
// If the subview is collapsed, this has no immediate effect.
- (void)setDimension:(float)value;

// This method is used internally when a divider is dragged. It tries to change the subview's dimension
// and returns the actual change, collapsing or expanding whenever possible. You usually won't need
// to call this directly.
- (float)changeDimensionBy:(float)increment mayCollapse:(BOOL)mayCollapse move:(BOOL)move;

@end

