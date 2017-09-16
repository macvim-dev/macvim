//
//  MVPFastFindResult.m
//  MacVim
//
//  Created by Doug Fales on 5/15/12.
//
//

#import "MVPFastFindResult.h"

@implementation MVPFastFindResult

- (id)copyWithZone:(NSZone *)zone
{
    MVPFastFindResult *copy = [[MVPFastFindResult alloc] initWithItem:_item andProject:_project];
    if(_path != nil){
        copy->_path = [_path retain];
    }
	return copy;
}

- (id)initWithItem:(NSMetadataItem *)item andProject:(MVPProject *)project
{
    [super init];
    _item = [item retain];
    _project = [project retain];
    _path = [_item valueForAttribute:NSMetadataItemPathKey];
    return self;
}

- (void)dealloc
{
    [_item release];
    [_project release];
    [super dealloc];
}

- (NSImage *)icon
{
    return [[NSWorkspace sharedWorkspace] iconForFileType:[_path pathExtension]];
}

- (NSString *)name
{
   return [_path stringByReplacingOccurrencesOfString:_project.pathToRoot withString:@""];
}

- (NSString *)title
{
 return [_path lastPathComponent];
}

@end
