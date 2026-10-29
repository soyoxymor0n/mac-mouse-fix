//
// --------------------------------------------------------------------------
// CommunitySetupsTests.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//
// Tests for the community setups validator and the cached index. Run with run_community_tests.sh in this folder.
//     The fixtures are in CommunityFixtures. Nothing is downloaded.

import Foundation

@main
struct CommunitySetupsTests {

    static var failures = 0

    static func expect(_ condition: Bool, _ name: String) {
        if condition {
            print("ok    \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static let chrome = "com.google.Chrome"

    static func row(button: Int = 4, duration: String = "click", level: Int = 1, type: String = "keyboardShortcut", keycode: Any = 13, flags: Any = 1048576, app: String = chrome) -> [String: Any] {
        return ["trigger": ["button": button, "duration": duration, "level": level], "modifiers": [String: Any](),
                "effect": ["type": type, "keycode": keycode, "flags": flags], "app": app]
    }

    static func isValid(_ row: [String: Any]) -> Bool {
        return CommunitySetupValidator.validRow(row, bundleID: chrome) != nil
    }

    static func main() {

        let fixtures = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "CommunityFixtures")

        //
        // Rows
        //

        expect(isValid(row()), "valid row passes")
        expect(isValid(row(duration: "hold", level: 3, keycode: 127, flags: 0x1E0000)), "hold, level 3, keycode 127 and all four modifiers pass")
        expect(!isValid(row(keycode: 128)), "keycode 128 fails")
        expect(!isValid(row(keycode: -1)), "negative keycode fails")
        expect(!isValid(row(flags: 0x100000 | 0x800000)), "flag outside 0x1E0000 fails")
        expect(!isValid(row(flags: 1)), "low flag bit fails")
        expect(!isValid(row(type: "symbolicHotkey")), "non-keyboardShortcut effect fails")
        expect(!isValid(row(keycode: 12, flags: 0x100000)), "denylist: Command+Q fails")
        expect(!isValid(row(keycode: 12, flags: 0x120000)), "denylist: Command+Shift+Q fails")
        expect(!isValid(row(keycode: 53, flags: 0x180000)), "denylist: Command+Option+Escape fails")
        expect(isValid(row(keycode: 12, flags: 0x40000)), "Control+Q is not on the denylist")
        expect(!isValid(row(button: 6)), "button 6 fails")
        expect(!isValid(row(duration: "double")), "duration other than click or hold fails")
        expect(!isValid(row(level: 4)), "level 4 fails")
        expect(!isValid(row(app: "com.apple.finder")), "row for another app fails")
        expect(!isValid(row(keycode: true)), "boolean keycode fails")
        expect(!isValid(row(keycode: 13.5)), "keycode with a fraction fails")

        var extraKey = row()
        extraKey["license"] = "x"
        expect(!isValid(extraKey), "unknown row key fails")
        var withModifiers = row()
        withModifiers["modifiers"] = ["buttonModifiers": [["button": 3, "level": 1]]]
        expect(!isValid(withModifiers), "row with modifiers fails")
        var extraEffectKey = row()
        extraEffectKey["effect"] = ["type": "keyboardShortcut", "keycode": 13, "flags": 1048576, "script": "x"]
        expect(!isValid(extraEffectKey), "unknown effect key fails")

        /// A valid row comes back in the same shape as a preset row
        let rebuilt = CommunitySetupValidator.validRow(row(), bundleID: chrome) ?? [:]
        let presetRow = AppPreset.remapRow(button: 4, effect: ["type": "keyboardShortcut", "keycode": 13, "flags": 1048576], app: chrome)
        expect((rebuilt as NSDictionary).isEqual(presetRow as NSDictionary), "valid row equals the preset row")

        //
        // Fixture index
        //

        guard let indexData = try? Data(contentsOf: fixtures.appendingPathComponent("index.json")),
              let index = CommunityIndex.decoded(from: indexData) else {
            print("FAIL  could not read the fixture index in \(fixtures.path)")
            exit(1)
        }
        expect(index.files.count == 6, "fixture index has 6 files")
        expect(index.listingETag == "W/\"fixture\"", "ETag is read")

        let list = index.setups(for: chrome)
        let names = list.setups.map { $0.fileName }
        expect(names == ["com.google.Chrome-back-forward.json", "com.google.Chrome-mixed.json"], "Chrome has two valid setups: \(names)")
        expect(list.rejectedFiles == 1, "the Command+Shift+Q file is rejected as a whole")
        expect(list.rejectedRows == 4, "3 rows of the mixed file and 1 row of the rejected file are counted: \(list.rejectedRows)")
        expect(list.newerFormatFiles == 1, "the schemaVersion 2 file is skipped as a newer format")

        if let mixed = list.setups.first(where: { $0.fileName == "com.google.Chrome-mixed.json" }) {
            expect(mixed.rows.count == 2 && mixed.rejectedRows == 3, "mixed file keeps 2 rows and rejects 3")
            expect(mixed.titleKey == "community-setups.title.other", "title maps to its localization key")
            let hold = mixed.rows[1]["trigger"] as? [String: Any]
            expect((hold?["duration"] as? String) == "hold", "hold trigger is kept")

            let preset = mixed.asPreset { _ in "title" }
            expect(preset.suggestions.count == 2 && preset.suggestions[1].duration == "hold", "setup converts to a preset with its triggers")
            let matches = AppPreset.classify(preset, against: [mixed.rows[0]], app: chrome)
            expect(matches == [.same, .new], "a row the tab already has is the same")
        } else {
            expect(false, "mixed setup is listed")
        }

        expect(index.setups(for: "com.apple.finder").setups.count == 1, "Finder has one setup")
        expect(index.setups(for: "com.example.none").setups.isEmpty, "unknown app has no setups")

        /// The cache survives a round trip
        if let data = try? index.encoded(), let again = CommunityIndex.decoded(from: data) {
            expect(again.files.map { $0.sha } == index.files.map { $0.sha } && again.fetchedAt == index.fetchedAt, "cache round trip")
        } else {
            expect(false, "cache round trip")
        }
        expect(CommunityIndex.decoded(from: Data("{\"cacheVersion\":99,\"fetchedAt\":\"2026-10-29T12:00:00Z\",\"files\":[]}".utf8)) == nil, "unknown cache version is ignored")

        //
        // Listing
        //

        /// The request never names an app: the listing URL is fixed, and every file of the listing is downloaded
        let listingURL = CommunitySource.listingURL.absoluteString
        expect(listingURL == "https://api.github.com/repos/soyoxymor0n/mac-mouse-fix-setups/contents/setups?ref=main", "listing URL is fixed")
        expect(![chrome, "com.apple.finder", "com.microsoft.teams2"].contains { listingURL.contains($0) }, "listing URL holds no bundle ID")

        let prefix = CommunitySource.downloadPrefix
        if let listingData = try? Data(contentsOf: fixtures.appendingPathComponent("listing.json")),
           let entries = CommunityIndex.listingEntries(from: listingData, allowedDownloadPrefix: prefix) {
            expect(entries.map { $0.name } == ["com.apple.finder-navigation.json", "com.google.Chrome-tabs.json"],
                   "listing keeps JSON files from the repository only: \(entries.map { $0.name })")
        } else {
            expect(false, "listing parses")
        }

        print("\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
