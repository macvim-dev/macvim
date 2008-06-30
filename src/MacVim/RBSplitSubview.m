//
//  RBSplitSubview.m version 1.1.4
//  RBSplitView
//
//  Created by Rainer Brockerhoff on 19/11/2004.
//  Copyright 2004-2006 Rainer Brockerhoff.
//	Some Rights Reserved under the Creative Commons Attribution License, version 2.5, and/or the MIT License.
//

#import "RBSplitView.h"
#import "RBSplitViewPrivateDefines.h"

// This variable points to the animation data structure while an animation is in
// progress; if there's none, it will be NULL. Animating may be very CPU-intensive so
// we allow only one animation to take place at a time.
static animationData* currentAnimation = NULL;

@implementation RBSplitSubview

// This class method returns YES if an animation is in progress.
+ (BOOL)animating {
	return currentAnimation!=NULL;
}

// This is the designated initializer for RBSplitSubview. It sets some reasonable defaults. However, you
// can't rely on anything working until you insert it into a RBSplitView.
- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
	if (self) {
		fraction = 0.0;
		canCollapse = NO;
		notInLimits = NO;
		minDimension = 1.0;
		maxDimension = WAYOUT;
		identifier = @"";
		previous = NSZeroRect;
		savedSize = frame.size;
		actDivider = NSNotFound;
		canDragWindow = NO;
	}
	return self;
}

// Just releases our stuff when going away.
- (void)dealloc {
	[identifier release];
	[super dealloc];
}

// These return nil since we're not a RBSplitView (they're overridden there).
- (RBSplitView*)asSplitView {
	return nil;
}

- (RBSplitView*)coupledSplitView {
	return nil;
}

// Sets and gets the coupling between a RBSplitView and its containing RBSplitView (if any).
// For convenience, these methods are also implemented here.
- (void)setCoupled:(BOOL)flag {
}

- (BOOL)isCoupled {
	return NO;
}

// RBSplitSubviews are never flipped, unless they're RBSplitViews.
- (BOOL)isFlipped {
	return NO;
}

// We copy the opacity of the owning split view.
- (BOOL)isOpaque {
	return [[self couplingSplitView] isOpaque];
}

// A hidden RBSplitSubview is not redrawn and is not considered for drawing dividers.
// This won't work before 10.3, though.
- (void)setHidden:(BOOL)flag {
	if ([self isHidden]!=flag) {
		RBSplitView* sv = [self splitView];
		[self RB___setHidden:flag];
		if (flag) {
			[sv adjustSubviews];
		} else {
			[sv adjustSubviewsExcepting:self];
		}
	}
}

// RBSplitSubviews can't be in the responder chain.
- (BOOL)acceptsFirstResponder {
	return NO;
}

// Mousing down should move the window only for a completely transparent background. This might have
// unintended side effects in metal windows, so for those you might want to use a background color
// with a very low alpha (0.01 for instance).
// This is commented out as I'm still experimenting with it.
/*- (BOOL)mouseDownCanMoveWindow {
	RBSplitView* sv = [self asSplitView];
	if (!sv) {
		sv = [self couplingSplitView];
	}
	return [sv background]==nil;
	return YES;
}*/

// This returns the owning splitview. It's guaranteed to return a RBSplitView or nil.
// You should avoid having "orphan" RBSplitSubviews, or at least manipulating
// them while they're not inserted in a RBSplitView.
- (RBSplitView*)splitView {
	id result = [self superview];
	if ([result isKindOfClass:[RBSplitView class]]) {
		return (RBSplitView*)result;
	}
	return nil;
}

// This also returns the owning splitview. It's overridden for nested RBSplitViews.
- (RBSplitView*)couplingSplitView {
	id result = [self superview];
	if ([result isKindOfClass:[RBSplitView class]]) {
		return (RBSplitView*)result;
	}
	return nil;
}

// This returns the outermost directly containing RBSplitView, or nil.
- (RBSplitView*)outermostSplitView {
	id result = nil;
	id sv = self;
	while ((sv = [sv superview])&&[sv isKindOfClass:[RBSplitView class]]) {
		result = sv;
	}
	return result;
}

// This convenience method returns YES if the containing RBSplitView is horizontal.
- (BOOL)splitViewIsHorizontal {
	return [[self splitView] isHorizontal];
}

// You can use either tags (ints) or identifiers (NSStrings) to identify individual subviews.
// We take care not to have nil identifiers.
- (void)setTag:(int)theTag {
	tag = theTag;
}

- (int)tag {
	return tag;
}

- (void)setIdentifier:(NSString*)aString {
	[identifier autorelease];
	identifier = aString?[aString retain]:@"";
}

- (NSString*)identifier {
	return identifier;
}

// If we have an identifier, this will make debugging a little easier by appending it to the
// default description.
- (NSString*)description {
	return [identifier length]>0?[NSString stringWithFormat:@"%@(%@)",[super description],identifier]:[super description];
}

// This pair of methods allows you to get and change the position of a subview (within the split view);
// this counts from zero from the left or top of the split view.
- (unsigned)position {
	RBSplitView* sv = [self splitView];
	return sv?[[sv subviews] indexOfObjectIdenticalTo:self]:0;
}

- (void)setPosition:(unsigned)newPosition {
	RBSplitView* sv = [self splitView];
	if (sv) {
		[self retain];
		[self removeFromSuperviewWithoutNeedingDisplay];
		NSArray* subviews = [sv subviews];
		if (newPosition>=[subviews count]) {
			[sv addSubview:self positioned:NSWindowAbove relativeTo:nil];
		} else {
			[sv addSubview:self positioned:NSWindowBelow relativeTo:[subviews objectAtIndex:newPosition]];
		}
		[self release];
	}
}

// Tests whether the subview is collapsed.
- (BOOL)isCollapsed {
	return [self RB___visibleDimension]<=0.0;
}

// Tests whether the subview can shrink further.
- (BOOL)canShrink {
	return [self RB___visibleDimension]>([self canCollapse]?0.0:minDimension);
}

// Tests whether the subview can expand further.
- (BOOL)canExpand {
	return [self RB___visibleDimension]<maxDimension;
}

// Returns the subview's status.
- (RBSSubviewStatus)status {
	animationData* anim = [self RB___animationData:NO resize:NO];
	if (anim) {
		return anim->collapsing?RBSSubviewCollapsing:RBSSubviewExpanding;
	}
	return [self RB___visibleDimension]<=0.0?RBSSubviewCollapsed:RBSSubviewNormal;
}

// Tests whether the subview can be collapsed. The local instance variable will be overridden by the
// delegate method if it's implemented.
- (BOOL)canCollapse {
	BOOL result = canCollapse;
	RBSplitView* sv = [self splitView];
	if ([sv RB___numberOfSubviews]<2) {
		return NO;
	}
	id delegate = [sv delegate];
	if ([delegate respondsToSelector:@selector(splitView:canCollapse:)]) {
		result = [delegate splitView:sv canCollapse:self];
	}
	return result;
}

// This sets the subview's "canCollapse" flag. Ignored if the delegate's splitView:canCollapse:
// method is implemented.
- (void)setCanCollapse:(BOOL)flag {
	canCollapse = flag;
}

// This expands a collapsed subview and calls the delegate's splitView:didExpand: method, if it exists.
// This is not called internally by other methods; call this to expand a subview programmatically.
// As a convenience to other methods, it returns the subview's dimension after expanding (this may be
// off by 1 pixel due to rounding) or 0.0 if it couldn't be expanded.
// The delegate should not change the subview's frame.
- (float)expand {
	return [self RB___expandAndSetToMinimum:NO];
}

// This collapses an expanded subview and calls the delegate's splitView:didCollapse: method, if it exists.
// This is not called internally by other methods; call this to expand a subview programmatically.
// As a convenience to other methods, it returns the negative of the subview's dimension before
// collapsing (or 0.0 if it couldn't be collapsed).
// The delegate should not change the subview's frame.
- (float)collapse {
	return [self RB___collapse];
}

// This tries to collapse the subview with animation, and collapses it instantly if some other
// subview is animating. Returns YES if animation was started successfully.
- (BOOL)collapseWithAnimation {
	return [self collapseWithAnimation:YES withResize:YES];
}

// This tries to expand the subview with animation, and expands it instantly if some other
// subview is animating. Returns YES if animation was started successfully.
- (BOOL)expandWithAnimation {
	return [self expandWithAnimation:YES withResize:YES];
}

// These methods collapse and expand subviews with animation, depending on the parameters.
// They return YES if animation startup was successful. If resize is NO, the subview is
// collapsed/expanded without resizing it during animation.
- (BOOL)collapseWithAnimation:(BOOL)animate withResize:(BOOL)resize {
	if ([self status]==RBSSubviewNormal) {
		if ([self canCollapse]) {
			if (animate&&[self RB___animationData:YES resize:resize]) {
				[self RB___clearResponder];
				[self RB___stepAnimation];
				return YES;
			} else {
				[self RB___collapse];
			}
		}
	}
	return NO;
}

- (BOOL)expandWithAnimation:(BOOL)animate withResize:(BOOL)resize {
	if ([self status]==RBSSubviewCollapsed) {
		if (animate&&[self RB___animationData:YES resize:resize]) {
			[self RB___stepAnimation];
			return YES;
		} else {
			[self RB___expandAndSetToMinimum:NO];
		}
	}
	return NO;
}


// These 3 methods get and set the view's minimum and maximum dimensions.
// The minimum dimension ought to be an integer at least equal to 1.0 but we make sure.
// The maximum dimension ought to be an integer at least equal to the minimum. As a convenience,
// pass in zero to set it to some huge number.
- (float)minDimension {
	return minDimension;
}

- (float)maxDimension {
	return maxDimension;
}

- (void)setMinDimension:(float)newMinDimension andMaxDimension:(float)newMaxDimension {
	minDimension = MAX(1.0,floorf(newMinDimension));
	if (newMaxDimension<1.0) {
		newMaxDimension = WAYOUT;
	}
	maxDimension = MAX(minDimension,floorf(newMaxDimension));
	float dim = [self dimension];
	if ((dim<minDimension)||(dim>maxDimension)) {
		[[self splitView] setMustAdjust];
	}
}

// This returns the subview's dimension. If it's collapsed, it returns the dimension it would have
// after expanding.
- (float)dimension {
	float dim = [self RB___visibleDimension];
	if (dim<=0.0) {
		dim = [[self splitView] RB___dimensionWithoutDividers]*fraction;
		if (dim<minDimension) {
			dim = minDimension;
		} else if (dim>maxDimension) {
			dim = maxDimension;
		}
	}
	return dim;
}

// Sets the current dimension of the subview, subject to the current maximum and minimum.
// If the subview is collapsed, this will have an effect only after reexpanding.
- (void)setDimension:(float)value {
	RBSplitView* sv = [self splitView];
	NSSize size = [self frame].size;
	BOOL ishor = [sv isHorizontal];
	if (DIM(size)>0.0) {
// We're not collapsed, set the size and adjust other subviews.
		DIM(size) = value;
		[self setFrameSize:size];
		[sv adjustSubviewsExcepting:self];
	} else {
// We're collapsed, adjust the fraction so that we'll have the (approximately) correct
// dimension after expanding.
		fraction = value/[sv RB___dimensionWithoutDividers];
	}
}

// This just draws the background of a subview, then tells the delegate, if any.
// The delegate would usually draw a frame inside the subview.
- (void)drawRect:(NSRect)rect {
	RBSplitView* sv = [self splitView];
	NSColor* bg = [sv background];
	if (bg) {
		[bg set];
		NSRectFillUsingOperation(rect,NSCompositeSourceOver);
	}
	id del = [sv delegate];
	if ([del respondsToSelector:@selector(splitView:willDrawSubview:inRect:)]) {
		[del splitView:sv willDrawSubview:self inRect:rect];
	}
}

// We check if the RBSplitView must be adjusted before redisplaying programmatically.
// if so, we adjust and display the whole RBSplitView.
- (void)display {
	RBSplitView* sv = [self splitView];
	if (sv) {
		if ([sv mustAdjust]) {
			[sv display];
		} else {
			[super display];
		}
	}
}

// RBSplitSubviews will always resize their own subviews.
- (BOOL)autoresizesSubviews {
	return YES;
}

// This is method is called automatically when the subview is resized; don't call it yourself.
- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize {
	RBSplitView* sv = [self splitView];
	if (sv) {
		BOOL ishor = [sv isHorizontal];
		NSRect frame = [self frame];
		float dim = DIM(frame.size);
		float other = OTHER(frame.size);
// We resize subviews only when we're inside the subview's limits and the containing splitview's limits.
		animationData* anim = [self RB___animationData:NO resize:NO];
		if ((dim>=(anim&&!anim->resizing?anim->dimension:minDimension))&&(dim<=maxDimension)&&(other>=[sv minDimension])&&(other<=[sv maxDimension])) {
			if (notInLimits) {
// The subviews can be resized, so we restore the saved size.
				oldBoundsSize = savedSize;
			}
// We save the size every time the subview's subviews are resized within the limits.
			notInLimits = NO;
			savedSize = frame.size;
			[super resizeSubviewsWithOldSize:oldBoundsSize];
		} else {
			notInLimits = YES;
		}
	}
}

// This method is used internally when a divider is dragged. It tries to change the subview's dimension
// and returns the actual change, collapsing or expanding whenever possible. You usually won't need
// to call this directly.
- (float)changeDimensionBy:(float)increment mayCollapse:(BOOL)mayCollapse move:(BOOL)move {
	RBSplitView* sv = [self splitView];
	if (!sv||(fabsf(increment)<1.0)) {
		return 0.0;
	}
	BOOL ishor = [sv isHorizontal];
	NSRect frame = [self frame];
	float olddim = DIM(frame.size);
	float newdim = MAX(0.0,olddim+increment);
	if (newdim<olddim) {
		if (newdim<minDimension) {
// Collapse if needed
			if (mayCollapse&&[self canCollapse]&&(newdim<MAX(1.0,minDimension*(0.5-HYSTERESIS)))) {
				return [self RB___collapse];
			}
			newdim = minDimension;
		}
	} else if (newdim>olddim) {
		if (olddim<1.0) {
// Expand if needed.
			if (newdim>(minDimension*(0.5+HYSTERESIS))) {
				newdim = MAX(newdim,[self RB___expandAndSetToMinimum:YES]);
			} else {
				return 0.0;
			}
		}
		if (newdim>maxDimension) {
			newdim = maxDimension;
		}
	}
	if ((int)newdim!=(int)olddim) {
// The dimension has changed.
		increment = newdim-olddim;
		DIM(frame.size) = newdim;
		if (move) {
			DIM(frame.origin) -= increment;
		}
// We call super instead of self here to postpone adjusting subviews for nested splitviews.
//		[super setFrameSize:frame.size];
		[super setFrame:frame];
		[sv RB___setMustClearFractions];
		[sv setMustAdjust];
	}
	return newdim-olddim;
}

// This convenience method returns the number of subviews (surprise!)
- (unsigned)numberOfSubviews {
	return [[self subviews] count];
}

// We return the deepest subview that's hit by aPoint. We also check with the delegate if aPoint is
// within an alternate drag view.
- (NSView*)hitTest:(NSPoint)aPoint {
	RBSplitView* sv = [self splitView];
	if ([self mouse:aPoint inRect:[self frame]]) {
		id delegate = [sv delegate];
		if ([delegate respondsToSelector:@selector(splitView:dividerForPoint:inSubview:)]) {
			actDivider = [delegate splitView:sv dividerForPoint:aPoint inSubview:self];
			if ((int)actDivider<(int)([sv RB___numberOfSubviews]-1)) {
				return self;
			}
		}
		actDivider = NSNotFound;
		NSView* result = [super hitTest:aPoint];
		canDragWindow = ![result isOpaque];
		return result;
	}
	return nil;
}

// This method handles clicking and dragging in an empty portion of the subview, or in an alternate
// drag view as designated by the delegate.
- (void)mouseDown:(NSEvent*)theEvent {
	NSWindow* window = [self window];
	NSPoint where = [theEvent locationInWindow];
	if (actDivider<NSNotFound) {
// The mouse down was inside an alternate drag view; actDivider was just set in hitTest.
		RBSplitView* sv = [self splitView];
		NSPoint point = [sv convertPoint:where fromView:nil];
		[[RBSplitView cursor:RBSVDragCursor] push];
		NSPoint base = NSZeroPoint;
// Record the current divider coordinate.
		float divc = [sv RB___dividerOrigin:actDivider];
		BOOL ishor = [sv isHorizontal];
		[sv RB___setDragging:YES];
// Loop while the button is down.
		while ((theEvent = [NSApp nextEventMatchingMask:NSLeftMouseDownMask|NSLeftMouseDraggedMask|NSLeftMouseUpMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES])&&([theEvent type]!=NSLeftMouseUp)) {
// Set up a local autorelease pool for the loop to prevent buildup of temporary objects.
			NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
			NSDisableScreenUpdates();
// This does the actual movement.
			[sv RB___trackMouseEvent:theEvent from:point withBase:base inDivider:actDivider];
			if ([sv mustAdjust]) {
// If something changed, we clear fractions and redisplay.
				[sv RB___setMustClearFractions];
				[sv display];
			}
// Change the drag point by the actual amount moved.
			float newc = [sv RB___dividerOrigin:actDivider];
			DIM(point) += newc-divc;
			divc = newc;
			NSEnableScreenUpdates();
			[pool release];
		}
		[sv RB___setDragging:NO];
		[NSCursor pop];
		actDivider = NSNotFound;
		return;
	}
	if (canDragWindow&&[window isMovableByWindowBackground]&&![[self couplingSplitView] background]) {
// If we get here, it's a textured (metal) window, the mouse has gone down on an non-opaque portion
// of the subview, and our RBSplitView has a transparent background. RBSplitView returns NO to
// mouseDownCanMoveWindow, but the window should move here - after all, the window background
// is visible right here! So we fake it and move the window as intended. Mwahahaha!
		where =  [window convertBaseToScreen:where];
		NSPoint origin = [window frame].origin;
// Now we loop handling mouse events until we get a mouse up event.
		while ((theEvent = [NSApp nextEventMatchingMask:NSLeftMouseDownMask|NSLeftMouseDraggedMask|NSLeftMouseUpMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES])&&([theEvent type]!=NSLeftMouseUp)) {
// Set up a local autorelease pool for the loop to prevent buildup of temporary objects.
			NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
			NSPoint now = [window convertBaseToScreen:[theEvent locationInWindow]];
			origin.x += now.x-where.x;
			origin.y += now.y-where.y;
// Move the window by the mouse displacement since the last event.
			[window setFrameOrigin:origin];
			where = now;
			[pool release];
		}
	}
}

// These two methods encode and decode subviews.
- (void)encodeWithCoder:(NSCoder*)coder {
	NSRect frame;
	BOOL coll = [self isCollapsed];
	if (coll) {
// We can't encode a collapsed subview as-is, so we correct the frame size first and add WAYOUT
// to the origin to signal it was collapsed. 
		NSRect newf = frame = [self frame];
		newf.origin.x += WAYOUT;
		[super setFrameOrigin:newf.origin];
		newf.size = savedSize;
		[super setFrameSize:newf.size];
	}
	[super encodeWithCoder:coder];
	if (coll) {
		[super setFrame:frame];
	}
	if ([coder allowsKeyedCoding]) {
		[coder encodeObject:identifier forKey:@"identifier"];
		[coder encodeInt:tag forKey:@"tag"];
		[coder encodeFloat:minDimension forKey:@"minDimension"];
		[coder encodeFloat:maxDimension forKey:@"maxDimension"];
		[coder encodeDouble:fraction forKey:@"fraction"];
		[coder encodeBool:canCollapse forKey:@"canCollapse"];
	} else {
		[coder encodeObject:identifier];
		[coder encodeValueOfObjCType:@encode(typeof(tag)) at:&tag];
		[coder encodeValueOfObjCType:@encode(typeof(minDimension)) at:&minDimension];
		[coder encodeValueOfObjCType:@encode(typeof(maxDimension)) at:&maxDimension];
		[coder encodeValueOfObjCType:@encode(typeof(fraction)) at:&fraction];
		[coder encodeValueOfObjCType:@encode(typeof(canCollapse)) at:&canCollapse];
	}
}

- (id)initWithCoder:(NSCoder*)coder {
    if ((self = [super initWithCoder:coder])) {
		fraction = 0.0;
		canCollapse = NO;
		notInLimits = NO;
		minDimension = 1.0;
		maxDimension = WAYOUT;
		identifier = @"";
		actDivider = NSNotFound;
		canDragWindow = NO;
		previous = [self frame];
		savedSize = previous.size;
		if (previous.origin.x>=WAYOUT) {
// The subview was collapsed when encoded, so we correct the origin and collapse it.
			BOOL ishor = [self splitViewIsHorizontal];
			previous.origin.x -= WAYOUT;
			DIM(previous.size) = 0.0;
			[self setFrameOrigin:previous.origin];
			[self setFrameSize:previous.size];
		}
		previous = NSZeroRect;
		if ([coder allowsKeyedCoding]) {
			[self setIdentifier:[coder decodeObjectForKey:@"identifier"]];
			tag = [coder decodeIntForKey:@"tag"];
			minDimension = [coder decodeFloatForKey:@"minDimension"];
			maxDimension = [coder decodeFloatForKey:@"maxDimension"];
			fraction = [coder decodeDoubleForKey:@"fraction"];
			canCollapse = [coder decodeBoolForKey:@"canCollapse"];
		} else {
			[self setIdentifier:[coder decodeObject]];
			[coder decodeValueOfObjCType:@encode(typeof(tag)) at:&tag];
			[coder decodeValueOfObjCType:@encode(typeof(minDimension)) at:&minDimension];
			[coder decodeValueOfObjCType:@encode(typeof(maxDimension)) at:&maxDimension];
			[coder decodeValueOfObjCType:@encode(typeof(fraction)) at:&fraction];
			[coder decodeValueOfObjCType:@encode(typeof(canCollapse)) at:&canCollapse];
		}
	}
    return self;
}

@end

@implementation RBSplitSubview (RB___SubviewAdditions)

// This hides/shows the subview without calling adjustSubview.
- (void)RB___setHidden:(BOOL)flag {
	[super setHidden:flag];
}

// This internal method returns the current animationData. It will always return nil if
// the receiver isn't the current owner and some other subview is already being animated.
// Otherwise, if the parameter is YES, a new animation will be started (or the current
// one will be restarted).
- (animationData*)RB___animationData:(BOOL)start resize:(BOOL)resize {
	if (currentAnimation&&(currentAnimation->owner!=self)) {
// There already is an animation in progress on some other subview.
		return nil;
	}
	if (start) {
// We want to start (or restart) an animation.
		RBSplitView* sv = [self splitView];
		if (sv) {
			float dim = [self dimension];
// First assume the default time, then ask the delegate.
			NSTimeInterval total = dim*(0.2/150.0);
			id delegate = [sv delegate];
			if ([delegate respondsToSelector:@selector(splitView:willAnimateSubview:withDimension:)]) {
				total = [delegate splitView:sv willAnimateSubview:self withDimension:dim];
			}
// No use animating anything shorter than the frametime.
			if (total>FRAMETIME) {
				if (!currentAnimation) {
					currentAnimation = (animationData*)malloc(sizeof(animationData));
				}
				if (currentAnimation) {
					currentAnimation->owner = self;
					currentAnimation->stepsDone = 0;
					currentAnimation->elapsedTime = 0.0;
					currentAnimation->dimension = dim;
					currentAnimation->collapsing = ![self isCollapsed];
					currentAnimation->totalTime = total;
					currentAnimation->finishTime = [NSDate timeIntervalSinceReferenceDate]+total;
					currentAnimation->resizing = resize;
					[sv RB___setDragging:YES];
				}
			} else if (currentAnimation) {
				free(currentAnimation);
				currentAnimation = NULL;
			}
		}
	}
	return currentAnimation;
}

// This internal method steps the animation to the next frame.
- (void)RB___stepAnimation {
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	animationData* anim = [self RB___animationData:NO resize:NO];
	if (anim) {
		RBSplitView* sv = [self splitView];
		NSTimeInterval remain = anim->finishTime-now;
		NSRect frame = [self frame];
		BOOL ishor = [sv isHorizontal];
// Continuing animation only makes sense if we still have at least FRAMETIME available.
		if (remain>=FRAMETIME) {
			float dim = DIM(frame.size);
			float avg = anim->elapsedTime;
// We try to keep a record of how long it takes, on the average, to resize and adjust
// one animation frame.
			if (anim->stepsDone) {
				avg /= anim->stepsDone;
			}
			NSTimeInterval delay = MIN(0.0,FRAMETIME-avg);
// We adjust the new dimension proportionally to how much of the designated time has passed.
			dim = floorf(anim->dimension*(remain-avg)/anim->totalTime);
			if (dim>4.0) {
				if (!anim->collapsing) {
					dim = anim->dimension-dim;
				} 
				DIM(frame.size) = dim;
				[self RB___setFrame:frame withFraction:0.0 notify:NO];
				[sv adjustSubviews];
				[self display];
				anim->elapsedTime += [NSDate timeIntervalSinceReferenceDate]-now;
				++anim->stepsDone;
// Schedule a timer to do the next animation step.
				[self performSelector:@selector(RB___stepAnimation) withObject:nil afterDelay:delay inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode,NSModalPanelRunLoopMode,
					NSEventTrackingRunLoopMode,nil]];
				return;
			}
		}
// We're finished, either collapse or expand entirely now.
		if (anim->collapsing) {
			DIM(frame.size) = 0.0;
			[self RB___finishCollapse:frame withFraction:anim->dimension/[sv RB___dimensionWithoutDividers]];
		} else {
			float savemin,savemax;
			float dim = [self RB___setMinAndMaxTo:anim->dimension savingMin:&savemin andMax:&savemax];
			DIM(frame.size) = dim;
			[self RB___finishExpand:frame withFraction:0.0];
			minDimension = savemin;
			maxDimension = savemax;
		}
	}
}

// This internal method stops the animation, if the receiver is being animated. It will
// return YES if the animation was stopped.
- (BOOL)RB___stopAnimation {
	if (currentAnimation&&(currentAnimation->owner==self)) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(RB___stepAnimation) object:nil];
		free(currentAnimation);
		currentAnimation = NULL;
		[[self splitView] RB___setDragging:NO];
		return YES;
	}
	return NO;
}

// This internal method returns the actual visible dimension of the subview. Differs from -dimension in
// that it returns 0.0 if the subview is collapsed.
- (float)RB___visibleDimension {
	BOOL ishor = [self splitViewIsHorizontal];
	NSRect frame = [self frame];
	return MAX(0.0,DIM(frame.size));
}

// This pair of internal methods is used only inside -[RBSplitView adjustSubviews] to copy subview data
// from and to that method's internal cache.
- (void)RB___copyIntoCache:(subviewCache*)cache {
	cache->sub = self;
	cache->rect = [self frame];
	cache->size = [self RB___visibleDimension];
	cache->fraction = fraction;
	cache->constrain = NO;
}

- (void)RB___updateFromCache:(subviewCache*)cache withTotalDimension:(float)value {
	float dim = [self RB___visibleDimension];
	if (cache->size>=1.0) {
// New state is not collapsed.
		if (dim>=1.0) {
// Old state was not collapsed, so we just change the frame.
			[self RB___setFrame:cache->rect withFraction:cache->fraction notify:YES];
		} else {
// Old state was collapsed, so we expand it.
			[self RB___finishExpand:cache->rect withFraction:cache->fraction];
		}
	} else {
// New state is collapsed.
		if (dim>=1.0) {
// Old state was not collapsed, so we clear first responder and change the frame.
			[self RB___clearResponder];
			[self RB___finishCollapse:cache->rect withFraction:dim/value];
		} else {
// It was collapsed already, but the frame may have changed, so we set it.
			[self RB___setFrame:cache->rect withFraction:cache->fraction notify:YES];
		}
	}
}

// This internal method sets minimum and maximum values to the same value, saves the old values,
// and returns the new value (which will be limited to the old values).
- (float)RB___setMinAndMaxTo:(float)value savingMin:(float*)oldmin andMax:(float*)oldmax {
	*oldmin = [self minDimension];
	*oldmax = [self maxDimension];
	if (value<*oldmin) {
		value = *oldmin;
	}
	if (value>*oldmax) {
		value = *oldmax;
	}
	minDimension = maxDimension = value;
	return value;
}

// This internal method tries to clear the first responder, if the current responder is a descendant of
// the receiving subview. If so, it will set first responder to nil, redisplay the former responder and
// return YES. Returns NO otherwise.
- (BOOL)RB___clearResponder {
	NSWindow* window = [self window];
	if (window) {
		NSView* responder = (NSView*)[window firstResponder];
		if (responder&&[responder respondsToSelector:@selector(isDescendantOf:)]) {
			if ([responder isDescendantOf:self]) {
				if ([window makeFirstResponder:nil]) {
					[responder display];
					return YES;
				}
			}
		}
	}
	return NO;
}

// This internal method collapses a subview.
// It returns the negative of the size of the subview before collapsing, or 0.0 if it wasn't collapsed.
- (float)RB___collapse {
	float result = 0.0;
	if (![self isCollapsed]) {
		RBSplitView* sv = [self splitView];
		if (sv&&[self canCollapse]) {
			[self RB___clearResponder];
			NSRect frame = [self frame];
			BOOL ishor = [sv isHorizontal];
			result = DIM(frame.size);
// For collapsed views, fraction will contain the fraction of the dimension previously occupied
			DIM(frame.size) = 0.0;
			[self RB___finishCollapse:frame withFraction:result/[sv RB___dimensionWithoutDividers]];
		}
	}
	return -result;
}

// This internal method finishes the collapse of a subview, stopping the animation if
// there is one, and calling the delegate method if there is one.
- (void)RB___finishCollapse:(NSRect)rect withFraction:(double)value {
	RBSplitView* sv = [self splitView];
	BOOL finish = [self RB___stopAnimation];
	[self RB___setFrame:rect withFraction:value notify:YES];
	[sv RB___setMustClearFractions];
	if (finish) {
		[self display];
	}
	id delegate = [sv delegate];
	if ([delegate respondsToSelector:@selector(splitView:didCollapse:)]) {
		[delegate splitView:sv didCollapse:self];
	}
}

// This internal method expands a subview. setToMinimum will usually be YES during a divider drag.
// It returns the size of the subview after expanding, or 0.0 if it wasn't expanded.
- (float)RB___expandAndSetToMinimum:(BOOL)setToMinimum {
	float result = 0.0;
	RBSplitView* sv = [self splitView];
	if (sv&&[self isCollapsed]) {
		NSRect frame = [super frame];
		double frac = fraction;
		BOOL ishor = [sv isHorizontal];
		if (setToMinimum) {
			result = DIM(frame.size) = minDimension;
		} else {
			result = [sv RB___dimensionWithoutDividers]*frac;
// We need to apply a compensation factor for proportional resizing in adjustSubviews.
			float newdim = floorf((frac>=1.0)?result:result/(1.0-frac));
			DIM(frame.size) = newdim;
			result = floorf(result);
		}
		[self RB___finishExpand:frame withFraction:0.0];
	}
	return result;
}

// This internal method finishes the the expansion of a subview, stopping the animation if
// there is one, and calling the delegate method if there is one.
- (void)RB___finishExpand:(NSRect)rect withFraction:(double)value {
	RBSplitView* sv = [self splitView];
	BOOL finish = [self RB___stopAnimation];
	[self RB___setFrame:rect withFraction:value notify:YES];
	[sv RB___setMustClearFractions];
	if (finish) {
		[self display];
	}
	id delegate = [sv delegate];
	if ([delegate respondsToSelector:@selector(splitView:didExpand:)]) {
		[delegate splitView:sv didExpand:self];
	}
}

// These internal methods set the subview's frame or size, and also store a fraction value
// which is used to ensure repeatability when the whole split view is resized.
- (void)RB___setFrame:(NSRect)rect withFraction:(double)value notify:(BOOL)notify {
	RBSplitView* sv = [self splitView];
	id delegate = nil;
	if (notify) {
		delegate = [sv delegate];
// If the delegate method isn't implemented, we ignore the delegate altogether.
		if ([delegate respondsToSelector:@selector(splitView:changedFrameOfSubview:from:to:)]) {
// If the rects are equal, the delegate isn't called.
			if (NSEqualRects(previous,rect)) {
				delegate = nil;
			}
		} else {
			delegate = nil;
		}
	}
	[sv setMustAdjust];
	[self setFrame:rect];
	fraction = value;
	[delegate splitView:sv changedFrameOfSubview:self from:previous to:rect];
	previous = delegate?rect:NSZeroRect;
}

- (void)RB___setFrameSize:(NSSize)size withFraction:(double)value {
	[[self splitView] setMustAdjust];
	[self setFrameSize:size];
	fraction = value;
}

// This internal method gets the fraction value.
- (double)RB___fraction {
	return fraction;
}

@end

