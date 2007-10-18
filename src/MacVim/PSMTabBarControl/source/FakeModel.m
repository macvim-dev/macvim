//
//  FakeModel.m
//  TabBarControl
//
//  Created by John Pannell on 12/19/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import "FakeModel.h"


@implementation FakeModel

- (id)init
{
    if(self == [super init]){
        _isProcessing = YES;
        _icon = nil;
        _iconName = nil;
        _objectCount = 2;
        controller = [[NSObjectController alloc] initWithContent:self];
    }
    return self;
}


// accessors
- (BOOL)isProcessing
{
    return _isProcessing;
}

- (void)setIsProcessing:(BOOL)value
{
    _isProcessing = value;
}

- (NSImage *)icon
{
    return _icon;
}

- (void)setIcon:(NSImage *)icon
{
    [icon retain];
    [_icon release];
    _icon = icon;
}

- (NSString *)iconName
{
    return _iconName;
}

- (void)setIconName:(NSString *)iconName
{
    [iconName retain];
    [_iconName release];
    _iconName = iconName;
}

- (int)objectCount
{
    return _objectCount;
}

- (void)setObjectCount:(int)value
{
    _objectCount = value;
}

- (NSObjectController *)controller
{
    return controller;
}

@end
