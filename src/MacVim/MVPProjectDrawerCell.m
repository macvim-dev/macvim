
#import "MVPProjectDrawerCell.h"

@implementation MVPProjectDrawerCell

#define kImageSize		16.0

#define kImageOriginXOffset 3
#define kImageOriginYOffset 1

#define kTextOriginXOffset	2
#define kTextOriginYOffset	2
#define kTextHeightAdjust	4


- (id)init {
	self = [super init];
	[self setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	return self;
}

- (void)dealloc{
    [image release]; image = nil;
    [super dealloc];
}


- (id)copyWithZone:(NSZone*)zone{
    MVPProjectDrawerCell *cell = (MVPProjectDrawerCell*)[super copyWithZone:zone];
    cell->image = [image retain];
    return cell;
}

- (void)setImage:(NSImage*)anImage{
    if (anImage != image){
        [image release];
        image = [anImage retain];
		[image setSize:NSMakeSize(kImageSize, kImageSize)];
    }
}

- (NSImage*)image{ return image; }

- (NSSize)cellSize{
    NSSize cellSize = [super cellSize];
	cellSize.width += 3;
	if(image) {
		cellSize.width += ([image size].width + 3);
	} 
    return cellSize;
}


- (NSRect)titleRectForBounds:(NSRect)cellRect{	
	// the cell has an image: draw the normal item cell
	NSSize imageSize;
	NSRect imageFrame;

	imageSize = [image size];
	NSDivideRect(cellRect, &imageFrame, &cellRect, 3 + imageSize.width, NSMinXEdge);

	imageFrame.origin.x += kImageOriginXOffset;
	imageFrame.origin.y -= kImageOriginYOffset;
	imageFrame.size = imageSize;
	
	imageFrame.origin.y += ceil((cellRect.size.height - imageFrame.size.height) / 2);
	
	NSRect newFrame = cellRect;
	newFrame.origin.x += kTextOriginXOffset;
	newFrame.origin.y += kTextOriginYOffset;
	newFrame.size.height -= kTextHeightAdjust;

	return newFrame;
}


- (void)editWithFrame:(NSRect)aRect inView:(NSView*)controlView editor:(NSText*)textObj delegate:(id)anObject event:(NSEvent*)theEvent{
	NSRect textFrame = [self titleRectForBounds:aRect];
	[super editWithFrame:textFrame inView:controlView editor:textObj delegate:anObject event:theEvent];
}

- (void)selectWithFrame:(NSRect)aRect inView:(NSView*)controlView editor:(NSText*)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength{
	NSRect textFrame = [self titleRectForBounds:aRect];
	[super selectWithFrame:textFrame inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView*)controlView{
	if(image == nil) {
		return;
	}
	
		// the cell has an image: draw the normal item cell
		NSSize imageSize;
        NSRect imageFrame;

        imageSize = [image size];
        NSDivideRect(cellFrame, &imageFrame, &cellFrame, 3 + imageSize.width, NSMinXEdge);
 
        imageFrame.origin.x += kImageOriginXOffset;
		imageFrame.origin.y -= kImageOriginYOffset;
        imageFrame.size = imageSize;
		
        if ([controlView isFlipped])
            imageFrame.origin.y += ceil((cellFrame.size.height + imageFrame.size.height) / 2);
        else
            imageFrame.origin.y += ceil((cellFrame.size.height - imageFrame.size.height) / 2);
		[image compositeToPoint:imageFrame.origin operation:NSCompositeSourceOver];

		NSRect newFrame = cellFrame;
		newFrame.origin.x += kTextOriginXOffset;
		newFrame.origin.y += kTextOriginYOffset;
		newFrame.size.height -= kTextHeightAdjust;
		[super drawWithFrame:newFrame inView:controlView];
}



@end

