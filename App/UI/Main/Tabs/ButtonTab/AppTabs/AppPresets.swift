//
// --------------------------------------------------------------------------
// AppPresets.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import Foundation

/// Built-in button assignments for common apps. A preset is offered only in an app tab that has no rows yet,
/// and it is written only when the user clicks Add. Nothing is applied automatically, and nothing is sent anywhere.
struct AppPreset {
    
    /// Bundle IDs this preset applies to
    let bundleIDs: [String]
    /// Localization key of the short description shown in the banner
    let summaryKey: String
    /// Remap rows without an `app` key. The app's bundle ID is added when the preset is applied.
    let rows: [[String: Any]]
    
    /// Verified 2026-10-25.
    /// - Microsoft Teams (com.microsoft.teams2): button 4 toggles the mic (Cmd+Shift+M), button 5 the camera (Cmd+Shift+O).
    /// - Google Chrome (com.google.Chrome): button 4 goes back and button 5 forward, with Cmd+Left and Cmd+Right.
    ///   The arrow keys are not character keys, so the keyboard layout doesn't change them.
    static let all: [AppPreset] = [
        AppPreset(
            bundleIDs: ["com.microsoft.teams2"],
            summaryKey: "app-presets.summary.teams",
            rows: [
                row(button: 4, keycode: 46, flags: 1179648),
                row(button: 5, keycode: 31, flags: 1179648),
            ]),
        AppPreset(
            bundleIDs: ["com.google.Chrome"],
            summaryKey: "app-presets.summary.chrome",
            rows: [
                row(button: 4, keycode: 123, flags: 1048576),
                row(button: 5, keycode: 124, flags: 1048576),
            ]),
    ]
    
    static func preset(for bundleID: String) -> AppPreset? {
        return all.first { $0.bundleIDs.contains(bundleID) }
    }
    
    /// The rows to write into the scope of `bundleID`, with the `app` key set.
    func rows(forApp bundleID: String) -> [[String: Any]] {
        return rows.map { row in
            var r = row
            r["app"] = bundleID
            return r
        }
    }
    
    private static func row(button: Int, keycode: Int, flags: Int) -> [String: Any] {
        return [
            "trigger": ["button": button, "duration": "click", "level": 1] as [String: Any],
            "modifiers": [String: Any](),
            "effect": ["type": "keyboardShortcut", "keycode": keycode, "flags": flags] as [String: Any],
        ]
    }
}
