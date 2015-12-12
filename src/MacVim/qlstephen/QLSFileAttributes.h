//
//  QLSMagicFileAttributes.h
//  QuickLookStephen
//
//  Created by Nick Hutchinson on 31/07/12.

#import <Foundation/Foundation.h>

@interface QLSFileAttributes : NSObject

+ (instancetype)attributesForItemAtURL:(NSURL *)aURL;

@property (readonly) NSURL *url;

@property (readonly) BOOL isTextFile;
@property (readonly) NSString *mimeType;
@property (readonly) CFStringEncoding fileEncoding;

@end


