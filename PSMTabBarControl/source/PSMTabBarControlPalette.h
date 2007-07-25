//
//  PSMTabBarControlPalette.h
//  PSMTabBarControl
//
//  Created by John Pannell on 12/21/05.
//  Copyright Positive Spin Media 2005 . All rights reserved.
//

#import <InterfaceBuilder/InterfaceBuilder.h>
#import "PSMTabBarControl.h"

@interface PSMTabBarControlPalette : IBPalette
{
    IBOutlet NSImageView    *repImage;
    PSMTabBarControl        *_customControl;
}
@end

@interface PSMTabBarControl (PSMTabBarControlPaletteInspector)
- (NSString *)inspectorClassName;
@end
