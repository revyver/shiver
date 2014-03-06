//
//  ApplicationController.m
//  Shiver
//
//  Created by Bryan Veloso on 6/8/13.
//  Copyright (c) 2013 Revyver, Inc. All rights reserved.
//

#import "AboutWindowController.h"
#import "DDASLLogger.h"
#import "DDTTYLogger.h"
#import "GeneralViewController.h"
#import "LogFormatter.h"
#import "LoginViewController.h"
#import "HexColor.h"
#import "MainWindowController.h"
#import "Preferences.h"
#import "Reachability.h"
#import "StartAtLoginController.h"
#import "UserViewModel.h"

#import "ApplicationController.h"

@interface ApplicationController ()

@property (nonatomic, strong) UserViewModel *viewModel;
@property (nonatomic, strong) MainWindowController *windowController;

@property (nonatomic, strong) AboutWindowController *aboutWindowController;
@property (nonatomic, strong) StartAtLoginController *loginController;

// Preferences.
@property (nonatomic, strong) Preferences *preferences;
@property (nonatomic, strong) RHPreferencesWindowController *preferencesWindowController;
@property (nonatomic, strong) GeneralViewController *generalPreferences;
@property (nonatomic, strong) LoginViewController *loginPreferences;

- (IBAction)showAbout:(id)sender;
- (IBAction)showPreferences:(id)sender;
- (IBAction)showMainWindow:(id)sender;

@end

@implementation ApplicationController

+ (ApplicationController *)sharedInstance
{
    return [NSApp delegate];
}

- (id)init
{
	self = [super init];
	if (self == nil) { return nil; }

    _viewModel = [[UserViewModel alloc] init];
    _windowController = [[MainWindowController alloc] initWithViewModel:_viewModel nibName:@"MainWindow"];

    _loginController = [[StartAtLoginController alloc] initWithIdentifier:ShiverHelperIdentifier];

    _aboutWindowController = [[AboutWindowController alloc] init];

    _preferences = [Preferences sharedPreferences];
    _generalPreferences = [[GeneralViewController alloc] init];
    _loginPreferences = [[LoginViewController alloc] init];

    return self;
}

- (void)awakeFromNib
{
    [self initializeDockIcon];
    [self initializeStatusItem];
}

#pragma mark - Preferences

- (NSWindowController *)preferencesWindowController
{
    // If we have not created the window controller yet, create it now.
    if (_preferencesWindowController == nil) {
        NSArray *controllers = @[ self.generalPreferences, self.loginPreferences ];
        _preferencesWindowController = [[RHPreferencesWindowController alloc] initWithViewControllers:controllers andTitle:NSLocalizedString(@"Shiver Preferences", @"Preferences Window Title")];
    }
    return _preferencesWindowController;
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [[Preferences sharedPreferences] setupDefaults];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(requestToOpenPreferences:) name:RequestToOpenPreferencesNotification object:nil];

    // Preload the window.
    (void)self.windowController.window;
    [self.windowController showWindow:self];

    [self initializeLogging];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    if (flag == NO) { [self.windowController.window makeKeyAndOrderFront:self]; }
    return YES;
}

- (void)initializeLogging
{
    // We log too verbosely for the console in development. Let's only add it
    // when running a release build.
    LogFormatter *formatter = [[LogFormatter alloc] init];

#ifndef DEBUG
    [[DDASLLogger sharedInstance] setLogFormatter:formatter];
    [DDLog addLogger:[DDASLLogger sharedInstance]];
#endif
    // Specify some custom colors and a custom formatter.
    [[DDTTYLogger sharedInstance] setForegroundColor:[NSColor colorWithHexString:@"#FF4136"] backgroundColor:nil forFlag:LOG_FLAG_ERROR];
    [[DDTTYLogger sharedInstance] setForegroundColor:[NSColor colorWithHexString:@"#FF851B"] backgroundColor:nil forFlag:LOG_FLAG_WARN];
    [[DDTTYLogger sharedInstance] setForegroundColor:[NSColor colorWithHexString:@"#333333"] backgroundColor:nil forFlag:LOG_FLAG_INFO];
    [[DDTTYLogger sharedInstance] setForegroundColor:[NSColor colorWithHexString:@"#AAAAAA"] backgroundColor:nil forFlag:LOG_FLAG_VERBOSE];
    [[DDTTYLogger sharedInstance] setLogFormatter:formatter];
    [[DDTTYLogger sharedInstance] setColorsEnabled:YES];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];

    NSString *productName =  [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
    NSString *shortVersionString = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
    DDLogInfo(@"Application: Loaded %@ v%@", productName, shortVersionString);
}

- (void)initializeDockIcon
{
    // Observe the icon visibility preference, if it is set to "Dock and Menu
    // Bar" (index 0) or "Only in Dock" (index 1), set the application
    // activation policy to "regular."
    [[RACObserve(self, preferences.iconVisibility)
        filter:^BOOL(id value) {
            return ([value isEqualToNumber:@0] || [value isEqualToNumber:@1]); }]
        subscribeNext:^(id x) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        }];

    // If the icon visibility preference is set to "Only in Menu Bar" (index 2),
    // set the application activation policy to "accessory," which removes the
    // dock icon. Forcefully order front the main window so it doesn't feel like
    // the app closes.
    [[RACObserve(self, preferences.iconVisibility)
        filter:^BOOL(id value) {
            return ([value isEqualToNumber:@2]); }]
        subscribeNext:^(id x) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
            [self.windowController.window makeKeyAndOrderFront:self];
            [self.preferencesWindowController.window makeKeyAndOrderFront:self];
            [NSApp activateIgnoringOtherApps:YES];
        }];
}

- (void)initializeStatusItem
{
    // Observe the icon visibility preference, if it is set to "Dock and Menu
    // Bar" (index 0) or "Only in Menu Bar" (index 2), create the status item.
    [[RACObserve(self, preferences.iconVisibility)
        filter:^BOOL(id value) {
            return ([value isEqualToNumber:@0] || [value isEqualToNumber:@2]); }]
        subscribeNext:^(id x) {
            [self createStatusItem];
        }];

    // If the icon visibility preference is set to "Only in Dock" (index 1),
    // remove the status bar icon.
    [[RACObserve(self, preferences.iconVisibility)
        filter:^BOOL(id value) {
            return ([value isEqualToNumber:@1]); }]
        subscribeNext:^(id x) {
            [self removeStatusItem];
        }];
}

- (void)createStatusItem
{
    NSImage *image = [NSImage imageNamed:@"StatusItem"];
    NSImage *alternateImage = [NSImage imageNamed:@"StatusItemAlternate"];
    NSStatusBar *bar = [NSStatusBar systemStatusBar];

    self.statusItem = [bar statusItemWithLength:NSVariableStatusItemLength];
    [self.statusItem setImage:image];
    [self.statusItem setAlternateImage:alternateImage];
    [self.statusItem setHighlightMode:YES];
    [self.statusItem setAction:@selector(toggleWindow)];
}

- (void)removeStatusItem
{
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    [bar removeStatusItem:self.statusItem];
}

- (void)toggleWindow
{
    NSWindow *window = self.windowController.window;
    if ([window isKeyWindow]) { [window orderOut:self]; }
    else { [window makeKeyAndOrderFront:self]; }
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - Notification Observers

- (void)requestToOpenPreferences:(NSNotification *)notification
{
    [self showPreferences:notification.object];
}

#pragma mark - Interface Builder Actions

- (IBAction)showAbout:(id)sender {
    [self.aboutWindowController.window center];
    [self.aboutWindowController.window makeKeyAndOrderFront:sender];
}

- (IBAction)showPreferences:(id)sender
{
    [self.preferencesWindowController.window center];
    [self.preferencesWindowController.window makeKeyAndOrderFront:sender];
}

- (IBAction)showMainWindow:(id)sender {
    [self.windowController.window makeKeyAndOrderFront:sender];
}

@end
