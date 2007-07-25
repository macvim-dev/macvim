//
//  PSMTabBarControlInspector.h
//  PSMTabBarControl
//
//  Created by John Pannell on 12/21/05.
//  Copyright Positive Spin Media 2005. All rights reserved.
//

#import <InterfaceBuilder/InterfaceBuilder.h>

@interface PSMTabBarControlInspector : IBInspector
{
    IBOutlet NSPopUpButton      *_stylePopUp;
    IBOutlet NSButton           *_canCloseOnlyTab;
    IBOutlet NSButton           *_hideForSingleTab;
    IBOutlet NSButton           *_showAddTab;
    IBOutlet NSTextField        *_cellMinWidth;
    IBOutlet NSTextField        *_cellMaxWidth;
    IBOutlet NSTextField        *_cellOptimumWidth;
    IBOutlet NSButton           *_sizeToFit;
    IBOutlet NSButton           *_allowsDragBetweenWindows;
}
@end
