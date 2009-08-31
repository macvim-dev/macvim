// IconFamily.m
// IconFamily class implementation
// by Troy Stephens, Thomas Schnitzer, David Remahl, Nathan Day, Ben Haller, Sven Janssen, Peter Hosey, Conor Dearden, Elliot Glaysher, and Dave MacLachlan
// version 0.9.3
//
// Project Home Page:
//   http://iconfamily.sourceforge.net/
//
// Problems, shortcomings, and uncertainties that I'm aware of are flagged with "NOTE:".  Please address bug reports, bug fixes, suggestions, etc. to the project Forums and bug tracker at https://sourceforge.net/projects/iconfamily/

/*
    Copyright (c) 2001-2006 Troy N. Stephens
    Portions Copyright (c) 2007 Google Inc.

    Use and distribution of this source code is governed by the MIT License, whose terms are as follows.

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#import "IconFamily.h"
#import "NSString+CarbonFSRefCreation.h"

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
// This is defined in 10.5 and beyond in IconStorage.h
enum {
  kIconServices512PixelDataARGB = 'ic09' /* non-premultiplied 512x512 ARGB bitmap*/
};
#endif

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_3
// This is defined in 10.4 and beyond in IconStorage.h
enum {
  kIconServices256PixelDataARGB = 'ic08' /* non-premultiplied 256x256 ARGB bitmap*/
};
#endif


@interface IconFamily (Internals)

+ (NSImage*) resampleImage:(NSImage*)image toIconWidth:(int)width usingImageInterpolation:(NSImageInterpolation)imageInterpolation;

+ (Handle) get32BitDataFromBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep requiredPixelSize:(int)requiredPixelSize;

+ (Handle) get8BitDataFromBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep requiredPixelSize:(int)requiredPixelSize;

+ (Handle) get8BitMaskFromBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep requiredPixelSize:(int)requiredPixelSize;

+ (Handle) get1BitMaskFromBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep requiredPixelSize:(int)requiredPixelSize;

- (BOOL) addResourceType:(OSType)type asResID:(int)resID;

@end

@implementation IconFamily

+ (IconFamily*) iconFamily
{
    return [[[IconFamily alloc] init] autorelease];
}

+ (IconFamily*) iconFamilyWithContentsOfFile:(NSString*)path
{
    return [[[IconFamily alloc] initWithContentsOfFile:path] autorelease];
}

+ (IconFamily*) iconFamilyWithIconOfFile:(NSString*)path
{
    return [[[IconFamily alloc] initWithIconOfFile:path] autorelease];
}

+ (IconFamily*) iconFamilyWithIconFamilyHandle:(IconFamilyHandle)hNewIconFamily
{
    return [[[IconFamily alloc] initWithIconFamilyHandle:hNewIconFamily] autorelease];
}

+ (IconFamily*) iconFamilyWithSystemIcon:(int)fourByteCode
{
    return [[[IconFamily alloc] initWithSystemIcon:fourByteCode] autorelease];
}

+ (IconFamily*) iconFamilyWithThumbnailsOfImage:(NSImage*)image
{
    return [[[IconFamily alloc] initWithThumbnailsOfImage:image] autorelease];
}

+ (IconFamily*) iconFamilyWithThumbnailsOfImage:(NSImage*)image usingImageInterpolation:(NSImageInterpolation)imageInterpolation
{
    return [[[IconFamily alloc] initWithThumbnailsOfImage:image usingImageInterpolation:imageInterpolation] autorelease];
}

// This is IconFamily's designated initializer.  It creates a new IconFamily that initially has no elements.
//
// The proper way to do this is to simply allocate a zero-sized handle (not to be confused with an empty handle) and assign it to hIconFamily.  This technique works on Mac OS X 10.2 as well as on 10.0.x and 10.1.x.  Our previous technique of allocating an IconFamily struct with a resourceSize of 0 no longer works as of Mac OS X 10.2.
- init
{
    self = [super init];
    if (self) {
        hIconFamily = (IconFamilyHandle) NewHandle( 0 );
        if (hIconFamily == NULL) {
            [self autorelease];
            return nil;
        }
    }
    return self;
}

- initWithContentsOfFile:(NSString*)path
{
    FSRef ref;
    OSStatus result;

    self = [self init];
    if (self) {
        if (hIconFamily) {
            DisposeHandle( (Handle)hIconFamily );
            hIconFamily = NULL;
        }
		if (![path getFSRef:&ref createFileIfNecessary:NO]) {
			[self autorelease];
			return nil;
		}
		result = ReadIconFromFSRef( &ref, &hIconFamily );
		if (result != noErr) {
			[self autorelease];
			return nil;
		}
    }
    return self;
}

- initWithIconFamilyHandle:(IconFamilyHandle)hNewIconFamily
{
    self = [self init];
    if (self) {
        if (hIconFamily) {
            DisposeHandle( (Handle)hIconFamily );
            hIconFamily = NULL;
        }
        hIconFamily = hNewIconFamily;
    }
    return self;
}

- initWithIconOfFile:(NSString*)path
{
    IconRef	iconRef;
    OSStatus	result;
    SInt16	label;
    FSRef	ref;

    self = [self init];
    if (self)
    {
        if (hIconFamily)
        {
            DisposeHandle( (Handle)hIconFamily );
            hIconFamily = NULL;
        }

        if( ![path getFSRef:&ref createFileIfNecessary:NO] )
        {
            [self autorelease];
            return nil;
        }

        result = GetIconRefFromFileInfo(
                                        &ref,
                                        /*inFileNameLength*/ 0,
                                        /*inFileName*/ NULL,
                                        kFSCatInfoNone,
                                        /*inCatalogInfo*/ NULL,
                                        kIconServicesNormalUsageFlag,
                                        &iconRef,
                                        &label );

        if (result != noErr)
        {
            [self autorelease];
            return nil;
        }

        result = IconRefToIconFamily(
                                     iconRef,
                                     kSelectorAllAvailableData,
                                     &hIconFamily );

        ReleaseIconRef( iconRef );

        if (result != noErr || !hIconFamily)
        {
            [self autorelease];
            return nil;
        }
    }
    return self;
}

- initWithSystemIcon:(int)fourByteCode
{
    IconRef	iconRef;
    OSErr	result;

    self = [self init];
    if (self)
    {
        if (hIconFamily)
        {
            DisposeHandle( (Handle)hIconFamily );
            hIconFamily = NULL;
        }

        result = GetIconRef(kOnSystemDisk, kSystemIconsCreator, fourByteCode, &iconRef);

        if (result != noErr)
        {
            [self autorelease];
            return nil;
        }

        result = IconRefToIconFamily(
                                     iconRef,
                                     kSelectorAllAvailableData,
                                     &hIconFamily );

        if (result != noErr || !hIconFamily)
        {
            [self autorelease];
            return nil;
        }

        ReleaseIconRef( iconRef );
    }
    return self;
}

- initWithThumbnailsOfImage:(NSImage*)image
{
    // The default is to use a high degree of antialiasing, producing a smooth image.
    return [self initWithThumbnailsOfImage:image usingImageInterpolation:NSImageInterpolationHigh];
}

- initWithThumbnailsOfImage:(NSImage*)image usingImageInterpolation:(NSImageInterpolation)imageInterpolation
{
    NSImage* iconImage512x512;
    NSImage* iconImage256x256;
    NSImage* iconImage128x128;
    NSImage* iconImage32x32;
    NSImage* iconImage16x16;
    NSImage* bitmappedIconImage512x512;
    NSBitmapImageRep* iconBitmap512x512;
    NSBitmapImageRep* iconBitmap256x256;
    NSBitmapImageRep* iconBitmap128x128;
    NSBitmapImageRep* iconBitmap32x32;
    NSBitmapImageRep* iconBitmap16x16;

    // Start with a new, empty IconFamily.
    self = [self init];
    if (self == nil)
        return nil;

    // Resample the given image to create a 512x512 pixel, 32-bit RGBA
    // version, and use that as our "thumbnail" (512x512) icon and mask.
    //
    // Our +resampleImage:toIconWidth:... method, in its present form,
    // returns an NSImage that contains an NSCacheImageRep, rather than
    // an NSBitmapImageRep.  We convert to an NSBitmapImageRep, so that
    // our methods can scan the image data, using initWithFocusedViewRect:.
    iconImage512x512 = [IconFamily resampleImage:image toIconWidth:512 usingImageInterpolation:imageInterpolation];
    if (!iconImage512x512) {
      [self autorelease];
      return nil;
    }

    [iconImage512x512 lockFocus];
    iconBitmap512x512 = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, 512, 512)];
    [iconImage512x512 unlockFocus];
    if (!iconBitmap512x512) {
      [self release];
      return nil;
    }
    // Create an NSImage with the iconBitmap512x512 NSBitmapImageRep, that we
    // can resample to create the smaller icon family elements.  (This is
    // most likely more efficient than resampling from the original image again,
    // particularly if it is large.  It produces a slightly different result, but
    // the difference is minor and should not be objectionable...)

    bitmappedIconImage512x512 = [[NSImage alloc] initWithSize:NSMakeSize(512, 512)];
    [bitmappedIconImage512x512 addRepresentation:iconBitmap512x512];

    if (!bitmappedIconImage512x512) {
      [self autorelease];
      return nil;
    }

    [self setIconFamilyElement:kIconServices512PixelDataARGB fromBitmapImageRep:iconBitmap512x512];
    [iconBitmap512x512 release];

    iconImage256x256 = [IconFamily resampleImage:bitmappedIconImage512x512 toIconWidth:256 usingImageInterpolation:imageInterpolation];
    if (iconImage256x256) {
      [iconImage256x256 lockFocus];
      iconBitmap256x256 = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, 256, 256)];
      [iconImage256x256 unlockFocus];
      if (iconBitmap256x256) {
        [self setIconFamilyElement:kIconServices256PixelDataARGB fromBitmapImageRep:iconBitmap256x256];
        [iconBitmap256x256 release];
      }
    }

    iconImage128x128 = [IconFamily resampleImage:bitmappedIconImage512x512 toIconWidth:128 usingImageInterpolation:imageInterpolation];
    if (iconImage128x128) {
      [iconImage128x128 lockFocus];
      iconBitmap128x128 = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, 128, 128)];
      [iconImage128x128 unlockFocus];

      if (iconBitmap128x128) {
        [self setIconFamilyElement:kThumbnail32BitData fromBitmapImageRep:iconBitmap128x128];
        [self setIconFamilyElement:kThumbnail8BitMask  fromBitmapImageRep:iconBitmap128x128];
        [iconBitmap128x128 release];
      }
    }

    // Resample the 512x512 image to create a 32x32 pixel, 32-bit RGBA version,
    // and use that as our "large" (32x32) icon and 8-bit mask.
    iconImage32x32 = [IconFamily resampleImage:bitmappedIconImage512x512 toIconWidth:32 usingImageInterpolation:imageInterpolation];
    if (iconImage32x32) {
      [iconImage32x32 lockFocus];
      iconBitmap32x32 = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, 32, 32)];
      [iconImage32x32 unlockFocus];
      if (iconBitmap32x32) {
        [self setIconFamilyElement:kLarge32BitData fromBitmapImageRep:iconBitmap32x32];
        [self setIconFamilyElement:kLarge8BitData fromBitmapImageRep:iconBitmap32x32];
        [self setIconFamilyElement:kLarge8BitMask fromBitmapImageRep:iconBitmap32x32];
        [self setIconFamilyElement:kLarge1BitMask fromBitmapImageRep:iconBitmap32x32];
        [iconBitmap32x32 release];
      }
    }

    // Resample the 512x512 image to create a 16x16 pixel, 32-bit RGBA version,
    // and use that as our "small" (16x16) icon and 8-bit mask.
    iconImage16x16 = [IconFamily resampleImage:bitmappedIconImage512x512 toIconWidth:16 usingImageInterpolation:imageInterpolation];
    if (iconImage16x16) {
      [iconImage16x16 lockFocus];
      iconBitmap16x16 = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, 16, 16)];
      [iconImage16x16 unlockFocus];
      if (iconBitmap16x16) {
        [self setIconFamilyElement:kSmall32BitData fromBitmapImageRep:iconBitmap16x16];
        [self setIconFamilyElement:kSmall8BitData fromBitmapImageRep:iconBitmap16x16];
        [self setIconFamilyElement:kSmall8BitMask fromBitmapImageRep:iconBitmap16x16];
        [self setIconFamilyElement:kSmall1BitMask fromBitmapImageRep:iconBitmap16x16];
        [iconBitmap16x16 release];
      }
    }

    // Release the icon.
    [bitmappedIconImage512x512 release];

    // Return the new icon family!
    return self;
}

- (void) dealloc
{
    DisposeHandle( (Handle)hIconFamily );
    [super dealloc];
}

- (NSBitmapImageRep*) bitmapImageRepWithAlphaForIconFamilyElement:(OSType)elementType;
{
    NSBitmapImageRep* bitmapImageRep;
    int pixelsWide;
    Handle hRawBitmapData;
    Handle hRawMaskData;
    OSType maskElementType;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
	NSBitmapFormat bitmapFormat = NSAlphaFirstBitmapFormat;
#endif
    OSErr result;
    unsigned long* pRawBitmapData;
    unsigned long* pRawBitmapDataEnd;
    unsigned char* pRawMaskData;
    unsigned char* pBitmapImageRepBitmapData;

    // Make sure elementType is a valid type that we know how to handle, and
    // figure out the dimensions and bit depth of the bitmap for that type.
    switch (elementType) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5
    // 'ic09' 512x512 32-bit RGB image
    case kIconServices512PixelDataARGB:
        maskElementType = 0;
        pixelsWide = 512;
        break;
#endif

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
	// 'ic08' 256x256 32-bit ARGB image
	case kIconServices256PixelDataARGB:
		maskElementType = 0;
		pixelsWide = 256;
	    break;
#endif

	// 'it32' 128x128 32-bit RGB image
	case kThumbnail32BitData:
		maskElementType = kThumbnail8BitMask;
		pixelsWide = 128;
	    break;

	// 'ih32' 48x48 32-bit RGB image
	case kHuge32BitData:
		maskElementType = kHuge8BitMask;
		pixelsWide = 48;
	    break;

	// 'il32' 32x32 32-bit RGB image
	case kLarge32BitData:
		maskElementType = kLarge8BitMask;
		pixelsWide = 32;
	    break;

	// 'is32' 16x16 32-bit RGB image
	case kSmall32BitData:
		maskElementType = kSmall8BitMask;
		pixelsWide = 16;
	    break;

	default:
	    return nil;
    }

    // Get the raw, uncompressed bitmap data for the requested element.
    hRawBitmapData = NewHandle( pixelsWide * pixelsWide * 4 );
    result = GetIconFamilyData( hIconFamily, elementType, hRawBitmapData );
    if (result != noErr) {
        DisposeHandle( hRawBitmapData );
        return nil;
    }

    if (maskElementType) {
        // Get the corresponding raw, uncompressed 8-bit mask data.
        hRawMaskData = NewHandle( pixelsWide * pixelsWide );
        result = GetIconFamilyData( hIconFamily, maskElementType, hRawMaskData );
        if (result != noErr) {
            DisposeHandle( hRawMaskData );
            hRawMaskData = NULL;
        }
    }

    // The retrieved raw bitmap data is stored in memory as 32 bit per pixel, 8 bit per sample xRGB data.  (The sample order provided by IconServices is the same, regardless of whether we're running on a big-endian (PPC) or little-endian (Intel) architecture.)
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
    // With proper attention to byte order, we can fold the mask data into the color data in-place, producing ARGB data suitable for handing off to NSBitmapImageRep.
#else
    // With proper attention to byte order, we can fold the mask data into the color data in-place, producing RGBA data suitable for handing off to NSBitmapImageRep.
#endif
//    HLock( hRawBitmapData ); // Handle-based memory isn't compacted anymore, so calling HLock()/HUnlock() is unnecessary.
    pRawBitmapData = (unsigned long*) *hRawBitmapData;
    pRawBitmapDataEnd = pRawBitmapData + pixelsWide * pixelsWide;
    if (hRawMaskData) {
//        HLock( hRawMaskData ); // Handle-based memory isn't compacted anymore, so calling HLock()/HUnlock() is unnecessary.
        pRawMaskData = (unsigned char*) *hRawMaskData;
        while (pRawBitmapData < pRawBitmapDataEnd) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
            // Convert the xRGB pixel data to ARGB.
            //                                                          PowerPC         Intel
            //                                                          -------         -----
            // Bytes in memory are                                      x R G B         x R G B
            // *pRawBitmapData loads as 32-bit word into register       xRGB            BGRx
            // NSSwapHostLongToBig() swaps this to                      xRGB            xRGB
            // Loading *pRawMaskData and shifting left 24 bits yields   A000            A000
            // Bitwise ORing these two words together yields            ARGB            ARGB
            // NSSwapBigLongToHost() swaps this to                      ARGB            BGRA
            // Bytes in memory after they're stored as a 32-bit word    A R G B         A R G B
            *pRawBitmapData = NSSwapBigLongToHost((*pRawMaskData++ << 24) | NSSwapHostLongToBig(*pRawBitmapData));
#else
            // Convert the xRGB pixel data to RGBA.
            //                                                          PowerPC         Intel
            //                                                          -------         -----
            // Bytes in memory are                                      x R G B         x R G B
            // *pRawBitmapData loads as 32-bit word into register       xRGB            BGRx
            // NSSwapHostLongToBig() swaps this to                      xRGB            xRGB
            // Shifting left 8 bits yields ('0' denotes all zero bits)  RGB0            RGB0
            // Bitwise ORing with *pRawMaskData byte yields             RGBA            RGBA
            // NSSwapBigLongToHost() swaps this to                      RGBA            ABGR
            // Bytes in memory after they're stored as a 32-bit word    R G B A         R G B A
            *pRawBitmapData = NSSwapBigLongToHost((NSSwapHostLongToBig(*pRawBitmapData) << 8) | *pRawMaskData++);
#endif
            ++pRawBitmapData;
        }
//        HUnlock( hRawMaskData ); // Handle-based memory isn't compacted anymore, so calling HLock()/HUnlock() is unnecessary.
    } else {
        if(maskElementType) {
            // We SHOULD have a mask, but apparently not. Fake it with alpha=1.
            while (pRawBitmapData < pRawBitmapDataEnd) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
                // Set alpha byte to 0xff.
                //                                                                  PowerPC         Intel
                //                                                                  -------         -----
                // Bytes in memory are                                              x R G B         x R G B
                // Writing a single 0xff byte ('1') at pRawBitmapData yields        1 R G B         1 R G B
                *(unsigned char *)pRawBitmapData = 0xff;
#else
                // Set alpha byte to 0xff.
                //                                                                  PowerPC         Intel
                //                                                                  -------         -----
                // Bytes in memory are                                              R G B x         R G B x
                // Writing a single 0xff byte, 3 bytes past pRawBitmapData yields   R G B 1         R G B 1
                *((unsigned char *)pRawBitmapData + 3) = 0xff;
#endif
                ++pRawBitmapData;
            }
        }
    }

    // Create a new NSBitmapImageRep with the given bitmap data.  Note that
    // when creating the NSBitmapImageRep we pass in NULL for the "planes"
    // parameter.  This causes the new NSBitmapImageRep to allocate its own
    // buffer for the bitmap data (which it will own and release when the
    // NSBitmapImageRep is released), rather than referencing the bitmap
    // data we pass in (which will soon disappear when we call
    // DisposeHandle() below!).  (See the NSBitmapImageRep documentation for
    // the -initWithBitmapDataPlanes:... method, where this is explained.)
    //
    // Once we have the new NSBitmapImageRep, we get a pointer to its
    // bitmapData and copy our bitmap data in.
    bitmapImageRep = [[[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:pixelsWide
                      pixelsHigh:pixelsWide
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace // NOTE: is this right?
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
                    bitmapFormat:bitmapFormat
#endif
                     bytesPerRow:0
                    bitsPerPixel:0] autorelease];
    pBitmapImageRepBitmapData = [bitmapImageRep bitmapData];
    if (pBitmapImageRepBitmapData) {
        memcpy( pBitmapImageRepBitmapData, *hRawBitmapData,
                pixelsWide * pixelsWide * 4 );
    }
//    HUnlock( hRawBitmapData ); // Handle-based memory isn't compacted anymore, so calling HLock()/HUnlock() is unnecessary.

    // Free the retrieved raw data.
    DisposeHandle( hRawBitmapData );
    if (hRawMaskData)
        DisposeHandle( hRawMaskData );

    // Return nil if the NSBitmapImageRep didn't give us a buffer to copy into.
    if (pBitmapImageRepBitmapData == NULL)
        return nil;

    // Return the new NSBitmapImageRep.
    return bitmapImageRep;
}

- (NSImage*) imageWithAllReps
{
    NSImage* image = NULL;
    image = [[[NSImage alloc] initWithData:[NSData dataWithBytes:*hIconFamily length:GetHandleSize((Handle)hIconFamily)]] autorelease];
    return image;
}

- (BOOL) setIconFamilyElement:(OSType)elementType fromBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep
{
    Handle hRawData = NULL;
    OSErr result;

    switch (elementType) {
      // 'ic08' 512x512 32-bit ARGB image
    case kIconServices512PixelDataARGB:
        hRawData = [IconFamily get32BitDataFromBitmapImageRep:bitmapImageRep requiredPixelSize:512];
        break;

    // 'ic08' 256x256 32-bit ARGB image
    case kIconServices256PixelDataARGB:
        hRawData = [IconFamily get32BitDataFromBitmapImageRep:bitmapImageRep requiredPixelSize:256];
        break;

    // 'it32' 128x128 32-bit RGB image
	case kThumbnail32BitData:
	    hRawData = [IconFamily get32BitDataFromBitmapImageRep:bitmapImageRep requiredPixelSize:128];
	    break;

	// 't8mk' 128x128 8-bit alpha mask
	case kThumbnail8BitMask:
	    hRawData = [IconFamily get8BitMaskFromBitmapImageRep:bitmapImageRep requiredPixelSize:128];
	    break;

	// 'il32' 32x32 32-bit RGB image
	case kLarge32BitData:
	    hRawData = [IconFamily get32BitDataFromBitmapImageRep:bitmapImageRep requiredPixelSize:32];
	    break;

	// 'l8mk' 32x32 8-bit alpha mask
	case kLarge8BitMask:
	    hRawData = [IconFamily get8BitMaskFromBitmapImageRep:bitmapImageRep requiredPixelSize:32];
	    break;

	// 'ICN#' 32x32 1-bit alpha mask
	case kLarge1BitMask:
	    hRawData = [IconFamily get1BitMaskFromBitmapImageRep:bitmapImageRep requiredPixelSize:32];
	    break;

	// 'icl8' 32x32 8-bit indexed image data
	case kLarge8BitData:
		hRawData = [IconFamily get8BitDataFromBitmapImageRep:bitmapImageRep requiredPixelSize:32];
		break;

	// 'is32' 16x16 32-bit RGB image
	case kSmall32BitData:
		hRawData = [IconFamily get32BitDataFromBitmapImageRep:bitmapImageRep requiredPixelSize:16];
		break;

	// 's8mk' 16x16 8-bit alpha mask
	case kSmall8BitMask:
	    hRawData = [IconFamily get8BitMaskFromBitmapImageRep:bitmapImageRep requiredPixelSize:16];
	    break;

	// 'ics#' 16x16 1-bit alpha mask
	case kSmall1BitMask:
	    hRawData = [IconFamily get1BitMaskFromBitmapImageRep:bitmapImageRep requiredPixelSize:16];
	    break;

	// 'ics8' 16x16 8-bit indexed image data
	case kSmall8BitData:
		hRawData = [IconFamily get8BitDataFromBitmapImageRep:bitmapImageRep requiredPixelSize:16];
		break;

	default:
	    return NO;
    }

	// NSLog(@"setIconFamilyElement:%@ fromBitmapImageRep:%@ generated handle %p of size %d", NSFileTypeForHFSTypeCode(elementType), bitmapImageRep, hRawData, GetHandleSize(hRawData));

    if (hRawData == NULL)
	{
		NSLog(@"Null data returned to setIconFamilyElement:fromBitmapImageRep:");
		return NO;
	}

    result = SetIconFamilyData( hIconFamily, elementType, hRawData );
    DisposeHandle( hRawData );

    if (result != noErr)
	{
		NSLog(@"SetIconFamilyData() returned error %d", result);
		return NO;
	}

    return YES;
}

- (BOOL) setAsCustomIconForFile:(NSString*)path
{
    return( [self setAsCustomIconForFile:path withCompatibility:NO] );
}

- (BOOL) setAsCustomIconForFile:(NSString*)path withCompatibility:(BOOL)compat
{
    FSRef targetFileFSRef;
    FSRef parentDirectoryFSRef;
    SInt16 file;
    OSStatus result;
    struct FSCatalogInfo catInfo;
    struct FileInfo *finderInfo = (struct FileInfo *)&catInfo.finderInfo;
    Handle hExistingCustomIcon;
    Handle hIconFamilyCopy;
	NSString *parentDirectory;

    // Before we do anything, get the original modification time for the target file.
    NSDate* modificationDate = [[[NSFileManager defaultManager] fileAttributesAtPath:path traverseLink:NO] objectForKey:NSFileModificationDate];

	if ([path isAbsolutePath])
		parentDirectory = [path stringByDeletingLastPathComponent];
    else
        parentDirectory = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:[path stringByDeletingLastPathComponent]];

    // Get an FSRef for the target file's parent directory that we can use in
    // the FSCreateResFile() and FNNotify() calls below.
    if (![parentDirectory getFSRef:&parentDirectoryFSRef createFileIfNecessary:NO])
		return NO;

	// Get the name of the file, for FSCreateResFile.
	struct HFSUniStr255 filename;
	NSString *filenameString = [path lastPathComponent];
	filename.length = [filenameString length];
	[filenameString getCharacters:filename.unicode];

    // Make sure the file has a resource fork that we can open.  (Although
    // this sounds like it would clobber an existing resource fork, the Carbon
    // Resource Manager docs for this function say that's not the case.  If
    // the file already has a resource fork, we receive a result code of
    // dupFNErr, which is not really an error per se, but just a notification
    // to us that creating a new resource fork for the file was not necessary.)
	FSCreateResFile(
	                &parentDirectoryFSRef,
	                filename.length,
	                filename.unicode,
	                kFSCatInfoNone,
	                /*catalogInfo/*/ NULL,
	                &targetFileFSRef,
	                /*newSpec*/ NULL);
	result = ResError();
	if (result == dupFNErr) {
        // If the call to FSCreateResFile() returned dupFNErr, targetFileFSRef will not have been set, so create it from the path.
        if (![path getFSRef:&targetFileFSRef createFileIfNecessary:NO])
            return NO;
    } else if (result != noErr) {
		return NO;
    }

    // Open the file's resource fork.
    file = FSOpenResFile( &targetFileFSRef, fsRdWrPerm );
    if (file == -1)
		return NO;

    // Make a copy of the icon family data to pass to AddResource().
    // (AddResource() takes ownership of the handle we pass in; after the
    // CloseResFile() call its master pointer will be set to 0xffffffff.
    // We want to keep the icon family data, so we make a copy.)
    // HandToHand() returns the handle of the copy in hIconFamily.
    hIconFamilyCopy = (Handle) hIconFamily;
    result = HandToHand( &hIconFamilyCopy );
    if (result != noErr) {
        CloseResFile( file );
        return NO;
    }

    // Remove the file's existing kCustomIconResource of type kIconFamilyType
    // (if any).
    hExistingCustomIcon = GetResource( kIconFamilyType, kCustomIconResource );
    if( hExistingCustomIcon )
        RemoveResource( hExistingCustomIcon );

    // Now add our icon family as the file's new custom icon.
    AddResource( (Handle)hIconFamilyCopy, kIconFamilyType,
                 kCustomIconResource, "\p");
    if (ResError() != noErr) {
        CloseResFile( file );
        return NO;
    }

    if( compat )
    {
        [self addResourceType:kLarge8BitData asResID:kCustomIconResource];
        [self addResourceType:kLarge1BitMask asResID:kCustomIconResource];
        [self addResourceType:kSmall8BitData asResID:kCustomIconResource];
        [self addResourceType:kSmall1BitMask asResID:kCustomIconResource];
    }

    // Close the file's resource fork, flushing the resource map and new icon
    // data out to disk.
    CloseResFile( file );
    if (ResError() != noErr)
		return NO;

    // Prepare to get the Finder info.

    // Now we need to set the file's Finder info so the Finder will know that
    // it has a custom icon.  Start by getting the file's current finder info:
    result = FSGetCatalogInfo(
	                          &targetFileFSRef,
	                          kFSCatInfoFinderInfo,
	                          &catInfo,
	                          /*outName*/ NULL,
	                          /*fsSpec*/ NULL,
	                          /*parentRef*/ NULL);
    if (result != noErr)
		return NO;

    // Set the kHasCustomIcon flag, and clear the kHasBeenInited flag.
    //
    // From Apple's "CustomIcon" code sample:
    //     "set bit 10 (has custom icon) and unset the inited flag
    //      kHasBeenInited is 0x0100 so the mask will be 0xFEFF:"
    //    finderInfo.fdFlags = 0xFEFF & (finderInfo.fdFlags | kHasCustomIcon ) ;
    finderInfo->finderFlags = (finderInfo->finderFlags | kHasCustomIcon ) & ~kHasBeenInited;

    // Now write the Finder info back.
    result = FSSetCatalogInfo( &targetFileFSRef, kFSCatInfoFinderInfo, &catInfo );
    if (result != noErr)
		return NO;

    // Now set the modification time back to when the file was actually last modified.
    NSDictionary* attributes = [NSDictionary dictionaryWithObjectsAndKeys:modificationDate, NSFileModificationDate, nil];
    [[NSFileManager defaultManager] changeFileAttributes:attributes atPath:path];

    // Notify the system that the directory containing the file has changed, to
    // give Finder the chance to find out about the file's new custom icon.
    result = FNNotify( &parentDirectoryFSRef, kFNDirectoryModifiedMessage, kNilOptions );
    if (result != noErr)
        return NO;

    return YES;
}

+ (BOOL) removeCustomIconFromFile:(NSString*)path
{
    FSRef targetFileFSRef;
    FSRef parentDirectoryFSRef;
    SInt16 file;
    OSStatus result;
    struct FSCatalogInfo catInfo;
    struct FileInfo *finderInfo = (struct FileInfo *)&catInfo.finderInfo;
    Handle hExistingCustomIcon;

    // Get an FSRef for the target file.
    if (![path getFSRef:&targetFileFSRef createFileIfNecessary:NO])
        return NO;

    // Open the file's resource fork, if it has one.
    file = FSOpenResFile( &targetFileFSRef, fsRdWrPerm );
    if (file == -1)
        return NO;

    // Remove the file's existing kCustomIconResource of type kIconFamilyType
    // (if any).
    hExistingCustomIcon = GetResource( kIconFamilyType, kCustomIconResource );
    if( hExistingCustomIcon )
        RemoveResource( hExistingCustomIcon );

    // Close the file's resource fork, flushing the resource map out to disk.
    CloseResFile( file );
    if (ResError() != noErr)
        return NO;

    // Now we need to set the file's Finder info so the Finder will know that
    // it has no custom icon. Start by getting the file's current Finder info.
    // Also get an FSRef for its parent directory, that we can use in the
    // FNNotify() call below.
    result = FSGetCatalogInfo(
                              &targetFileFSRef,
                              kFSCatInfoFinderInfo,
                              &catInfo,
                              /*outName*/ NULL,
                              /*fsSpec*/ NULL,
                              &parentDirectoryFSRef );
    if (result != noErr)
        return NO;

    // Clear the kHasCustomIcon flag and the kHasBeenInited flag.
    finderInfo->finderFlags = finderInfo->finderFlags & ~(kHasCustomIcon | kHasBeenInited);

    // Now write the Finder info back.
    result = FSSetCatalogInfo( &targetFileFSRef, kFSCatInfoFinderInfo, &catInfo );
    if (result != noErr)
        return NO;

    // Notify the system that the directory containing the file has changed, to give Finder the chance to find out about the file's new custom icon.
    result = FNNotify( &parentDirectoryFSRef, kFNDirectoryModifiedMessage, kNilOptions );
    if (result != noErr)
        return NO;

    return YES;
}

- (BOOL) setAsCustomIconForDirectory:(NSString*)path
{
    return [self setAsCustomIconForDirectory:path withCompatibility:NO];
}

- (BOOL) setAsCustomIconForDirectory:(NSString*)path withCompatibility:(BOOL)compat
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;
    BOOL exists;
    NSString *iconrPath;
    FSRef targetFolderFSRef, iconrFSRef;
    SInt16 file;
    OSErr result;
    struct HFSUniStr255 filename;
    struct FSCatalogInfo catInfo;
    Handle hExistingCustomIcon;
    Handle hIconFamilyCopy;

    // Confirm that "path" exists and specifies a directory.
    exists = [fm fileExistsAtPath:path isDirectory:&isDir];
    if( !isDir || !exists )
        return NO;

    // Get an FSRef for the folder.
    if( ![path getFSRef:&targetFolderFSRef createFileIfNecessary:NO] )
        return NO;

    // Remove and re-create any existing "Icon\r" file in the directory, and get an FSRef for it.
    iconrPath = [path stringByAppendingPathComponent:@"Icon\r"];
    if( [fm fileExistsAtPath:iconrPath] )
    {
        if( ![fm removeFileAtPath:iconrPath handler:nil] )
            return NO;
    }
    if( ![iconrPath getFSRef:&iconrFSRef createFileIfNecessary:YES] )
        return NO;

    // Get type and creator information for the Icon file.
    result = FSGetCatalogInfo(
                              &iconrFSRef,
                              kFSCatInfoFinderInfo,
                              &catInfo,
                              /*outName*/ NULL,
                              /*fsSpec*/ NULL,
                              /*parentRef*/ NULL );
    if( result == fnfErr ) {
        // The file doesn't exist. Prepare to create it.

        struct FileInfo *finderInfo = (struct FileInfo *)catInfo.finderInfo;

        // These are the file type and creator given to Icon files created by
        // the Finder.
        finderInfo->fileType = 'icon';
        finderInfo->fileCreator = 'MACS';

        // Icon files should be invisible.
        finderInfo->finderFlags = kIsInvisible;

        // Because the inited flag is not set in finderFlags above, the Finder
        // will ignore the location, unless it's in the 'magic rectangle' of
        // { -24,000, -24,000, -16,000, -16,000 } (technote TB42).
        // So we need to make sure to set this to zero anyway, so that the
        // Finder will position it automatically. If the user makes the Icon
        // file visible for any reason, we don't want it to be positioned in an
        // exotic corner of the window.
        finderInfo->location.h = finderInfo->location.v = 0;

        // Standard reserved-field practice.
        finderInfo->reservedField = 0;
    } else if( result != noErr )
        return NO;

    // Get the filename, to be applied to the Icon file.
    filename.length = [@"Icon\r" length];
    [@"Icon\r" getCharacters:filename.unicode];

    // Make sure the file has a resource fork that we can open.  (Although
    // this sounds like it would clobber an existing resource fork, the Carbon
    // Resource Manager docs for this function say that's not the case.)
    FSCreateResFile(
                    &targetFolderFSRef,
                    filename.length,
                    filename.unicode,
                    kFSCatInfoFinderInfo,
                    &catInfo,
                    &iconrFSRef,
                    /*newSpec*/ NULL);
    result = ResError();
    if (!(result == noErr || result == dupFNErr))
        return NO;

    // Open the file's resource fork.
    file = FSOpenResFile( &iconrFSRef, fsRdWrPerm );
    if (file == -1)
        return NO;

    // Make a copy of the icon family data to pass to AddResource().
    // (AddResource() takes ownership of the handle we pass in; after the
    // CloseResFile() call its master pointer will be set to 0xffffffff.
    // We want to keep the icon family data, so we make a copy.)
    // HandToHand() returns the handle of the copy in hIconFamily.
    hIconFamilyCopy = (Handle) hIconFamily;
    result = HandToHand( &hIconFamilyCopy );
    if (result != noErr) {
        CloseResFile( file );
        return NO;
    }

    // Remove the file's existing kCustomIconResource of type kIconFamilyType
    // (if any).
    hExistingCustomIcon = GetResource( kIconFamilyType, kCustomIconResource );
    if( hExistingCustomIcon )
        RemoveResource( hExistingCustomIcon );

    // Now add our icon family as the file's new custom icon.
    AddResource( (Handle)hIconFamilyCopy, kIconFamilyType,
                 kCustomIconResource, "\p");

    if (ResError() != noErr) {
        CloseResFile( file );
        return NO;
    }

    if( compat )
    {
        [self addResourceType:kLarge8BitData asResID:kCustomIconResource];
        [self addResourceType:kLarge1BitMask asResID:kCustomIconResource];
        [self addResourceType:kSmall8BitData asResID:kCustomIconResource];
        [self addResourceType:kSmall1BitMask asResID:kCustomIconResource];
    }

    // Close the file's resource fork, flushing the resource map and new icon
    // data out to disk.
    CloseResFile( file );
    if (ResError() != noErr)
        return NO;

    result = FSGetCatalogInfo( &targetFolderFSRef,
                               kFSCatInfoFinderInfo,
                               &catInfo,
                               /*outName*/ NULL,
                               /*fsSpec*/ NULL,
                               /*parentRef*/ NULL);
    if( result != noErr )
        return NO;

    // Tell the Finder that the folder now has a custom icon.
    ((struct FolderInfo *)catInfo.finderInfo)->finderFlags = ( ((struct FolderInfo *)catInfo.finderInfo)->finderFlags | kHasCustomIcon ) & ~kHasBeenInited;

    result = FSSetCatalogInfo( &targetFolderFSRef,
                      kFSCatInfoFinderInfo,
                      &catInfo);
    if( result != noErr )
        return NO;

    // Notify the system that the target directory has changed, to give Finder
    // the chance to find out about its new custom icon.
    result = FNNotify( &targetFolderFSRef, kFNDirectoryModifiedMessage, kNilOptions );
    if (result != noErr)
        return NO;

    return YES;
}

- (BOOL) writeToFile:(NSString*)path
{
    NSData* iconData = nil;

//    HLock((Handle)hIconFamily); // Handle-based memory isn't compacted anymore, so calling HLock()/HUnlock() is unnecessary.

    iconData = [NSData dataWithBytes:*hIconFamily length:GetHandleSize((Handle)hIconFamily)];
    BOOL success = [iconData writeToFile:path atomically:NO];

//    HUnlock((Handle)hIconFamily); // Handle-based memory isn't compacted anymore, so calling HLock()/HUnlock() is unnecessary.

    return success;
}

@end

@implementation IconFamily (Internals)

+ (NSImage*) resampleImage:(NSImage*)image toIconWidth:(int)iconWidth usingImageInterpolation:(NSImageInterpolation)imageInterpolation
{
    NSGraphicsContext* graphicsContext;
    BOOL wasAntialiasing;
    NSImageInterpolation previousImageInterpolation;
    NSImage* newImage;
    NSImage* workingImage;
    NSImageRep* workingImageRep;
    NSSize size, pixelSize, newSize;
    NSRect iconRect;
    NSRect targetRect;

    // Create a working copy of the image and scale its size down to fit in
    // the square area of the icon.
    //
    // It seems like there should be a more memory-efficient alternative to
    // first duplicating the entire original image, but I don't know what it
    // is.  We need to change some properties ("size" and "scalesWhenResized")
    // of the original image, but we shouldn't change the original, so a copy
    // is necessary.
    workingImage = [image copyWithZone:[image zone]];
    [workingImage setScalesWhenResized:YES];
    size = [workingImage size];
    workingImageRep = [workingImage bestRepresentationForDevice:nil];
    if ([workingImageRep isKindOfClass:[NSBitmapImageRep class]]) {
        pixelSize.width  = [workingImageRep pixelsWide];
        pixelSize.height = [workingImageRep pixelsHigh];
        if (!NSEqualSizes( size, pixelSize )) {
            [workingImage setSize:pixelSize];
            [workingImageRep setSize:pixelSize];
            size = pixelSize;
        }
    }
    if (size.width >= size.height) {
        newSize.width  = iconWidth;
        newSize.height = floor( (float) iconWidth * size.height / size.width + 0.5 );
    } else {
        newSize.height = iconWidth;
        newSize.width  = floor( (float) iconWidth * size.width / size.height + 0.5 );
    }
    [workingImage setSize:newSize];

    // Create a new image the size of the icon, and clear it to transparent.
    newImage = [[NSImage alloc] initWithSize:NSMakeSize(iconWidth,iconWidth)];
    [newImage lockFocus];
    iconRect.origin.x = iconRect.origin.y = 0;
    iconRect.size.width = iconRect.size.height = iconWidth;
    [[NSColor clearColor] set];
    NSRectFill( iconRect );

    // Set current graphics context to use antialiasing and high-quality
    // image scaling.
    graphicsContext = [NSGraphicsContext currentContext];
    wasAntialiasing = [graphicsContext shouldAntialias];
    previousImageInterpolation = [graphicsContext imageInterpolation];
    [graphicsContext setShouldAntialias:YES];
    [graphicsContext setImageInterpolation:imageInterpolation];

    // Composite the working image into the icon bitmap, centered.
    targetRect.origin.x = ((float)iconWidth - newSize.width ) / 2.0;
    targetRect.origin.y = ((float)iconWidth - newSize.height) / 2.0;
    targetRect.size.width = newSize.width;
    targetRect.size.height = newSize.height;
    [workingImageRep drawInRect:targetRect];

    // Restore previous graphics context settings.
    [graphicsContext setShouldAntialias:wasAntialiasing];
    [graphicsContext setImageInterpolation:previousImageInterpolation];

    [newImage unlockFocus];

    [workingImage release];

    // Return the new image!
    return [newImage autorelease];
}

+ (Handle) get32BitDataFromBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep requiredPixelSize:(int)requiredPixelSize
{
    Handle hRawData;
    unsigned char* pRawData;
    Size rawDataSize;
    unsigned char* pSrc;
    unsigned char* pDest;
    int x, y;
    unsigned char alphaByte;
    float oneOverAlpha;

    // Get information about the bitmapImageRep.
    int pixelsWide      = [bitmapImageRep pixelsWide];
    int pixelsHigh      = [bitmapImageRep pixelsHigh];
    int bitsPerSample   = [bitmapImageRep bitsPerSample];
    int samplesPerPixel = [bitmapImageRep samplesPerPixel];
    int bitsPerPixel    = [bitmapImageRep bitsPerPixel];
    BOOL isPlanar       = [bitmapImageRep isPlanar];
    int bytesPerRow     = [bitmapImageRep bytesPerRow];
    unsigned char* bitmapData = [bitmapImageRep bitmapData];

    // Make sure bitmap has the required dimensions.
    if (pixelsWide != requiredPixelSize || pixelsHigh != requiredPixelSize)
	return NULL;

    // So far, this code only handles non-planar 32-bit RGBA and 24-bit RGB source bitmaps.
    // This could be made more flexible with some additional programming to accommodate other possible
    // formats...
    if (isPlanar)
	{
		NSLog(@"get32BitDataFromBitmapImageRep:requiredPixelSize: returning NULL due to isPlanar == YES");
		return NULL;
	}
    if (bitsPerSample != 8)
	{
		NSLog(@"get32BitDataFromBitmapImageRep:requiredPixelSize: returning NULL due to bitsPerSample == %d", bitsPerSample);
		return NULL;
	}

	if (((samplesPerPixel == 3) && (bitsPerPixel == 24)) || ((samplesPerPixel == 4) && (bitsPerPixel == 32)))
	{
		rawDataSize = pixelsWide * pixelsHigh * 4;
		hRawData = NewHandle( rawDataSize );
		if (hRawData == NULL)
			return NULL;
		pRawData = (unsigned char*) *hRawData;

		pSrc = bitmapData;
		pDest = pRawData;

		if (bitsPerPixel == 32) {
			for (y = 0; y < pixelsHigh; y++) {
				pSrc = bitmapData + y * bytesPerRow;
					for (x = 0; x < pixelsWide; x++) {
						// Each pixel is 3 bytes of RGB data, followed by 1 byte of
						// alpha.  The RGB values are premultiplied by the alpha (so
						// that Quartz can save time when compositing the bitmap to a
						// destination), and we undo this premultiplication (with some
						// lossiness unfortunately) when retrieving the bitmap data.
						*pDest++ = alphaByte = *(pSrc+3);
						if (alphaByte) {
							oneOverAlpha = 255.0f / (float)alphaByte;
							*pDest++ = *(pSrc+0) * oneOverAlpha;
							*pDest++ = *(pSrc+1) * oneOverAlpha;
							*pDest++ = *(pSrc+2) * oneOverAlpha;
						} else {
							*pDest++ = 0;
							*pDest++ = 0;
							*pDest++ = 0;
						}
						pSrc+=4;
				}
			}
		} else if (bitsPerPixel == 24) {
			for (y = 0; y < pixelsHigh; y++) {
				pSrc = bitmapData + y * bytesPerRow;
				for (x = 0; x < pixelsWide; x++) {
					*pDest++ = 0xFF;
					*pDest++ = *pSrc++;
					*pDest++ = *pSrc++;
					*pDest++ = *pSrc++;
				}
			}
		}
	}
	else
	{
		NSLog(@"get32BitDataFromBitmapImageRep:requiredPixelSize: returning NULL due to samplesPerPixel == %d, bitsPerPixel == %", samplesPerPixel, bitsPerPixel);
		return NULL;
	}

    return hRawData;
}

+ (Handle) get8BitDataFromBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep requiredPixelSize:(int)requiredPixelSize
{
    Handle hRawData;
    unsigned char* pRawData;
    Size rawDataSize;
    unsigned char* pSrc;
    unsigned char* pDest;
    int x, y;

    // Get information about the bitmapImageRep.
    int pixelsWide      = [bitmapImageRep pixelsWide];
    int pixelsHigh      = [bitmapImageRep pixelsHigh];
    int bitsPerSample   = [bitmapImageRep bitsPerSample];
    int samplesPerPixel = [bitmapImageRep samplesPerPixel];
    int bitsPerPixel    = [bitmapImageRep bitsPerPixel];
    BOOL isPlanar       = [bitmapImageRep isPlanar];
    int bytesPerRow     = [bitmapImageRep bytesPerRow];
    unsigned char* bitmapData = [bitmapImageRep bitmapData];

    // Make sure bitmap has the required dimensions.
    if (pixelsWide != requiredPixelSize || pixelsHigh != requiredPixelSize)
        return NULL;

    // So far, this code only handles non-planar 32-bit RGBA and 24-bit RGB source bitmaps.
    // This could be made more flexible with some additional programming...
    if (isPlanar)
	{
		NSLog(@"get8BitDataFromBitmapImageRep:requiredPixelSize: returning NULL due to isPlanar == YES");
		return NULL;
	}
    if (bitsPerSample != 8)
	{
		NSLog(@"get8BitDataFromBitmapImageRep:requiredPixelSize: returning NULL due to bitsPerSample == %d", bitsPerSample);
		return NULL;
	}

	if (((samplesPerPixel == 3) && (bitsPerPixel == 24)) || ((samplesPerPixel == 4) && (bitsPerPixel == 32)))
	{
		CGDirectPaletteRef cgPal;
		CGDeviceColor cgCol;

		rawDataSize = pixelsWide * pixelsHigh;
		hRawData = NewHandle( rawDataSize );
		if (hRawData == NULL)
			return NULL;
		pRawData = (unsigned char*) *hRawData;

		cgPal = CGPaletteCreateDefaultColorPalette();

		pSrc = bitmapData;
		pDest = pRawData;
		if (bitsPerPixel == 32) {
			for (y = 0; y < pixelsHigh; y++) {
				pSrc = bitmapData + y * bytesPerRow;
				for (x = 0; x < pixelsWide; x++) {
					cgCol.red = ((float)*(pSrc)) / 255;
					cgCol.green = ((float)*(pSrc+1)) / 255;
					cgCol.blue = ((float)*(pSrc+2)) / 255;

					*pDest++ = CGPaletteGetIndexForColor(cgPal, cgCol);

					pSrc+=4;
				}
			}
		} else if (bitsPerPixel == 24) {
			for (y = 0; y < pixelsHigh; y++) {
				pSrc = bitmapData + y * bytesPerRow;
				for (x = 0; x < pixelsWide; x++) {
					cgCol.red = ((float)*(pSrc)) / 255;
					cgCol.green = ((float)*(pSrc+1)) / 255;
					cgCol.blue = ((float)*(pSrc+2)) / 255;

					*pDest++ = CGPaletteGetIndexForColor(cgPal, cgCol);

					pSrc+=3;
				}
			}
		}

		CGPaletteRelease(cgPal);
	}
	else
	{
		NSLog(@"get8BitDataFromBitmapImageRep:requiredPixelSize: returning NULL due to samplesPerPixel == %d, bitsPerPixel == %", samplesPerPixel, bitsPerPixel);
		return NULL;
	}

    return hRawData;
}

+ (Handle) get8BitMaskFromBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep requiredPixelSize:(int)requiredPixelSize
{
    Handle hRawData;
    unsigned char* pRawData;
    Size rawDataSize;
    unsigned char* pSrc;
    unsigned char* pDest;
    int x, y;

    // Get information about the bitmapImageRep.
    int pixelsWide      = [bitmapImageRep pixelsWide];
    int pixelsHigh      = [bitmapImageRep pixelsHigh];
    int bitsPerSample   = [bitmapImageRep bitsPerSample];
    int samplesPerPixel = [bitmapImageRep samplesPerPixel];
    int bitsPerPixel    = [bitmapImageRep bitsPerPixel];
    BOOL isPlanar       = [bitmapImageRep isPlanar];
    int bytesPerRow     = [bitmapImageRep bytesPerRow];
    unsigned char* bitmapData = [bitmapImageRep bitmapData];

    // Make sure bitmap has the required dimensions.
    if (pixelsWide != requiredPixelSize || pixelsHigh != requiredPixelSize)
		return NULL;

    // So far, this code only handles non-planar 32-bit RGBA, 24-bit RGB and 8-bit grayscale source bitmaps.
    // This could be made more flexible with some additional programming...
    if (isPlanar)
	{
		NSLog(@"get8BitMaskFromBitmapImageRep:requiredPixelSize: returning NULL due to isPlanar == YES");
		return NULL;
	}
    if (bitsPerSample != 8)
	{
		NSLog(@"get8BitMaskFromBitmapImageRep:requiredPixelSize: returning NULL due to bitsPerSample == %d", bitsPerSample);
		return NULL;
	}

	if (((samplesPerPixel == 1) && (bitsPerPixel == 8)) || ((samplesPerPixel == 3) && (bitsPerPixel == 24)) || ((samplesPerPixel == 4) && (bitsPerPixel == 32)))
	{
		rawDataSize = pixelsWide * pixelsHigh;
		hRawData = NewHandle( rawDataSize );
		if (hRawData == NULL)
			return NULL;
		pRawData = (unsigned char*) *hRawData;

		pSrc = bitmapData;
		pDest = pRawData;

		if (bitsPerPixel == 32) {
			for (y = 0; y < pixelsHigh; y++) {
				pSrc = bitmapData + y * bytesPerRow;
				for (x = 0; x < pixelsWide; x++) {
					pSrc += 3;
					*pDest++ = *pSrc++;
				}
			}
		}
		else if (bitsPerPixel == 24) {
			memset( pDest, 255, rawDataSize );
		}
		else if (bitsPerPixel == 8) {
			for (y = 0; y < pixelsHigh; y++) {
				memcpy( pDest, pSrc, pixelsWide );
				pSrc += bytesPerRow;
				pDest += pixelsWide;
			}
		}
	}
	else
	{
		NSLog(@"get8BitMaskFromBitmapImageRep:requiredPixelSize: returning NULL due to samplesPerPixel == %d, bitsPerPixel == %", samplesPerPixel, bitsPerPixel);
		return NULL;
	}

    return hRawData;
}

// NOTE: This method hasn't been fully tested yet.
+ (Handle) get1BitMaskFromBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep requiredPixelSize:(int)requiredPixelSize
{
    Handle hRawData;
    unsigned char* pRawData;
    Size rawDataSize;
    unsigned char* pSrc;
    unsigned char* pDest;
    int x, y;
    unsigned char maskByte;

    // Get information about the bitmapImageRep.
    int pixelsWide      = [bitmapImageRep pixelsWide];
    int pixelsHigh      = [bitmapImageRep pixelsHigh];
    int bitsPerSample   = [bitmapImageRep bitsPerSample];
    int samplesPerPixel = [bitmapImageRep samplesPerPixel];
    int bitsPerPixel    = [bitmapImageRep bitsPerPixel];
    BOOL isPlanar       = [bitmapImageRep isPlanar];
    int bytesPerRow     = [bitmapImageRep bytesPerRow];
    unsigned char* bitmapData = [bitmapImageRep bitmapData];

    // Make sure bitmap has the required dimensions.
    if (pixelsWide != requiredPixelSize || pixelsHigh != requiredPixelSize)
		return NULL;

    // So far, this code only handles non-planar 32-bit RGBA, 24-bit RGB, 8-bit grayscale, and 1-bit source bitmaps.
    // This could be made more flexible with some additional programming...
    if (isPlanar)
	{
		NSLog(@"get1BitMaskFromBitmapImageRep:requiredPixelSize: returning NULL due to isPlanar == YES");
		return NULL;
	}

	if (((bitsPerPixel == 1) && (samplesPerPixel == 1) && (bitsPerSample == 1)) || ((bitsPerPixel == 8) && (samplesPerPixel == 1) && (bitsPerSample == 8)) ||
		((bitsPerPixel == 24) && (samplesPerPixel == 3) && (bitsPerSample == 8)) || ((bitsPerPixel == 32) && (samplesPerPixel == 4) && (bitsPerSample == 8)))
	{
		rawDataSize = (pixelsWide * pixelsHigh)/4;
		hRawData = NewHandle( rawDataSize );
		if (hRawData == NULL)
			return NULL;
		pRawData = (unsigned char*) *hRawData;

		pSrc = bitmapData;
		pDest = pRawData;

		if (bitsPerPixel == 32) {
			for (y = 0; y < pixelsHigh; y++) {
				pSrc = bitmapData + y * bytesPerRow;
				for (x = 0; x < pixelsWide; x += 8) {
					maskByte = 0;
					maskByte |= (*(unsigned*)pSrc & 0xff) ? 0x80 : 0; pSrc += 4;
					maskByte |= (*(unsigned*)pSrc & 0xff) ? 0x40 : 0; pSrc += 4;
					maskByte |= (*(unsigned*)pSrc & 0xff) ? 0x20 : 0; pSrc += 4;
					maskByte |= (*(unsigned*)pSrc & 0xff) ? 0x10 : 0; pSrc += 4;
					maskByte |= (*(unsigned*)pSrc & 0xff) ? 0x08 : 0; pSrc += 4;
					maskByte |= (*(unsigned*)pSrc & 0xff) ? 0x04 : 0; pSrc += 4;
					maskByte |= (*(unsigned*)pSrc & 0xff) ? 0x02 : 0; pSrc += 4;
					maskByte |= (*(unsigned*)pSrc & 0xff) ? 0x01 : 0; pSrc += 4;
					*pDest++ = maskByte;
				}
			}
		}
		else if (bitsPerPixel == 24) {
			memset( pDest, 255, rawDataSize );
		}
		else if (bitsPerPixel == 8) {
			for (y = 0; y < pixelsHigh; y++) {
				pSrc = bitmapData + y * bytesPerRow;
				for (x = 0; x < pixelsWide; x += 8) {
					maskByte = 0;
					maskByte |= *pSrc++ ? 0x80 : 0;
					maskByte |= *pSrc++ ? 0x40 : 0;
					maskByte |= *pSrc++ ? 0x20 : 0;
					maskByte |= *pSrc++ ? 0x10 : 0;
					maskByte |= *pSrc++ ? 0x08 : 0;
					maskByte |= *pSrc++ ? 0x04 : 0;
					maskByte |= *pSrc++ ? 0x02 : 0;
					maskByte |= *pSrc++ ? 0x01 : 0;
					*pDest++ = maskByte;
				}
			}
		}
		else if (bitsPerPixel == 1) {
			for (y = 0; y < pixelsHigh; y++) {
				memcpy( pDest, pSrc, pixelsWide / 8 );
				pDest += pixelsWide / 8;
				pSrc += bytesPerRow;
			}
		}

		memcpy( pRawData+(pixelsWide*pixelsHigh)/8, pRawData, (pixelsWide*pixelsHigh)/8 );
	}
	else
	{
		NSLog(@"get1BitMaskFromBitmapImageRep:requiredPixelSize: returning NULL due to bitsPerPixel == %d, samplesPerPixel== %d, bitsPerSample == %d", bitsPerPixel, samplesPerPixel, bitsPerSample);
		return NULL;
	}

    return hRawData;
}

- (BOOL) addResourceType:(OSType)type asResID:(int)resID
{
    Handle hIconRes = NewHandle(0);
    OSErr err;

    err = GetIconFamilyData( hIconFamily, type, hIconRes );

    if( !GetHandleSize(hIconRes) || err != noErr )
        return NO;

    AddResource( hIconRes, type, resID, "\p" );

    return YES;
}

@end

#if MAC_OS_X_VERSION_MAX_ALLOWED <= 1050  // Scrap Manager has been nixed on Snow Leopard
// Methods for interfacing with the Carbon Scrap Manager (analogous to and
// interoperable with the Cocoa Pasteboard).

@implementation IconFamily (ScrapAdditions)

+ (BOOL) canInitWithScrap
{
    ScrapRef scrap = NULL;
    ScrapFlavorInfo* scrapInfos = NULL;
    UInt32 numInfos = 0;
    int i = 0;
    BOOL canInit = NO;

    GetCurrentScrap(&scrap);

    GetScrapFlavorCount(scrap,&numInfos);
    scrapInfos = malloc( sizeof(ScrapFlavorInfo)*numInfos );
    if (scrapInfos) {
      GetScrapFlavorInfoList(scrap, &numInfos, scrapInfos);

      for( i=0; i<numInfos; i++ )
      {
          if( scrapInfos[i].flavorType == 'icns' )
              canInit = YES;
      }

      free( scrapInfos );
    }

    return canInit;
}

+ (IconFamily*) iconFamilyWithScrap
{
    return [[[IconFamily alloc] initWithScrap] autorelease];
}

- initWithScrap
{
    Handle storageMem = NULL;
    Size amountMem = 0;
    ScrapRef scrap;

    self = [super init];

    if( self )
    {
        GetCurrentScrap(&scrap);

        GetScrapFlavorSize( scrap, 'icns', &amountMem );

        storageMem = NewHandle(amountMem);

        GetScrapFlavorData( scrap, 'icns', &amountMem, *storageMem );

        hIconFamily = (IconFamilyHandle)storageMem;
    }
    return self;
}

- (BOOL) putOnScrap
{
    ScrapRef scrap = NULL;

    ClearCurrentScrap();
    GetCurrentScrap(&scrap);

//    HLock((Handle)hIconFamily); // Handle-based memory isn't compacted anymore, so calling HLock()/HUnlock() is unnecessary.
    PutScrapFlavor( scrap, 'icns', kScrapFlavorMaskNone, GetHandleSize((Handle)hIconFamily), *hIconFamily);
//    HUnlock((Handle)hIconFamily); // Handle-based memory isn't compacted anymore, so calling HLock()/HUnlock() is unnecessary.
    return YES;
}

@end

#endif
