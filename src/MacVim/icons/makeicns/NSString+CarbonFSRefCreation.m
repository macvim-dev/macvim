/*
    Copyright (c) 2001-2006 Troy N. Stephens

    Use and distribution of this source code is governed by the MIT License, whose terms are as follows.

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#import "NSString+CarbonFSRefCreation.h"

@implementation NSString (CarbonFSRefCreation)

- (BOOL) getFSRef:(FSRef*)fsRef createFileIfNecessary:(BOOL)createFile
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    CFURLRef urlRef;
    Boolean gotFSRef;

    // Check whether the file exists already.  If not, create an empty file if requested.
    if (![fileManager fileExistsAtPath:self]) {
        if (createFile) {
            if (![@"" writeToFile:self atomically:YES]) {
                return NO;
            }
        } else {
            return NO;
        }
    }

    // Create a CFURL with the specified POSIX path.
    urlRef = CFURLCreateWithFileSystemPath( kCFAllocatorDefault,
                                            (CFStringRef) self,
                                            kCFURLPOSIXPathStyle,
                                            FALSE /* isDirectory */ );
    if (urlRef == NULL) {
//        printf( "** Couldn't make a CFURLRef for the file.\n" );
        return NO;
    }

    // Try to create an FSRef from the URL.  (If the specified file doesn't exist, this
    // function will return false, but if we've reached this code we've already insured
    // that the file exists.)
    gotFSRef = CFURLGetFSRef( urlRef, fsRef );
    CFRelease( urlRef );

    if (!gotFSRef) {
//        printf( "** Couldn't get an FSRef for the file.\n" );
        return NO;
    }

    return YES;
}

@end
