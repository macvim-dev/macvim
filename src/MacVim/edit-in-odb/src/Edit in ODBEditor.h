//
//  Edit in ODBEditor.h
//
//  Created by Allan Odgaard on 2005-11-26.
//  See LICENSE for license details
//
//  Generalized by Chris Eidhof and Eelco Lempsink from 'Edit in TextMate.h'

#import <Cocoa/Cocoa.h>

@interface EditInODBEditor : NSObject
{
}
+ (void)externalEditString:(NSString*)aString startingAtLine:(int)aLine forView:(NSView*)aView;
+ (void)externalEditString:(NSString*)aString startingAtLine:(int)aLine forView:(NSView*)aView withObject:(NSObject*)anObject;
@end
