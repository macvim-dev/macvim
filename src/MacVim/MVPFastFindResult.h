//
//  MVPFastFindResult.h
//  MacVim
//
//  Created by Doug Fales on 5/15/12.
//
//

#import <Foundation/Foundation.h>
#import "MVPProject.h"

@interface MVPFastFindResult : NSObject <NSCopying>  {
    NSMetadataItem *_item;
    MVPProject *_project;
    NSString *_path;
}


- (id)copyWithZone:(NSZone *)zone;
- (id)initWithItem:(NSMetadataItem *)item andProject:(MVPProject *)project;
- (NSString *)name;
- (NSString *)title;
- (NSImage *)icon;


@end
