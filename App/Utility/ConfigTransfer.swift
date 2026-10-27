//
// --------------------------------------------------------------------------
// ConfigTransfer.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import AppKit

/// Exports the settings to a JSON file and imports them again.
///
/// File format (`formatVersion` 1):
/// ```
/// {
///   "format": "mac-mouse-fix-settings",
///   "formatVersion": 1,
///   "appVersion": "3.1.0", "appBuild": "...", "configVersion": 24, "exportedAt": "2026-10-27T10:00:00Z",
///   "settings": { "General": {...}, "Pointer": {...}, "Scroll": {...}, "Remaps": [...], "AppTabs": [...] }
/// }
/// ```
/// - `settings` holds every top-level config section except the ones in `excludedSections`. New sections in later versions are exported without changes here.
/// - Plist types that JSON doesn't have are wrapped: data as `{"$data": "<base64>"}`, dates as `{"$date": "<ISO 8601>"}`.
/// - `formatVersion` only changes if the wrapper changes. Changes to the settings themselves are tracked by `configVersion`.
///
/// Import starts from the default config, so keys the file doesn't have get their default value. Keys the file has replace the default if the type fits.
/// Keys the defaults don't have (e.g. `AppTabs`, or keys from a newer version) are kept. `State`, `License` and `Constants` of the current config are never touched.
@objc class ConfigTransfer: NSObject {

    static let formatID = "mac-mouse-fix-settings"
    static let formatVersion = 1

    /// Machine state, license caches and default presets. These belong to this Mac and this app version, not to the user's settings.
    static let excludedSections: Set<String> = ["State", "License", "Constants", kMFConfigKeyAppOverrides]

    enum TransferError: LocalizedError {
        case notASettingsFile
        case unsupportedFormatVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notASettingsFile: return MFLocalizedString("settings-transfer.error.not-a-settings-file", comment: "")
            case .unsupportedFormatVersion: return MFLocalizedString("settings-transfer.error.newer-format", comment: "")
            }
        }
    }

    //
    // MARK: Menu
    //

    /// Adds a File menu with Export and Import after the app menu
    @objc static func installMenuItems() {
        guard let mainMenu = NSApp.mainMenu, mainMenu.item(withTitle: MFLocalizedString("settings-transfer.menu.file", comment: "")) == nil else { return }

        let fileMenu = NSMenu(title: MFLocalizedString("settings-transfer.menu.file", comment: ""))
        let exportItem = fileMenu.addItem(withTitle: MFLocalizedString("settings-transfer.menu.export", comment: ""), action: #selector(exportSettings(_:)), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        exportItem.target = self
        let importItem = fileMenu.addItem(withTitle: MFLocalizedString("settings-transfer.menu.import", comment: ""), action: #selector(importSettings(_:)), keyEquivalent: "i")
        importItem.keyEquivalentModifierMask = [.command, .shift]
        importItem.target = self

        let fileItem = NSMenuItem(title: fileMenu.title, action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        mainMenu.insertItem(fileItem, at: min(1, mainMenu.numberOfItems))
    }

    //
    // MARK: Actions
    //

    @objc static func exportSettings(_ sender: Any?) {

        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        let date = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        panel.nameFieldStringValue = "Mac Mouse Fix Settings \(date).json"

        let write = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            do {
                try exportData().write(to: url, options: .atomic)
            } catch {
                showError(error)
            }
        }
        if let window = MainAppState.shared.window { panel.beginSheetModal(for: window, completionHandler: write) }
        else { write(panel.runModal()) }
    }

    @objc static func importSettings(_ sender: Any?) {

        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.allowsMultipleSelection = false

        let read = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            do {
                let file = try parse(try Data(contentsOf: url))
                confirmImport(file) { apply(file) }
            } catch {
                showError(error)
            }
        }
        if let window = MainAppState.shared.window { panel.beginSheetModal(for: window, completionHandler: read) }
        else { read(panel.runModal()) }
    }

    //
    // MARK: Export
    //

    static func exportData() throws -> Data {

        let config = Config.shared().config as NSDictionary? ?? [:]

        var settings: [String: Any] = [:]
        for case let (key as String, value) in config where !excludedSections.contains(key) {
            settings[key] = toJSON(value)
        }

        let info = Bundle.main.infoDictionary ?? [:]
        let file: [String: Any] = [
            "format": formatID,
            "formatVersion": formatVersion,
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "",
            "appBuild": info["CFBundleVersion"] as? String ?? "",
            "configVersion": currentConfigVersion(),
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "settings": settings,
        ]
        return try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys])
    }

    //
    // MARK: Import
    //

    struct SettingsFile {
        var appVersion: String
        var configVersion: Int
        var settings: [String: Any]
    }

    static func parse(_ data: Data) throws -> SettingsFile {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == formatID,
              let settings = root["settings"] as? [String: Any]
        else { throw TransferError.notASettingsFile }

        let version = root["formatVersion"] as? Int ?? 0
        if version > formatVersion { throw TransferError.unsupportedFormatVersion(version) }

        return SettingsFile(appVersion: root["appVersion"] as? String ?? "",
                            configVersion: root["configVersion"] as? Int ?? 0,
                            settings: settings.mapValues { fromJSON($0) })
    }

    /// Builds the config that an import of `file` produces. Doesn't change anything.
    static func mergedConfig(_ file: SettingsFile, current: NSDictionary, defaults: NSDictionary) throws -> NSMutableDictionary {

        let result = NSMutableDictionary()

        /// Machine state stays as it is
        for case let (key as String, value) in current where excludedSections.contains(key) {
            result[key] = value
        }
        /// Settings start from the defaults
        for case let (key as String, value) in defaults where !excludedSections.contains(key) {
            result[key] = value
        }
        /// Then the file's values are applied
        for (key, value) in migrated(file.settings, from: file.configVersion) where !excludedSections.contains(key) {
            result[key] = merge(value, onto: result[key])
        }

        /// Round trip through plist: gives mutable containers all the way down, which `setConfig()` needs, and fails if anything isn't a plist type
        let data = try PropertyListSerialization.data(fromPropertyList: result, format: .binary, options: 0)
        guard let merged = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? NSMutableDictionary
        else { throw TransferError.notASettingsFile }

        /// Otherwise the first enable after a reset replaces the imported rows with the default rows (see `ButtonTabController.initRemaps()`)
        if file.settings[kMFConfigKeyRemaps] != nil {
            merged.setObject(true as NSNumber, forCoolKeyPath: "State.remapsAreInitialized")
        }

        return merged
    }

    /// Hook for future config versions that change the shape of an exported section.
    ///     Steps go here in the style of `_loadAndRepair()` in Config.m. None are needed up to configVersion 24: versions 21 to 24 only changed `License` and `Constants`.
    static func migrated(_ settings: [String: Any], from configVersion: Int) -> [String: Any] {
        return settings
    }

    private static func confirmImport(_ file: SettingsFile, onConfirm: @escaping () -> Void) {

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = MFLocalizedString("settings-transfer.import.alert.title", comment: "")
        var message = MFLocalizedString("settings-transfer.import.alert.message", comment: "")
        if file.configVersion > currentConfigVersion() {
            message += "\n\n" + String(format: MFLocalizedString("settings-transfer.import.alert.newer-version", comment: ""), file.appVersion)
        }
        alert.informativeText = message
        _ = alert.addButton(withTitle: MFLocalizedString("settings-transfer.import.alert.confirm", comment: ""))
        _ = alert.addButton(withTitle: MFLocalizedString("settings-transfer.import.alert.cancel", comment: ""))

        let handle = { (response: NSApplication.ModalResponse) in
            if response == .alertFirstButtonReturn { onConfirm() }
        }
        if let window = MainAppState.shared.window { alert.beginSheetModal(for: window, completionHandler: handle) }
        else { handle(alert.runModal()) }
    }

    private static func apply(_ file: SettingsFile) {

        guard let current = Config.shared().config, let defaults = defaultConfig() else { return }
        do {
            Config.shared().config = try mergedConfig(file, current: current, defaults: defaults)
        } catch {
            showError(error)
            return
        }
        commitConfig()

        /// The button tab reads the remaps when it reloads. The other tabs follow `ReactiveConfig`.
        if let buttonTab = MainAppState.shared.buttonTabController {
            buttonTab.refreshAppTabStrip()
            buttonTab.selectScope(nil)
        }
    }

    //
    // MARK: JSON <-> plist values
    //

    static func toJSON(_ value: Any) -> Any {
        switch value {
        case let dict as NSDictionary:
            var result: [String: Any] = [:]
            for case let (key as String, v) in dict { result[key] = toJSON(v) }
            return result
        case let array as NSArray:
            return array.map { toJSON($0) }
        case let data as Data:
            return ["$data": data.base64EncodedString()]
        case let date as Date:
            return ["$date": ISO8601DateFormatter().string(from: date)]
        default:
            return value
        }
    }

    static func fromJSON(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            if dict.count == 1, let base64 = dict["$data"] as? String, let data = Data(base64Encoded: base64) { return data }
            if dict.count == 1, let string = dict["$date"] as? String, let date = ISO8601DateFormatter().date(from: string) { return date }
            return dict.mapValues { fromJSON($0) }
        case let array as [Any]:
            return array.map { fromJSON($0) }
        default:
            return value
        }
    }

    /// Applies `value` onto the default value `base`.
    ///     Dictionaries are merged key by key. A value whose type doesn't match the default is dropped, so a broken or foreign file can't put a string where the app reads a number.
    static func merge(_ value: Any, onto base: Any?) -> Any {
        guard let base = base else { return value }

        switch (value, base) {
        case let (dict as [String: Any], baseDict as NSDictionary):
            let result = NSMutableDictionary(dictionary: baseDict)
            for (key, v) in dict { result[key] = merge(v, onto: baseDict[key]) }
            return result
        case let (number as NSNumber, baseNumber as NSNumber):
            if isBool(baseNumber) != isBool(number) { return base }
            /// JSON writes 1.0 as 1. Keep it a real number where the default is one.
            if CFNumberIsFloatType(baseNumber) && !CFNumberIsFloatType(number) { return NSNumber(value: number.doubleValue) }
            return number
        case (is [Any], is NSArray), (is String, is NSString), (is Data, is NSData), (is Date, is NSDate):
            return value
        default:
            return base
        }
    }

    private static func isBool(_ number: NSNumber) -> Bool {
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    //
    // MARK: Helpers
    //

    private static func defaultConfig() -> NSDictionary? {
        guard let url = Bundle.main.url(forResource: "default_config", withExtension: "plist") else { return nil }
        return NSDictionary(contentsOf: url)
    }

    private static func currentConfigVersion() -> Int {
        return (config("Constants.configVersion") as? NSNumber)?.intValue ?? 0
    }

    private static func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = MFLocalizedString("settings-transfer.error.title", comment: "")
        alert.informativeText = error.localizedDescription
        if let window = MainAppState.shared.window { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }
}
