//
//  RBSplitViewPrivateDefines.h version 1.1.4
//  RBSplitView
//
//  Created by Rainer Brockerhoff on 19/11/2004.
//  Copyright 2004-2006 Rainer Brockerhoff.
//	Some Rights Reserved under the Creative Commons Attribution License, version 2.5, and/or the MIT License.
//

// These defines are used only locally; no sense exporting them in the main header file where they might
// conflict with something...

// This is the hysteresis value for collapsing/expanding subviews with the mouse. 0.05 (5%) works well.
#define HYSTERESIS (0.05)

// This selects the main horizontal or vertical coordinate according to the split view's orientation.
// It can be used as an lvalue, too. You need to have BOOL ishor declared to use it.
#define DIM(x) (((float*)&(x))[ishor])

// This selects the other coordinate.
#define OTHER(x) (((float*)&(x))[!ishor])

// This value for the view offsets is guaranteed to be out of view for quite some time and is used
// to mark the view as collapsed.
#define WAYOUT (1000000.0)

// This is the default framerate for collapse/expand animation.
#define FRAMETIME (1.0/60.0)

// This struct is used internally for speeding up adjustSubviews.
typedef struct subviewCache {
	NSRect rect;					// the subview's frame
	double fraction;				// fractional extra
	RBSplitSubview* sub;			// points at the subview
	float size;						// current dimension (integer)
	BOOL constrain;					// set if constrained
} subviewCache;

// This struct is used internally for doing collapse/expand animation.
typedef struct animationData {
	RBSplitSubview* owner;			// the subview being animated
	float dimension;				// the subview's starting or ending dimension
	int stepsDone;					// counts already done animation steps
	NSTimeInterval elapsedTime;		// time already spent in resizing and adjusting subviews
	NSTimeInterval finishTime;		// the animation should be finished at this time
	NSTimeInterval totalTime;		// total time the animation should take
	BOOL collapsing;				// YES if we're collapsing, NO if we're expanding
	BOOL resizing;					// YES if we're resizing, NO if we're frozen
} animationData;

// The following methods are for internal use, and you should never call or override them.
// They'll probably vary wildy from version to version, too.

@interface RBSplitSubview (RB___SubviewAdditions)

- (void)RB___setHidden:(BOOL)flag;
- (animationData*)RB___animationData:(BOOL)start resize:(BOOL)resize;
- (void)RB___stepAnimation;
- (BOOL)RB___stopAnimation;
- (float)RB___visibleDimension;
- (float)RB___setMinAndMaxTo:(float)value savingMin:(float*)oldmin andMax:(float*)oldmax;
- (float)RB___collapse;
- (float)RB___expandAndSetToMinimum:(BOOL)setToMinimum;
- (void)RB___finishCollapse:(NSRect)rect withFraction:(double)value;
- (void)RB___finishExpand:(NSRect)rect withFraction:(double)value;
- (void)RB___setFrameSize:(NSSize)size withFraction:(double)value;
- (void)RB___setFrame:(NSRect)rect withFraction:(double)value notify:(BOOL)notify;
- (double)RB___fraction;
- (void)RB___copyIntoCache:(subviewCache*)cache;
- (void)RB___updateFromCache:(subviewCache*)cache withTotalDimension:(float)value;
- (BOOL)RB___clearResponder;

@end

@interface RBSplitView (RB___ViewAdditions)

- (void)RB___adjustOutermostIfNeeded;
- (void)RB___setDragging:(BOOL)flag;
- (float)RB___dividerOrigin:(int)indx;
- (NSArray*)RB___subviews;
- (unsigned int)RB___numberOfSubviews;
- (void)RB___adjustSubviewsExcepting:(RBSplitSubview*)excepting;
- (float)RB___dimensionWithoutDividers;
- (float)RB___dividerThickness;
- (NSRect)RB___dividerRect:(unsigned)indx relativeToView:(RBSplitView*)view;
- (void)RB___setMustClearFractions;
- (BOOL)RB___shouldResizeWindowForDivider:(unsigned int)indx betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing willGrow:(BOOL)grow;
- (void)RB___tryToExpandLeading:(RBSplitSubview*)leading divider:(unsigned int)indx trailing:(RBSplitSubview*)trailing delta:(float)delta;
- (void)RB___tryToShortenLeading:(RBSplitSubview*)leading divider:(unsigned int)indx trailing:(RBSplitSubview*)trailing delta:(float)delta always:(BOOL)always;
- (void)RB___tryToExpandTrailing:(RBSplitSubview*)trailing leading:(RBSplitSubview*)leading delta:(float)delta;
- (void)RB___tryToShortenTrailing:(RBSplitSubview*)trailing divider:(unsigned int)indx leading:(RBSplitSubview*)leading delta:(float)delta always:(BOOL)always;
- (void)RB___trackMouseEvent:(NSEvent*)theEvent from:(NSPoint)where withBase:(NSPoint)base inDivider:(unsigned)indx;
- (void)RB___addCursorRectsTo:(RBSplitView*)masterView forDividerRect:(NSRect)rect thickness:(float)delta;
- (unsigned)RB___dividerHitBy:(NSPoint)point relativeToView:(RBSplitView*)view thickness:(float)delta;
- (void)RB___drawDividersIn:(RBSplitView*)masterView forDividerRect:(NSRect)rect thickness:(float)delta;

@end

