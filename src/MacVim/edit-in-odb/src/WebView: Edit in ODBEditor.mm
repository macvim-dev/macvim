//
//  WebView: Edit in ODBEditor.mm
//
//  Created by Allan Odgaard on 2005-11-27.
//  See LICENSE for license details
//
//  Generalized by Chris Eidhof and Eelco Lempsink from 'WebView: Edit in TextMate.mm'


#import <WebKit/WebKit.h>
#import <vector>
#import "Edit in ODBEditor.h"

#ifndef sizeofA
#define sizeofA(x) (sizeof(x)/sizeof(x[0]))
#endif

// only latest WebKit has this stuff, and it is private
@interface DOMHTMLTextAreaElement (DOMHTMLTextAreaElementPrivate)
- (int)selectionStart;
- (void)setSelectionStart:(int)newSelectionStart;
- (int)selectionEnd;
- (void)setSelectionEnd:(int)newSelectionEnd;
- (void)setSelectionRange:(int)start end:(int)end;
@end

@interface WebView (EditInODBEditor)
- (void)editInODBEditor:(id)sender;
@end

@interface NSString (EditInODBEditor)
- (NSString*)ODB_stringByTrimmingWhitespace;
- (NSString*)ODB_stringByReplacingString:(NSString*)aSearchString withString:(NSString*)aReplaceString;
- (NSString*)ODB_stringByNbspEscapingSpaces;
@end

@implementation NSString (EditInODBEditor)
- (NSString*)ODB_stringByTrimmingWhitespace
{
	NSString* str = self;
	while([str hasPrefix:@" "])
		str = [str substringFromIndex:1];

	while([str hasSuffix:@"  "])
		str = [str substringToIndex:[str length]-1];
	return str;
}

- (NSString*)ODB_stringByReplacingString:(NSString*)aSearchString withString:(NSString*)aReplaceString
{
	return [[self componentsSeparatedByString:aSearchString] componentsJoinedByString:aReplaceString];
}

- (NSString*)ODB_stringByNbspEscapingSpaces
{
	unsigned len = [self length];
	unichar* buf = new unichar[len];
	[self getCharacters:buf];
	for(unsigned i = 0; i != len; i++)
	{
		if(buf[i] == ' ' && (i+1 == len || buf[i+1] == ' '))
			buf[i] = 0xA0;
	}
	return [NSString stringWithCharacters:buf length:len];
}
@end

struct convert_dom_to_text
{
	convert_dom_to_text (DOMTreeWalker* treeWalker) : string([NSMutableString new]), quoteLevel(0), pendingFlush(NO), pendingWhitespace(NO), didOutputText(NO), atBeginOfLine(YES) { visit_nodes(treeWalker); }
	~convert_dom_to_text () { [string autorelease]; }
	operator NSString* () const { return string; }

private:
	void enter_block_tag ()
	{
		pendingFlush |= didOutputText;
		didOutputText = NO;
		pendingWhitespace = NO;
	}

	void leave_block_tag ()
	{
		pendingFlush |= didOutputText;
		didOutputText = NO;
		pendingWhitespace = NO;
	}

	void output_text (NSString* str)
	{
		if([str isEqualToString:@""])
			return;

		str = [str ODB_stringByTrimmingWhitespace];
		if([str isEqualToString:@""])
		{
			pendingWhitespace = YES;
			return;
		}

		str = [str ODB_stringByReplacingString:[NSString stringWithUTF8String:" "] withString:@" "];

		if(pendingFlush)
		{
			[string appendString:@"\n"];
			pendingFlush = NO;
			atBeginOfLine = YES;
		}

		if(atBeginOfLine && quoteLevel)
		{
			for(unsigned i = 0; i < quoteLevel; i++)
				[string appendString:@"> "];
		}
		else if(!atBeginOfLine && pendingWhitespace)
		{
			[string appendString:@" "];
		}

		[string appendString:str];
		atBeginOfLine = NO;
		didOutputText = YES;
		pendingWhitespace = NO;
	}

	void visit_nodes (DOMTreeWalker* treeWalker);

	NSMutableString* string;
	unsigned quoteLevel;
	BOOL pendingFlush;
	BOOL pendingWhitespace;
	BOOL didOutputText;
	BOOL atBeginOfLine;
};

struct helper
{
	helper (DOMHTMLTextAreaElement* textArea) : textArea(textArea)
	{
		value = [textArea value];
		selectionStart = [textArea selectionStart];
		selectionEnd = [textArea selectionEnd];
	}

	helper () : textArea(nil), value(nil)		{ }
	bool should_change () const					{ return selectionStart != 0 || selectionEnd != [value length]; }
	bool did_change () const						{ return selectionStart != [textArea selectionStart] || selectionEnd != [textArea selectionEnd]; }
	void reset () const
	{ 
		if([textArea value] != value) [textArea setValue:value];
		if(did_change()) [textArea setSelectionRange:selectionStart end:selectionEnd];
	}

	static bool usable (DOMNode* node)
	{
		static SEL const selectors[] = { @selector(selectionStart), @selector(selectionEnd), @selector(setSelectionStart:), @selector(setSelectionEnd:), @selector(value), @selector(setValue:), @selector(setSelectionRange:end:) };
		BOOL res = [node isKindOfClass:[DOMHTMLTextAreaElement class]] && ![(DOMHTMLTextAreaElement*)node disabled] && ![(DOMHTMLTextAreaElement*)node readOnly];
		for(size_t i = 0; i < sizeofA(selectors); ++i)
			res = res && [node respondsToSelector:selectors[i]];
		return res;
	}

	DOMHTMLTextAreaElement* textArea;
	NSString* value;
	unsigned long selectionStart;
	unsigned long selectionEnd;
};

void convert_dom_to_text::visit_nodes (DOMTreeWalker* treeWalker)
{
	for(DOMNode* node = [treeWalker currentNode]; node; node = [treeWalker nextSibling])
	{
		if([node nodeType] == DOM_TEXT_NODE)
			output_text([node nodeValue]);
		else if([[[node nodeName] uppercaseString] isEqualToString:@"BR"])
			output_text(@"\n"), (atBeginOfLine = YES), (didOutputText = NO);
		else if([[[node nodeName] uppercaseString] isEqualToString:@"DIV"])
			enter_block_tag();
		else if([[[node nodeName] uppercaseString] isEqualToString:@"BLOCKQUOTE"])
			enter_block_tag(), ++quoteLevel;
		else if([[[node nodeName] uppercaseString] isEqualToString:@"P"])
			enter_block_tag();

		if([treeWalker firstChild])
		{
			visit_nodes(treeWalker);
			[treeWalker parentNode];
		}

		if([[[node nodeName] uppercaseString] isEqualToString:@"DIV"])
			leave_block_tag();
		else if([[[node nodeName] uppercaseString] isEqualToString:@"BLOCKQUOTE"])
			leave_block_tag(), --quoteLevel;
		else if([[[node nodeName] uppercaseString] isEqualToString:@"P"])
			leave_block_tag();
	}
}

static DOMHTMLTextAreaElement* find_active_text_area_for_frame (WebFrame* frame)
{
	DOMHTMLTextAreaElement* res = nil;
	DOMDocument* doc = [frame DOMDocument];
	if([doc respondsToSelector:@selector(focusNode)])
	{
		// OmniWeb 5.6 has a method to get the focused node
		res = [doc performSelector:@selector(focusNode)];
		if(!helper::usable(res))
			res = nil;
	}
	else
	{
		// The following is a heuristic for finding the active text area:
		// 
		//  1. If there is just one text area, we use that.
		// 
		//  2. If there are multiple, we ask the web view to “select all”
		//     which goes to the active text area (hopefully) and then we
		//     check which of the text areas in the DOM actually changed.
		// 
		//     There is a problem if either a text area has no content (in
		//     which case select all makes no changes) or if everything is
		//     already selected. If only one text area is in the state of
		//     “select all would not affect it” and no text areas were
		//     changed, we assume the one with that state is the active.

		std::vector<helper> v;
		DOMNodeList* textAreas = [doc getElementsByTagName:@"TEXTAREA"];
		for(unsigned long i = 0; i < [textAreas length]; ++i)
		{
			if(helper::usable([textAreas item:i]))
				v.push_back((DOMHTMLTextAreaElement*)[textAreas item:i]);
		}

		if(v.size() == 1)
		{
			res = v[0].textArea;
		}
		else if(v.size() > 1)
		{
			for(std::vector<helper>::iterator it = v.begin(); it != v.end(); ++it)
				if (!it->should_change())
					[it->textArea setValue:@" "];
			[[frame webView] selectLine:nil];

			size_t should_change = 0, did_change = 0;
			for(std::vector<helper>::iterator it = v.begin(); it != v.end(); ++it)
			{
				did_change    += it->did_change()    ? 1 : 0;
				should_change += it->should_change() ? 1 : 0;
			}

			if(did_change == 1)
			{
				for(std::vector<helper>::iterator it = v.begin(); it != v.end(); ++it)
					res = it->did_change() ? it->textArea : res;
			}
			else if(did_change == 0 && should_change == v.size()-1)
			{
				for(std::vector<helper>::iterator it = v.begin(); it != v.end(); ++it)
					res = !it->should_change() ? it->textArea : res;
			}

			for(std::vector<helper>::iterator it = v.begin(); it != v.end(); ++it)
				it->reset();
		}
	}
	return res;
}

static DOMHTMLTextAreaElement* find_active_text_area (WebView* view)
{
	DOMHTMLTextAreaElement* res = nil;
	if([view respondsToSelector:@selector(selectedFrame)])
		res = find_active_text_area_for_frame([view performSelector:@selector(selectedFrame)]);
	else
	{
		WebFrame* frame = [view mainFrame];
		NSArray* frames = [[NSArray arrayWithObject: frame] arrayByAddingObjectsFromArray: [frame childFrames]];
		for(unsigned i = 0; i != [frames count] && !res; i++)
			res = find_active_text_area_for_frame([frames objectAtIndex:i]);
	}
	return res;
}

@implementation WebView (EditInODBEditor)
- (void)editInODBEditor:(id)sender
{
	if([self isEditable])
	{
		// Mail uses an editable WebView, in which case we want to send the entire page to the ODB Editor

		NSString* const CARET = [NSString stringWithFormat:@"%C", 0xFFFD];
		NSString* str = @"";
		int lineNumber = 0;

		DOMDocumentFragment* selection = [[self selectedDOMRange] cloneContents];
		if(!selection)
		{
			[self insertText:CARET]; // ugly hack, but we want to preserve the position of the caret
			[self selectAll:nil];
			selection = [[self selectedDOMRange] cloneContents];

			// remove the caret marker. TODO we should start an undo group, so the (chunked) undo doesn’t remove more than just the caret
			if(NSUndoManager* undoManager = [self undoManager])
			{
				if([undoManager canUndo])
				{
					[undoManager undo];
					[self selectAll:nil];
				}
			}
		}

		if(selection)
		{
			str = convert_dom_to_text([[[self mainFrame] DOMDocument] createTreeWalker:selection :DOM_SHOW_ALL :nil :YES]);
			while([str hasSuffix:@"\n\n"])
				str = [str substringToIndex:[str length]-1];

			NSArray* split = [str componentsSeparatedByString:CARET];
			if([split count] == 2)
			{
				lineNumber = [[[split objectAtIndex:0] componentsSeparatedByString:@"\n"] count] - 1;
				str = [split componentsJoinedByString:@""];
			}
		}
		[EditInODBEditor externalEditString:str startingAtLine:lineNumber forView:self];
	}
	else
	{
		// Likely the user wants to edit just a text area, so let’s try to find which
		if(DOMHTMLTextAreaElement* textArea = find_active_text_area(self))
			{
				NSString* str = [textArea value];
				unsigned long selectionStart = [textArea selectionStart];
				int lineNumber = 0;
				NSRange range = NSMakeRange(0, 0);
				do {
					NSRange oldRange = range;
					range = [str lineRangeForRange:NSMakeRange(NSMaxRange(range), 0)];
					if(NSMaxRange(oldRange) == NSMaxRange(range) || selectionStart < NSMaxRange(range))
						break;
					lineNumber++;
				} while(true);
				[EditInODBEditor externalEditString:str startingAtLine:lineNumber forView:self withObject:textArea];
			}
		else	NSBeep();
	}
}

- (void)odbEditorDidModifyString:(NSString*)newString withObject:(NSObject*)textArea
{
	if([self isEditable])
	{
		NSArray* lines = [newString componentsSeparatedByString:@"\n"];
		NSMutableString* res = [NSMutableString string];
		unsigned quoteLevel = 0;
		for(unsigned i = 0; i != [lines count]; i++)
		{
			NSString* line = [lines objectAtIndex:i];

			unsigned newQuoteLevel = 0;
			while([line hasPrefix:@"> "])
			{
				line = [line substringFromIndex:2];
				newQuoteLevel++;
			}

			if([line isEqualToString:@">"])
			{
				line = @"";
				newQuoteLevel++;
			}

			if(newQuoteLevel > quoteLevel)
			{
				for(unsigned j = 0; j != newQuoteLevel - quoteLevel; j++)
					[res appendString:@"<BLOCKQUOTE type=\"cite\">"];
			}
			else if(newQuoteLevel < quoteLevel)
			{
				for(unsigned j = 0; j != quoteLevel - newQuoteLevel; j++)
					[res appendString:@"</BLOCKQUOTE>"];
			}
			quoteLevel = newQuoteLevel;

			if([line isEqualToString:@""])
			{
				[res appendString:@"<DIV><BR></DIV>"];
			}
			else
			{
				line = [line ODB_stringByNbspEscapingSpaces];
				line = [line ODB_stringByReplacingString:@"&" withString:@"&amp;"];
				line = [line ODB_stringByReplacingString:@"<" withString:@"&lt;"];
				line = [line ODB_stringByReplacingString:@">" withString:@"&gt;"];
				[res appendFormat:@"<DIV>%@</DIV>", line];
			}
		}

		[self replaceSelectionWithMarkupString:res];
		if(![[self selectedDOMRange] cloneContents])
			[self selectAll:nil];
	}
	else
	{
		[(DOMHTMLTextAreaElement*)textArea setValue:newString];
	}
}
@end
