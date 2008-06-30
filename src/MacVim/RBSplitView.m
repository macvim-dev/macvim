//
//  RBSplitView.m version 1.1.4
//  RBSplitView
//
//  Created by Rainer Brockerhoff on 24/09/2004.
//  Copyright 2004-2006 Rainer Brockerhoff.
//	Some Rights Reserved under the Creative Commons Attribution License, version 2.5, and/or the MIT License.
//

#import "RBSplitView.h"
#import "RBSplitViewPrivateDefines.h"

// Please don't remove this copyright notice!
static const unsigned char RBSplitView_Copyright[] __attribute__ ((used)) =
	"RBSplitView 1.1.4 Copyright(c)2004-2006 by Rainer Brockerhoff <rainer@brockerhoff.net>.";

// This vector keeps currently used cursors. nil means the default cursor.
static NSCursor* cursors[RBSVCursorTypeCount] = {nil};

// Our own fMIN and fMAX
static inline float fMIN(float a,float b) {
	return a<b?a:b;
}

static inline float fMAX(float a,float b) {
	return a>b?a:b;
}

@implementation RBSplitView

// These class methods get and set the cursor used for each type.
// Pass in nil to reset to the default cursor for that type.
+ (NSCursor*)cursor:(RBSVCursorType)type {
	if ((type>=0)&&(type<RBSVCursorTypeCount)) {
		NSCursor* result = cursors[type];
		if (result) {
			return result;
		}
		switch (type) {
			case RBSVHorizontalCursor:
				return [NSCursor resizeUpDownCursor];
			case RBSVVerticalCursor:
				return [NSCursor resizeLeftRightCursor];
			case RBSV2WayCursor:
				return [NSCursor openHandCursor];
			case RBSVDragCursor:
				return [NSCursor closedHandCursor];
			default:
				break;
		}
	}
	return [NSCursor currentCursor];
}

+ (void)setCursor:(RBSVCursorType)type toCursor:(NSCursor*)cursor {
	if ((type>=0)&&(type<RBSVCursorTypeCount)) {
		[cursors[type] release];
		cursors[type] = [cursor retain];
	}
}

// This class method clears the saved state(s) for a given autosave name from the defaults.
+ (void)removeStateUsingName:(NSString*)name {
	if ([name length]) {
		NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
		[defaults removeObjectForKey:[[self class] defaultsKeyForName:name isHorizontal:NO]];
		[defaults removeObjectForKey:[[self class] defaultsKeyForName:name isHorizontal:YES]];
	}
}

// This class method returns the actual key used to store autosave data in the defaults.
+ (NSString*)defaultsKeyForName:(NSString*)name isHorizontal:(BOOL)orientation {
    return [NSString stringWithFormat:@"RBSplitView %@ %@",orientation?@"H":@"V",name];
}

// This pair of methods gets and sets the autosave name, which allows restoring the subview's
// state from the user defaults.
// We take care not to allow nil autosaveNames.
- (NSString*)autosaveName {
	return autosaveName;
}

// Sets the autosaveName; this should be a unique key to be used to store the subviews' proportions
// in the user defaults. Default is @"", which doesn't save anything. Set flag to YES to set
// unique names for nested subviews. You are responsible for avoiding duplicates; avoid using
// the characters '[' and ']' in autosaveNames.
- (void)setAutosaveName:(NSString*)aString recursively:(BOOL)flag {
	BOOL clear;
	if ((clear = ![aString length])) {
		aString = @"";
	}
	[RBSplitView removeStateUsingName:autosaveName];
	[autosaveName autorelease];
	autosaveName = [aString retain];
	if (flag) {
		NSArray* subviews = [self subviews];
		int subcount = [subviews count];
		int i;
		for (i=0;i<subcount;i++) {
			RBSplitView* sv = [[subviews objectAtIndex:i] asSplitView];
			if (sv) {
				NSString* subst = clear?@"":[aString stringByAppendingFormat:@"[%d]",i];
				[sv setAutosaveName:subst recursively:YES];
			}
		}
	}
}

// Saves the current state of the subviews if there's a valid autosave name set. If the argument
// is YES, it's then also called recursively for nested RBSplitViews. Returns YES if successful.
// You must call restoreState explicity at least once before saveState will begin working.
- (BOOL)saveState:(BOOL)recurse {
// Saving the state is also disabled while dragging.
	if (canSaveState&&![self isDragging]&&[autosaveName length]) {
		[[NSUserDefaults standardUserDefaults] setObject:[self stringWithSavedState] forKey:[[self class] defaultsKeyForName:autosaveName isHorizontal:[self isHorizontal]]];
		if (recurse) {
			NSEnumerator* enumerator = [[self subviews] objectEnumerator];
			RBSplitSubview* sub;
			while ((sub = [enumerator nextObject])) {
				[[sub asSplitView] saveState:YES];
			}
		}
		return YES;
	}
	return NO;
}

// Restores the saved state of the subviews if there's a valid autosave name set. If the argument
// is YES, it's also called recursively for nested RBSplitViews. Returns YES if successful.
// It's good policy to call adjustSubviews immediately after calling restoreState.
- (BOOL)restoreState:(BOOL)recurse {
	BOOL result = NO;
	if ([autosaveName length]) {
		result = [self setStateFromString:[[NSUserDefaults standardUserDefaults] stringForKey:[[self class] defaultsKeyForName:autosaveName isHorizontal:[self isHorizontal]]]];
		if (result&&recurse) {
			NSEnumerator* enumerator = [[self subviews] objectEnumerator];
			RBSplitSubview* sub;
			while ((sub = [enumerator nextObject])) {
				[[sub asSplitView] restoreState:YES];
			}
		}
	}
	canSaveState = YES;
	return result;
}

// Returns an array with complete state information for the receiver and all subviews, taking
// nesting into account. Don't store this array in a file, as its format might change in the
// future; this is for taking a state snapshot and later restoring it with setStatesFromArray.
- (NSArray*)arrayWithStates {
	NSMutableArray* array = [NSMutableArray array];
	[array addObject:[self stringWithSavedState]];
	NSEnumerator* enumerator = [[self subviews] objectEnumerator];
	RBSplitSubview* sub;
	while ((sub = [enumerator nextObject])) {
		RBSplitView* suv = [sub asSplitView];
		if (suv) {
			[array addObject:[suv arrayWithStates]];
		} else {
			[array addObject:[NSNull null]];
		}
	}
	return array;
}

// Restores the state of the receiver and all subviews. The array must have been produced by a
// previous call to arrayWithStates. Returns YES if successful. This will fail if you have
// added or removed subviews in the meantime!
// You need to call adjustSubviews after calling this.
- (BOOL)setStatesFromArray:(NSArray*)array {
	NSArray* subviews = [self subviews];
	unsigned int count = [array count];
	if (count==([subviews count]+1)) {
		NSString* me = [array objectAtIndex:0];
		if ([me isKindOfClass:[NSString class]]) {
			if ([self setStateFromString:me]) {
				unsigned int i;
				for (i=1;i<count;i++) {
					NSArray* item = [array objectAtIndex:i];
					RBSplitView* suv = [[subviews objectAtIndex:i-1] asSplitView];
					if ([item isKindOfClass:[NSArray class]]==(suv!=nil)) {
						if (suv&&![suv setStatesFromArray:item]) {
							return NO;
						}
					} else {
						return NO;
					}
				}
				return YES;
			}
		}
	}
	return NO;
}

// Returns a string encoding the current state of all direct subviews. Does not check for nesting.
// The string contains the number of direct subviews, then the dimension for each subview (which will
// be negative for collapsed subviews), all separated by blanks.
- (NSString*)stringWithSavedState {
	NSArray* subviews = [self subviews];
	NSMutableString* result = [NSMutableString stringWithFormat:@"%d",[subviews count]];
	NSEnumerator* enumerator = [subviews objectEnumerator];
	RBSplitSubview* sub;
	while ((sub = [enumerator nextObject])) {
		double size = [sub dimension];
		if ([sub isCollapsed]) {
			size = -size;
		} else {
			size += +[sub RB___fraction];
		}
		[result appendFormat:[sub isHidden]?@" %gH":@" %g",size];
	}
	return result;
}

// Readjusts all direct subviews according to the encoded string parameter.
// The number of subviews must match. Returns YES if successful. Does not check for nesting.
- (BOOL)setStateFromString:(NSString*)aString {
	if ([aString length]) {
		NSArray* parts = [aString componentsSeparatedByString:@" "];
		NSArray* subviews = [self subviews];
		int subcount = [subviews count];
		int k = [parts count];
		if ((k-->1)&&([[parts objectAtIndex:0] intValue]==subcount)&&(k==subcount)) {
			int i;
			NSRect frame = [self frame];
			BOOL ishor = [self isHorizontal];
			for (i=0;i<subcount;i++) {
				NSString* part = [parts objectAtIndex:i+1];
				BOOL hidden = [part hasSuffix:@"H"];
				double size = [part doubleValue];
				BOOL negative = size<=0.0;
				if (negative) {
					size = -size;
				}
				double fract = size;
				size = floorf(size);
				fract -= size;
				DIM(frame.size) = size;
				RBSplitSubview* sub = [subviews objectAtIndex:i];
				[sub RB___setFrame:frame withFraction:fract notify:NO];
				if (negative) {
					[sub RB___collapse];
				}
				[sub RB___setHidden:hidden];
			}
			[self setMustAdjust];
			return YES;
		}
	}
	return NO;
}

// This is the designated initializer for creating RBSplitViews programmatically. You can set the
// divider image and other parameters afterwards.
- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
 		dividers = NULL;
		isCoupled = YES;
		isDragging = NO;
		isInScrollView = NO;
		canSaveState = NO;
		[self setVertical:YES];
		[self setDivider:nil];
		[self setAutosaveName:nil recursively:NO];
		[self setBackground:nil];
	}
	return self;
}

// This convenience initializer adds any number of subviews and adjusts them proportionally.
- (id)initWithFrame:(NSRect)frame andSubviews:(unsigned)count {
	self = [self initWithFrame:frame];
	if (self) {
		while (count-->0) {
			[self addSubview:[[[RBSplitSubview alloc] initWithFrame:frame] autorelease]];
		}
		[self setMustAdjust];
	}
	return self;
}

// Frees retained objects when going away.
- (void)dealloc {
	if (dividers) {
		free(dividers);
	}
	[autosaveName release];
	[divider release];
	[background release];
	[super dealloc];
}

// Sets and gets the coupling between the view and its containing RBSplitView (if any). Coupled
// RBSplitViews take some parameters, such as divider images, from the containing view. The default
// is for nested RBSplitViews is YES; however, isCoupled returns NO if we're not nested.
- (void)setCoupled:(BOOL)flag {
	if (flag!=isCoupled) {
		isCoupled = flag;
// If we've just been uncoupled and there's no divider image, we copy it from the containing view. 
		if (!isCoupled&&!divider) {
			[self setDivider:[[self splitView] divider]];
		}
		[self setMustAdjust];
	}
}

- (BOOL)isCoupled {
	return isCoupled&&([super splitView]!=nil);
}

// This returns the containing splitview if they are coupled. It's guaranteed to return a RBSplitView or nil.
- (RBSplitView*)couplingSplitView {
	return isCoupled?[super couplingSplitView]:nil;
}

// This returns self.
- (RBSplitView*)asSplitView {
	return self;
}

// This return self if we're really coupled to the owning splitview.
- (RBSplitView*)coupledSplitView {
	return [self isCoupled]?self:nil;
}

// We always return NO, but do special handling in RBSplitSubview's mouseDown: method.
- (BOOL)mouseDownCanMoveWindow {
	return NO;
}

// RBSplitViews must be flipped to work properly for horizontal dividers. As the subviews are never
// flipped, this won't make your life harder.
- (BOOL)isFlipped {
	return YES;
}

// Call this method to make sure that the subviews and divider rectangles are recalculated
// properly before display.
- (void)setMustAdjust {
	mustAdjust = YES;
	[self setNeedsDisplay:YES];
}

// Returns YES if there's a pending adjustment.
- (BOOL)mustAdjust {
	return mustAdjust;
}

// Returns YES if we're in a dragging loop.
- (BOOL)isDragging {
	return isDragging;
}

// Returns YES if the view is directly contained in an NSScrollView.
- (BOOL)isInScrollView {
	return isInScrollView;
}

// This pair of methods allows you to move the dividers for background windows while holding down
// the command key, without bringing the window to the foreground.
- (BOOL)acceptsFirstMouse:(NSEvent*)theEvent {
	return ([theEvent modifierFlags]&NSCommandKeyMask)==0;
}

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent*)theEvent {
	return ([theEvent modifierFlags]&NSCommandKeyMask)!=0;
}

// These 3 methods handle view background colors and opacity. The default is the window background.
// Pass nil or a completely transparent color to setBackground to use transparency. If you set any
// other background color, it will completely fill the RBSplitView (including subviews and dividers).
// The view will be considered opaque only if its alpha is equal to 1.0.
// For a nested, coupled RBSplitView, background and opacity are copied from the containing RBSplitView,
// and setting the background has no effect.
- (NSColor*)background {
	RBSplitView* sv = [self couplingSplitView];
	return sv?[sv background]:background;
}

- (void)setBackground:(NSColor*)color {
	if (![self couplingSplitView]) {
		[background autorelease];
		background = color?([color alphaComponent]>0.0?[color retain]:nil):nil;
		[self setNeedsDisplay:YES];
	}
}

- (BOOL)isOpaque {
	RBSplitView* sv = [self couplingSplitView];
	return sv?[sv isOpaque]:(background&&([background alphaComponent]>=1.0));
}

// This will make debugging a little easier by appending the state string to the
// default description.
- (NSString*)description {
	return [NSString stringWithFormat:@"%@ {%@}",[super description],[self stringWithSavedState]];
}

// The following 3 methods handle divider orientation. The actual stored trait is horizontality,
// but verticality is used for setting to conform to the NSSplitView convention.
// For a nested RBSplitView, orientation is perpendicular to the containing RBSplitView, and
// setting it has no effect. This parameter is not affected by coupling.
// After changing the orientation you may want to restore the state with restoreState:.
- (BOOL)isHorizontal {
	RBSplitView* sv = [self splitView];
	return sv?[sv isVertical]:isHorizontal;
}

- (BOOL)isVertical {
	return 1-[self isHorizontal];
}

- (void)setVertical:(BOOL)flag {
	if (![self splitView]&&(isHorizontal!=!flag)) {
		BOOL ishor = isHorizontal = !flag;
		NSSize size = divider?[divider size]:NSZeroSize;
		[self setDividerThickness:DIM(size)];
		[self setMustAdjust];
	}
}

// Returns the subview which a given identifier.
- (RBSplitSubview*)subviewWithIdentifier:(NSString*)anIdentifier {
	NSEnumerator* enumerator = [[self subviews] objectEnumerator];
	RBSplitSubview* subview;
	while ((subview = [enumerator nextObject])) {
		if ([anIdentifier isEqualToString:[subview identifier]]) {
			return subview;
		}
	}
	return nil;
}

// Returns the subview at a given position
- (RBSplitSubview*)subviewAtPosition:(unsigned)position {
	NSArray* subviews = [super subviews];
	unsigned int subcount = [subviews count];
	if (position<subcount) {
		return [subviews objectAtIndex:position];
	}
	return nil;
}

// This pair of methods gets and sets the delegate object. Delegates aren't retained.
- (id)delegate {
	return delegate;
}

- (void)setDelegate:(id)anObject {
	delegate = anObject;
}

// This pair of methods gets and sets the divider image. Setting the image automatically adjusts the
// divider thickness. A nil image means a 0-pixel wide divider, unless you set a thickness explicitly.
// For a nested RBSplitView, the divider is copied from the containing RBSplitView, and
// setting it has no effect. The returned image is always flipped.
- (NSImage*)divider {
	RBSplitView* sv = [self couplingSplitView];
	return sv?[sv divider]:divider;
}

- (void)setDivider:(NSImage*)image {
	if (![self couplingSplitView]) {
		[divider autorelease];
		if ([image isFlipped]) {
// If the image is flipped, we just retain it.
			divider = [image retain];
		} else {
// if the image isn't flipped, we copy the image instead of retaining it, and flip it.
			divider = [image copy];
			[divider setFlipped:YES];
		}
// We set the thickness to 0.0 so the image dimension will prevail.
		[self setDividerThickness:0.0];
		[self setMustAdjust];
	}
}

// This pair of methods gets and sets the divider thickness. It should be an integer value and at least
// 0.0, so we make sure. Set it to 0.0 to make the image dimensions prevail.
- (float)dividerThickness {
	if (dividerThickness>0.0) {
		return dividerThickness;
	}
	NSImage* divdr = [self divider];
	if (divdr) {
		NSSize size = [divdr size];
		BOOL ishor = [self isHorizontal];
		return DIM(size);
	}
	return 0.0;
}

- (void)setDividerThickness:(float)thickness {
	float t = fMAX(0.0,floorf(thickness));
	if ((int)dividerThickness!=(int)t) {
		dividerThickness = t;
		[self setMustAdjust];
	}
}

// These three methods add subviews. If aView isn't a RBSplitSubview, one is automatically inserted above
// it, and aView's frame and resizing mask is set to occupy the entire RBSplitSubview.
- (void)addSubview:(NSView*)aView {
	if ([aView isKindOfClass:[RBSplitSubview class]]) {
		[super addSubview:aView];
	} else {
		[aView setFrameOrigin:NSZeroPoint];
		RBSplitSubview* sub = [[[RBSplitSubview alloc] initWithFrame:[aView frame]] autorelease];
		[aView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
		[sub addSubview:aView];
		[super addSubview:sub];
	}
	[self setMustAdjust];
}

- (void)addSubview:(NSView*)aView positioned:(NSWindowOrderingMode)place relativeTo:(NSView*)otherView {
	if ([aView isKindOfClass:[RBSplitSubview class]]) {
		[super addSubview:aView positioned:place relativeTo:otherView];
	} else {
		[aView setFrameOrigin:NSZeroPoint];
		RBSplitSubview* sub = [[[RBSplitSubview alloc] initWithFrame:[aView frame]] autorelease];
		[aView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
		[sub addSubview:aView];
		[super addSubview:sub positioned:place relativeTo:otherView];
		[aView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
	}
	[self setMustAdjust];
}

- (void)addSubview:(NSView*)aView atPosition:(unsigned)position {
	RBSplitSubview* suv = [self subviewAtPosition:position];
	if (suv) {
		[self addSubview:aView positioned:NSWindowBelow relativeTo:suv];
	} else {
		[self addSubview:aView];
	}
}

// This keeps the isInScrollView flag up-to-date.
- (void)viewDidMoveToSuperview {
	[super viewDidMoveToSuperview];
	NSScrollView* scrollv = [self enclosingScrollView];
	isInScrollView = scrollv?[scrollv documentView]==self:NO;
}

// This makes sure the subviews are adjusted after a subview is removed.
- (void)willRemoveSubview:(NSView*)subview {
	if ([subview respondsToSelector:@selector(RB___stopAnimation)]) {
		[(RBSplitSubview*)subview RB___stopAnimation];
	}
	[super willRemoveSubview:subview];
	[self setMustAdjust];
}

// RBSplitViews never resize their subviews automatically.
- (BOOL)autoresizesSubviews {
	return NO;
}

// This adjusts the subviews when the size is set. setFrame: calls this, so all is well. It calls
// the delegate if implemented.
- (void)setFrameSize:(NSSize)size {
	NSSize oldsize = [self frame].size;
	[super setFrameSize:size];
	[self setMustAdjust];
	if ([delegate respondsToSelector:@selector(splitView:wasResizedFrom:to:)]) {
		BOOL ishor = [self isHorizontal];
		float olddim = DIM(oldsize);
		float newdim = DIM(size);
// The delegate is not called if the dimension hasn't changed.
		if (((int)newdim!=(int)olddim)) {
			[delegate splitView:self wasResizedFrom:olddim to:newdim];
		}
	}
// We adjust the subviews only if the delegate didn't.
	if (mustAdjust&&!isAdjusting) {
		[self adjustSubviews];
	}
}

// This method handles dragging and double-clicking dividers with the mouse. While dragging, the
// "closed hand" cursor is shown. Double clicks are handled separately. Nothing will happen if
// no divider image is set.
- (void)mouseDown:(NSEvent*)theEvent {
	if (!dividers) {
		return;
	}
	NSArray* subviews = [self RB___subviews];
	int subcount = [subviews count];
	if (subcount<2) {
		return;
	}
// If the mousedown was in an alternate dragview, or if there's no divider image, handle it in RBSplitSubview.
	if ((actDivider<NSNotFound)||![self divider]) {
		[super mouseDown:theEvent];
		return;
	}
	NSPoint where = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	BOOL ishor = [self isHorizontal];
	int i;
	--subcount;
// Loop over the divider rectangles.
	for (i=0;i<subcount;i++) {
		NSRect* divdr = &dividers[i];
		if ([self mouse:where inRect:*divdr]) {
// leading points at the subview immediately leading the divider being tracked.
			RBSplitView* leading = [subviews objectAtIndex:i];
// trailing points at the subview immediately trailing the divider being tracked.
			RBSplitView* trailing = [subviews objectAtIndex:i+1];
			if ([delegate respondsToSelector:@selector(splitView:shouldHandleEvent:inDivider:betweenView:andView:)]) {
				if (![delegate splitView:self shouldHandleEvent:theEvent inDivider:i betweenView:leading andView:trailing]) {
					return;
				}
			}
// If it's a double click, try to expand or collapse one of the neighboring subviews.
			if ([theEvent clickCount]>1) {
// If both are collapsed, we do nothing. If one of them is collapsed, we try to expand it.
				if ([trailing isCollapsed]) {
					if (![leading isCollapsed]) {
						[self RB___tryToExpandTrailing:trailing leading:leading delta:-[trailing dimension]];
					}
				} else {
					if ([leading isCollapsed]) {
						[self RB___tryToExpandLeading:leading divider:i trailing:trailing delta:[leading dimension]];
					} else {
// If neither are collapsed, we check if both are collapsible.
						BOOL lcan = [leading canCollapse];
						BOOL tcan = [trailing canCollapse];
						float ldim = [leading dimension];
						if (lcan&&tcan) {
// If both are collapsible, we try asking the delegate.
							if ([delegate respondsToSelector:@selector(splitView:collapseLeading:orTrailing:)]) {
								RBSplitSubview* sub = [delegate splitView:self collapseLeading:leading orTrailing:trailing];
// If the delegate returns nil, neither view will collapse.
								lcan = sub==leading;
								tcan = sub==trailing;
							} else {
// Otherwise we try collapsing the smaller one. If they're equal, the trailing one will be collapsed.
								lcan = ldim<[trailing dimension];
							}
						}
// At this point, we'll try to collapse the leading subview.
						if (lcan) {
							[self RB___tryToShortenLeading:leading divider:i trailing:trailing delta:-ldim always:NO];
						}
// If the leading subview didn't collapse for some reason, we try to collapse the trailing one.
						if (!mustAdjust&&tcan) {
							[self RB___tryToShortenTrailing:trailing divider:i leading:leading delta:[trailing dimension] always:NO];
						}
					}
				}
// If the subviews have changed, clear the fractions, adjust and redisplay
				if (mustAdjust) {
					[self RB___setMustClearFractions];
					RBSplitView* sv = [self splitView];
					[sv?sv:self adjustSubviews];
					[super display];
				}
			} else {
// Single click; record the offsets within the divider rectangle and check for nesting.
				float divt = [self dividerThickness];
				float offset = DIM(where)-DIM(divdr->origin);
// Check if the leading subview is nested and if yes, if one of its two-axis thumbs was hit.
				int ldivdr = NSNotFound;
				float loffset = 0.0;
				NSPoint lwhere = where;
				NSRect lrect = NSZeroRect;
				if ((leading = [leading coupledSplitView])) {
					ldivdr = [leading RB___dividerHitBy:lwhere relativeToView:self thickness:divt];
					if (ldivdr!=NSNotFound) {
						lrect = [leading RB___dividerRect:ldivdr relativeToView:self];
						loffset = OTHER(lwhere)-OTHER(lrect.origin);
					}
				}
// Check if the trailing subview is nested and if yes, if one of its two-axis thumbs was hit.
				int tdivdr = NSNotFound;
				float toffset = 0.0;
				NSPoint twhere = where;
				NSRect trect = NSZeroRect;
				if ((trailing = [trailing coupledSplitView])) {
					tdivdr = [trailing RB___dividerHitBy:twhere relativeToView:self thickness:divt];
					if (tdivdr!=NSNotFound) {
						trect = [trailing RB___dividerRect:tdivdr relativeToView:self];
						toffset = OTHER(twhere)-OTHER(trect.origin);
					}
				}
// Now we loop handling mouse events until we get a mouse up event, while showing the drag cursor.
				[[RBSplitView cursor:RBSVDragCursor] push];
				[self RB___setDragging:YES];
				while ((theEvent = [NSApp nextEventMatchingMask:NSLeftMouseDownMask|NSLeftMouseDraggedMask|NSLeftMouseUpMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES])&&([theEvent type]!=NSLeftMouseUp)) {
// Set up a local autorelease pool for the loop to prevent buildup of temporary objects.
					NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
					NSDisableScreenUpdates();
// Track the mouse along the main coordinate. 
					[self RB___trackMouseEvent:theEvent from:where withBase:NSZeroPoint inDivider:i];
					if (ldivdr!=NSNotFound) {
// Track any two-axis thumbs for the leading nested RBSplitView.
						[leading RB___trackMouseEvent:theEvent from:[self convertPoint:lwhere toView:leading] withBase:NSZeroPoint inDivider:ldivdr];
					}
					if (tdivdr!=NSNotFound) {
// Track any two-axis thumbs for the trailing nested RBSplitView.
						[trailing RB___trackMouseEvent:theEvent from:[self convertPoint:twhere toView:trailing] withBase:NSZeroPoint inDivider:tdivdr];
					}
					if (mustAdjust||[leading mustAdjust]||[trailing mustAdjust]) {
// The mouse was dragged and the subviews changed, so we must redisplay, as
// several divider rectangles may have changed.
						RBSplitView* sv = [self splitView];
						[sv?sv:self adjustSubviews];
						[super display];
						divdr = &dividers[i];
// Adjust to the new cursor coordinates.
						DIM(where) = DIM(divdr->origin)+offset;
						if ((ldivdr!=NSNotFound)&&![leading isCollapsed]) {
// Adjust for the leading nested RBSplitView's thumbs while it's not collapsed.
							lrect = [leading RB___dividerRect:ldivdr relativeToView:self];
							OTHER(lwhere) = OTHER(lrect.origin)+loffset;
						}
						if ((tdivdr!=NSNotFound)&&![trailing isCollapsed]) {
// Adjust for the trailing nested RBSplitView's thumbs while it's not collapsed.
							trect = [trailing RB___dividerRect:tdivdr relativeToView:self];
							OTHER(twhere) = OTHER(trect.origin)+toffset;
						}
					}
					NSEnableScreenUpdates();
					[pool release];
				}
				[self RB___setDragging:NO];
// Redisplay the previous cursor.
				[NSCursor pop];
			}
		}
	}
}

// This will be called before the view will be redisplayed, so we adjust subviews if necessary.
- (BOOL)needsDisplay {
	if (mustAdjust&&!isAdjusting) {
		[self adjustSubviews];
		return YES;
	}
	return [super needsDisplay];
}

// We implement awakeFromNib to restore the state. This works if an autosaveName is set in the nib.
- (void)awakeFromNib {
	if ([RBSplitSubview instancesRespondToSelector:@selector(awakeFromNib)]) {
		[super awakeFromNib];
	}
	if (![self splitView]) {
		[self restoreState:YES];
	}
}

// We check if subviews must be adjusted before redisplaying programmatically.
- (void)display {
	if (mustAdjust&&!isAdjusting) {
		[self adjustSubviews];
	}
	[super display];
}

// This method draws the divider rectangles and then the two-axis thumbs if there are any.
- (void)drawRect:(NSRect)rect {
	[super drawRect:rect];
	if (!dividers) {
		return;
	}
	NSArray* subviews = [self RB___subviews];
	int subcount = [subviews count];
// Return if there are no dividers to draw.
	if (subcount<2) {
		return;
	}
	--subcount;
	int i;
// Cache the divider image.
	NSImage* divdr = [self divider];
	float divt = [self dividerThickness];
// Loop over the divider rectangles.
	for (i=0;i<subcount;i++) {
// Check if we need to draw this particular divider.
		if ([self needsToDrawRect:dividers[i]]) {
			RBSplitView* leading = [subviews objectAtIndex:i];
			RBSplitView* trailing = [subviews objectAtIndex:i+1];
			BOOL lexp = divdr?![leading isCollapsed]:NO;
			BOOL texp = divdr?![trailing isCollapsed]:NO;
// We don't draw the divider image if either of the neighboring subviews is a non-collapsed
// nested split view.
			BOOL nodiv = (lexp&&[leading coupledSplitView])||(texp&&[trailing coupledSplitView]);
			[self drawDivider:nodiv?nil:divdr inRect:dividers[i] betweenView:leading andView:trailing];
			if (divdr) {
// Draw the corresponding two-axis thumbs if the leading view is a nested RBSplitView.
				if ((leading = [leading coupledSplitView])&&lexp) {
					[leading RB___drawDividersIn:self forDividerRect:dividers[i] thickness:divt];
				}
// Draw the corresponding two-axis thumbs if the trailing view is a nested RBSplitView.
				if ((trailing = [trailing coupledSplitView])&&texp) {
					[trailing RB___drawDividersIn:self forDividerRect:dividers[i] thickness:divt];
				}
			}
		}
	}
}

// This method draws dividers. You should never call it directly but you can override it when
// subclassing, if you need custom dividers. It draws the divider image centered in the divider rectangle.
// If we're drawing a two-axis thumb leading and trailing will be nil, and the rectangle
// will be the thumb rectangle.
// If there are nested split views this will be called once to draw the main divider rect,
// and again for every thumb.
- (void)drawDivider:(NSImage*)anImage inRect:(NSRect)rect betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing {
// Fill the view with the background color (if there's any). Don't draw the background again for
// thumbs.
	if (leading||trailing) {
		NSColor* bg = [self background];
		if (bg) {
			[bg set];
			NSRectFillUsingOperation(rect,NSCompositeSourceOver);
		}
	}
// Center the image, if there is one.
	NSRect imrect = NSZeroRect;
	NSRect dorect = NSZeroRect;
	if (anImage) {
		imrect.size = dorect.size = [anImage size];
		dorect.origin = NSMakePoint(floorf(rect.origin.x+(rect.size.width-dorect.size.width)/2),
									floorf(rect.origin.y+(rect.size.height-dorect.size.height)/2));
	}
// Ask the delegate for the final rect where the image should be drawn.
	if ([delegate respondsToSelector:@selector(splitView:willDrawDividerInRect:betweenView:andView:withProposedRect:)]) {
		dorect = [delegate splitView:self willDrawDividerInRect:rect betweenView:leading andView:trailing withProposedRect:dorect];
	}
// Draw the image if the delegate returned a non-empty rect.
	if (!NSIsEmptyRect(dorect)) {
		[anImage drawInRect:dorect fromRect:imrect operation:NSCompositeSourceOver fraction:1.0];
	}
}

// This method should be called only from within the splitView:wasResizedFrom:to: delegate method
// to keep some specific subview the same size.
- (void)adjustSubviewsExcepting:(RBSplitSubview*)excepting {
	[self RB___adjustSubviewsExcepting:[excepting isCollapsed]?nil:excepting];
}

// This method adjusts subviews and divider rectangles.
- (void)adjustSubviews {
	[self RB___adjustSubviewsExcepting:nil];
}

// This resets the appropriate cursors for each divider according to the orientation.
// No cursors are shown if there is no divider image.
- (void)resetCursorRects {
	if (!dividers) {
		return;
	}
	id del = [delegate respondsToSelector:@selector(splitView:cursorRect:forDivider:)]?delegate:nil;
	NSArray* subviews = [self RB___subviews];
	int divcount = [subviews count]-1;
	if ((divcount<1)||![self divider]) {
		[del splitView:self cursorRect:NSZeroRect forDivider:0];
		return;
	}
	int i;
	NSCursor* cursor = [RBSplitView cursor:[self isVertical]?RBSVVerticalCursor:RBSVHorizontalCursor];
	float divt = [self dividerThickness];
	for (i=0;i<divcount;i++) {
		RBSplitView* sub = [[subviews objectAtIndex:i] coupledSplitView];
// If the leading subview is a nested RBSplitView, add the thumb rectangles first.
		if (sub) {
			[sub  RB___addCursorRectsTo:self forDividerRect:dividers[i] thickness:divt];
		}
		sub = [[subviews objectAtIndex:i+1] coupledSplitView];
// If the trailing subview is a nested RBSplitView, add the thumb rectangles first.
		if (sub) {
			[sub  RB___addCursorRectsTo:self forDividerRect:dividers[i] thickness:divt];
		}
// Now add thedivider rectangle.
		NSRect divrect = dividers[i];
		if (del) {
			divrect = [del splitView:self cursorRect:divrect forDivider:i];
		}
		if (!NSIsEmptyRect(divrect)) {
			[self addCursorRect:divrect cursor:cursor];
		}
	}
}

// These two methods encode and decode RBSplitViews. One peculiarity is that we encode the divider image's
// bitmap representation as data; this makes the nib files larger, but the user can just paste any image
// into the RBSplitView inspector - or use the default divider image - without having to include it into the
// project, too.
- (void)encodeWithCoder:(NSCoder *)coder {
	[super encodeWithCoder:coder];
	if ([coder allowsKeyedCoding]) {
        [coder encodeConditionalObject:delegate forKey:@"delegate"];
		[coder encodeObject:autosaveName forKey:@"autosaveName"];
		[coder encodeObject:[divider TIFFRepresentation] forKey:@"divider"];
		[coder encodeObject:background forKey:@"background"];
		[coder encodeFloat:dividerThickness forKey:@"dividerThickness"];
		[coder encodeBool:isHorizontal forKey:@"isHorizontal"];
		[coder encodeBool:isCoupled forKey:@"isCoupled"];
	} else {
		[coder encodeConditionalObject:delegate];
		[coder encodeObject:autosaveName];
		[coder encodeObject:[divider TIFFRepresentation]];
		[coder encodeObject:background];
		[coder encodeValueOfObjCType:@encode(typeof(dividerThickness)) at:&dividerThickness];
		[coder encodeValueOfObjCType:@encode(typeof(isHorizontal)) at:&isHorizontal];
		[coder encodeValueOfObjCType:@encode(typeof(isCoupled)) at:&isCoupled];
	}
}

- (id)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
		NSData* data = nil;
		float divt = 0.0;
		isCoupled = YES;
		isDragging = NO;
		isInScrollView = NO;
		canSaveState = NO;
		if ([coder allowsKeyedCoding]) {
			isCoupled = [coder decodeBoolForKey:@"isCoupled"];
			[self setDelegate:[coder decodeObjectForKey:@"delegate"]];
			[self setAutosaveName:[coder decodeObjectForKey:@"autosaveName"] recursively:NO];
			data = [coder decodeObjectForKey:@"divider"];
			[self setBackground:[coder decodeObjectForKey:@"background"]];
			divt = [coder decodeFloatForKey:@"dividerThickness"];
			isHorizontal = [coder decodeBoolForKey:@"isHorizontal"];
		} else {
			[self setDelegate:[coder decodeObject]];
			[self setAutosaveName:[coder decodeObject] recursively:NO];
			data = [coder decodeObject];
			[self setBackground:[coder decodeObject]];
			[coder decodeValueOfObjCType:@encode(typeof(divt)) at:&divt];
			[coder decodeValueOfObjCType:@encode(typeof(isHorizontal)) at:&isHorizontal];
			[coder decodeValueOfObjCType:@encode(typeof(isCoupled)) at:&isCoupled];
		}
		dividers = NULL;
		if (data) {
			NSBitmapImageRep* rep = [NSBitmapImageRep imageRepWithData:data];
			NSImage* image = [[[NSImage alloc] initWithSize:[rep size]] autorelease];
			[image setFlipped:YES];
			[image addRepresentation:rep];
			[self setDivider:image];
		} else {
			[self setDivider:nil];
		}
		[self setDividerThickness:divt];
		[self setMustAdjust];
		[self performSelector:@selector(viewDidMoveToSuperview) withObject:nil afterDelay:0.0];
		[self performSelector:@selector(RB___adjustOutermostIfNeeded) withObject:nil afterDelay:0.0];
	}
    return self;
}

@end

@implementation RBSplitView (RB___ViewAdditions)

// This sets the dragging status flag. After clearing the flag, the state must be saved explicitly.
- (void)RB___setDragging:(BOOL)flag {
	BOOL save = isDragging&&!flag;
	isDragging = flag;
	if (save) {
		[self saveState:NO];
	}
}

// This returns the number of visible subviews.
- (unsigned int)RB___numberOfSubviews {
	unsigned int result = 0;
	NSEnumerator* enumerator = [[self subviews] objectEnumerator];
	RBSplitSubview* sub;
	while ((sub = [enumerator nextObject])) {
		++result;
	}
	return result;
}

// This returns the origin coordinate of the Nth divider.
- (float)RB___dividerOrigin:(int)indx {
	float result = 0.0;
	if (dividers) {
		BOOL ishor = [self isHorizontal];
		result = DIM(dividers[indx].origin);
	}
	return result;
}

// This returns an array with all non-hidden subviews.
- (NSArray*)RB___subviews {
	NSMutableArray* result = [NSMutableArray arrayWithArray:[self subviews]];
	int i;
	for (i=[result count]-1;i>=0;i--) {
		RBSplitSubview* view = [result objectAtIndex:i];
		if ([view isHidden]) {
			[result removeObjectAtIndex:i];
		}
	}
	return result;
}

// This returns the actual value set in dividerThickness. 
- (float)RB___dividerThickness {
	return dividerThickness;
}

// This method returns the actual dimension occupied by the subviews; that is, without dividers.
- (float)RB___dimensionWithoutDividers {
	BOOL ishor = [self isHorizontal];
	NSSize size = [self frame].size;
	return fMAX(1.0,DIM(size)-[self dividerThickness]*([self RB___numberOfSubviews]-1));
}

// This method returns one of the divider rectangles, or NSZeroRect if the index is invalid.
// If view is non-nil, the rect will be expressed in that view's coordinates. We assume
// that view is a superview of self.
- (NSRect)RB___dividerRect:(unsigned)indx relativeToView:(RBSplitView*)view {
	if (dividers&&(indx<[self RB___numberOfSubviews]-1)) {
		NSRect result = dividers[indx];
		if (view&&(view!=self)) {
			result = [self convertRect:result toView:view];
		}
		return result;
	}
	return NSZeroRect;
}

// Returns the index of the divider hit by the point, or NSNotFound if none.
// point is in coordinates relative to view. delta is the divider thickness added
// to both ends of the divider rect, to accomodate two-axis thumbs.
- (unsigned)RB___dividerHitBy:(NSPoint)point relativeToView:(RBSplitView*)view thickness:(float)delta {
	if (!dividers) {
		return NSNotFound;
	}
	int divcount = [self RB___numberOfSubviews]-1;
	if (divcount<1) {
		return NSNotFound;
	}
	int i;
	BOOL ishor = [self isHorizontal];
	point = [self convertPoint:point fromView:view];
	for (i=0;i<divcount;i++) {
		NSRect divdr = dividers[i];
		OTHER(divdr.origin) -= delta;
		OTHER(divdr.size) += 2*delta;
		if ([self mouse:point inRect:divdr]) {
			return i;
		}
	}
	return NSNotFound;
}

// This method sets a flag to clear all fractions before adjusting.
- (void)RB___setMustClearFractions {
	mustClearFractions = YES;
}

// This local method asks the delegate if we should resize the trailing subview or the window
// when a divider is dragged. Not called if we're inside an NSScrollView.
- (BOOL)RB___shouldResizeWindowForDivider:(unsigned int)indx betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing willGrow:(BOOL)grow {
	if (!isInScrollView&&[delegate respondsToSelector:@selector(splitView:shouldResizeWindowForDivider:betweenView:andView:willGrow:)]) {
		return [delegate splitView:self shouldResizeWindowForDivider:indx betweenView:leading andView:trailing willGrow:grow];
	}
	return NO;
}

// This local method tries to expand the leading subview (which is assumed to be collapsed). Delta should be positive.
- (void)RB___tryToExpandLeading:(RBSplitSubview*)leading divider:(unsigned int)indx trailing:(RBSplitSubview*)trailing delta:(float)delta {
	NSWindow* window = nil;
	NSView* document = nil;
	NSSize maxsize = NSMakeSize(WAYOUT,WAYOUT);
	NSRect frame = NSZeroRect;
	NSRect screen = NSMakeRect(0,0,WAYOUT,WAYOUT);
	BOOL ishor = NO;
// First we ask the delegate, if there's any, if the window should resize.
	BOOL dowin = ([self RB___shouldResizeWindowForDivider:indx betweenView:leading andView:trailing willGrow:YES]);
	if (dowin) {
// We initialize the other local variables only if we need them for the window.
		ishor = [self isHorizontal];
		document = [[self enclosingScrollView] documentView];
		if (document) {
			frame = [document frame];
		} else {
			window = [self window];
			frame = [window frame];
			maxsize = [window maxSize];
			screen = [[NSScreen mainScreen] visibleFrame];
		}
	}
// The mouse has to move over half of the expanded size (plus hysteresis) and the expansion shouldn't
// reduce the trailing subview to less than its minimum size (or grow the window beyond its maximum).
	float limit = [leading minDimension];
	float dimension = 0.0;
	if (dowin) {
		float maxd = fMAX(0.0,(ishor?frame.origin.y-screen.origin.y:(screen.origin.x+screen.size.width)-(frame.origin.x+frame.size.width)));
		dimension = fMIN(DIM(maxsize)-DIM(frame.size),maxd);
	} else {
		dimension = trailing?[trailing dimension]:WAYOUT;
	}
	if (limit>dimension) {
		return;
	}
	if (!dowin&&trailing) {
		limit += [trailing minDimension];
		if (limit>dimension) {
// If the trailing subview is going below its minimum, we try to collapse it first.
// However, we don't collapse if that would cause the leading subview to become larger than its maximum.
			if (([trailing canCollapse])&&(delta>(0.5+HYSTERESIS)*dimension)&&([leading maxDimension]<=dimension)) {
				delta = -[trailing RB___collapse];
				[leading changeDimensionBy:delta mayCollapse:NO move:NO];
			}
			return;
		}
	}
// The leading subview may be expanded normally.
	delta = -[leading changeDimensionBy:delta mayCollapse:NO move:NO];
	if (dowin) {
// If it does expand, we widen the window.
		DIM(frame.size) -= delta;
		if (ishor) {
			DIM(frame.origin) += delta;
		}
		if (document) {
			[document setFrame:frame];
			[document setNeedsDisplay:YES];
		} else {
			[window setFrame:frame display:YES];
		}
		[self setMustAdjust];
	} else {
// If it does expand, we shorten the trailing subview.
		[trailing changeDimensionBy:delta mayCollapse:NO move:YES];
	}
}

// This local method tries to shorten the leading subview. Both subviews are assumed to be expanded.
// delta should be negative. If always is NO, the subview will be shortened only if it might also be
// collapsed; otherwise, it's shortened as much as possible.
- (void)RB___tryToShortenLeading:(RBSplitSubview*)leading divider:(unsigned int)indx trailing:(RBSplitSubview*)trailing delta:(float)delta always:(BOOL)always {
	NSWindow* window = nil;
	NSView* document = nil;
	NSSize minsize = NSZeroSize;
	NSRect frame = NSZeroRect;
	BOOL ishor = NO;
// First we ask the delegate, if there's any, if the window should resize.
	BOOL dowin = ([self RB___shouldResizeWindowForDivider:indx betweenView:leading andView:trailing willGrow:NO]);
	if (dowin) {
// We initialize the other local variables only if we need them for the window.
		ishor = [self isHorizontal];
		document = [[self enclosingScrollView] documentView];
		if (document) {
			frame = [document frame];
		} else {
			window = [self window];
			frame = [window frame];
			minsize = [window minSize];
		}
	}
// We avoid making the trailing subview larger than its maximum, or the window smaller than its minimum.
	float limit = 0.0;
	if (dowin) {
		limit = DIM(frame.size)-DIM(minsize);
	} else {
		limit = trailing?([trailing maxDimension]-[trailing dimension]):WAYOUT;
	}
	if (-delta>limit) {
		if (always) {
			delta = -limit;
		} else {
			return;
		}
	}
	BOOL okl = limit>=[leading dimension];
	if (always||okl) {
// Resize leading.
		delta = -[leading changeDimensionBy:delta mayCollapse:okl move:NO];
		if (dowin) {
// Resize the window.
			DIM(frame.size) -= delta;
			if (ishor) {
				DIM(frame.origin) += delta;
			}
			if (document) {
				[document setFrame:frame];
				[document setNeedsDisplay:YES];
			} else {
				[window setFrame:frame display:YES];
			}
			[self setMustAdjust];
		} else {
// Otherwise, resize trailing.
			[trailing changeDimensionBy:delta mayCollapse:NO move:YES];
		}
	}
}

// This local method tries to shorten the trailing subview. Both subviews are assumed to be expanded.
// delta should be positive. If always is NO, the subview will be shortened only if it might also be
// collapsed; otherwise, it's shortened as much as possible.
- (void)RB___tryToShortenTrailing:(RBSplitSubview*)trailing divider:(unsigned int)indx leading:(RBSplitSubview*)leading delta:(float)delta always:(BOOL)always {
	NSWindow* window = nil;
	NSView* document = nil;
	NSSize maxsize = NSMakeSize(WAYOUT,WAYOUT);
	NSRect frame = NSZeroRect;
	NSRect screen = NSMakeRect(0,0,WAYOUT,WAYOUT);
	BOOL ishor = NO;
// First we ask the delegate, if there's any, if the window should resize.
	BOOL dowin = ([self RB___shouldResizeWindowForDivider:indx betweenView:leading andView:trailing willGrow:YES]);
	if (dowin) {
// We initialize the other local variables only if we need them for the window.
		ishor = [self isHorizontal];
		document = [[self enclosingScrollView] documentView];
		if (document) {
			frame = [document frame];
		} else {
			window = [self window];
			frame = [window frame];
			maxsize = [window maxSize];
			screen = [[NSScreen mainScreen] visibleFrame];
		}
	}
// We avoid making the leading subview larger than its maximum, or the window larger than its maximum.
	float limit = 0.0;
	if (dowin) {
		float maxd = fMAX(0.0,(ishor?frame.origin.y-screen.origin.y:(screen.origin.x+screen.size.width)-(frame.origin.x+frame.size.width)));
		limit = fMIN(DIM(maxsize)-DIM(frame.size),maxd);
	} else {
		limit = [leading maxDimension]-[leading dimension];
	}
	if (delta>limit) {
		if (always) {
			delta = limit;
		} else {
			return;
		}
	}
	BOOL okl = dowin||(limit>=(trailing?[trailing dimension]:WAYOUT));
	if (always||okl) {
		if (dowin) {
// If we should resize the window, resize leading, then the window.
			delta = [leading changeDimensionBy:delta mayCollapse:NO move:NO];
			DIM(frame.size) += delta;
			if (ishor) {
				DIM(frame.origin) -= delta;
			}
			if (document) {
				[document setFrame:frame];
				[document setNeedsDisplay:YES];
			} else {
				[window setFrame:frame display:YES];
			}
			[self setMustAdjust];
		} else {
// Otherwise, resize trailing, then leading.
			if (trailing) {
				delta = -[trailing changeDimensionBy:-delta mayCollapse:okl move:YES];
			}
			[leading changeDimensionBy:delta mayCollapse:NO move:NO];
		}
	}
}

// This method tries to expand the trailing subview (which is assumed to be collapsed).
- (void)RB___tryToExpandTrailing:(RBSplitSubview*)trailing leading:(RBSplitSubview*)leading delta:(float)delta {
// The mouse has to move over half of the expanded size (plus hysteresis) and the expansion shouldn't
// reduce the leading subview to less than its minimum size. If it does, we try to collapse it first.
// However, we don't collapse if that would cause the trailing subview to become larger than its maximum.
	float limit = trailing?[trailing minDimension]:0.0;
	float dimension = [leading dimension];
	if (limit>dimension) {
		return;
	}
	limit += [leading minDimension];
	if (limit>dimension) {
		if ([leading canCollapse]&&(-delta>(0.5+HYSTERESIS)*dimension)&&((trailing?[trailing maxDimension]:0.0)<=dimension)) {
			delta = -[leading RB___collapse];
			[trailing changeDimensionBy:delta mayCollapse:NO move:YES];
		}
		return;
	}
// The trailing subview may be expanded normally. If it does expand, we shorten the leading subview.
	if (trailing) {
		delta = -[trailing changeDimensionBy:-delta mayCollapse:NO move:YES];
	}
	[leading changeDimensionBy:delta mayCollapse:NO move:NO];
}


// This method is called by the mouseDown:method for every tracking event. It's separated out as it's
// called from the Interface Builder palette in a slightly different way, and also if you have a
// separate drag view designated by the delegate. You'll never need to call this directly.
// theEvent is the event (which should be a NSLeftMouseDragged event).
// where is the point where the original mouse-down happened, corrected for the current divider position,
// and expressed in local coordinates.
// base is an offset (x,y) applied to the mouse location (usually will be zero)
// indx is the number of the divider that's being dragged.
- (void)RB___trackMouseEvent:(NSEvent*)theEvent from:(NSPoint)where withBase:(NSPoint)base inDivider:(unsigned)indx {
	NSPoint result;
	NSArray* subviews = [self RB___subviews];
	int subcount = [subviews count];
	int k;
// leading and trailing point at the subviews immediately leading and trailing the divider being tracked
	RBSplitSubview* leading = [subviews objectAtIndex:indx];
	RBSplitSubview* trailing = [subviews objectAtIndex:indx+1];
// convert the mouse coordinates to apply to the same system the divider rects are in.
	NSPoint mouse = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	mouse.x -= base.x;
	mouse.y -= base.y;
	result.x = mouse.x-where.x;
	result.y = mouse.y-where.y;
// delta is the actual amount the mouse has moved in the relevant coordinate since the last event.
	BOOL ishor = [self isHorizontal];
	float delta = DIM(result);
	if (delta<0.0) {
// Negative delta means the mouse is being moved left or upwards.
// firstLeading will point at the first expanded subview to the left (or upwards) of the divider.
// If there's none (all subviews are collapsed) it will point at the nearest subview.
		RBSplitSubview* firstLeading = leading;
		k = indx;
		while (![firstLeading canShrink]) {
			if (--k<0) {
				firstLeading = leading;
				break;
			}
			firstLeading = [subviews objectAtIndex:k];
		}
		if (isInScrollView) {
			trailing = nil;
		}
// If the trailing subview is collapsed, it might be expanded if some conditions are met.
		if ([trailing isCollapsed]) {
			[self RB___tryToExpandTrailing:trailing leading:firstLeading delta:delta];
		} else {
			[self RB___tryToShortenLeading:firstLeading divider:indx trailing:trailing delta:delta always:YES];
		}
	} else if (delta>0.0) {
// Positive delta means the mouse is being moved right or downwards.
// firstTrailing will point at the first expanded subview to the right (or downwards) of the divider.
// If there's none (all subviews are collapsed) it will point at the nearest subview.
		RBSplitSubview* firstTrailing = nil;
		if (!isInScrollView) {
			firstTrailing = trailing;
			k = indx+1;
			while (![firstTrailing canShrink]) {
				if (++k>=subcount) {
					firstTrailing = trailing;
					break;
				}
				firstTrailing = [subviews objectAtIndex:k];
			}
		}
// If the leading subview is collapsed, it might be expanded if some conditions are met.
		if ([leading isCollapsed]) {
			[self RB___tryToExpandLeading:leading divider:indx trailing:firstTrailing delta:delta];
		} else {
// The leading subview is not collapsed, so we try to shorten or even collapse it
			[self RB___tryToShortenTrailing:firstTrailing divider:indx leading:leading delta:delta always:YES];
		}
	}
}

// This is called for nested RBSplitViews, to add the cursor rects for the two-axis thumbs.
- (void)RB___addCursorRectsTo:(RBSplitView*)masterView forDividerRect:(NSRect)rect thickness:(float)delta {
	if (dividers&&[self divider]) {
		NSArray* subviews = [self RB___subviews];
		int divcount = [subviews count]-1;
		if (divcount<1) {
			return;
		}
		int i;
		NSCursor* cursor = [RBSplitView cursor:RBSV2WayCursor];
		BOOL ishor = [self isHorizontal];
// Loop over the divider rectangles, intersect them with the view's own, and add the thumb rectangle
// to the containing split view.
		for (i=0;i<divcount;i++) {
			NSRect divdr = dividers[i];
			divdr.origin = [self convertPoint:divdr.origin toView:masterView];
			OTHER(divdr.origin) -= delta;
			OTHER(divdr.size) += 2*delta;
			divdr = NSIntersectionRect(divdr,rect);
			if (!NSIsEmptyRect(divdr)) {
				[masterView addCursorRect:divdr cursor:cursor];
			}
		}
	}
}

// This is called for nested RBSplitViews, to draw the two-axis thumbs.
- (void)RB___drawDividersIn:(RBSplitView*)masterView forDividerRect:(NSRect)rect thickness:(float)delta {
	if (!dividers) {
		return;
	}
	NSArray* subviews = [self RB___subviews];
	int divcount = [subviews count]-1;
	if (divcount<1) {
		return;
	}
	int i;
	BOOL ishor = [self isHorizontal];
// Get the outer split view's divider image.
	NSImage* image = [masterView divider];
// Loop over the divider rectangles, intersect them with the view's own, and draw the thumb there.
	for (i=0;i<divcount;i++) {
		NSRect divdr = dividers[i];
		divdr.origin = [self convertPoint:divdr.origin toView:masterView];
		OTHER(divdr.origin) -= delta;
		OTHER(divdr.size) += 2*delta;
		divdr = NSIntersectionRect(divdr,rect);
		if (!NSIsEmptyRect(divdr)) {
			[masterView drawDivider:image inRect:divdr betweenView:nil andView:nil];
		}
	}
}

// This is usually called from initWithCoder to ensure that the outermost RBSplitView is
// properly adjusted when first displayed.
- (void)RB___adjustOutermostIfNeeded {
	RBSplitView* sv = [self splitView];
	if (sv) {
		[sv RB___adjustOutermostIfNeeded];
		return;
	}
	if (mustAdjust&&!isAdjusting) {
		[self adjustSubviews];
	}
}

// Here we try to keep all subviews adjusted in as natural a manner as possible, given the constraints.
// The main idea is to always keep the RBSplitView completely covered by dividers and subviews, have at
// least one expanded subview, and never make a subview smaller than its minimum dimension, or larger
// than its maximum dimension.
// We try to account for most unusual situations but this may fail under some circumstances. YMMV.
- (void)RB___adjustSubviewsExcepting:(RBSplitSubview*)excepting {
	mustAdjust = NO;
	NSArray* subviews = [self RB___subviews];
	unsigned subcount = [subviews count];
	if (subcount<1) {
		return;
	}
	NSRect bounds = [self bounds];
// Never adjust if the splitview itself is collapsed.
	if ((bounds.size.width<1.0)||(bounds.size.height<1.0)) {
		return;
	}
// Prevents adjustSubviews being called recursively, which unfortunately may happen otherwise.
	if (isAdjusting) {
		return;
	}
	isAdjusting = YES;
// Tell the delegate we're about to adjust subviews.
	if ([delegate respondsToSelector:@selector(willAdjustSubviews:)]) {
		[delegate willAdjustSubviews:self];
		bounds = [self bounds];
	}
	unsigned divcount = subcount-1;
	if (divcount<1) {
// No dividers at all.
		if (dividers) {
			free(dividers);
			dividers = NULL;
		}
	} else {
// Try to allocate or resize if we already have a dividers array.
		unsigned long divsiz = sizeof(NSRect)*divcount;
		dividers = dividers?reallocf(dividers,divsiz):malloc(divsiz);
		if (!dividers) {
			return;
		}
	}
// This C array of subviewCaches is used to cache the subview information.
	subviewCache* caches = malloc(sizeof(subviewCache)*subcount);
	double realsize = 0.0;
	double expsize = 0.0;
	float newsize = 0.0;
	float effsize = 0.0;
	float limit;
	subviewCache* curr;
	unsigned int i;
	BOOL ishor = [self isHorizontal];
	float divt = [self dividerThickness];
// First we loop over subviews and cache their information.
	for (i=0;i<subcount;i++) {
		curr = &caches[i];
		[[subviews objectAtIndex:i] RB___copyIntoCache:curr];
	}
// This is a counter to limit the outer loop to three iterations (six if excepting is non-nil).
	int sanity = excepting?-3:0;
	while (sanity++<3) {
// We try to accomodate the exception for the first group of loops, turn it off for the second.
		if (sanity==1) {
			excepting = nil;
		}
// newsize is the available space for actual subviews (so dividers don't count). It will be an integer.
// Same as calling [self RB___dimensionWithoutDividers].
		unsigned smallest = 0;
		float smalldim = -1.0;
		BOOL haveexp = NO;
// Loop over subviews and sum the expanded dimensions into expsize, including fractions.
// Also find the collapsed subview with the smallest minimum dimension.
		for (i=0;i<subcount;i++) {
			curr = &caches[i];
			curr->constrain = NO;
			if (curr->size>0.0) {
				expsize += curr->size;
				if (!isInScrollView) {
// ignore fractions if we're in a NSScrollView, however.
					expsize += curr->fraction;
				}
				haveexp = YES;
			} else {
				limit = [curr->sub minDimension];
				if (smalldim>limit) {
					smalldim = limit;
					smallest = i;
				}
			}
		}
// haveexp should be YES at this point. If not, all subviews were collapsed; can't have that, so we 
// expand the smallest subview (or the first, if all have the same minimum).
		curr = &caches[smallest];
		if (!haveexp) {
			curr->size = [curr->sub minDimension];
			curr->fraction = 0.0;
			expsize += curr->size;
		}
		if (isInScrollView) {
// If we're inside an NSScrollView, we just grow the view to accommodate the subviews, instead of 
// the other way around.
			DIM(bounds.size) = expsize;
			break;
		} else {
// If the total dimension of all expanded subviews is less than 1.0 we set the dimension of the smallest
// subview (which we're sure is expanded at this point) to the available space.
			newsize = DIM(bounds.size)-divcount*divt;
			if (expsize<1.0) {
				curr->size = newsize;
				curr->fraction = 0.0;
				expsize = newsize;
			}
// Loop over the subviews and check if they're within the limits after scaling. We also recalculate the
// exposed size and repeat until no more subviews hit the constraints during that loop.
			BOOL constrained;
			effsize = newsize;// we're caching newsize here, this is an integer.
			do {
// scale is the scalefactor by which all views should be scaled - assuming none have constraints.
// It's a double to (hopefully) keep rounding errors small enough for all practical purposes.
				double scale = newsize/expsize;
				constrained = NO;
				realsize = 0.0;
				expsize = 0.0;
				for (i=0;i<subcount;i++) {
// Loop over the cached subview info.
					curr = &caches[i];
					if (curr->size>0.0) {
// Check non-collapsed subviews only.
						if (!curr->constrain) {
// Check non-constrained subviews only; calculate the proposed new size.
							float cursize = (curr->size+curr->fraction)*scale;
// Check if we hit a limit. limit will contain either the max or min dimension, whichever was hit.
							if (([curr->sub RB___animationData:NO resize:NO]&&((limit = curr->size)>=0.0))||
								((curr->sub==excepting)&&((limit = [curr->sub dimension])>0.0))||
								(cursize<(limit = [curr->sub minDimension]))||
								(cursize>(limit = [curr->sub maxDimension]))) {
// If we hit a limit, we mark the view and set to repeat the loop; non-constrained subviews will
// have to be recalculated.
								curr->constrain = constrained = YES;
// We set the new size to the limit we hit, and subtract it from the total size to be subdivided.
								cursize = limit;
								curr->fraction = 0.0;
								newsize -= cursize;
							} else {
// If we didn't hit a limit, we round the size to the nearest integer and recalculate the fraction. 
								double rem = fmod(cursize,1.0);
								cursize -= rem;
								if (rem>0.5) {
									++cursize;
									--rem;
								}
								expsize += cursize;
								curr->fraction = rem;
							}
// We store the new size in the cache.
							curr->size = cursize;
						}
// And add the full size with fraction to the actual sum of all expanded subviews.
						realsize += curr->size+curr->fraction;
					}
				}
// At this point, newsize will be the sum of the new dimensions of non-constrained views.
// expsize will be the sum of the recalculated dimensions of the same views, if any.
// We repeat the loop if any view has been recently constrained, and if there are any
// unconstrained views left.
			} while (constrained&&(expsize>0.0));
// At this point, the difference between realsize and effsize should be less than 1 pixel.
// realsize is the total size of expanded subviews as recalculated above, and
// effsize is the value realsize should have.
			limit = realsize-effsize;
			if (limit>=1.0) {
// If realsize is larger than effsize by 1 pixel or more, we will need to collapse subviews to make room.
// This in turn might expand previously collapsed subviews. So, we'll try collapsing constrained subviews
// until we're back into range, and then recalculate everything from the beginning.
				for (i=0;i<subcount;i++) {
					curr = &caches[i];
					if (curr->constrain&&(curr->sub!=excepting)&&([curr->sub RB___animationData:NO resize:NO]==nil)&&[curr->sub canCollapse]) {
						realsize -= curr->size;
						if (realsize<1.0) {
							break;
						}
						curr->size = 0.0;
						if ((realsize-effsize)<1.0) {
							break;
						}
					}
				}
			} else if (limit<=-1.0) {
// If realsize is smaller than effsize by 1 pixel or more, we will need to expand subviews.
// This in turn might collapse previously expanded subviews. So, we'll try expanding collapsed subviews
// until we're back into range, and then recalculate everything from the beginning.
				for (i=0;i<subcount;i++) {
					curr = &caches[i];
					if (curr->size<=0.0) {
						curr->size = [curr->sub minDimension];
						curr->fraction = 0.0;
						realsize += curr->size;
						if ((realsize-effsize)>-1.0) {
							break;
						}
					}
				}
			} else {
// The difference is less than 1 pixel, meaning that in all probability our calculations are
// exact or off by at most one pixel after rounding, so we break the loop here.
				break;
			}
		}
// After passing through the outer loop a few times, the frames may still be wrong, but there's nothing
// else we can do about it. You probably should avoid this by some other means like setting a minimum
// or maximum size for the window, for instance, or leaving at least one unlimited subview.
	}
// newframe is used to reset all subview frames. Subviews always fill the entire RBSplitView along the
// current orientation.
	NSRect newframe = NSMakeRect(0.0,0.0,bounds.size.width,bounds.size.height);
// We now loop over the subviews yet again and set the definite frames, also recalculating the
// divider rectangles as we go along, and collapsing and expanding subviews whenever requested.
	RBSplitSubview* last = nil;
// And we make a note if there's any nested RBSplitView.
	int nested = NSNotFound;
	newsize = DIM(bounds.size)-divcount*divt;
	for (i=0;i<subcount;i++) {
		curr = &caches[i];
// If we have a nested split view store its index.
		if ((nested==NSNotFound)&&([curr->sub asSplitView]!=nil)) {
			nested = i;
		}
// Adjust the subview to the correct origin and resize it to fit into the "other" dimension.
		curr->rect.origin = newframe.origin;
		OTHER(curr->rect.size) = OTHER(newframe.size);
		DIM(curr->rect.size) = curr->size;
// Clear fractions for expanded subviews if requested.
		if ((curr->size>0.0)&&mustClearFractions) {
			curr->fraction = 0.0;
		}
// Ask the subview to do the actual moving/resizing etc. from the cache.
		[curr->sub RB___updateFromCache:curr withTotalDimension:effsize];
// Step to the next position and record the subview if it's not collapsed.
		DIM(newframe.origin) += curr->size;
		if (curr->size>0.0) {
			last = curr->sub;
		}
		if (i==divcount) {
// We're at the last subview, so we now check if the actual and calculated dimensions
// are the same.
			float remain = DIM(bounds.size)-DIM(newframe.origin);
			if (last&&(fabsf(remain)>0.0)) {
// We'll resize the last expanded subview to whatever it takes to squeeze within the frame.
// Normally the change should be at most one pixel, but if too many subviews were constrained,
// this may be a large value, and the last subview may be resized beyond its constraints;
// there's nothing else to do at this point.
				newframe = [last frame];
				DIM(newframe.size) += remain;
				[last RB___setFrameSize:newframe.size withFraction:[last RB___fraction]-remain];
// And we loop back over the rightmost dividers (if any) to adjust their offsets.
				while ((i>0)&&(last!=[subviews objectAtIndex:i])) {
					DIM(dividers[--i].origin) += remain;
				}
				break;
			}
		} else {
// For any but the last subview, we just calculate the divider frame.
			DIM(newframe.size) = divt;
			dividers[i] = newframe;
			DIM(newframe.origin) += divt;
		}
	}
// We resize our frame at this point, if we're inside an NSScrollView.
	if (isInScrollView) {
		[super setFrameSize:bounds.size];
	}
// If there was at least one nested RBSplitView, we loop over the subviews and adjust those that need it.
	for (i=nested;i<subcount;i++) {
		curr = &caches[i];
		RBSplitView* sv = [curr->sub asSplitView];
		if ([sv mustAdjust]) {
			[sv adjustSubviews];
		}
	}
// Free the cache array.
	free(caches);
// Clear cursor rects.
	mustAdjust = NO;
	mustClearFractions = NO;
	[[self window] invalidateCursorRectsForView:self];
// Save the state for all subviews.
	if (!isDragging) {
		[self saveState:NO];
	}
// If we're a nested RBSplitView, also invalidate cursorRects for the superview.
	RBSplitView* sv = [self couplingSplitView];
	if (sv) {
		[[self window] invalidateCursorRectsForView:sv];
	}
	isAdjusting = NO;
// Tell the delegate we're finished.
	if ([delegate respondsToSelector:@selector(didAdjustSubviews:)]) {
		[delegate didAdjustSubviews:self];
	}
}

@end

