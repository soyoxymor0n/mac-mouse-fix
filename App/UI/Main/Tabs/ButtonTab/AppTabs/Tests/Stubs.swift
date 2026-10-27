//
// --------------------------------------------------------------------------
// Stubs.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

/// Stand-ins for the app code that AppTabs.swift uses, so it compiles on its own. Not part of the Xcode project.

import Foundation

let kMFConfigKeyAppTabs = "AppTabs"
let kMFConfigKeyRemaps = "Remaps"

func config(_ keyPath: String) -> NSObject? { return nil }
func setConfig(_ keyPath: String, _ value: NSObject) {}
func commitConfig() {}

func MFLocalizedString(_ key: String, comment: String) -> String { return key }

enum RemapScope {
    static func app(forRow row: [String: Any]) -> String? { return nil }
}
