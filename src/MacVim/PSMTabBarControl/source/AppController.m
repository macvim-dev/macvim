//
//  AppController.m
//  TabBarControl
//
//  Created by John Pannell on 12/19/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import "AppController.h"
#import "WindowController.h"

@implementation AppController

- (void)awakeFromNib
{
    [self newWindow:self];
    [self newWindow:self];
    NSRect frontFrame = [[NSApp keyWindow] frame];
    frontFrame.origin.x += 400;
    [[NSApp keyWindow] setFrame:frontFrame display:YES];
}

- (IBAction)newWindow:(id)sender
{
    // put up a window
    WindowController *newWindow = [[WindowController alloc] initWithWindowNibName:@"Window"];
    [newWindow showWindow:self];
}

@end
