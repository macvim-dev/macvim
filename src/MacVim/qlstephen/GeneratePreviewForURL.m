#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#import <Foundation/Foundation.h>

#import "QLSFileAttributes.h"


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
