//
// --------------------------------------------------------------------------
// AppPresets.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import Foundation

/// One suggested assignment of a preset: a button and the action it triggers in the app.
struct AppPresetSuggestion {
    /// 1-based button number
    let button: Int
    /// Localization key of the action name, shown in the review sheet
    let titleKey: String
    /// Shortcut symbols shown after the action name, for example ⌘⇧M
    let symbols: String
    /// Action dict in the same format as the effects of remap rows (`type`, `keycode`, `flags`)
    let effect: [String: Any]
}

/// How a suggestion compares to the rows an app tab already has
enum AppPresetMatch: Equatable {
    /// No row of the tab uses the same trigger and modifiers
    case new
    /// A row of the tab has the same trigger, modifiers and effect
    case same
    /// A row of the tab has the same trigger and modifiers but another effect. `rowIndex` is its index in the rows that were compared.
    case conflict(rowIndex: Int)
}

/// Built-in button assignments for common apps. The banner offers a preset only in an app tab that has no rows yet,
/// and "Recommended setup…" opens it in any tab of an app that has one, comparing it with the tab's rows.
/// The user reviews it in a sheet first, and nothing is written until the user clicks Add Selected.
/// Nothing is applied automatically, and nothing is sent anywhere.
struct AppPreset {

    /// Bundle IDs this preset applies to
    let bundleIDs: [String]
    /// Localization key of the short description shown in the banner
    let summaryKey: String
    /// One suggestion per button
    let suggestions: [AppPresetSuggestion]

    /// Buttons the review sheet offers for a suggestion. Buttons 1 and 2 are left and right click.
    static let selectableButtons: [Int] = [3, 4, 5]

    /// Verified 2026-10-25.
    /// - Microsoft Teams (com.microsoft.teams2): button 4 toggles the mic (Cmd+Shift+M), button 5 the camera (Cmd+Shift+O).
    /// - Google Chrome (com.google.Chrome): button 4 goes back and button 5 forward, with Cmd+Left and Cmd+Right.
    ///   The arrow keys are not character keys, so the keyboard layout doesn't change them.
    static let all: [AppPreset] = [
        AppPreset(
            bundleIDs: ["com.microsoft.teams2"],
            summaryKey: "app-presets.summary.teams",
            suggestions: [
                AppPresetSuggestion(button: 4, titleKey: "app-presets.action.teams-mic", symbols: "⌘⇧M", effect: keyboardShortcut(keycode: 46, flags: 1179648)),
                AppPresetSuggestion(button: 5, titleKey: "app-presets.action.teams-camera", symbols: "⌘⇧O", effect: keyboardShortcut(keycode: 31, flags: 1179648)),
            ]),
        AppPreset(
            bundleIDs: ["com.google.Chrome"],
            summaryKey: "app-presets.summary.chrome",
            suggestions: [
                AppPresetSuggestion(button: 4, titleKey: "app-presets.action.chrome-back", symbols: "⌘←", effect: keyboardShortcut(keycode: 123, flags: 1048576)),
                AppPresetSuggestion(button: 5, titleKey: "app-presets.action.chrome-forward", symbols: "⌘→", effect: keyboardShortcut(keycode: 124, flags: 1048576)),
            ]),
    ]

    static func preset(for bundleID: String) -> AppPreset? {
        return all.first { $0.bundleIDs.contains(bundleID) }
    }

    /// A remap row for `app`, in the same shape as the rows the Buttons tab writes.
    static func remapRow(button: Int, effect: [String: Any], app: String) -> [String: Any] {
        return [
            "trigger": ["button": button, "duration": "click", "level": 1] as [String: Any],
            "modifiers": [String: Any](),
            "effect": effect,
            "app": app,
        ]
    }

    //
    // Comparing with the rows of a tab. Pure, so it can be tested on its own (see Tests/run_tests.sh).
    //

    /// Whether two rows have the same trigger and modifiers, so only one of them can be in a tab
    static func rowsHaveSameTrigger(_ row: [String: Any], _ otherRow: [String: Any]) -> Bool {
        let trigger = row["trigger"] as AnyObject?
        let otherTrigger = otherRow["trigger"] as AnyObject?
        let modifiers = row["modifiers"] as? NSDictionary ?? NSDictionary()
        let otherModifiers = otherRow["modifiers"] as? NSDictionary ?? NSDictionary()
        return (trigger?.isEqual(otherTrigger) ?? false) && modifiers.isEqual(otherModifiers)
    }

    /// Compares one row that would be written for `app` with `rows`. Only the rows of `app` count; global rows and rows of other apps are ignored.
    static func classify(_ row: [String: Any], against rows: [[String: Any]], app: String) -> AppPresetMatch {
        for (index, existing) in rows.enumerated() {
            guard (existing["app"] as? String) == app, rowsHaveSameTrigger(existing, row) else { continue }
            let effect = row["effect"] as? NSDictionary
            let existingEffect = existing["effect"] as? NSDictionary
            if let effect, let existingEffect, effect.isEqual(existingEffect) { return .same }
            return .conflict(rowIndex: index)
        }
        return .new
    }

    /// Compares each suggestion of `preset`, as it would be written for `app`, with `rows`. One result per suggestion, in the same order.
    static func classify(_ preset: AppPreset, against rows: [[String: Any]], app: String) -> [AppPresetMatch] {
        return preset.suggestions.map { classify(remapRow(button: $0.button, effect: $0.effect, app: app), against: rows, app: app) }
    }

    private static func keyboardShortcut(keycode: Int, flags: Int) -> [String: Any] {
        return ["type": "keyboardShortcut", "keycode": keycode, "flags": flags]
    }

    //
    // "Don't suggest this again" for an app. Stored locally, not in the config file.
    //

    private static let dismissedKey = "AppPresets.dismissedBundleIDs"

    static func isDismissed(_ bundleID: String) -> Bool {
        return (UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []).contains(bundleID)
    }

    static func setDismissed(_ bundleID: String) {
        var list = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        if !list.contains(bundleID) { list.append(bundleID) }
        UserDefaults.standard.set(list, forKey: dismissedKey)
    }
}
