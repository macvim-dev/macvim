//
//  Edit in ODBEditor.h
//
//  Created by Allan Odgaard on 2005-11-26.
//  Copyright (c) 2005 MacroMates. All rights reserved.
//
//  Generalized by Chris Eidhof and Eelco Lempsink from 'Edit in TextMate.h'

#import <Cocoa/Cocoa.h>

@interface EditInODBEditor : NSObject
{
}
+ (void)externalEditString:(NSString*)aString startingAtLine:(int)aLine forView:(NSView*)aView;
@end
