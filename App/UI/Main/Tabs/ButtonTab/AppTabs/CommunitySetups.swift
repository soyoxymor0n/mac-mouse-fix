//
// --------------------------------------------------------------------------
// CommunitySetups.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import Foundation

/// Community setups are button setups for one app that other users shared in the public repository
///     https://github.com/soyoxymor0n/mac-mouse-fix-setups (one JSON file per setup under `setups/`).
/// This file holds the parts that don't need the app: the validator, the cached index and the conversion to a preset.
///     It only needs Foundation and AppPresets.swift, so it can be tested on its own (see Tests/run_community_tests.sh).
/// Phase 1 is read-only. Nothing is uploaded. See docs/features/community-sharing.md.

/// Where the setups come from. The URLs are the same for every user and never name an app.
enum CommunitySource {
    static let repository = "soyoxymor0n/mac-mouse-fix-setups"
    static let listingURL = URL(string: "https://api.github.com/repos/\(repository)/contents/setups?ref=main")!
    /// Files are only downloaded from this prefix, whatever the listing says
    static let downloadPrefix = "https://raw.githubusercontent.com/\(repository)/"
    static let repositoryWebURL = URL(string: "https://github.com/\(repository)")!
}

/// One setup file that passed the validator. `rows` holds only the rows that passed, rebuilt from the checked values.
struct CommunitySetup {
    /// Name of the file in the repository, for example `com.google.Chrome-tabs.json`
    let fileName: String
    let bundleID: String
    /// Localization key of the title. The repository only allows titles from a fixed list.
    let titleKey: String
    /// Remap rows in the same shape as the rows the Buttons tab writes
    let rows: [[String: Any]]
    /// Number of rows of the file that the validator rejected
    let rejectedRows: Int
}

/// What the validator makes of one setup file
enum CommunitySetupFileResult {
    case setup(CommunitySetup)
    /// The file uses a `schemaVersion` this version of the app doesn't know. It is skipped, not treated as an error.
    case newerFormat
    case invalid(String)
}

/// The setups of one app, and what was left out
struct CommunitySetupList {
    var setups: [CommunitySetup] = []
    /// Rows left out of the setups above, plus all rows of files that were rejected as a whole
    var rejectedRows = 0
    /// Files for this app that were rejected as a whole
    var rejectedFiles = 0
    /// Files (for any app) that use a newer format
    var newerFormatFiles = 0
}

/// The same rules as `scripts/validate.py` in the setups repository, plus a check that numbers are really integers.
///     The validator there is the source of truth. If it changes, change this too.
enum CommunitySetupValidator {

    static let schemaVersion = 1
    static let maxRows = 20
    static let maxBytes = 16 * 1024
    /// Command, Shift, Control and Option
    static let flagMask = 0x1E0000
    /// Command+Q, Command+Shift+Q and Command+Option+Escape (force quit)
    static let denylist: [(keycode: Int, flags: Int)] = [(12, 0x100000), (12, 0x120000), (53, 0x180000)]

    /// The fixed list of titles in the repository, with their localization keys
    static let titleKeys: [String: String] = [
        "Mic and camera": "community-setups.title.mic-and-camera",
        "Browser navigation": "community-setups.title.browser-navigation",
        "Tab switching": "community-setups.title.tab-switching",
        "Finder navigation": "community-setups.title.finder-navigation",
        "Other": "community-setups.title.other",
    ]

    private static let allowedTopKeys: Set<String> = ["schemaVersion", "bundleID", "title", "rows"]
    private static let allowedRowKeys: Set<String> = ["trigger", "modifiers", "effect", "app"]
    private static let triggerKeys: Set<String> = ["button", "duration", "level"]
    private static let effectKeys: Set<String> = ["type", "keycode", "flags"]

    static func isValidBundleID(_ bundleID: String) -> Bool {
        return bundleID.range(of: "^[A-Za-z0-9.-]{3,200}$", options: .regularExpression) != nil
    }

    /// Checks one setup file. Rows that fail are left out and counted. The file is rejected as a whole if its own fields are wrong, or if no row passes.
    static func parse(_ data: Data, fileName: String) -> CommunitySetupFileResult {
        if data.count > maxBytes { return .invalid("larger than 16 KB") }
        guard let object = try? JSONSerialization.jsonObject(with: data), let top = object as? [String: Any] else { return .invalid("not a JSON object") }
        guard let version = integer(top["schemaVersion"]) else { return .invalid("no schemaVersion") }
        if version > schemaVersion { return .newerFormat }
        if version != schemaVersion { return .invalid("unknown schemaVersion") }
        if !Set(top.keys).isSubset(of: allowedTopKeys) { return .invalid("unknown top-level keys") }
        guard let bundleID = top["bundleID"] as? String, isValidBundleID(bundleID) else { return .invalid("invalid bundleID") }
        guard let title = top["title"] as? String, let titleKey = titleKeys[title] else { return .invalid("title not in the fixed list") }
        guard let rows = top["rows"] as? [Any], (1...maxRows).contains(rows.count) else { return .invalid("rows must be 1 to \(maxRows) entries") }

        var validRows: [[String: Any]] = []
        for row in rows {
            if let validRow = validRow(row, bundleID: bundleID) { validRows.append(validRow) }
        }
        if validRows.isEmpty { return .invalid("no valid rows") }
        return .setup(CommunitySetup(fileName: fileName, bundleID: bundleID, titleKey: titleKey, rows: validRows, rejectedRows: rows.count - validRows.count))
    }

    /// Returns the row rebuilt from its checked values, or nil if it breaks a rule. Only the checked keys are copied.
    static func validRow(_ row: Any, bundleID: String) -> [String: Any]? {
        guard let row = row as? [String: Any], Set(row.keys).isSubset(of: allowedRowKeys) else { return nil }
        guard (row["app"] as? String) == bundleID else { return nil }
        guard let modifiers = row["modifiers"] as? [String: Any], modifiers.isEmpty else { return nil }

        guard let trigger = row["trigger"] as? [String: Any], Set(trigger.keys) == triggerKeys,
              let button = integer(trigger["button"]), (1...5).contains(button),
              let duration = trigger["duration"] as? String, duration == "click" || duration == "hold",
              let level = integer(trigger["level"]), (1...3).contains(level) else { return nil }

        guard let effect = row["effect"] as? [String: Any], Set(effect.keys) == effectKeys,
              (effect["type"] as? String) == "keyboardShortcut",
              let keycode = integer(effect["keycode"]), (0...127).contains(keycode),
              let flags = integer(effect["flags"]), flags >= 0, flags & ~flagMask == 0 else { return nil }
        if isDenied(keycode: keycode, flags: flags) { return nil }

        return AppPreset.remapRow(button: button, effect: ["type": "keyboardShortcut", "keycode": keycode, "flags": flags], app: bundleID, duration: duration, level: level)
    }

    static func isDenied(keycode: Int, flags: Int) -> Bool {
        return denylist.contains { $0.keycode == keycode && $0.flags == flags }
    }

    /// An integer from JSON. Booleans and numbers with a fraction are not integers.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), !CFNumberIsFloatType(number) else { return nil }
        return number.intValue
    }
}

/// The downloaded setup files, as cached in Application Support. The raw files are kept and checked again on every load,
///     so a stricter validator in a newer version of the app also applies to the cache.
struct CommunityIndex: Codable {

    struct File: Codable {
        let name: String
        /// Git blob SHA from the listing. A file is only downloaded again when it changes.
        let sha: String
        let content: String
    }

    /// Version of this cache format
    static let cacheVersion = 1

    var cacheVersion = CommunityIndex.cacheVersion
    /// When the listing was last checked with the server
    var fetchedAt: Date
    /// ETag of the listing. GitHub doesn't count a request that returns 304 Not Modified against the rate limit.
    var listingETag: String?
    var files: [File]

    /// The valid setups for one app. Every file is checked; a request never names an app.
    func setups(for bundleID: String) -> CommunitySetupList {
        var list = CommunitySetupList()
        for file in files {
            switch CommunitySetupValidator.parse(Data(file.content.utf8), fileName: file.name) {
            case .setup(let setup):
                guard setup.bundleID == bundleID else { continue }
                list.setups.append(setup)
                list.rejectedRows += setup.rejectedRows
            case .newerFormat:
                list.newerFormatFiles += 1
            case .invalid:
                /// The bundle ID of a rejected file is only known from its name: `<bundle ID>-<topic>.json`
                guard file.name.hasPrefix(bundleID + "-") else { continue }
                list.rejectedFiles += 1
                if let object = try? JSONSerialization.jsonObject(with: Data(file.content.utf8)) as? [String: Any], let rows = object["rows"] as? [Any] {
                    list.rejectedRows += rows.count
                }
            }
        }
        list.setups.sort { $0.fileName < $1.fileName }
        return list
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// nil if the data isn't a cache in a format this version knows
    static func decoded(from data: Data) -> CommunityIndex? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let index = try? decoder.decode(CommunityIndex.self, from: data), index.cacheVersion == cacheVersion else { return nil }
        return index
    }

    //
    // The listing of the `setups` folder, from the GitHub contents API
    //

    struct ListingEntry: Equatable {
        let name: String
        let sha: String
        let downloadURL: URL
    }

    /// Only `.json` files whose download URL points into the setups repository are kept
    static func listingEntries(from data: Data, allowedDownloadPrefix: String) -> [ListingEntry]? {
        guard let items = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        var entries: [ListingEntry] = []
        for case let item as [String: Any] in items {
            guard (item["type"] as? String) == "file",
                  let name = item["name"] as? String, name.hasSuffix(".json"),
                  let sha = item["sha"] as? String,
                  let urlString = item["download_url"] as? String, urlString.hasPrefix(allowedDownloadPrefix),
                  let url = URL(string: urlString) else { continue }
            if let size = item["size"] as? Int, size > CommunitySetupValidator.maxBytes { continue }
            entries.append(ListingEntry(name: name, sha: sha, downloadURL: url))
        }
        return entries
    }
}

extension CommunitySetup {

    /// The setup as a preset, so it goes through the same review sheet. `actionTitle` names a row's action in the sheet.
    func asPreset(actionTitle: ([String: Any]) -> String) -> AppPreset {
        let suggestions: [AppPresetSuggestion] = rows.compactMap { row in
            guard let trigger = row["trigger"] as? [String: Any], let effect = row["effect"] as? [String: Any],
                  let button = trigger["button"] as? Int else { return nil }
            return AppPresetSuggestion(button: button, titleKey: "", symbols: "", effect: effect,
                                       duration: trigger["duration"] as? String ?? "click", level: trigger["level"] as? Int ?? 1, title: actionTitle(row))
        }
        return AppPreset(bundleIDs: [bundleID], summaryKey: titleKey, suggestions: suggestions)
    }
}
