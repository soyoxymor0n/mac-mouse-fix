//
// --------------------------------------------------------------------------
// ShortcutLibrary.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

#import "ShortcutLibrary.h"
#import "Constants.h"
#import "Mac_Mouse_Fix-Swift.h"

/// Modifier flags (CGEventFlags)
#define kFlagsCmd        1048576   /// 0x100000
#define kFlagsCmdShift   1179648   /// 0x120000
#define kFlagsCmdOption  1572864   /// 0x180000
#define kFlagsCtrl       262144    /// 0x040000

/// Virtual key codes (Carbon HIToolbox/Events.h)
#define kKeyM      46
#define kKeyO      31
#define kKeyN      45
#define kKeyG      5
#define kKeyLeft   123
#define kKeyRight  124
#define kKeyUp     126
#define kKeySpace  49

@implementation ShortcutLibrary

/// Each entry: label key, the key symbols shown as a hint, key code, flags.
/// Sources (2026-10-25):
/// - Google Chrome, Mac: https://support.google.com/chrome/answer/157179 (back and forward with Command+Left and Command+Right, tab switching with Option+Command+Left and Right)
/// - Microsoft Teams, Mac: https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2 (Command+Shift+M mute, Command+Shift+O camera)
/// - Finder, Mac: https://support.apple.com/en-us/102650 (Command+Up Arrow parent folder, Shift+Command+N new folder, Shift+Command+G Go to Folder, Control+Up Arrow Mission Control)
+ (NSDictionary<NSString *, NSArray *> *)library {
    static NSDictionary *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        library = @{
            @"com.google.Chrome": @[
                @[@"shortcut-library.chrome.back",         @"⌘←",   @(kKeyLeft),  @(kFlagsCmd)],
                @[@"shortcut-library.chrome.forward",      @"⌘→",   @(kKeyRight), @(kFlagsCmd)],
                @[@"shortcut-library.chrome.next-tab",     @"⌥⌘→",  @(kKeyRight), @(kFlagsCmdOption)],
                @[@"shortcut-library.chrome.previous-tab", @"⌥⌘←",  @(kKeyLeft),  @(kFlagsCmdOption)],
            ],
            @"com.microsoft.teams2": @[
                @[@"shortcut-library.teams.mute",   @"⇧⌘M", @(kKeyM), @(kFlagsCmdShift)],
                @[@"shortcut-library.teams.camera", @"⇧⌘O", @(kKeyO), @(kFlagsCmdShift)],
            ],
            @"com.apple.finder": @[
                @[@"shortcut-library.finder.enclosing-folder", @"⌘↑",  @(kKeyUp), @(kFlagsCmd)],
                @[@"shortcut-library.finder.new-folder",       @"⇧⌘N", @(kKeyN),  @(kFlagsCmdShift)],
                @[@"shortcut-library.finder.go-to-folder",     @"⇧⌘G", @(kKeyG),  @(kFlagsCmdShift)],
                @[@"shortcut-library.finder.mission-control",  @"⌃↑",  @(kKeyUp), @(kFlagsCtrl)],
            ],
        };
    });
    return library;
}

+ (NSArray *)effectsMenuEntriesForBundleID:(NSString *)bundleID {
    NSArray *entries = [self library][bundleID];
    if (entries == nil) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (NSArray *e in entries) {
        [result addObject:@{
            @"ui": MFLocalizedString(e[0], @""),
            @"tool": e[1],
            @"dict": @{
                kMFActionDictKeyType: kMFActionDictTypeKeyboardShortcut,
                kMFActionDictKeyKeyboardShortcutVariantKeycode: e[2],
                kMFActionDictKeyKeyboardShortcutVariantModifierFlags: e[3],
            },
        }];
    }
    return result;
}

@end
