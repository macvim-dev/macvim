//
//  Edit in ODBEditor.mm
//
//  Created by Allan Odgaard on 2005-11-26.
//  See LICENSE for license details
//
//  Generalized by Chris Eidhof and Eelco Lempsink from 'Edit in TextMate.mm'

#import <WebKit/WebKit.h>
#import <Carbon/Carbon.h>
#import <map>
#import "Edit in ODBEditor.h"

// from ODBEditorSuite.h
#define keyFileSender   'FSnd'
#define kODBEditorSuite 'R*ch'
#define kAEModifiedFile 'FMod'
#define kAEClosedFile   'FCls'

static NSMutableDictionary* OpenFiles;
static NSMutableSet* FailedFiles;
static NSString* ODBEditorBundleIdentifier;
static NSString* ODBEditorName;

#pragma options align=mac68k
struct PBX_SelectionRange
{
	short unused1;		// 0 (not used)
	short lineNum;		// line to select (<0 to specify range)
	long startRange;	// start of selection range (if line < 0)
	long endRange;		// end of selection range (if line < 0)
	long unused2;		// 0 (not used)
	long theDate;		// modification date/time
};
#pragma options align=reset

@implementation EditInODBEditor
+ (void)setODBEventHandlers
{
	NSAppleEventManager* eventManager = [NSAppleEventManager sharedAppleEventManager];
	[eventManager setEventHandler:self andSelector:@selector(handleModifiedFileEvent:withReplyEvent:) forEventClass:kODBEditorSuite andEventID:kAEModifiedFile];
	[eventManager setEventHandler:self andSelector:@selector(handleClosedFileEvent:withReplyEvent:) forEventClass:kODBEditorSuite andEventID:kAEClosedFile];
}

+ (void)removeODBEventHandlers
{
	NSAppleEventManager* eventManager = [NSAppleEventManager sharedAppleEventManager];
	[eventManager removeEventHandlerForEventClass:kODBEditorSuite andEventID:kAEModifiedFile];
	[eventManager removeEventHandlerForEventClass:kODBEditorSuite andEventID:kAEClosedFile];
}

+ (BOOL)launchODBEditor
{
	NSArray* array = [[NSWorkspace sharedWorkspace] launchedApplications];
	for(unsigned i = [array count]; --i; )
	{
		if([[[array objectAtIndex:i] objectForKey:@"NSApplicationBundleIdentifier"] isEqualToString:ODBEditorBundleIdentifier])
			return YES;
	}
	return [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:ODBEditorBundleIdentifier options:0L additionalEventParamDescriptor:nil launchIdentifier:nil];
}

+ (void)asyncEditStringWithOptions:(NSDictionary*)someOptions
{
	NSAutoreleasePool* pool = [NSAutoreleasePool new];

	if(![self launchODBEditor])
		return;

	/* =========== */

	NSData* targetBundleID = [ODBEditorBundleIdentifier dataUsingEncoding:NSUTF8StringEncoding];
	NSAppleEventDescriptor* targetDescriptor = [NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID data:targetBundleID];
	NSAppleEventDescriptor* appleEvent = [NSAppleEventDescriptor appleEventWithEventClass:kCoreEventClass eventID:kAEOpenDocuments targetDescriptor:targetDescriptor returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
	NSAppleEventDescriptor* replyDescriptor = nil;
	NSAppleEventDescriptor* errorDescriptor = nil;
	AEDesc reply = { typeNull, NULL };														

	NSString* fileName = [someOptions objectForKey:@"fileName"];
	[appleEvent setParamDescriptor:[NSAppleEventDescriptor descriptorWithDescriptorType:typeFileURL data:[[[NSURL fileURLWithPath:fileName] absoluteString] dataUsingEncoding:NSUTF8StringEncoding]] forKeyword:keyDirectObject];

	UInt32 packageType = 0, packageCreator = 0;
	CFBundleGetPackageInfo(CFBundleGetMainBundle(), &packageType, &packageCreator);
	[appleEvent setParamDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:packageCreator] forKeyword:keyFileSender];

	if(int line = [[someOptions objectForKey:@"line"] intValue])
	{
		PBX_SelectionRange pos = { };
		pos.lineNum = line;
		[appleEvent setParamDescriptor:[NSAppleEventDescriptor descriptorWithDescriptorType:typeChar bytes:&pos length:sizeof(pos)] forKeyword:keyAEPosition];
	}

	OSStatus status = AESend([appleEvent aeDesc], &reply, kAEWaitReply, kAENormalPriority, kAEDefaultTimeout, NULL, NULL);
	if(status == noErr)
	{
		replyDescriptor = [[[NSAppleEventDescriptor alloc] initWithAEDescNoCopy:&reply] autorelease];
		errorDescriptor = [replyDescriptor paramDescriptorForKeyword:keyErrorNumber];
		if(errorDescriptor != nil)
			status = [errorDescriptor int32Value];
		
		if(status != noErr)
			NSLog(@"%s error %d", _cmd, status), NSBeep();
	}

	[pool release];
}

+ (NSString*)extensionForURL:(NSURL*)anURL
{
	NSString* res = nil;
	if(NSString* urlString = [anURL absoluteString])
	{
		NSString* path = [[NSBundle bundleForClass:[self class]] pathForResource:@"url map" ofType:@"plist"];
		NSMutableDictionary* map = [NSMutableDictionary dictionaryWithContentsOfFile:path];

		NSString* customBindingsPath = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"Preferences/org.slashpunt.edit_in_odbeditor.plist"];
		if(NSDictionary* associations = [[NSDictionary dictionaryWithContentsOfFile:customBindingsPath] objectForKey:@"URLAssociations"])
			[map addEntriesFromDictionary:associations];

		unsigned longestMatch = 0;
		NSEnumerator* enumerator = [map keyEnumerator];
		while(NSString* key = [enumerator nextObject])
		{
			if([urlString rangeOfString:key].location != NSNotFound && [key length] > longestMatch)
			{
				res = [map objectForKey:key];
				longestMatch = [key length];
			}
		}
	}
	return res;
}

+ (void)externalEditString:(NSString*)aString startingAtLine:(int)aLine forView:(NSView*)aView
{
	[self externalEditString:aString startingAtLine:aLine forView:aView withObject:nil];
}

+ (void)externalEditString:(NSString*)aString startingAtLine:(int)aLine forView:(NSView*)aView withObject:(NSObject*)anObject
{
	Class cl = NSClassFromString(@"WebFrameView");

	NSURL* url = nil;
	for(NSView* view = aView; view && !url && cl; view = [view superview])
	{
		if([view isKindOfClass:cl])
			url = [[[[(WebFrameView*)view webFrame] dataSource] mainResource] URL];
	}

	NSString* basename = [[[[aView window] title] componentsSeparatedByString:@"/"] componentsJoinedByString:@"-"] ?: @"untitled";
	NSString* extension = [self extensionForURL:url] ?: [[[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"] lowercaseString];
	NSString* fileName = [NSString stringWithFormat:@"%@/%@.%@", NSTemporaryDirectory(), basename, extension];
	for(unsigned i = 2; [[NSFileManager defaultManager] fileExistsAtPath:fileName]; i++)
		fileName = [NSString stringWithFormat:@"%@/%@ %u.%@", NSTemporaryDirectory(), basename, i, extension];

	[[aString dataUsingEncoding:NSUTF8StringEncoding] writeToFile:fileName atomically:NO];
	fileName = [fileName stringByStandardizingPath];

	NSDictionary* options = [NSDictionary dictionaryWithObjectsAndKeys:
		aString,                         @"string",
		aView,                           @"view",
		fileName,                        @"fileName",
		[NSNumber numberWithInt:aLine],  @"line",
		anObject,                        @"object", /* last since anObject might be nil */
		nil];

	[OpenFiles setObject:options forKey:[fileName precomposedStringWithCanonicalMapping]];
	if([OpenFiles count] == 1)
		[self setODBEventHandlers];
	[NSThread detachNewThreadSelector:@selector(asyncEditStringWithOptions:) toTarget:self withObject:options];
}

+ (void)handleModifiedFileEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
	NSAppleEventDescriptor* fileURL = [[event paramDescriptorForKeyword:keyDirectObject] coerceToDescriptorType:typeFileURL];
	NSString* urlString = [[[NSString alloc] initWithData:[fileURL data] encoding:NSUTF8StringEncoding] autorelease];
	NSString* fileName = [[[NSURL URLWithString:urlString] path] stringByStandardizingPath];
	NSDictionary* options = [OpenFiles objectForKey:[fileName precomposedStringWithCanonicalMapping]];
	NSView* view = [options objectForKey:@"view"];

	if([view window])
	{
		if ([view respondsToSelector:@selector(odbEditorDidModifyString:withObject:)])
		{
			NSString* newString = [[[NSString alloc] initWithData:[NSData dataWithContentsOfFile:fileName] encoding:NSUTF8StringEncoding] autorelease];
			NSObject* anObject = [options objectForKey:@"object"];
			[view performSelector:@selector(odbEditorDidModifyString:withObject:) withObject:newString withObject:anObject];
			[FailedFiles removeObject:fileName];
			fileName = nil;
		}
		else if([view respondsToSelector:@selector(odbEditorDidModifyString:)])
		{
			NSString* newString = [[[NSString alloc] initWithData:[NSData dataWithContentsOfFile:fileName] encoding:NSUTF8StringEncoding] autorelease];
			[view performSelector:@selector(odbEditorDidModifyString:) withObject:newString];
			[FailedFiles removeObject:fileName];
			fileName = nil;
		}
	}
	if (fileName)
	{
		[FailedFiles addObject:fileName];
		NSLog(@"%s view %p, %@, window %@", _cmd, view, view, [view window]);
		NSLog(@"%s file name %@, options %@", _cmd, fileName, [options description]);
		NSLog(@"%s all %@", _cmd, [OpenFiles description]);
		NSBeep();
	}
}

+ (void)handleClosedFileEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
	NSAppleEventDescriptor* fileURL = [[event paramDescriptorForKeyword:keyDirectObject] coerceToDescriptorType:typeFileURL];
	NSString* urlString = [[[NSString alloc] initWithData:[fileURL data] encoding:NSUTF8StringEncoding] autorelease];
	NSString* fileName = [[[NSURL URLWithString:urlString] path] stringByStandardizingPath];

	if([FailedFiles containsObject:fileName])
	{
		if([[NSFileManager defaultManager] fileExistsAtPath:fileName])
			[[NSWorkspace sharedWorkspace] selectFile:fileName inFileViewerRootedAtPath:[fileName stringByDeletingLastPathComponent]];
		[FailedFiles removeObject:fileName];
	}
	else
	{
		[[NSFileManager defaultManager] removeFileAtPath:fileName handler:nil];
		[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
	}

	[OpenFiles removeObjectForKey:[fileName precomposedStringWithCanonicalMapping]];
	if([OpenFiles count] == 0)
		[self removeODBEventHandlers];
}

+ (NSMenu*)findEditMenu
{
	NSMenu* mainMenu = [NSApp mainMenu];
	std::map<size_t, NSMenu*> ranked;
	for(int i = 0; i != [mainMenu numberOfItems]; i++)
	{
		NSMenu* candidate = [[mainMenu itemAtIndex:i] submenu];
		static SEL const actions[] = { @selector(undo:), @selector(redo:), @selector(cut:), @selector(copy:), @selector(paste:), @selector(delete:), @selector(selectAll:) };
		size_t score = 0;
		for(int j = 0; j != sizeof(actions)/sizeof(actions[0]); j++)
		{
			if(-1 != [candidate indexOfItemWithTarget:nil andAction:actions[j]])
				score++;
		}

		if(score > 0 && ranked.find(score) == ranked.end())
			ranked[score] = candidate;
	}
	return ranked.empty() ? nil : (--ranked.end())->second;
}

+ (void)installMenuItem:(id)sender
{
	if(NSMenu* editMenu = [self findEditMenu])
	{
		[editMenu addItem:[NSMenuItem separatorItem]];
		NSString* ellips = [NSString stringWithUTF8String:"\xe2\x80\xa6"]; // utf-8 for the '...' character (literal utf8 is not allowed in source code)
		id <NSMenuItem> menuItem = [editMenu addItemWithTitle:[NSString stringWithFormat:@"Edit in %@%@", ODBEditorName, ellips] action:@selector(editInODBEditor:) keyEquivalent:@"E"];
		[menuItem setKeyEquivalentModifierMask:NSControlKeyMask | NSCommandKeyMask];
	}
}

+ (void)load
{
	OpenFiles = [NSMutableDictionary new];
	FailedFiles = [NSMutableSet new];
	NSString* mainBundleIdentifier = [[NSBundle mainBundle] bundleIdentifier]; // reads app we're used inside off
	NSString* bundleIdentifier = @"org.slashpunt.edit_in_odbeditor"; // XXX Should this be hardcoded?
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults addSuiteNamed:bundleIdentifier];
	NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
		@"NO",        @"DisableEditInODBEditorMenuItem",
		@"",          @"ODBEditorBundleIdentifier",
		@"<Unknown>", @"ODBEditorName",
		nil];
 
	[defaults registerDefaults:appDefaults];	
	
	ODBEditorBundleIdentifier = [[defaults stringForKey:@"ODBEditorBundleIdentifier"] retain] ?: @"";
	ODBEditorName             = [[defaults stringForKey:@"ODBEditorName"] retain] ?: @"<Unknown>";
	if([defaults boolForKey:@"DisableEditInODBEditorMenuItem"] == NO
		&& ![ODBEditorBundleIdentifier isEqualToString:@""]
		&& ![ODBEditorBundleIdentifier isEqualToString:mainBundleIdentifier])
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(installMenuItem:) name:NSApplicationDidFinishLaunchingNotification object:[NSApplication sharedApplication]];
}
@end
