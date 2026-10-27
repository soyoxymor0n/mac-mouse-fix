//
// --------------------------------------------------------------------------
// AppPresetsTests.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//
// Tests for `AppPreset.classify`. Run with run_tests.sh in this folder.

import Foundation

@main
struct AppPresetsTests {

    static var failures = 0

    static func expect(_ actual: [AppPresetMatch], _ expected: [AppPresetMatch], _ name: String) {
        if actual == expected {
            print("ok    \(name)")
        } else {
            failures += 1
            print("FAIL  \(name): got \(actual), expected \(expected)")
        }
    }

    static func main() {

        let teams = "com.microsoft.teams2"
        guard let preset = AppPreset.preset(for: teams) else {
            print("FAIL  no Teams preset")
            print("1 failures")
            exit(1)
        }
        let mic = preset.suggestions[0]   /// Button 4
        let camera = preset.suggestions[1] /// Button 5
        let otherEffect: [String: Any] = ["type": "keyboardShortcut", "keycode": 0, "flags": 1048576]

        /// Empty tab: everything is new
        expect(AppPreset.classify(preset, against: [], app: teams), [.new, .new], "empty tab")

        /// An identical row is the same, the other suggestion is still new
        let identical = AppPreset.remapRow(button: mic.button, effect: mic.effect, app: teams)
        expect(AppPreset.classify(preset, against: [identical], app: teams), [.same, .new], "identical row")

        /// A row read back from config has NSNumber values. It still counts as the same.
        let fromConfig = (identical as NSDictionary).mutableCopy() as! NSMutableDictionary
        fromConfig["effect"] = NSDictionary(dictionary: ["type": "keyboardShortcut", "keycode": NSNumber(value: 46), "flags": NSNumber(value: 1179648)])
        expect(AppPreset.classify(preset, against: [fromConfig as! [String: Any]], app: teams), [.same, .new], "identical row from config")

        /// Same trigger, different action: a conflict with that row
        let conflicting = AppPreset.remapRow(button: camera.button, effect: otherEffect, app: teams)
        expect(AppPreset.classify(preset, against: [identical, conflicting], app: teams), [.same, .conflict(rowIndex: 1)], "same trigger, different action")

        /// Same button but with a modifier: a different trigger, so new
        var withModifier = AppPreset.remapRow(button: mic.button, effect: otherEffect, app: teams)
        withModifier["modifiers"] = ["buttonModifiers": [["button": 3, "level": 1]]]
        expect(AppPreset.classify(preset, against: [withModifier], app: teams), [.new, .new], "row with modifiers")

        /// Rows of another app and global rows never conflict
        let otherApp = AppPreset.remapRow(button: mic.button, effect: otherEffect, app: "com.google.Chrome")
        var global = AppPreset.remapRow(button: camera.button, effect: otherEffect, app: teams)
        global.removeValue(forKey: "app")
        expect(AppPreset.classify(preset, against: [otherApp, global], app: teams), [.new, .new], "row for another app and global row")

        print("\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
