//
//  WindowController.m
//  Shiver
//
//  Created by Bryan Veloso on 6/8/13.
//  Copyright (c) 2013 Revyver, Inc. All rights reserved.
//

#import "WindowController.h"

#import "APIClient.h"
#import "EmptyStreamListViewController.h"
#import "OBMenuBarWindow.h"
#import "OAuthViewController.h"
#import "SORelativeDateTransformer.h"
#import "StreamListViewController.h"

@interface WindowController () {
@private
    dispatch_source_t _timer;
}

@property (strong) NSViewController *currentViewController;
@property (strong) EmptyStreamListViewController *emptyStreamListViewController;
@property (strong) StreamListViewController *streamListViewController;
@property (strong) NSDate *lastUpdatedTimestamp;

-(void) setupControllers;
-(void) swapViewController:(NSViewController *)viewController;
-(void) composeInterface;

- (void)startTimerForLastUpdatedLabel;
- (void)updateLastUpdatedLabel;
@end

@implementation WindowController

- (id)init
{
    self = [super init];
    if (self) {
        return [super initWithWindowNibName:@"Window"];
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [[self window] setAllowsConcurrentViewDrawing:YES];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(streamListWasUpdated:) name:StreamListWasUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userConnectedAccount:) name:UserDidConnectAccountNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDisconnectedAccount:) name:UserDidDisconnectAccountNotification object:nil];

    // Set up our initial controllers and initialize and display the window
    // and status bar menu item.
    [self setupControllers];
    [self composeInterface];
}

#pragma mark Window Compositioning

- (void)setupControllers
{
    self.emptyStreamListViewController = [[EmptyStreamListViewController alloc] initWithNibName:@"EmptyStreamListView" bundle:nil];
    self.streamListViewController = [[StreamListViewController alloc] initWithNibName:@"StreamListView" bundle:nil];

    if ([[APIClient sharedClient] isAuthenticated]) {
        self.currentViewController = self.streamListViewController;
    } else {
        self.currentViewController = self.emptyStreamListViewController;
    }

    [self.currentViewController.view setFrame:self.masterView.bounds];
    [self.masterView addSubview:self.currentViewController.view];
}

- (void)swapViewController:(NSViewController *)viewController
{
    // Don't switch the view if it doesn't need switching.
    if (self.currentViewController == viewController) return;

    NSView *currentView = [self.currentViewController view];
    NSView *swappedView = [viewController view];

    [self.masterView replaceSubview:currentView with:swappedView];
    self.currentViewController = viewController;
    currentView = swappedView;

    [currentView setFrame:[self.masterView bounds]];
    [currentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
}

- (void)composeInterface
{
    OBMenuBarWindow *window = (OBMenuBarWindow *)[self window];
    [window setHasMenuBarIcon:YES];
    [window setMenuBarIcon:[NSImage imageNamed:@"StatusBarIcon"]];
    [window setHighlightedMenuBarIcon:[NSImage imageNamed:@"StatusBarIconInverted"]];
    [window setAttachedToMenuBar:YES];

    // Compose our own title bar.
    [window setTitle:@""];
    [[window toolbarView] addSubview:self.titleBarView];

    // Make things pretty.
    [[self.refreshButton cell] setBackgroundStyle:NSBackgroundStyleLowered];
    [[self.preferencesButton cell] setBackgroundStyle:NSBackgroundStyleLowered];
    [[self.lastUpdatedLabel cell] setBackgroundStyle:NSBackgroundStyleLowered];
    [[self.statusLabel cell] setBackgroundStyle:NSBackgroundStyleRaised];
}

#pragma mark UI Update Methods

- (void)startTimerForLastUpdatedLabel
{
    // Schedule a timer to update `lastUpdatedLabel` every 30 seconds.
    // Keep a strong reference to _timer in ARC.
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 30.0 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(_timer, ^{ [self updateLastUpdatedLabel]; });
    dispatch_resume(_timer);
}

- (void)updateLastUpdatedLabel
{
    // Update `lastUpdatedLabel` with the current date (relative).
    SORelativeDateTransformer *relativeDateTransformer = [[SORelativeDateTransformer alloc] init];
    NSString *relativeDate = [relativeDateTransformer transformedValue:self.lastUpdatedTimestamp];
    [[self lastUpdatedLabel] setStringValue:[NSString stringWithFormat:@"Last updated %@", relativeDate]];
}

#pragma mark Notification Observers

- (void)streamListWasUpdated:(NSNotification *)notification
{
    StreamListViewController *object = [notification object];
    if ([object isKindOfClass:[StreamListViewController class]]) {
        // Update the interface, starting with the number of live streams.
        NSString *statusLabelString = nil;
        if ([object.streamArray count] == 1) {
            statusLabelString = [NSString stringWithFormat:@"%lu live stream", (unsigned long)[object.streamArray count]];
        } else {
            statusLabelString = [NSString stringWithFormat:@"%lu live streams", (unsigned long)[object.streamArray count]];
        }
        [[self statusLabel] setStringValue:statusLabelString];

        self.lastUpdatedTimestamp = [NSDate date];
        [self updateLastUpdatedLabel];
        [self startTimerForLastUpdatedLabel];
    }
}

- (void)userConnectedAccount:(NSNotification *)notification
{
    OAuthViewController *object = [notification object];
    if ([object isKindOfClass:[OAuthViewController class]]) {
        [self.refreshButton setEnabled:YES];
    }
}

- (void)userDisconnectedAccount:(NSNotification *)notification
{
    OAuthViewController *object = [notification object];
    if ([object isKindOfClass:[OAuthViewController class]]) {
        // Ah, don't forget we have a timer. We should stop it.
        dispatch_source_cancel(_timer);
        dispatch_release(_timer);

        [self.refreshButton setEnabled:NO];
        [self.statusLabel setStringValue:@"Not logged in."];
    }
}

#pragma mark Interface Builder Actions

- (IBAction)showContextMenu:(NSButton *)sender
{
    [self.contextMenu popUpMenuPositioningItem:nil atLocation:NSMakePoint(14,26) inView:sender];
}

- (IBAction)showPreferences:(id)sender
{
    // If we have not created the window controller yet, create it now.
    if (!self.preferencesWindowController) {
        OAuthViewController *oauth = [[OAuthViewController alloc] init];
        NSArray *controllers = [NSArray arrayWithObjects:oauth, nil];
        self.preferencesWindowController = [[RHPreferencesWindowController alloc] initWithViewControllers:controllers andTitle:NSLocalizedString(@"Shiver Preferences", @"Preferences Window Title")];
    }

    [self.preferencesWindowController.window setLevel:NSFloatingWindowLevel];
    [self.preferencesWindowController showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)refreshStreamList:(NSButton *)sender
{
    [[NSNotificationCenter defaultCenter] postNotificationName:RequestToUpdateStreamNotification object:self userInfo:nil];
}

@end
