/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * MMCoreTextView+ToolTip
 *
 * Cocoa's tool tip interface does not allow changing the tool tip without the
 * user moving the mouse outside the view and then back again.  This category
 * takes care of this problem.
 *
 * The tool tip code was borrowed from the Chromium project which in turn had
 * borrowed it from WebKit (copyright and comments are below).  Some minor
 * changes were made to adapt the code to MacVim.
 */

#import "MacVim.h"
#import "MMCoreTextView.h"


// Below is the nasty tooltip stuff -- copied from WebKit's WebHTMLView.mm
// with minor modifications for code style and commenting.
//
//  The 'public' interface is -setToolTipAtMousePoint:. This differs from
// -setToolTip: in that the updated tooltip takes effect immediately,
//  without the user's having to move the mouse out of and back into the view.
//
// Unfortunately, doing this requires sending fake mouseEnter/Exit events to
// the view, which in turn requires overriding some internal tracking-rect
// methods (to keep track of its owner & userdata, which need to be filled out
// in the fake events.) --snej 7/6/09


/*
 * Copyright (C) 2005, 2006, 2007, 2008, 2009 Apple Inc. All rights reserved.
 *           (C) 2006, 2007 Graham Dennis (graham.dennis@gmail.com)
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1.  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 * 2.  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 * 3.  Neither the name of Apple Computer, Inc. ("Apple") nor the names of
 *     its contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

// Any non-zero value will do, but using something recognizable might help us
// debug some day.
static const NSTrackingRectTag kTrackingRectTag = 0xBADFACE;


@implementation MMCoreTextView (ToolTip)

// Override of a public NSView method, replacing the inherited functionality.
// See above for rationale.
- (NSTrackingRectTag)addTrackingRect:(NSRect)rect
                               owner:(id)owner
                            userData:(void *)data
                        assumeInside:(BOOL)assumeInside
{
    //DCHECK(trackingRectOwner_ == nil);
    trackingRectOwner_ = owner;
    trackingRectUserData_ = data;
    return kTrackingRectTag;
}

// Override of (apparently) a private NSView method(!) See above for rationale.
- (NSTrackingRectTag)_addTrackingRect:(NSRect)rect
                                owner:(id)owner
                             userData:(void *)data
                         assumeInside:(BOOL)assumeInside
                       useTrackingNum:(int)tag
{
    //DCHECK(tag == 0 || tag == kTrackingRectTag);
    //DCHECK(trackingRectOwner_ == nil);
    trackingRectOwner_ = owner;
    trackingRectUserData_ = data;
    return kTrackingRectTag;
}

// Override of (apparently) a private NSView method(!) See above for rationale.
- (void)_addTrackingRects:(NSRect *)rects
                    owner:(id)owner
             userDataList:(void **)userDataList
         assumeInsideList:(BOOL *)assumeInsideList
             trackingNums:(NSTrackingRectTag *)trackingNums
                    count:(int)count
{
    //DCHECK(count == 1);
    //DCHECK(trackingNums[0] == 0 || trackingNums[0] == kTrackingRectTag);
    //DCHECK(trackingRectOwner_ == nil);
    trackingRectOwner_ = owner;
    trackingRectUserData_ = userDataList[0];
    trackingNums[0] = kTrackingRectTag;
}

// Override of a public NSView method, replacing the inherited functionality.
// See above for rationale.
- (void)removeTrackingRect:(NSTrackingRectTag)tag
{
    if (tag == 0)
        return;

    if (tag == kTrackingRectTag) {
        trackingRectOwner_ = nil;
        return;
    }

    if (tag == lastToolTipTag_) {
        [super removeTrackingRect:tag];
        lastToolTipTag_ = 0;
        return;
    }

    // If any other tracking rect is being removed, we don't know how it was
    // created and it's possible there's a leak involved (see Radar 3500217).
    //NOTREACHED();
}

// Override of (apparently) a private NSView method(!)
- (void)_removeTrackingRects:(NSTrackingRectTag *)tags count:(int)count
{
    int i;
    for (i = 0; i < count; ++i) {
        int tag = tags[i];
        if (tag == 0)
            continue;
        //DCHECK(tag == kTrackingRectTag);
        trackingRectOwner_ = nil;
    }
}

// Sends a fake NSEventTypeMouseExited event to the view for its current tracking rect.
- (void)_sendToolTipMouseExited
{
    // Nothing matters except window, trackingNumber, and userData.
    int windowNumber = [[self window] windowNumber];
    NSEvent *fakeEvent = [NSEvent enterExitEventWithType:NSEventTypeMouseExited
                                                location:NSMakePoint(0, 0)
                                           modifierFlags:0
                                               timestamp:0
                                            windowNumber:windowNumber
                                                 context:NULL
                                             eventNumber:0
                                          trackingNumber:kTrackingRectTag
                                                userData:trackingRectUserData_];
    [trackingRectOwner_ mouseExited:fakeEvent];
}

// Sends a fake NSEventTypeMouseEntered event to the view for its current tracking rect.
- (void)_sendToolTipMouseEntered
{
    // Nothing matters except window, trackingNumber, and userData.
    int windowNumber = [[self window] windowNumber];
    NSEvent *fakeEvent = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered
                                                location:NSMakePoint(0, 0)
                                           modifierFlags:0
                                               timestamp:0
                                            windowNumber:windowNumber
                                                 context:NULL
                                             eventNumber:0
                                          trackingNumber:kTrackingRectTag
                                                userData:trackingRectUserData_];
    [trackingRectOwner_ mouseEntered:fakeEvent];
}

// Sets the view's current tooltip, to be displayed at the current mouse
// location. (This does not make the tooltip appear -- as usual, it only
// appears after a delay.) Pass null to remove the tooltip.
- (void)setToolTipAtMousePoint:(NSString *)string
{
    // If the mouse is outside the view, then clear the tooltip (otherwise the
    // tooltip may appear outside the view which looks weird!).
    NSPoint pt = [[self window] mouseLocationOutsideOfEventStream];
    if (!NSMouseInRect([self convertPoint:pt fromView:nil], [self frame], NO))
        string = nil;

    NSString *toolTip = [string length] == 0 ? nil : string;
    NSString *oldToolTip = toolTip_;
    if ((toolTip == nil || oldToolTip == nil) ? toolTip == oldToolTip
            : [toolTip isEqualToString:oldToolTip]) {
        return;
    }
    if (oldToolTip) {
        [self _sendToolTipMouseExited];
        [oldToolTip release];
    }
    toolTip_ = [toolTip copy];
    if (toolTip) {
        // See radar 3500217 for why we remove all tooltips
        // rather than just the single one we created.
        [self removeAllToolTips];
        NSRect wideOpenRect = NSMakeRect(-100000, -100000, 200000, 200000);
        lastToolTipTag_ = [self addToolTipRect:wideOpenRect
                                         owner:self
                                      userData:NULL];
        [self _sendToolTipMouseEntered];
    }
}

// NSView calls this to get the text when displaying the tooltip.
- (NSString *)view:(NSView *)view
  stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point
          userData:(void *)data
{
    return [[toolTip_ copy] autorelease];
}

@end
