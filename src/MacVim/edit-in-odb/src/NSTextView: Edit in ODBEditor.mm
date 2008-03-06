//
//  NSTextView: Edit in ODBEditor.mm
//
//  Created by Allan Odgaard on 2005-11-27.
//  See LICENSE for license details
//
//  Generalized by Chris Eidhof and Eelco Lempsink from 'NSTextView: Edit in TextMate.mm'

#import "Edit in ODBEditor.h"

@interface NSTextView (EditInODBEditor)
- (void)editInODBEditor:(id)sender;
@end

@implementation NSTextView (EditInODBEditor)
- (void)editInODBEditor:(id)sender
{
	if(![self isEditable])
		return (void)NSBeep();

	NSString* str = [[self textStorage] string];
	NSRange selectedRange = [self selectedRange];
	int lineNumber = 0;
	if(selectedRange.length == 0)
	{
		NSRange range = NSMakeRange(0, 0);
		do {
			NSRange oldRange = range;
			range = [str lineRangeForRange:NSMakeRange(NSMaxRange(range), 0)];
			if(NSMaxRange(oldRange) == NSMaxRange(range) || selectedRange.location < NSMaxRange(range))
				break;
			lineNumber++;
		} while(true);
		selectedRange = NSMakeRange(0, [str length]);
	}

	[EditInODBEditor externalEditString:[str substringWithRange:selectedRange] startingAtLine:lineNumber forView:self];
}

- (void)odbEditorDidModifyString:(NSString*)newString
{
	NSRange selectedRange = [self selectedRange];
	BOOL hadSelection = selectedRange.length != 0;
	selectedRange = hadSelection ? selectedRange : NSMakeRange(0, [[self textStorage] length]);
	if([self shouldChangeTextInRange:selectedRange replacementString:newString])
	{
		if(!hadSelection)
			[self setSelectedRange:NSMakeRange(0, [[self textStorage] length])];
		[self insertText:newString];
		if(hadSelection)
			[self setSelectedRange:NSMakeRange(selectedRange.location, [newString length])];
		[self didChangeText];
	}
	else
	{
		NSBeep();
		NSLog(@"%s couldn't edit text", _cmd);
	}
}
@end
