/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

/*
 * MMPlugInInstanceMediator
 *
 * Implementation of the PlugInInstanceMediator protocol.  One of these is
 * created per vim instance.  It manages all of the plugin instances for that
 * vim instance.
 *
 * MMPlugInAppMediator
 *
 * Implementation of the PlugInAppMediator protocol.  Singleton class.
 *
 * Author: Matt Tolton
 */

#import "MacVim.h"

#ifdef MM_ENABLE_PLUGINS

#import "PlugInImpl.h"
#import "PlugInGUI.h"
#import "MMPlugInManager.h"
#import "RBSplitView.h"
#import "MMAppController.h"
#import "MMVimController.h"


@implementation MMPlugInInstanceMediator

- (void)setupDrawer
{
    // XXX The drawer does not work in full screen mode.  Eventually, the
    // drawer will go away so I'm ignoring this issue for now.
    drawer = [[NSDrawer alloc] initWithContentSize:NSMakeSize(200,100)
                                     preferredEdge:NSMinXEdge];


    NSSize contentSize = [drawer contentSize];

    // XXX memory management for this
    MMPlugInViewContainer * containerView = [[MMPlugInViewContainer alloc]
        initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];

    [drawer setContentView:containerView];

    [containerView release];

    [drawer setParentWindow:[[vimController windowController] window]];

}

- (void)initializeInstances
{
    NSArray *plugInClasses = [[MMPlugInManager sharedManager] plugInClasses];
    int i, count = [plugInClasses count];
    for (i = 0; i < count; i++) {
        Class plugInClass = [plugInClasses objectAtIndex:i];
        if ([plugInClass instancesRespondToSelector:
                         @selector(initWithMediator:)]) {
            id instance = [[[plugInClass alloc] initWithMediator:self] autorelease];
            [instances addObject:instance];
        }
    }
}

- (id)initWithVimController:(MMVimController *)controller
{
    if ((self = [super init]) == nil) return nil;
    vimController = controller;
    instances = [[NSMutableArray alloc] init];
    plugInViews = [[NSMutableArray alloc] init];

    [self setupDrawer];
    [self initializeInstances];

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);

    [plugInViews release]; plugInViews = nil;
    [instances release]; instances = nil;
    [drawer release]; drawer = nil;
    vimController = nil;

    [super dealloc];
}

- (id)evaluateVimExpression:(NSString *)vimExpression
{
    NSString *errstr = nil;
    id res = [vimController evaluateVimExpressionCocoa:vimExpression
                                           errorString:&errstr];
    if (!res)
        [NSException raise:@"VimEvaluationException" format:errstr];

    return res;
}

- (void)addVimInput:(NSString *)input
{
    [vimController addVimInput:input];
}

- (void)addPlugInView:(NSView *)view withTitle:(NSString *)title
{
    //NSLog(@"%@ %s", [self className], _cmd);

    // For now, just always open the drawer when adding a plugin view
    [drawer open];

    MMPlugInViewController *newView =
        [[MMPlugInViewController alloc] initWithView:view title:title];

    [plugInViews addObject:newView];

    [newView moveToContainer:(MMPlugInViewContainer *)[drawer contentView]];

    [newView release];
}

- (void)openFiles:(NSArray *)filenames
{
    [vimController dropFiles:filenames forceOpen:YES];
}

- (id)instanceWithClass:(Class)class
{
    int i, count = [instances count];
    for (i = 0; i < count; i++) {
        id instance = [instances objectAtIndex:i];
        if ([instance isKindOfClass:class])
            return instance;
    }

    return nil;
}

@end

@implementation MMPlugInAppMediator

MMPlugInAppMediator *sharedAppMediator = nil;

+ (MMPlugInAppMediator *)sharedAppMediator
{
    if (sharedAppMediator == nil)
        sharedAppMediator = [[MMPlugInAppMediator alloc] init];

    return sharedAppMediator;
}

- (void)addPlugInMenuItem:(NSMenuItem *)menuItem
{
    NSAssert(menuItem, @"menuItem cannot be nil");
    [[MMAppController sharedInstance] addItemToPlugInMenu:menuItem];
}

// It is a little bit ugly having to pass the class in here.  An alternative
// would be to have a 1:1 relationship between app mediators and plugins, so
// that we'd know exactly which plugin class to look for.
- (id)keyPlugInInstanceWithClass:(Class)class
{
    MMVimController *keyVimController = [[NSApp delegate] keyVimController];

    if (keyVimController)
        return [[keyVimController instanceMediator] instanceWithClass:class];

    return nil;
}

@end

#endif
