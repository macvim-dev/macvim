//
//  FastFindCell.h
//  MacVim
//
//  Created by Doug Fales on 4/3/10.
//  MacVimProject (MVP) by Doug Fales, 2010
//

#import <Cocoa/Cocoa.h>

@class MVPFastFindController;

@interface MVPFastFindCell : NSTextFieldCell<NSCopying> {
	MVPFastFindController *fastFindController;
}
@property (nonatomic,retain) MVPFastFindController *fastFindController;

@end
