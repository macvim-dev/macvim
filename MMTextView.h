/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import <Cocoa/Cocoa.h>


@interface MMTextView : NSTextView {
    BOOL    ownsTextStorage;
    int     tabpageIdx;
    NSPort  *sendPort;
    BOOL    shouldDrawInsertionPoint;
}

- (id)initWithPort:(NSPort *)port frame:(NSRect)frame
     textContainer:(NSTextContainer *)tc;
- (MMTextView *)initWithFrame:(NSRect)frame port:(NSPort *)port;
- (void)setShouldDrawInsertionPoint:(BOOL)enable;

@end

// vim: set ft=objc :
