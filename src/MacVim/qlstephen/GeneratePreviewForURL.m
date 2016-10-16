#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#import <Foundation/Foundation.h>

#import "QLSFileAttributes.h"

#define DEFAULT_MAX_FILE_SIZE 1024 * 100

// Generate a preview for the document with the given url
OSStatus GeneratePreviewForURL(void *thisInterface,
                               QLPreviewRequestRef request,
                               CFURLRef url,
                               CFStringRef contentTypeUTI,
                               CFDictionaryRef options) {
  @autoreleasepool {
    if (QLPreviewRequestIsCancelled(request))
      return noErr;

    QLSFileAttributes *magicAttributes =
        [QLSFileAttributes attributesForItemAtURL:(__bridge NSURL *)url];

    if (!magicAttributes) {
      NSLog(@"QLStephen: Could not determine attribtues of file %@", url);
      return noErr;
    }

    if (!magicAttributes.isTextFile) {
      return noErr;
    }

    if (magicAttributes.fileEncoding == kCFStringEncodingInvalidId) {
      NSLog(@"QLStephen: Could not determine encoding of file %@", url);
      return noErr;
    }

    NSDictionary *previewProperties = @{
      (NSString *)kQLPreviewPropertyStringEncodingKey : @( magicAttributes.fileEncoding ),
      (NSString *)kQLPreviewPropertyWidthKey      : @700,
      (NSString *)kQLPreviewPropertyHeightKey     : @800
    };

    // Get size of current File
    NSFileManager *man = [NSFileManager defaultManager];
    NSURL *file_url = (__bridge NSURL *)(url);
    NSDictionary *attrs = [man attributesOfItemAtPath: [file_url path] error: NULL];

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

    // the plugin is running as com.apple.quicklook.satellite therefore we need to load our own settings
    NSDictionary *defaults = [userDefaults persistentDomainForName:@"com.whomwah.quicklookstephen"];

    long long maxFileSizeSetting = [[defaults valueForKey:@"maxFileSize"] longLongValue];
    unsigned long long maxFileSize = DEFAULT_MAX_FILE_SIZE;
    if(maxFileSizeSetting > 0) {
      maxFileSize = maxFileSizeSetting;
    }

    // Display less data, if file is too big
    if(attrs.fileSize > maxFileSize) {
      NSFileHandle *myFile= [NSFileHandle fileHandleForReadingAtPath:[file_url path]];
      if(!myFile) {
        return noErr;
      }
      NSData *displayData = [myFile readDataOfLength:maxFileSize];
      [myFile closeFile];

      QLPreviewRequestSetDataRepresentation(
          request,
          (__bridge CFDataRef)displayData,
          kUTTypePlainText,
          (__bridge CFDictionaryRef)previewProperties);
      return noErr;
    }
    QLPreviewRequestSetURLRepresentation(
        request,
        url,
        kUTTypePlainText,
        (__bridge CFDictionaryRef)previewProperties);

    return noErr;
  }
}

void CancelPreviewGeneration(void* thisInterface, QLPreviewRequestRef preview) {
  // implement only if supported
}
