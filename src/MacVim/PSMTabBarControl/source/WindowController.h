//
//  WindowController.h
//  PSMTabBarControl
//
//  Created by John Pannell on 4/6/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>
@class PSMTabBarControl;

@interface WindowController : NSWindowController {
    IBOutlet    NSTabView           *tabView;
    IBOutlet    NSTextField         *tabField;
    IBOutlet    NSDrawer            *drawer;
    
    IBOutlet    PSMTabBarControl    *tabBar;
    
    IBOutlet    NSButton            *isProcessingButton;
    IBOutlet    NSTextField         *objectCounterField;
    IBOutlet    NSPopUpButton       *iconButton;
}

// UI
- (IBAction)addNewTab:(id)sender;
- (IBAction)closeTab:(id)sender;
- (IBAction)stopProcessing:(id)sender;
- (IBAction)setIconNamed:(id)sender;
- (IBAction)setObjectCount:(id)sender;
- (IBAction)setTabLabel:(id)sender;

// Actions
- (IBAction)isProcessingAction:(id)sender;

// tab bar config
- (void)configStyle:(id)sender;
- (void)configCanCloseOnlyTab:(id)sender;
- (void)configHideForSingleTab:(id)sender;
- (void)configAddTabButton:(id)sender;
- (void)configTabMinWidth:(id)sender;
- (void)configTabMaxWidth:(id)sender;
- (void)configTabOptimumWidth:(id)sender;
- (void)configTabSizeToFit:(id)sender;

// delegate
- (void)tabView:(NSTabView *)aTabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem;
- (BOOL)tabView:(NSTabView *)aTabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)aTabView willCloseTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)aTabView didCloseTabViewItem:(NSTabViewItem *)tabViewItem;

// toolbar
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag;
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar;
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar;
- (IBAction)toggleToolbar:(id)sender;
- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem;

@end
