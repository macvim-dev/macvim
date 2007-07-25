//
//  PSMTabBarControlPalette.m
//  PSMTabBarControl
//
//  Created by John Pannell on 12/21/05.
//  Copyright Positive Spin Media 2005 . All rights reserved.
//

#import "PSMTabBarControlPalette.h"

@implementation PSMTabBarControlPalette

- (void)finishInstantiate
{
    // associate representative image with actual control
    _customControl = [[PSMTabBarControl alloc] initWithFrame:NSMakeRect(0,0,180,22)];
    [self associateObject:_customControl ofType:IBViewPboardType withView:repImage];
}

- (void)dealloc
{
    [_customControl release];
    [super dealloc];
}

@end

@implementation PSMTabBarControl (PSMTabBarControlPaletteInspector)

- (NSString *)inspectorClassName
{
    return @"PSMTabBarControlInspector";
}

@end
