//
// --------------------------------------------------------------------------
// AppTabs.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import Carbon

/// The per-app tabs of the Buttons tab.
///     The tab list is stored in `kMFConfigKeyAppTabs`. The rows of an app are stored in `kMFConfigKeyRemaps`, with an `app` key.
///     An app gets a tab if it's in the stored list, or if it has rows (for example after a hand edit of config.plist).
enum AppTabs {

    /// The stored tab list, in the order the tabs were added
    static func storedBundleIDs() -> [String] {
        return (config(kMFConfigKeyAppTabs) as? [String]) ?? []
    }

    /// The stored tab list, plus apps that have rows but aren't in the list. Those rows must never be hidden.
    static func allBundleIDs() -> [String] {
        var bundleIDs = storedBundleIDs()
        let remaps = (config(kMFConfigKeyRemaps) as? [[String: Any]]) ?? []
        for remap in remaps {
            guard let app = RemapScope.app(forRow: remap) else { continue }
            if !bundleIDs.contains(app) { bundleIDs.append(app) }
        }
        return bundleIDs
    }

    static func save(_ bundleIDs: [String]) {
        setConfig(kMFConfigKeyAppTabs, bundleIDs as NSArray)
        commitConfig()
    }

    /// The app's localized name. Falls back to the bundle ID if the app isn't installed.
    static func name(for bundleID: String) -> String {
        guard let url = appURL(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// The app's icon. Falls back to a generic icon if the app isn't installed.
    static func icon(for bundleID: String) -> NSImage {
        if let url = appURL(for: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    static func appURL(for bundleID: String) -> URL? {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The repository that problem reports go to, as "owner/name"
    static let issueRepository = "soyoxymor0n/mac-mouse-fix-ng"

    /// A "new issue" link on GitHub for a problem with the shortcuts of an app. Pre-fills the fields of `problemReportURL(appName:bundleID:appVersion:macOSVersion:keyboardLayout:)`.
    static func problemReportURL(for bundleID: String) -> URL? {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "?"
        let buildVersion = info["CFBundleVersion"] as? String ?? "?"
        return problemReportURL(appName: name(for: bundleID),
                                bundleID: bundleID,
                                appVersion: "\(shortVersion) (\(buildVersion))",
                                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                keyboardLayout: currentKeyboardLayoutID() ?? "unknown")
    }

    /// Builds the link from plain values.
    ///     Privacy: the report contains only these fields. Don't add rows, the config, paths, the user name, the device, the license or other settings.
    static func problemReportURL(appName: String, bundleID: String, appVersion: String, macOSVersion: String, keyboardLayout: String) -> URL? {
        let body = """
            App: \(appName)
            Bundle ID: \(bundleID)
            Mac Mouse Fix NG version: \(appVersion)
            macOS: \(macOSVersion)
            Keyboard layout: \(keyboardLayout)

            Which shortcut doesn't work:


            What happens:


            What you expected:


            FAQ: https://github.com/\(issueRepository)/blob/beta/docs/faq.md
            """
        guard var components = URLComponents(string: "https://github.com/\(issueRepository)/issues/new") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "title", value: "Shortcut problem: \(appName)"),
            URLQueryItem(name: "body", value: body),
        ]
        /// `queryItems` leaves "+" as is, and GitHub would read it as a space
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// The ID of the current keyboard layout, for example "com.apple.keylayout.German"
    private static func currentKeyboardLayoutID() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }

    /// Lets the user pick any app from the Applications folder. Calls `completion` with the bundle ID.
    static func chooseApp(in window: NSWindow, completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = MFLocalizedString("app-tabs.picker.open-panel.message", comment: "")
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [UTType.application]
        } else {
            panel.allowedFileTypes = ["app"]
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK,
                  let url = panel.url,
                  let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            completion(bundleID)
        }
    }
}
