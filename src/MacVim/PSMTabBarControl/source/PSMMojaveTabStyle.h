//
//  PSMMojaveTabStyle.h
//  PSMTabBarControl
//
//  This file is copied from PSMYosemiteTabStyle to allow for modifications to
//  adapt to Mojave-specific functionality such as Dark Mode without needing to
//  pollute the implementation of Yosemite tab style.
//
//

#if defined(MAC_OS_X_VERSION_10_14) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
#define HAS_MOJAVE_TAB_STYLE 1

#import <Cocoa/Cocoa.h>
#import "PSMTabStyle.h"

@interface PSMMojaveTabStyle : NSObject <PSMTabStyle> {
    NSImage *closeButton;
    NSImage *closeButtonDown;
    NSImage *closeButtonOver;
    NSImage *closeButtonOverDark;
    NSImage *_addTabButtonImage;
    NSMutableParagraphStyle *truncatingTailParagraphStyle;
    NSMutableParagraphStyle *centeredParagraphStyle;
}

- (void)drawInteriorWithTabCell:(PSMTabBarCell *)cell inView:(NSView*)controlView;

- (void)styleAddTabButton:(PSMRolloverButton *)addTabButton;

- (void)encodeWithCoder:(NSCoder *)aCoder;
- (id)initWithCoder:(NSCoder *)aDecoder;

@end
#endif
