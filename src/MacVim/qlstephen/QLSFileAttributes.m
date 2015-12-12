//
//  QLSMagicFileAttributes.m
//  QuickLookStephen
//
//  Created by Nick Hutchinson on 31/07/12.
//

#import "QLSFileAttributes.h"
#import "RegexKitLite.h"

@interface QLSFileAttributes ()

@property (readwrite) BOOL isTextFile;
@property (readwrite) NSString *mimeType;
@property (readwrite) CFStringEncoding fileEncoding;
@property (readwrite) NSURL *url;

@end

@implementation QLSFileAttributes

+ (instancetype)attributesForItemAtURL:(NSURL *)aURL
{
  NSString *magicString = [self magicStringForItemAtURL:aURL];
  if (!magicString) return nil;

  NSArray *matches = [magicString rkl_captureComponentsMatchedByRegex:
                         @"(\\S+/\\S+); charset=(\\S+)"];

  if (![matches count]) return nil;

  NSString *mimeType = matches[1];
  NSString *charset = matches[2];

  BOOL mimeTypeIsTextual = [self mimeTypeIsTextual:mimeType];

  CFStringEncoding encoding =
      CFStringConvertIANACharSetNameToEncoding((CFStringRef)charset);

  QLSFileAttributes *attributes = [QLSFileAttributes new];
  attributes.fileEncoding = encoding;
  attributes.isTextFile = mimeTypeIsTextual;
  attributes.mimeType = mimeType;
  attributes.url = aURL;

  return attributes;
}

////////////////////////////////////////////////////////////////////////////////
// Private Methods
////////////////////////////////////////////////////////////////////////////////

+ (NSString *)magicStringForItemAtURL:(NSURL *)aURL
{
  NSString *path = [aURL path];
  NSParameterAssert(path);

  NSMutableDictionary *environment =
      [NSProcessInfo.processInfo.environment mutableCopy];
  environment[@"LC_ALL"] = @"en_US.UTF-8";

  NSTask *task = [NSTask new];
  task.launchPath = @"/usr/bin/file";
  task.arguments = @[@"--mime", @"--brief", path];
  task.environment = environment;
  task.standardOutput = [NSPipe new];

  [task launch];

  NSData *output =
      [[task.standardOutput fileHandleForReading] readDataToEndOfFile];

  [task waitUntilExit];

  if (task.terminationReason != NSTaskTerminationReasonExit
        || task.terminationStatus != 0) {
    return nil;
  }

  NSCharacterSet *whitespaceCharset =
      [NSCharacterSet whitespaceAndNewlineCharacterSet];

  NSString *stringOutput =
      [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];

  stringOutput =
      [stringOutput stringByTrimmingCharactersInSet:whitespaceCharset];

  return stringOutput;
}


/**
 * @return YES if mimeType contains "text", or if the mime type conforms to the
 *         public.text UTI.
 */
+ (BOOL)mimeTypeIsTextual:(NSString *)mimeType
{
  NSArray *components = [mimeType componentsSeparatedByString:@"/"];
  if (components.count != 2)
    return NO;

  if ([components[0] rangeOfString:@"text"].location != NSNotFound)
    return YES;

  NSString *UTType =
      CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(
                            kUTTagClassMIMEType,
                            (__bridge CFStringRef)mimeType,
                            kUTTypeData));

  if (UTTypeConformsTo((__bridge CFStringRef)UTType, kUTTypeText)) {
    return YES;
  }

  return NO;
}

@end
