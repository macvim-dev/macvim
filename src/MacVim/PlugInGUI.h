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
#import "RBSplitView.h"


@class MMPlugInView;
@class MMPlugInViewContainer;
@class MMPlugInViewController;

@interface MMPlugInViewHeader : NSView {
    IBOutlet MMPlugInViewController *controller;
}
@end

@interface MMPlugInView : RBSplitSubview {
    IBOutlet MMPlugInViewController *controller;
}

- (MMPlugInViewController *)controller;

@end

@interface MMPlugInViewController : NSObject {
    IBOutlet RBSplitSubview *plugInSubview;
    IBOutlet MMPlugInViewHeader *headerView;
    IBOutlet NSView *contentView;
    IBOutlet NSTextField *titleField;
}

- (id)initWithView:(NSView *)view title:(NSString *)title;
- (void)moveToContainer:(MMPlugInViewContainer *)container;
- (RBSplitSubview *)plugInSubview;
- (MMPlugInViewContainer *)container;

// called when the dropView on the container holding this plugin view was
// changed, and this was the current dropView or it is the new dropView
- (void)dropViewChanged;
@end

@interface MMPlugInViewContainer : RBSplitView {
    RBSplitSubview *fillerView;

    // only used during drag and drop
    MMPlugInView *dropView;
}

- (MMPlugInView *)dropView;
@end
