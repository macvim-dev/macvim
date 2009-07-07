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
 * MMPlugInViewHeader
 *
 * Essentially just a title bar for a plugin view.  Handles drawing the
 * drag-and-drop line where a new plugin view will be inserted.
 *
 * MMPlugInView
 *
 * This contains a single view added by a plugin.
 *
 * MMPlugInViewContainer
 *
 * This contains multiple MMPlugInViews.  It handles the drag and drop aspects
 * of the views, as well.
 *
 * Author: Matt Tolton
 */
#import "MacVim.h"

#ifdef MM_ENABLE_PLUGINS

#import "PlugInGUI.h"
#import "CTGradient.h"

NSString *MMPlugInViewPboardType = @"MMPlugInViewPboardType";

@implementation MMPlugInViewHeader

- (void)mouseDown:(NSEvent *)theEvent
{
    // Make image from view
    NSView *view = self;
    [view lockFocus];
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc]
        initWithFocusedViewRect: [view bounds]] autorelease];
    [view unlockFocus];

    NSImage *image = [[[NSImage alloc] initWithSize: [view bounds].size]
                        autorelease];
    [image addRepresentation:bitmap];

    NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];

    [pboard declareTypes:[NSArray arrayWithObject:MMPlugInViewPboardType]
                   owner:self];

    NSPoint pt = [view convertPoint:[view bounds].origin
                             toView:[controller plugInSubview]];
    [[controller plugInSubview] dragImage:image
                                       at:pt
                                   offset:NSMakeSize(0, 0)
                                    event:theEvent
                               pasteboard:pboard
                                   source:controller
                                slideBack:YES];
}

- (void)drawRect:(NSRect)rect
{
    NSColor *startColor;
    startColor = [NSColor colorWithCalibratedRed:.600
                                           green:.600
                                            blue:.600
                                           alpha:1.0];

    NSColor *endColor = [NSColor colorWithCalibratedRed:.800
                                                  green:.800
                                                   blue:.800
                                                  alpha:1.0];

    CTGradient *grad = [CTGradient gradientWithBeginningColor:startColor
                                                  endingColor:endColor];
    [grad fillRect:[self bounds] angle:90];

    MMPlugInView *dropView = [[controller container] dropView];

    if (dropView == [controller plugInSubview]) {
        NSRect insertionRect = NSMakeRect(0,[self bounds].size.height - 2,
                [self bounds].size.width, 2);
        [[NSColor redColor] set];
        NSRectFill(insertionRect);
    }
}

- (BOOL)isOpaque
{
    return YES;
}

- (NSRect)dragRect
{
    return NSMakeRect(0, [self bounds].size.height - 6, [self bounds].size.width, 6);
}

@end

@implementation MMPlugInView

- (MMPlugInViewController *)controller
{
    return controller;
}

@end

@implementation MMPlugInViewController

- (id)initWithView:(NSView *)view title:(NSString *)title
{
    if ((self = [super init]) == nil) return nil;

    if (![NSBundle loadNibNamed:@"PlugInView" owner:self])
        ASLogErr(@"Error loading PlugIn nib");

    [titleField setStringValue:title];

    [plugInSubview setMinDimension:50
                   andMaxDimension:0.0];

    [view setFrame:[contentView bounds]];
    [contentView addSubview:view];

    return self;
}

- (RBSplitSubview *)plugInSubview
{
    return plugInSubview;
}

- (void)moveToContainer:(MMPlugInViewContainer *)container
{
    if ([plugInSubview splitView]) {
        [plugInSubview removeFromSuperview];
    }
    [container addSubview:plugInSubview];
}

- (void)moveToContainer:(MMPlugInViewContainer *)container before:(MMPlugInView *)lowerView
{
    if ([plugInSubview splitView]) {
        [plugInSubview removeFromSuperview];
    }
    [container addSubview:plugInSubview positioned:NSWindowBelow relativeTo:lowerView];
}

- (MMPlugInViewHeader *)headerView
{
    return headerView;
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    if (isLocal)
        return NSDragOperationPrivate;
    else
        return NSDragOperationNone;
}

- (void)dropViewChanged {
    [headerView setNeedsDisplay:YES];
}

- (MMPlugInViewContainer *)container {
    return (MMPlugInViewContainer *)[plugInSubview splitView];
}
@end

@implementation MMPlugInViewContainer

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]) == nil) return nil;

    [self registerForDraggedTypes:
            [NSArray arrayWithObjects:MMPlugInViewPboardType, nil]];

    [self setVertical:NO];
    [self setDelegate:self];

    fillerView = [[RBSplitSubview alloc] initWithFrame:NSMakeRect(0,0,0,0)];
    [fillerView setHidden:YES];

    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [fillerView release]; fillerView = nil;
    [super dealloc];
}

- (unsigned int)splitView:(RBSplitView*)sender dividerForPoint:(NSPoint)point
                inSubview:(RBSplitSubview*)subview
{
    MMPlugInViewController *controller = [(MMPlugInView *)subview controller];
    MMPlugInViewHeader *header = [controller headerView];

    if ([header mouse:[header convertPoint:point fromView:sender]
               inRect:[header dragRect]])
        return [subview position] - 1;

    return NSNotFound;
}

- (NSRect)splitView:(RBSplitView*)sender cursorRect:(NSRect)rect
         forDivider:(unsigned int)theDivider
{

    if (theDivider != 0) return NSZeroRect;

    int i;
    for (i = 1;; i++) {
        MMPlugInView *view = (MMPlugInView *)[sender subviewAtPosition:i];
        if (!view) break;

        MMPlugInViewHeader *header = [[view controller] headerView];
        NSRect rect = [header dragRect];
        rect = [sender convertRect:rect fromView:header];
        [sender addCursorRect:rect
                       cursor:[RBSplitView cursor:RBSVHorizontalCursor]];

    }

    return NSZeroRect;
}

- (void)clearDragInfo
{
    if (dropView) {
        MMPlugInView *save = dropView;
        dropView = nil;
        [[save controller] dropViewChanged];
    }
}

// point should be in the window's coordinate system
- (void)updateDragInfo:(id<NSDraggingInfo>)info
{

    [self clearDragInfo];

    if (!([info draggingSourceOperationMask] & NSDragOperationPrivate)) return;

    if (![[info draggingSource] isKindOfClass:[MMPlugInViewController class]]) return; 

    // for now has to be THIS container.  in the future, it will be ok for any
    // container associated with the same vim instance
    if ([[info draggingSource] container] != self) return;

    // XXX for now we just use the view that the mouse is currently over, and
    // always insert "above" that view.  In the future, we might want to try to
    // find the divider that the mouse is closest to and have the dropView be
    // the view below that divider.

    NSPoint point = [info draggingLocation];

    int i;
    for (i = 0;; i++) {
        MMPlugInView *subview = (MMPlugInView *)[self subviewAtPosition:i];
        if (!subview) break;

        if ([subview mouse:[subview convertPoint:point fromView:nil]
                    inRect:[subview bounds]]) {
            dropView = subview;
            break;
        }
    }

    if ([[info draggingSource] plugInSubview] == dropView)
        dropView = nil;

    if (dropView) [[dropView controller] dropViewChanged];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    [self updateDragInfo:sender];

    if (dropView != nil)
        return NSDragOperationPrivate;
    else
        return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
    [self updateDragInfo:sender];

    if (dropView != nil)
        return NSDragOperationPrivate;

    return NSDragOperationNone;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender
{
    [self updateDragInfo:sender];
    return dropView != nil;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    MMPlugInViewController *source = [sender draggingSource];
    [source moveToContainer:self before:dropView];
    [self clearDragInfo];
    return YES;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender
{
    [self clearDragInfo];
}


- (MMPlugInView *)dropView {
    return dropView;
}

@end

#endif
