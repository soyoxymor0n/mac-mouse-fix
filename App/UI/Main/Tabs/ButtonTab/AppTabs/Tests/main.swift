//
// --------------------------------------------------------------------------
// main.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

/// Checks the problem report link of AppTabs.swift.
///     Run with `./run_tests.sh`. It compiles the real AppTabs.swift with Stubs.swift. Not part of the Xcode project.

import Foundation

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if !condition { failures += 1; print("FAIL: \(message)") }
}

let url = AppTabs.problemReportURL(appName: "Notepad++ & Co", bundleID: "com.example.Notepad",
                                   appVersion: "3.0.1 (25000)", macOSVersion: "Version 26.1 (Build 25B78)",
                                   keyboardLayout: "com.apple.keylayout.Austrian")
check(url != nil, "no URL")

if let url = url {
    let string = url.absoluteString
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let title = items.first { $0.name == "title" }?.value
    let body = items.first { $0.name == "body" }?.value ?? ""

    check(string.hasPrefix("https://github.com/\(AppTabs.issueRepository)/issues/new?"), "wrong base: \(string)")
    check(query.contains("com.example.Notepad"), "bundle ID missing from the query")
    check(!string.contains(" "), "unencoded space")
    check(!query.contains("+"), "unencoded plus")
    check(title == "Shortcut problem: Notepad++ & Co", "wrong title: \(title ?? "nil")")
    check(items.count == 2, "expected only title and body")

    let expectedOrder = ["App: Notepad++ & Co", "Bundle ID: com.example.Notepad", "Mac Mouse Fix NG version: 3.0.1 (25000)",
                         "macOS: Version 26.1 (Build 25B78)", "Keyboard layout: com.apple.keylayout.Austrian",
                         "Which shortcut doesn't work:", "What happens:", "What you expected:",
                         "https://github.com/\(AppTabs.issueRepository)/blob/beta/docs/faq.md"]
    var searchStart = body.startIndex
    for line in expectedOrder {
        guard let range = body.range(of: line, range: searchStart..<body.endIndex) else { check(false, "body missing or out of order: \(line)"); continue }
        searchStart = range.upperBound
    }
}

print("\(failures) failures")
exit(failures == 0 ? 0 : 1)
