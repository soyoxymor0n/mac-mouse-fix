//
// --------------------------------------------------------------------------
// ShortcutLibraryTests.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

/// Checks the data and the pure functions in ShortcutLibrary.m.
///     Run with `./run_tests.sh`. It compiles the real ShortcutLibrary.m. Not part of the Xcode project.
///     Checks:
///     - every entry (and every layout variant) has valid steps, no label looks destructive
///     - phase 2: choosing a library entry creates the same row dictionary as recording the same key by hand, on every layout
///     - per-layout variants: the variant is picked by input source ID, unknown layouts use US
///     - library entries appear only for their matching bundle IDs
///     - the "Show shortcut library" switch hides every entry (effect menu and Apps tab)

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "Constants.h"
#import "ShortcutLibrary.h"

@interface ShortcutLibrary (Tests)
+ (BOOL)stepsAreValid:(NSArray *)steps;
+ (NSArray *)effectsMenuEntriesForBundleID:(NSString *)bundleID layout:(NSString *)layout;
+ (NSArray *)effectsMenuEntriesForBundleID:(NSString *)bundleID inputSourceID:(NSString *)inputSourceID enabled:(BOOL)enabled;
+ (NSArray *)overviewEntriesForBundleID:(NSString *)bundleID inputSourceID:(NSString *)inputSourceID enabled:(BOOL)enabled;
+ (NSString *)layoutKeyForInputSourceID:(NSString *)inputSourceID;
@end

static NSString *const kUS = @"com.apple.keylayout.US";
static NSString *const kGerman = @"com.apple.keylayout.German";
static NSString *const kAustrian = @"com.apple.keylayout.Austrian";

/// The row that recording a key creates: the helper payload of the pressed button (trigger and an empty modification precondition),
///     whose effect the key capture field then replaces with the recorded key. Same dict as in RemapTableTranslator's capture handler.
static NSDictionary *recordedRow(NSDictionary *trigger, CGKeyCode keyCode, CGEventFlags flags) {
    NSMutableDictionary *row = [@{ kMFRemapsKeyTrigger: trigger, kMFRemapsKeyModificationPrecondition: @{} } mutableCopy];
    row[kMFRemapsKeyEffect] = @{
        kMFActionDictKeyType: kMFActionDictTypeKeyboardShortcut,
        kMFActionDictKeyKeyboardShortcutVariantKeycode: @(keyCode),
        kMFActionDictKeyKeyboardShortcutVariantModifierFlags: @(flags),
    };
    return row;
}

int main(void) { @autoreleasepool {

    int failures = 0;
    NSUInteger nOfEntries = 0;
    NSUInteger nOfRowComparisons = 0;
    NSRegularExpression *destructive = [NSRegularExpression regularExpressionWithPattern:@"\\b(delete|erase|quit|log ?out|sign ?out|force|empty trash|purchase|unsubscribe|uninstall)\\b" options:NSRegularExpressionCaseInsensitive error:nil];
    NSArray *inputSources = @[kUS, kGerman, kAustrian, @"com.apple.keylayout.French"];
    NSDictionary *trigger = @{ kMFButtonTriggerKeyButtonNumber: @4, kMFButtonTriggerKeyClickLevel: @1, kMFButtonTriggerKeyDuration: kMFButtonTriggerDurationClick };

    for (NSDictionary *app in [ShortcutLibrary apps]) {

        NSArray *bundleIDs = app[@"bundleIDs"];
        if (bundleIDs.count == 0) { failures++; printf("FAIL: %s has no bundle ID\n", [app[@"name"] UTF8String]); }

        for (NSDictionary *entry in app[@"entries"]) {
            nOfEntries++;
            NSString *label = entry[@"label"];
            if (![ShortcutLibrary stepsAreValid:entry[@"steps"]]) { failures++; printf("FAIL: invalid steps: %s\n", label.UTF8String); }
            for (NSString *layout in entry[@"variants"]) {
                if (![ShortcutLibrary stepsAreValid:entry[@"variants"][layout]]) { failures++; printf("FAIL: invalid %s steps: %s\n", layout.UTF8String, label.UTF8String); }
            }
            if ([destructive firstMatchInString:label options:0 range:NSMakeRange(0, label.length)]) { failures++; printf("FAIL: destructive label: %s\n", label.UTF8String); }
            if (entry[@"layouts"] && ![entry[@"layouts"] isKindOfClass:NSArray.class]) { failures++; printf("FAIL: layouts is not an array: %s\n", label.UTF8String); }

            /// Layout-dependent entries have a variant for each layout they work on
            if ([entry[@"layoutDependent"] boolValue]) {
                for (NSString *layout in entry[@"layouts"] ?: @[@"us", @"de", @"at"]) {
                    if (entry[@"variants"][layout] == nil) { failures++; printf("FAIL: no %s variant: %s\n", layout.UTF8String, label.UTF8String); }
                }
            }
            /// Verified entries have a source and a date
            if ([entry[@"verified"] boolValue] && (entry[@"sourceURL"] == nil || entry[@"verifiedOn"] == nil)) { failures++; printf("FAIL: verified without source: %s\n", label.UTF8String); }

            /// The variant is picked by input source, unknown layouts use US
            for (NSString *source in inputSources) {
                NSString *layout = [ShortcutLibrary layoutKeyForInputSourceID:source];
                NSArray *steps = [ShortcutLibrary stepsForEntry:entry inputSourceID:source];
                BOOL available = entry[@"layouts"] == nil || [entry[@"layouts"] containsObject:layout];
                NSArray *expected = available ? (entry[@"variants"][layout] ?: entry[@"steps"]) : nil;
                if (!(steps == expected || [steps isEqual:expected])) { failures++; printf("FAIL: wrong steps for %s: %s\n", source.UTF8String, label.UTF8String); }
            }
        }

        /// Every entry for the US layout makes it into the effect menu (nothing is dropped by the validation)
        NSUInteger nForUS = 0;
        for (NSDictionary *entry in app[@"entries"]) {
            if (!entry[@"layouts"] || [entry[@"layouts"] containsObject:@"us"]) nForUS++;
        }
        NSArray *menuEntries = [ShortcutLibrary effectsMenuEntriesForBundleID:bundleIDs.firstObject layout:@"us"];
        if (menuEntries.count != nForUS) { failures++; printf("FAIL: %s: %lu menu entries for %lu library entries\n", [app[@"name"] UTF8String], menuEntries.count, nForUS); }

        /// Phase 2: choosing an entry creates the same row as recording the same key by hand. On every layout, in the effect menu and in the Apps tab.
        for (NSString *source in inputSources) {
            NSArray *effectMenu = [ShortcutLibrary effectsMenuEntriesForBundleID:bundleIDs.firstObject inputSourceID:source enabled:YES];
            NSArray *overview = [ShortcutLibrary overviewEntriesForBundleID:bundleIDs.firstObject inputSourceID:source enabled:YES];
            if (effectMenu.count != overview.count) { failures++; printf("FAIL: %s: effect menu and Apps tab differ on %s\n", [app[@"name"] UTF8String], source.UTF8String); continue; }
            for (NSUInteger i = 0; i < effectMenu.count; i++) {
                NSDictionary *effect = effectMenu[i][@"dict"];
                if (![effect isEqual:overview[i][@"dict"]]) { failures++; printf("FAIL: effect menu and Apps tab create different effects: %s\n", [effectMenu[i][@"ui"] UTF8String]); }
                if (![effect[kMFActionDictKeyType] isEqual:kMFActionDictTypeKeyboardShortcut]) continue; /// Sequences can't be recorded by hand
                CGKeyCode keyCode = [effect[kMFActionDictKeyKeyboardShortcutVariantKeycode] unsignedShortValue];
                CGEventFlags flags = [effect[kMFActionDictKeyKeyboardShortcutVariantModifierFlags] unsignedLongLongValue];
                NSDictionary *libraryRow = [ShortcutLibrary rowWithTrigger:trigger effect:effect];
                NSDictionary *byHand = recordedRow(trigger, keyCode, flags);
                nOfRowComparisons++;
                if (![libraryRow isEqualToDictionary:byHand]) { failures++; printf("FAIL: library row differs from recorded row: %s\n", [effectMenu[i][@"ui"] UTF8String]); }
                if (![[ShortcutLibrary effectForRecordedKeyCode:keyCode flags:flags] isEqualToDictionary:byHand[kMFRemapsKeyEffect]]) { failures++; printf("FAIL: effectForRecordedKeyCode differs from the capture handler\n"); }
            }
        }

        /// Bundle ID rule: every bundle ID of the app gets the app's entries, and only those
        for (NSString *bundleID in bundleIDs) {
            NSUInteger expected = 0;
            for (NSDictionary *other in [ShortcutLibrary apps]) {
                if (![other[@"bundleIDs"] containsObject:bundleID]) continue;
                for (NSDictionary *entry in other[@"entries"]) { if (!entry[@"layouts"] || [entry[@"layouts"] containsObject:@"us"]) expected++; }
            }
            NSUInteger got = [ShortcutLibrary effectsMenuEntriesForBundleID:bundleID inputSourceID:kUS enabled:YES].count;
            if (got != expected) { failures++; printf("FAIL: %s: %lu entries for %lu expected\n", bundleID.UTF8String, got, expected); }
            /// Near misses don't match
            NSArray *nearMisses = @[bundleID.lowercaseString, bundleID.uppercaseString, [bundleID stringByAppendingString:@".helper"], [bundleID substringToIndex:bundleID.length - 1]];
            for (NSString *miss in nearMisses) {
                if ([miss isEqualToString:bundleID]) continue;
                BOOL isRealID = NO;
                for (NSDictionary *other in [ShortcutLibrary apps]) { if ([other[@"bundleIDs"] containsObject:miss]) isRealID = YES; }
                if (isRealID) continue;
                if ([ShortcutLibrary effectsMenuEntriesForBundleID:miss inputSourceID:kUS enabled:YES].count != 0) { failures++; printf("FAIL: entries for near miss %s\n", miss.UTF8String); }
                if ([ShortcutLibrary overviewEntriesForBundleID:miss inputSourceID:kUS enabled:YES].count != 0) { failures++; printf("FAIL: Apps tab entries for near miss %s\n", miss.UTF8String); }
            }
        }

        /// Switch: off hides every entry, in the effect menu and in the Apps tab (which also carries the suggestions)
        for (NSString *source in inputSources) {
            if ([ShortcutLibrary effectsMenuEntriesForBundleID:bundleIDs.firstObject inputSourceID:source enabled:NO].count != 0) { failures++; printf("FAIL: %s: effect menu entries while switched off\n", [app[@"name"] UTF8String]); }
            if ([ShortcutLibrary overviewEntriesForBundleID:bundleIDs.firstObject inputSourceID:source enabled:NO].count != 0) { failures++; printf("FAIL: %s: Apps tab entries while switched off\n", [app[@"name"] UTF8String]); }
        }
    }

    if ([ShortcutLibrary effectsMenuEntriesForBundleID:@"com.example.not-in-library" inputSourceID:kUS enabled:YES].count != 0) { failures++; printf("FAIL: entries for an unknown app\n"); }
    if ([ShortcutLibrary overviewEntriesForBundleID:@"" inputSourceID:kUS enabled:YES].count != 0) { failures++; printf("FAIL: entries for an empty bundle ID\n"); }

    /// Input source IDs map to variants. Unknown layouts use US.
    NSDictionary *layoutCases = @{ kUS: @"us", kGerman: @"de", kAustrian: @"at", @"com.apple.keylayout.ABC": @"us", @"com.apple.keylayout.German-DIN-2": @"us", @"com.apple.keylayout.French": @"us", @"": @"us" };
    for (NSString *source in layoutCases) {
        if (![[ShortcutLibrary layoutKeyForInputSourceID:source] isEqual:layoutCases[source]]) { failures++; printf("FAIL: layout for %s\n", source.UTF8String); }
    }
    NSDictionary *bracketEntry = @{ @"steps": @[@[@33, @(kCGEventFlagMaskCommand)]], @"layoutDependent": @YES,
                                    @"variants": @{ @"us": @[@[@33, @(kCGEventFlagMaskCommand)]], @"de": @[@[@23, @(kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate)]], @"at": @[@[@23, @(kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate)]] } };
    if (![[ShortcutLibrary stepsForEntry:bracketEntry inputSourceID:kGerman][0][0] isEqual:@23]) { failures++; printf("FAIL: German variant not picked\n"); }
    if (![[ShortcutLibrary stepsForEntry:bracketEntry inputSourceID:@"com.apple.keylayout.Dvorak"][0][0] isEqual:@33]) { failures++; printf("FAIL: unknown layout doesn't use US\n"); }

    /// The validation rejects what the helper rejects
    if ([ShortcutLibrary stepsAreValid:@[@[@128, @0]]]) { failures++; printf("FAIL: key code 128 accepted\n"); }
    if ([ShortcutLibrary stepsAreValid:@[@[@0, @(kCGEventFlagMaskSecondaryFn)]]]) { failures++; printf("FAIL: fn flag accepted\n"); }
    if ([ShortcutLibrary stepsAreValid:@[]]) { failures++; printf("FAIL: empty steps accepted\n"); }
    if (![ShortcutLibrary stepsAreValid:@[@[@46, @(kCGEventFlagMaskCommand | kCGEventFlagMaskShift)]]]) { failures++; printf("FAIL: Cmd-Shift-M rejected\n"); }

    /// Entries with `layouts` are left out on the other layouts. "Create new terminal" is US-only: on German and Austrian keyboards VS Code has no default for it.
    for (NSString *layout in @[@"us", @"de", @"at"]) {
        NSArray *menuEntries = [ShortcutLibrary effectsMenuEntriesForBundleID:@"com.microsoft.VSCode" layout:layout];
        BOOL hasTerminal = NO;
        for (NSDictionary *menuEntry in menuEntries) { if ([menuEntry[@"ui"] isEqualToString:@"Create new terminal"]) hasTerminal = YES; }
        BOOL shouldHave = [layout isEqualToString:@"us"];
        if (hasTerminal != shouldHave) { failures++; printf("FAIL: Create new terminal on %s: %s\n", layout.UTF8String, hasTerminal ? "shown" : "missing"); }
    }

    printf("%lu apps, %lu entries, %lu library rows compared with recorded rows, %d failures\n", (unsigned long)[ShortcutLibrary apps].count, (unsigned long)nOfEntries, (unsigned long)nOfRowComparisons, failures);
    return failures ? 1 : 0;
}}
