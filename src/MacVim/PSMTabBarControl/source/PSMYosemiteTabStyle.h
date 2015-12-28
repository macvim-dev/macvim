//
//  PSMYosemiteTabStyle.h
//  PSMTabBarControl
//
//  Created by Christoffer Winterkvist on 25/08/14.
//
//

#import <Cocoa/Cocoa.h>
#import "PSMTabStyle.h"

@interface PSMYosemiteTabStyle : NSObject <PSMTabStyle> {
    NSImage *closeButton;
    NSImage *closeButtonDown;
    NSImage *closeButtonOver;
    NSImage *_addTabButtonImage;
    NSImage *_addTabButtonPressedImage;
    NSImage *_addTabButtonRolloverImage;
    NSMutableParagraphStyle *truncatingTailParagraphStyle;
    NSMutableParagraphStyle *centeredParagraphStyle;
}

- (void)drawInteriorWithTabCell:(PSMTabBarCell *)cell inView:(NSView*)controlView;

- (void)encodeWithCoder:(NSCoder *)aCoder;
- (id)initWithCoder:(NSCoder *)aDecoder;

@end
