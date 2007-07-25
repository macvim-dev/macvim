//
//  WindowController.m
//  PSMTabBarControl
//
//  Created by John Pannell on 4/6/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "WindowController.h"
#import "FakeModel.h"
#import "PSMTabBarControl.h"

@implementation WindowController

- (void)awakeFromNib
{
    // toolbar
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"DemoToolbar"];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:YES];
    [toolbar setAutosavesConfiguration:YES];
    /*SInt32 MacVersion;
    if (Gestalt(gestaltSystemVersion, &MacVersion) == noErr){
        if (MacVersion >= 0x1040){
            // this call is Tiger only
            [toolbar setShowsBaselineSeparator:NO];
        }
    }*/
    [[self window] setToolbar:toolbar];
    
    // hook up add tab button
    [[tabBar addTabButton] setTarget:self];
    [[tabBar addTabButton] setAction:@selector(addNewTab:)];
    
    // remove any tabs present in the nib
    NSArray *existingItems = [tabView tabViewItems];
    NSEnumerator *e = [existingItems objectEnumerator];
    NSTabViewItem *item;
    while(item = [e nextObject]){
        [tabView removeTabViewItem:item];
    }
    
    [self addNewTab:self];
    [self addNewTab:self];
    [self addNewTab:self];
    [[tabView tabViewItemAtIndex:0] setLabel:@"Tab"];
    [[tabView tabViewItemAtIndex:1] setLabel:@"Bar"];
    [[tabView tabViewItemAtIndex:2] setLabel:@"Control"];
    
    // open drawer
    //[drawer toggle:self];
}

- (IBAction)addNewTab:(id)sender
{
    FakeModel *newModel = [[FakeModel alloc] init];
    NSTabViewItem *newItem = [[[NSTabViewItem alloc] initWithIdentifier:[newModel controller]] autorelease];
    [newItem setLabel:@"Untitled"];
    [tabView addTabViewItem:newItem];
    [tabView selectTabViewItem:newItem]; // this is optional, but expected behavior
    [newModel release];
}

- (IBAction)closeTab:(id)sender
{
    [tabView removeTabViewItem:[tabView selectedTabViewItem]];
}

- (void)stopProcessing:(id)sender
{
    [[[tabView selectedTabViewItem] identifier] setValue:[NSNumber numberWithBool:NO] forKeyPath:@"selection.isProcessing"];
}

- (void)setIconNamed:(id)sender
{
    NSString *iconName = [sender titleOfSelectedItem];
    if([iconName isEqualToString:@"None"]){
        [[[tabView selectedTabViewItem] identifier] setValue:nil forKeyPath:@"selection.icon"];
        [[[tabView selectedTabViewItem] identifier] setValue:@"None" forKeyPath:@"selection.iconName"];
    } else {
        NSImage *newIcon = [NSImage imageNamed:iconName];
        [[[tabView selectedTabViewItem] identifier] setValue:newIcon forKeyPath:@"selection.icon"];
        [[[tabView selectedTabViewItem] identifier] setValue:iconName forKeyPath:@"selection.iconName"];
    }
}

- (void)setObjectCount:(id)sender
{
    [[[tabView selectedTabViewItem] identifier] setValue:[NSNumber numberWithInt:[sender intValue]] forKeyPath:@"selection.objectCount"];
}

- (IBAction)isProcessingAction:(id)sender
{
    [[[tabView selectedTabViewItem] identifier] setValue:[NSNumber numberWithBool:[sender state]] forKeyPath:@"selection.isProcessing"];
}

- (IBAction)setTabLabel:(id)sender
{
    [[tabView selectedTabViewItem] setLabel:[sender stringValue]];
}

- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem
{
    if([menuItem action] == @selector(closeTab:)){
        if(![tabBar canCloseOnlyTab] && ([tabView numberOfTabViewItems] <= 1)){
            return NO;
        }
    }
    return YES;
}

#pragma mark -
#pragma mark ---- tab bar config ----

- (void)configStyle:(id)sender
{
    [tabBar setStyleNamed:[sender titleOfSelectedItem]];
}

- (void)configCanCloseOnlyTab:(id)sender
{
    [tabBar setCanCloseOnlyTab:[sender state]];
}

- (void)configHideForSingleTab:(id)sender
{
    [tabBar setHideForSingleTab:[sender state]];
}

- (void)configAddTabButton:(id)sender
{
    [tabBar setShowAddTabButton:[sender state]];
}

- (void)configTabMinWidth:(id)sender
{
    if([tabBar cellOptimumWidth] < [sender intValue]){
        [tabBar setCellMinWidth:[tabBar cellOptimumWidth]];
        [sender setIntValue:[tabBar cellOptimumWidth]];
        return;
    }
    
    [tabBar setCellMinWidth:[sender intValue]];
}

- (void)configTabMaxWidth:(id)sender
{
    if([tabBar cellOptimumWidth] > [sender intValue]){
        [tabBar setCellMaxWidth:[tabBar cellOptimumWidth]];
        [sender setIntValue:[tabBar cellOptimumWidth]];
        return;
    }
    
    [tabBar setCellMaxWidth:[sender intValue]];
}

- (void)configTabOptimumWidth:(id)sender
{
    if([tabBar cellMaxWidth] < [sender intValue]){
        [tabBar setCellOptimumWidth:[tabBar cellMaxWidth]];
        [sender setIntValue:[tabBar cellMaxWidth]];
        return;
    }
    
    if([tabBar cellMinWidth] > [sender intValue]){
        [tabBar setCellOptimumWidth:[tabBar cellMinWidth]];
        [sender setIntValue:[tabBar cellMinWidth]];
        return;
    }
    
    [tabBar setCellOptimumWidth:[sender intValue]];
}

- (void)configTabSizeToFit:(id)sender
{
    [tabBar setSizeCellsToFit:[sender state]];
}

#pragma mark -
#pragma mark ---- delegate ----

- (void)tabView:(NSTabView *)aTabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    // need to update bound values to match the selected tab
    if([[tabViewItem identifier] respondsToSelector:@selector(content)]){
        if([[[tabViewItem identifier] content] respondsToSelector:@selector(objectCount)]){
            [objectCounterField setIntValue:[[[tabViewItem identifier] content] objectCount]];
        }
    }
    if([[tabViewItem identifier] respondsToSelector:@selector(content)]){
        if([[[tabViewItem identifier] content] respondsToSelector:@selector(isProcessing)]){
            [isProcessingButton setState:[[[tabViewItem identifier] content] isProcessing]];
        }
    }
    if([[tabViewItem identifier] respondsToSelector:@selector(content)]){
        if([[[tabViewItem identifier] content] respondsToSelector:@selector(iconName)]){
            NSString *newName = [[[tabViewItem identifier] content] iconName];
            if(newName){
                [iconButton selectItem:[[iconButton menu] itemWithTitle:newName]];
            } else {
                [iconButton selectItem:[[iconButton menu] itemWithTitle:@"None"]];
            }
        }
    }
}

- (BOOL)tabView:(NSTabView *)aTabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
    if([[tabViewItem label] isEqualToString:@"Drake"]){
        NSAlert *drakeAlert = [NSAlert alertWithMessageText:@"No Way!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"I refuse to close a tab named \"Drake\""];
        [drakeAlert beginSheetModalForWindow:[NSApp keyWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];
        return NO;
    }
    return YES;
}    

- (void)tabView:(NSTabView *)aTabView willCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
    NSLog(@"willCloseTabViewItem: %@", [tabViewItem label]);
}

- (void)tabView:(NSTabView *)aTabView didCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
    NSLog(@"didCloseTabViewItem: %@", [tabViewItem label]);
}

#pragma mark -
#pragma mark ---- toolbar ----

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag 
{
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    
    if([itemIdentifier isEqualToString:@"TabField"]){
        [item setPaletteLabel:@"Tab Label"]; 
        [item setLabel:@"Tab Label"]; 
        [item setView:tabField];
        [item setMinSize:NSMakeSize(100, [tabField frame].size.height)];
        [item setMaxSize:NSMakeSize(500, [tabField frame].size.height)];
        
    } else if([itemIdentifier isEqualToString:@"DrawerItem"]){
        [item setPaletteLabel:@"Configuration"]; 
        [item setLabel:@"Configuration"]; 
        [item setToolTip:@"Configuration"];
        [item setImage:[NSImage imageNamed:@"32x32_log"]];
        [item setTarget:drawer]; 
        [item setAction:@selector(toggle:)];
        
    }
    
    return [item autorelease];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar 
{
    return [NSArray arrayWithObjects:@"TabField",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"DrawerItem",
        nil];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar 
{
    return [NSArray arrayWithObjects:@"TabField",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"DrawerItem",
        nil];
}

- (IBAction)toggleToolbar:(id)sender 
{
    [[[self window] toolbar] setVisible:![[[self window] toolbar] isVisible]];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
    return YES;
}

@end
