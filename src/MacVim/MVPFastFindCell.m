//
//  FastFindCell.m
//  MacVim
//
//  Created by Doug Fales on 4/3/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import "MVPFastFindCell.h"
#import "MVPFastFindController.h"
#import "MVPProject.h"
#import "MVPFastFindResult.h"

@interface MVPFastFindCell () 
-(NSAttributedString *)addAttributesToString:(NSString *)filename;
@end


@implementation MVPFastFindCell

@synthesize fastFindController;

- copyWithZone:(NSZone *)zone {
	MVPFastFindCell *cell = (MVPFastFindCell *)[super copyWithZone:zone];
	cell.fastFindController = self.fastFindController;
    return cell;
}

- (void)dealloc {
	[fastFindController release]; fastFindController = nil;
	[super dealloc];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	
	MVPFastFindResult *item = [self objectValue];
	NSAttributedString *aString = [self addAttributesToString:[item title]];
	[aString drawAtPoint:NSMakePoint(cellFrame.origin.x + 28, cellFrame.origin.y + 4)];
	
	
	NSColor *gray = [NSColor grayColor];
	NSDictionary *pathAttributes = [NSDictionary dictionaryWithObjectsAndKeys:gray, NSForegroundColorAttributeName, [NSFont systemFontOfSize:9], NSFontAttributeName, nil];

	[[item name] drawAtPoint:NSMakePoint(cellFrame.origin.x + 28, cellFrame.origin.y + 21) withAttributes:pathAttributes];
	
	[[NSGraphicsContext currentContext] saveGraphicsState];
	
	
	float startY = cellFrame.origin.y;
	if([controlView isFlipped]) {
		NSAffineTransform *transform = [NSAffineTransform transform];
		[transform translateXBy:0.0 yBy:cellFrame.size.height];
		[transform scaleXBy:1.0 yBy:-1.0];
		[transform concat];
		startY = -cellFrame.origin.y;
	}
	
    NSImage *icon =  [item icon];
    
	NSRect toRect = NSMakeRect(cellFrame.origin.x +2, startY + 3, 25, 25);
	NSRect fromRect = NSMakeRect(0, 0, [icon size].width, [icon size].height);
	NSImageInterpolation interp = [[NSGraphicsContext currentContext] imageInterpolation];
	[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
	[icon drawInRect:toRect fromRect:fromRect operation:NSCompositeSourceOver fraction:1.0];
	
	[[NSGraphicsContext currentContext] setImageInterpolation:interp];
	[[NSGraphicsContext currentContext] restoreGraphicsState];
	
}

-(NSAttributedString *)addAttributesToString:(NSString *)filename  {
	NSColor *filenameColor = ([self isHighlighted] ? [NSColor alternateSelectedControlTextColor] : [NSColor grayColor]);	
	NSDictionary *filenameAttributes = [NSDictionary dictionaryWithObjectsAndKeys:filenameColor, NSForegroundColorAttributeName, [NSFont systemFontOfSize:14], NSFontAttributeName, nil];
	NSMutableAttributedString *aString = [[NSMutableAttributedString alloc] initWithString:filename attributes:filenameAttributes]; 
    NSRange r =	[filename rangeOfString:[fastFindController searchString]];
    [aString addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:14] range:r];
	[aString addAttribute:NSForegroundColorAttributeName value:[NSColor blackColor] range:r];
    return aString;    
}

@end
