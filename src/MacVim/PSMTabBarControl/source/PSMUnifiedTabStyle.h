//
//  PSMUnifiedTabStyle.h
//  --------------------
//
//  Created by Keith Blount on 30/04/2006.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PSMTabStyle.h"

@interface PSMUnifiedTabStyle : NSObject <PSMTabStyle>
{
    NSImage *unifiedCloseButton;
    NSImage *unifiedCloseButtonDown;
    NSImage *unifiedCloseButtonOver;
    NSImage *_addTabButtonImage;
    NSImage *_addTabButtonPressedImage;
    NSImage *_addTabButtonRolloverImage;
    NSMutableParagraphStyle *truncatingTailParagraphStyle;
    NSMutableParagraphStyle *centeredParagraphStyle;
	
    float leftMargin;
}
- (void)setLeftMarginForTabBarControl:(float)margin;
@end
