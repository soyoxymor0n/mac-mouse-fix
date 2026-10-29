//
// --------------------------------------------------------------------------
// ShortcutLibrary.h
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted when the "Show shortcut library" switch changes.
extern NSString *const kShortcutLibraryVisibilityDidChangeNotification;

/// Built-in keyboard shortcuts of common apps. They appear at the top of the effect menu of that app's rows, and in the Apps tab.
/// Character-based entries store one variant per keyboard layout (US, German, Austrian). Rows get the variant of the active layout.
@interface ShortcutLibrary : NSObject

/// The "Show shortcut library" switch in the Buttons tab. Stored in UserDefaults, not in the config. On by default.
///     Off hides every library entry (effect menu, Apps tab, suggestions). Rows that were already added stay.
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;

/// Effect-menu entries for the app, in the same format as the one-shot effects table (`ui`, `tool`, `dict`), for the active layout.
/// Empty if the app has no entries or the library is switched off.
+ (NSArray *)effectsMenuEntriesForBundleID:(NSString *)bundleID;

/// All apps of the library. Each app is a dictionary with `name` (NSString), `bundleIDs` (NSArray of NSString) and `entries` (NSArray of dictionaries with `label` and `symbols`).
+ (NSArray *)apps;

/// The shortcut groups shown for every app, in display order. Specific groups come after these.
+ (NSArray *)defaultShortcutGroups;

/// Entries of an app that work on the active keyboard layout. Empty when the library is switched off.
///     Each entry is a dictionary with `label`, `symbols`, `group`, `verified` (NSNumber BOOL), `dict` (the effect),
///     and optionally `sourceURL`, `verifiedOn`, `suggestedButton` (NSNumber) and `suggestionReason`.
+ (NSArray *)overviewEntriesForBundleID:(NSString *)bundleID;

/// The input source ID of the active keyboard layout (TIS), for example `com.apple.keylayout.German`.
+ (NSString *)activeInputSourceID;

/// The steps ([keycode, flags] pairs) of a library entry for an input source ID. Unknown layouts use the US variant.
///     nil if the entry doesn't work on that layout. Pure function.
+ (NSArray * _Nullable)stepsForEntry:(NSDictionary *)entry inputSourceID:(NSString *)inputSourceID;

/// The effect that recording a key in the table creates.
+ (NSDictionary *)effectForRecordedKeyCode:(CGKeyCode)keyCode flags:(CGEventFlags)flags;

/// A new row with this trigger and effect, and no modification precondition.
+ (NSDictionary *)rowWithTrigger:(NSDictionary *)trigger effect:(NSDictionary *)effect;

@end

NS_ASSUME_NONNULL_END
