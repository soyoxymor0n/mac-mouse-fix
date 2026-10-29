//
// --------------------------------------------------------------------------
// CommunitySharing.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//
//
/// Phase 2 of community sharing: the user can share the rows of one app tab. See docs/features/community-sharing.md.
///     The submission goes to a Cloudflare Worker (tools/community-worker) that puts it in a review queue. Nothing is public until
///     the owner publishes it to the setups repository by hand.
/// This file holds the parts that don't need AppKit: the switch, the endpoint, the sensitive-app list, the submission builder,
///     the local list of shared setups with their delete tokens, and the uploader. It needs Foundation, AppPresets.swift and CommunitySetups.swift,
///     so it can be tested on its own (see Tests/run_community_tests.sh).

import Foundation

//
// MARK: Endpoint
//

/// Where shared setups are sent. The owner deploys the Worker and pastes its URL into `workerURL` (see tools/community-worker/README.md).
///     While it is the placeholder, sharing is shown as unavailable and nothing is sent.
enum CommunitySharingEndpoint {

    /// The base URL of the deployed Worker, for example `https://<name>.<subdomain>.workers.dev`, without a trailing path.
    ///     `example.invalid` is a reserved name that can never resolve, so the placeholder can't send anything by mistake.
    static let workerURL = "https://example.invalid/community"

    /// The Worker's base URL, or nil while the constant is still the placeholder or isn't HTTPS
    static var url: URL? { return url(from: workerURL) }

    static func url(from string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https", let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host == "example.invalid" || host.hasSuffix(".invalid") { return nil }
        return url
    }
}

//
// MARK: Switch
//

/// The one "Community setups" switch. It controls both downloading and sharing, and it is off by default.
///     Off: the "Community setups…" button is hidden, nothing is downloaded, and sharing is unavailable.
///     Stored in UserDefaults like the shortcut library switch, not in the config file.
enum CommunityConsent {

    static let defaultsKey = "CommunitySetups.enabled"
    /// Posted on the main thread when the switch changes
    static let didChangeNotification = Notification.Name("CommunitySetupsEnabledDidChange")

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        return defaults.bool(forKey: defaultsKey) /// false if never set
    }

    static func setEnabled(_ enabled: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

/// Whether sharing can be offered, in the order the reasons are checked
enum CommunitySharingAvailability: Equatable {
    case available
    /// The "Community setups" switch is off
    case switchOff
    /// No Worker URL is set in the app yet
    case notConfigured

    static func current(enabled: Bool, endpoint: URL?) -> CommunitySharingAvailability {
        if !enabled { return .switchOff }
        if endpoint == nil { return .notConfigured }
        return .available
    }
}

//
// MARK: Sensitive apps
//

/// Apps whose bundle ID can reveal health, dating, religious, political or financial information are never shared.
///     The Worker has the same list (tools/community-worker/src/validate.js); its tests check that both lists are equal.
///     The owner can extend both lists. Matching is case-insensitive.
enum CommunitySensitiveApps {

    /// A bundle ID that equals one of these, or starts with one followed by a dot, is excluded
    static let bundleIDPrefixes: [String] = [
        "com.apple.health",
        "com.cardify.tinder",
        "com.bumble",
        "co.hinge",
        "com.grindr",
        "com.okcupid",
        "com.match",
        "com.headspace",
        "com.calm",
        "com.betterhelp",
        "com.talkspace",
        "com.youversion",
        "com.muslimpro",
        "com.intuit",
        "com.paypal",
        "com.coinbase",
        "com.binance",
        "com.robinhood",
        "com.revolut",
        "de.number26",
        "com.moneymoney-app",
        "com.ledger",
    ]

    /// A bundle ID that contains one of these anywhere is excluded
    static let keywords: [String] = [
        "bank",
        "dating",
        "bible",
        "quran",
        "church",
        "mosque",
        "prayer",
        "health",
        "medical",
        "therapy",
        "fertility",
        "crypto",
        "bitcoin",
        "wallet",
        "election",
        "politic",
    ]

    static func isSensitive(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        if bundleIDPrefixes.contains(where: { id == $0 || id.hasPrefix($0 + ".") }) { return true }
        return keywords.contains { id.contains($0) }
    }
}

//
// MARK: Submission
//

/// The exact data that is sent for one app tab: the same format as a file in the setups repository, and nothing else.
///     `body` is what is sent, byte for byte, and `json` is the same bytes as text for the sheet.
struct CommunitySubmission {
    let bundleID: String
    let title: String
    /// Rows rebuilt from the checked values by the phase 1 validator, so no other key of the config can get in
    let rows: [[String: Any]]
    let body: Data

    var json: String { return String(decoding: body, as: UTF8.self) }

    /// Why a tab can't be shared
    enum Problem: Error, Equatable {
        case invalidBundleID
        case sensitiveApp
        case invalidTitle
        case noRows
        case tooManyRows(Int)
        /// This many rows break a rule of the validator (keycode, flags, effect type, modifiers, denylisted key combination)
        case invalidRows(Int)
        case tooLarge
    }

    /// Titles a submission can have, as in the repository
    static let titles: [String] = ["Mic and camera", "Browser navigation", "Tab switching", "Finder navigation", "Other"]

    /// Builds the submission from the rows of one app tab. Refuses if any row fails the phase 1 rules.
    static func build(bundleID: String, title: String, tabRows: [[String: Any]]) -> Result<CommunitySubmission, Problem> {
        guard CommunitySetupValidator.isValidBundleID(bundleID) else { return .failure(.invalidBundleID) }
        if CommunitySensitiveApps.isSensitive(bundleID) { return .failure(.sensitiveApp) }
        guard CommunitySetupValidator.titleKeys[title] != nil else { return .failure(.invalidTitle) }
        if tabRows.isEmpty { return .failure(.noRows) }
        if tabRows.count > CommunitySetupValidator.maxRows { return .failure(.tooManyRows(tabRows.count)) }

        var rows: [[String: Any]] = []
        var invalid = 0
        for row in tabRows {
            if let checked = CommunitySetupValidator.validRow(row, bundleID: bundleID) { rows.append(checked) } else { invalid += 1 }
        }
        if invalid > 0 { return .failure(.invalidRows(invalid)) }

        let object: [String: Any] = ["schemaVersion": CommunitySetupValidator.schemaVersion, "bundleID": bundleID, "title": title, "rows": rows]
        guard let body = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return .failure(.invalidRows(rows.count)) }
        if body.count > CommunitySetupValidator.maxBytes { return .failure(.tooLarge) }

        /// The bytes must pass the same validator the download uses, with no row left out
        guard case .setup(let parsed) = CommunitySetupValidator.parse(body, fileName: "submission.json"), parsed.rejectedRows == 0 else { return .failure(.invalidRows(rows.count)) }

        return .success(CommunitySubmission(bundleID: bundleID, title: title, rows: rows, body: body))
    }
}

//
// MARK: Shared setups on this Mac
//

/// One setup this Mac shared. The delete token is the only way to delete it from the server.
struct SharedSetupRecord: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let id: String
    let bundleID: String
    let title: String
    let sharedAt: Date
    let deleteToken: String

    /// Never prints the token, so a record can't leak it into a log
    var description: String { return "SharedSetupRecord(id: \(id), bundleID: \(bundleID), title: \(title))" }
    var debugDescription: String { return description }
}

/// The list of shared setups and their delete tokens, in a JSON file in the app's Application Support folder.
///     Not in the config file (which can be exported) and not in UserDefaults. The file is readable by this user only.
final class SharedSetupStore {

    static let fileName = "CommunitySharedSetups.json"
    static let formatVersion = 1

    private struct File: Codable {
        var version: Int
        var records: [SharedSetupRecord]
    }

    let url: URL

    init(url: URL) {
        self.url = url
    }

    func records() -> [SharedSetupRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.version == SharedSetupStore.formatVersion else { return [] }
        return file.records
    }

    func add(_ record: SharedSetupRecord) throws {
        var list = records().filter { $0.id != record.id }
        list.append(record)
        try write(list)
    }

    func remove(id: String) throws {
        try write(records().filter { $0.id != id })
    }

    private func write(_ records: [SharedSetupRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(File(version: SharedSetupStore.formatVersion, records: records))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

//
// MARK: Uploader
//

/// Sends submissions and delete requests to the Worker. HTTPS only, a JSON body, a 10-second timeout,
///     and no credentials, cookies or cache. Nothing about the Mac is sent: no app version, no device data, no custom headers.
///     A submission first checks the switch and the endpoint, so nothing is sent while either is missing. A delete request only needs the endpoint.
///     Completions are called on a background queue.
final class CommunityUploader {

    static let timeout: TimeInterval = 10

    enum Failure: Error, Equatable {
        case switchOff
        case notConfigured
        /// The server couldn't be reached, or the request timed out
        case network
        /// The server rejected the submission as invalid
        case rejected
        /// No record with that ID and token (delete only)
        case notFound
        case server(Int)
        case badResponse
    }

    struct Receipt: Equatable {
        let id: String
        let deleteToken: String
    }

    private let endpoint: URL?
    private let isEnabled: () -> Bool
    private let session: URLSession

    init(endpoint: URL? = CommunitySharingEndpoint.url, isEnabled: @escaping () -> Bool = { CommunityConsent.isEnabled() }, session: URLSession = CommunityUploader.makeSession()) {
        self.endpoint = endpoint
        self.isEnabled = isEnabled
        self.session = session
    }

    /// `protocolClasses` is for tests, to answer requests without a network
    static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        if let protocolClasses { configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? []) }
        return URLSession(configuration: configuration)
    }

    var availability: CommunitySharingAvailability {
        return .current(enabled: isEnabled(), endpoint: endpoint)
    }

    /// The request for `path` with `body`, or why there is none. Only HTTPS.
    ///     `needsSwitch` is false for deleting: withdrawing must stay possible after the switch is turned off.
    func request(path: String, body: Data, needsSwitch: Bool = true) -> Result<URLRequest, Failure> {
        switch availability {
        case .switchOff where needsSwitch: return .failure(.switchOff)
        case .notConfigured: return .failure(.notConfigured)
        default: break
        }
        guard let endpoint, endpoint.scheme == "https" else { return .failure(.notConfigured) }
        var request = URLRequest(url: endpoint.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: CommunityUploader.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = false
        request.httpBody = body
        return .success(request)
    }

    /// Sends `submission.body` as it is. On success the receipt holds the record ID and the delete token.
    func submit(_ submission: CommunitySubmission, completion: @escaping (Result<Receipt, Failure>) -> Void) {
        let request: URLRequest
        switch self.request(path: "submit", body: submission.body) {
        case .failure(let failure): completion(.failure(failure)); return
        case .success(let r): request = r
        }
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let response = response as? HTTPURLResponse else { completion(.failure(.network)); return }
            switch response.statusCode {
            case 200, 201:
                guard let data, let receipt = CommunityUploader.receipt(from: data) else { completion(.failure(.badResponse)); return }
                completion(.success(receipt))
            case 400, 413, 415, 422: completion(.failure(.rejected))
            default: completion(.failure(.server(response.statusCode)))
            }
        }.resume()
    }

    /// Asks the server to delete one record. Works with the switch off, so a user can always withdraw a setup.
    func delete(id: String, token: String, completion: @escaping (Result<Void, Failure>) -> Void) {
        guard let body = try? JSONSerialization.data(withJSONObject: ["id": id, "token": token], options: [.sortedKeys]) else { completion(.failure(.badResponse)); return }
        let request: URLRequest
        switch self.request(path: "delete", body: body, needsSwitch: false) {
        case .failure(let failure): completion(.failure(failure)); return
        case .success(let r): request = r
        }
        session.dataTask(with: request) { _, response, error in
            guard error == nil, let response = response as? HTTPURLResponse else { completion(.failure(.network)); return }
            switch response.statusCode {
            case 200, 204: completion(.success(()))
            case 404: completion(.failure(.notFound))
            default: completion(.failure(.server(response.statusCode)))
            }
        }.resume()
    }

    /// The Worker answers a submission with `{"id": "...", "deleteToken": "...", ...}`
    static func receipt(from data: Data) -> Receipt? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String, !id.isEmpty, id.count <= 64,
              let token = object["deleteToken"] as? String, !token.isEmpty, token.count <= 128 else { return nil }
        return Receipt(id: id, deleteToken: token)
    }
}
