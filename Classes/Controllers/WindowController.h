//
//  WindowController.h
//  Shiver
//
//  Created by Bryan Veloso on 6/8/13.
//  Copyright (c) 2013 Revyver, Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <RHPreferences/RHPreferences.h>

@interface WindowController : NSWindowController <NSWindowDelegate>

@property (nonatomic, strong, readonly) RHPreferencesWindowController *preferencesWindowController;

// These are controls that need to be accessed from the stream list controller.
@property (weak) IBOutlet NSButton *refreshButton;
@property (weak) IBOutlet NSTextField *lastUpdatedLabel;
@property (weak) IBOutlet NSTextField *statusLabel;
@property (weak) IBOutlet NSPopUpButton *streamMenu;

@end
