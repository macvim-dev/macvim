//
//  PSMTabDragAssistant.m
//  PSMTabBarControl
//
//  Created by John Pannell on 4/10/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMTabDragAssistant.h"
#import "PSMTabBarCell.h"
#import "PSMTabStyle.h"


@implementation PSMTabDragAssistant

static PSMTabDragAssistant *sharedDragAssistant = nil;

#pragma mark -
#pragma mark Creation/Destruction

+ (PSMTabDragAssistant *)sharedDragAssistant
{
    if (!sharedDragAssistant){
        sharedDragAssistant = [[PSMTabDragAssistant alloc] init];
    }
    
    return sharedDragAssistant;
}

- (id)init
{
    if(self = [super init]){
        _sourceTabBar = nil;
        _destinationTabBar = nil;
        _participatingTabBars = [[NSMutableSet alloc] init];
        _draggedCell = nil;
        _animationTimer = nil;
        _sineCurveWidths = [[NSMutableArray alloc] initWithCapacity:kPSMTabDragAnimationSteps];
        _targetCell = nil;
        _isDragging = NO;
    }
    
    return self;
}

- (void)dealloc
{
    [_sourceTabBar release];
    [_destinationTabBar release];
    [_participatingTabBars release];
    [_draggedCell release];
    [_animationTimer release];
    [_sineCurveWidths release];
    [_targetCell release];
    [super dealloc];
}

#pragma mark -
#pragma mark Accessors

- (PSMTabBarControl *)sourceTabBar
{
    return _sourceTabBar;
}

- (void)setSourceTabBar:(PSMTabBarControl *)tabBar
{
    [tabBar retain];
    [_sourceTabBar release];
    _sourceTabBar = tabBar;
}

- (PSMTabBarControl *)destinationTabBar
{
    return _destinationTabBar;
}

- (void)setDestinationTabBar:(PSMTabBarControl *)tabBar
{
    [tabBar retain];
    [_destinationTabBar release];
    _destinationTabBar = tabBar;
}

- (PSMTabBarCell *)draggedCell
{
    return _draggedCell;
}

- (void)setDraggedCell:(PSMTabBarCell *)cell
{
    [cell retain];
    [_draggedCell release];
    _draggedCell = cell;
}

- (int)draggedCellIndex
{
    return _draggedCellIndex;
}

- (void)setDraggedCellIndex:(int)value
{
    _draggedCellIndex = value;
}

- (BOOL)isDragging
{
    return _isDragging;
}

- (void)setIsDragging:(BOOL)value
{
    _isDragging = value;
}

- (NSPoint)currentMouseLoc
{
    return _currentMouseLoc;
}

- (void)setCurrentMouseLoc:(NSPoint)point
{
    _currentMouseLoc = point;
}

- (PSMTabBarCell *)targetCell
{
    return _targetCell;
}

- (void)setTargetCell:(PSMTabBarCell *)cell
{
    [cell retain];
    [_targetCell release];
    _targetCell = cell;
}

#pragma mark -
#pragma mark Functionality

- (void)startDraggingCell:(PSMTabBarCell *)cell fromTabBar:(PSMTabBarControl *)control withMouseDownEvent:(NSEvent *)event
{
    [self setIsDragging:YES];
    [self setSourceTabBar:control];
    [self setDestinationTabBar:control];
    [_participatingTabBars addObject:control];
    [self setDraggedCell:cell];
    [self setDraggedCellIndex:[[control cells] indexOfObject:cell]];
    
    NSRect cellFrame = [cell frame];
    // list of widths for animation
    int i;
    float cellWidth = cellFrame.size.width;
    for(i = 0; i < kPSMTabDragAnimationSteps; i++){
        int thisWidth;
        thisWidth = (int)(cellWidth - ((cellWidth/2.0) + ((sin((PI/2.0) + ((float)i/(float)kPSMTabDragAnimationSteps)*PI) * cellWidth) / 2.0)));
        [_sineCurveWidths addObject:[NSNumber numberWithInt:thisWidth]];
    }
    
    // hide UI buttons
    [[control overflowPopUpButton] setHidden:YES];
    [[control addTabButton] setHidden:YES];
    
    [[NSCursor closedHandCursor] set];
    
    NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    NSImage *dragImage = [cell dragImageForRect:cellFrame];
    [[cell indicator] removeFromSuperview];
    [self distributePlaceholdersInTabBar:control withDraggedCell:cell];

    if([control isFlipped]){
        cellFrame.origin.y += cellFrame.size.height;
    }
    [cell setHighlighted:NO];
    NSSize offset = NSZeroSize;
    [pboard declareTypes:[NSArray arrayWithObjects:@"PSMTabBarControlItemPBType", nil] owner: nil];
    [pboard setString:[[NSNumber numberWithInt:[[control cells] indexOfObject:cell]] stringValue] forType:@"PSMTabBarControlItemPBType"];
    _animationTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0/30.0) target:self selector:@selector(animateDrag:) userInfo:nil repeats:YES];
    [control dragImage:dragImage at:cellFrame.origin offset:offset event:event pasteboard:pboard source:control slideBack:YES];
}

- (void)draggingEnteredTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc
{
    [self setDestinationTabBar:control];
    [self setCurrentMouseLoc:mouseLoc];
    // hide UI buttons
    [[control overflowPopUpButton] setHidden:YES];
    [[control addTabButton] setHidden:YES];
    if(![[[control cells] objectAtIndex:0] isPlaceholder])
        [self distributePlaceholdersInTabBar:control];
    [_participatingTabBars addObject:control];
}

- (void)draggingUpdatedInTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc
{
    if([self destinationTabBar] != control)
        [self setDestinationTabBar:control];
    [self setCurrentMouseLoc:mouseLoc];
}

- (void)draggingExitedTabBar:(PSMTabBarControl *)control
{
    [self setDestinationTabBar:nil];
    [self setCurrentMouseLoc:NSMakePoint(-1.0, -1.0)];
}

- (void)performDragOperation
{
#if 1
    // move cell
    [[[self destinationTabBar] cells] replaceObjectAtIndex:[[[self destinationTabBar] cells] indexOfObject:[self targetCell]] withObject:[self draggedCell]];
    [[self draggedCell] setControlView:[self destinationTabBar]];
    // move actual NSTabViewItem
    if([self sourceTabBar] != [self destinationTabBar]){
        [[[self sourceTabBar] tabView] removeTabViewItem:[[self draggedCell] representedObject]];
        [[[self destinationTabBar] tabView] addTabViewItem:[[self draggedCell] representedObject]];
    }
    [self finishDrag];
#else
    unsigned idx = [[[self destinationTabBar] cells] indexOfObject:[self targetCell]];
    
    // move cell
    [[[self destinationTabBar] cells] replaceObjectAtIndex:idx withObject:[self draggedCell]];
    [[self draggedCell] setControlView:[self destinationTabBar]];
    // move actual NSTabViewItem
    if([self sourceTabBar] != [self destinationTabBar]){
        [[[self sourceTabBar] tabView] removeTabViewItem:[[self draggedCell] representedObject]];
        idx = [[[self destinationTabBar] cells] indexOfObject:[self draggedCell]];
        NSLog(@"Inserting at index %d", idx);
        [[[self destinationTabBar] tabView] insertTabViewItem:[[self draggedCell] representedObject] atIndex:idx];
    }
    [self finishDrag];
#endif
}

- (void)draggedImageEndedAt:(NSPoint)aPoint operation:(NSDragOperation)operation
{
    if([self isDragging]){  // means there was not a successful drop (performDragOperation)
        // put cell back
        [[[self sourceTabBar] cells] insertObject:[self draggedCell] atIndex:[self draggedCellIndex]];
        [self finishDrag];
    }
}

- (void)finishDrag
{
    [self setIsDragging:NO];
    [self removeAllPlaceholdersFromTabBar:[self sourceTabBar]];
    [self setSourceTabBar:nil];
    [self setDestinationTabBar:nil];
    NSEnumerator *e = [_participatingTabBars objectEnumerator];
    PSMTabBarControl *tabBar;
    while(tabBar = [e nextObject]){
        [self removeAllPlaceholdersFromTabBar:tabBar];
    }
    [_participatingTabBars removeAllObjects];
    [self setDraggedCell:nil];
    [_animationTimer invalidate];
    _animationTimer = nil;
    [_sineCurveWidths removeAllObjects];
    [self setTargetCell:nil];
}

#pragma mark -
#pragma mark Animation

- (void)animateDrag:(NSTimer *)timer
{
    NSEnumerator *e = [_participatingTabBars objectEnumerator];
    PSMTabBarControl *tabBar;
    while(tabBar = [e nextObject]){
        [self calculateDragAnimationForTabBar:tabBar];
        [[NSRunLoop currentRunLoop] performSelector:@selector(display) target:tabBar argument:nil order:1 modes:[NSArray arrayWithObjects:@"NSEventTrackingRunLoopMode", @"NSDefaultRunLoopMode", nil]];
    }
}

- (void)calculateDragAnimationForTabBar:(PSMTabBarControl *)control
{
    BOOL removeFlag = YES;
    NSMutableArray *cells = [control cells];
    int i, cellCount = [cells count];
    float xPos = [[control psmTabStyle] leftMarginForTabBarControl];
    
    // identify target cell
    // mouse at beginning of tabs
    NSPoint mouseLoc = [self currentMouseLoc];
    if([self destinationTabBar] == control){
        removeFlag = NO;
        if(mouseLoc.x < [[control psmTabStyle] leftMarginForTabBarControl]){
            [self setTargetCell:[cells objectAtIndex:0]];
            goto layout;
        }
        
        NSRect overCellRect;
        PSMTabBarCell *overCell = [control cellForPoint:mouseLoc cellFrame:&overCellRect];
        if(overCell){
            // mouse among cells - placeholder
            if([overCell isPlaceholder]){
                [self setTargetCell:overCell];
                goto layout;
            }
            
            // non-placeholders
            if(mouseLoc.x < (overCellRect.origin.x + (overCellRect.size.width / 2.0))){
                // mouse on left side of cell
                [self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] - 1)]];
                goto layout;
            } else {
                // mouse on right side of cell
                [self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] + 1)]];
                goto layout;
            }
        } else {
            // out at end - must find proper cell (could be more in overflow menu)
            [self setTargetCell:[control lastVisibleTab]];
            goto layout;
        }
    } else {
        [self setTargetCell:nil];
    }
    
layout: 
    for(i = 0; i < cellCount; i++){
        PSMTabBarCell *cell = [cells objectAtIndex:i];
        NSRect newRect = [cell frame];
        if(![cell isInOverflowMenu]){
            if([cell isPlaceholder]){
                if(cell == [self targetCell]){
                    [cell setCurrentStep:([cell currentStep] + 1)];
                } else {
                    [cell setCurrentStep:([cell currentStep] - 1)];
                    if([cell currentStep] > 0){
                        removeFlag = NO;
                    }
                }
                newRect.size.width = [[_sineCurveWidths objectAtIndex:[cell currentStep]] intValue];
            }
        } else {
            break;
        }
        newRect.origin.x = xPos;
        [cell setFrame:newRect];
        if([cell indicator])
            [[cell indicator] setFrame:[[control psmTabStyle] indicatorRectForTabCell:cell]];
        xPos += newRect.size.width;
    }
    if(removeFlag){
        [_participatingTabBars removeObject:control];
        [self removeAllPlaceholdersFromTabBar:control];
    }
}

#pragma mark -
#pragma mark Placeholders

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control withDraggedCell:(PSMTabBarCell *)cell
{
    // called upon first drag - must distribute placeholders
    [self distributePlaceholdersInTabBar:control];
    // replace dragged cell with a placeholder, and clean up surrounding cells
    int cellIndex = [[control cells] indexOfObject:cell];
    PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:YES inControlView:control] autorelease];
    [[control cells] replaceObjectAtIndex:cellIndex withObject:pc];
    [[control cells] removeObjectAtIndex:(cellIndex + 1)];
    [[control cells] removeObjectAtIndex:(cellIndex - 1)];
    return;
}

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control
{
    int i, numVisibleTabs = [control numberOfVisibleTabs];
    for(i = 0; i < numVisibleTabs; i++){
        PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:NO inControlView:control] autorelease]; 
        [[control cells] insertObject:pc atIndex:(2 * i)];
    }
    if(numVisibleTabs > 0){
        PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:NO inControlView:control] autorelease];
        if([[control cells] count] > (2 * numVisibleTabs)){
            [[control cells] insertObject:pc atIndex:(2 * numVisibleTabs)];
        } else {
            [[control cells] addObject:pc];
        }
    }
}

- (void)removeAllPlaceholdersFromTabBar:(PSMTabBarControl *)control
{
    int i, cellCount = [[control cells] count];
    for(i = (cellCount - 1); i >= 0; i--){
        PSMTabBarCell *cell = [[control cells] objectAtIndex:i];
        if([cell isPlaceholder])
            [[control cells] removeObject:cell];
    }
    // redraw
    [[NSRunLoop currentRunLoop] performSelector:@selector(update) target:control argument:nil order:1 modes:[NSArray arrayWithObjects:@"NSEventTrackingRunLoopMode", @"NSDefaultRunLoopMode", nil]];
    [[NSRunLoop currentRunLoop] performSelector:@selector(display) target:control argument:nil order:1 modes:[NSArray arrayWithObjects:@"NSEventTrackingRunLoopMode", @"NSDefaultRunLoopMode", nil]];
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder {
    //[super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_sourceTabBar forKey:@"sourceTabBar"];
        [aCoder encodeObject:_destinationTabBar forKey:@"destinationTabBar"];
        [aCoder encodeObject:_participatingTabBars forKey:@"participatingTabBars"];
        [aCoder encodeObject:_draggedCell forKey:@"draggedCell"];
        [aCoder encodeInt:_draggedCellIndex forKey:@"draggedCellIndex"];
        [aCoder encodeBool:_isDragging forKey:@"isDragging"];
        [aCoder encodeObject:_animationTimer forKey:@"animationTimer"];
        [aCoder encodeObject:_sineCurveWidths forKey:@"sineCurveWidths"];
        [aCoder encodePoint:_currentMouseLoc forKey:@"currentMouseLoc"];
        [aCoder encodeObject:_targetCell forKey:@"targetCell"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    //self = [super initWithCoder:aDecoder];
    //if (self) {
        if ([aDecoder allowsKeyedCoding]) {
            _sourceTabBar = [[aDecoder decodeObjectForKey:@"sourceTabBar"] retain];
            _destinationTabBar = [[aDecoder decodeObjectForKey:@"destinationTabBar"] retain];
            _participatingTabBars = [[aDecoder decodeObjectForKey:@"participatingTabBars"] retain];
            _draggedCell = [[aDecoder decodeObjectForKey:@"draggedCell"] retain];
            _draggedCellIndex = [aDecoder decodeIntForKey:@"draggedCellIndex"];
            _isDragging = [aDecoder decodeBoolForKey:@"isDragging"];
            _animationTimer = [[aDecoder decodeObjectForKey:@"animationTimer"] retain];
            _sineCurveWidths = [[aDecoder decodeObjectForKey:@"sineCurveWidths"] retain];
            _currentMouseLoc = [aDecoder decodePointForKey:@"currentMouseLoc"];
            _targetCell = [[aDecoder decodeObjectForKey:@"targetCell"] retain];
        }
    //}
    return self;
}


@end
