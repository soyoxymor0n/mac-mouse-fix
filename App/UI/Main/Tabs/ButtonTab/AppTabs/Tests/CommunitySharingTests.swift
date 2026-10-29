//
// --------------------------------------------------------------------------
// CommunitySharingTests.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//
// Tests for phase 2 (sharing): the switch, the endpoint, the sensitive-app list, the submission builder, the delete token store
//     and the uploader. Run with run_community_tests.sh. No request leaves the process: a URLProtocol stub answers them.

import Foundation

/// Answers every request of the test session and records it. Never touches the network.
final class StubWorker: URLProtocol {

    static let lock = NSLock()
    static var requests: [(url: URL, method: String, body: Data, headers: [String: String])] = []
    /// Status code for the next responses, and the JSON they return
    static var status = 201
    static var responseBody = Data("{\"id\":\"rec_1\",\"deleteToken\":\"tok_secret\",\"status\":\"pending\",\"license\":\"CC0-1.0\"}".utf8)

    static func reset(status: Int = 201) {
        lock.lock(); requests = []; self.status = status; lock.unlock()
    }
    static var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }

    override class func canInit(with request: URLRequest) -> Bool { return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        StubWorker.lock.lock()
        StubWorker.requests.append((request.url!, request.httpMethod ?? "", body, request.allHTTPHeaderFields ?? [:]))
        let status = StubWorker.status
        let responseBody = StubWorker.responseBody
        StubWorker.lock.unlock()

        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if status != 204 { client?.urlProtocol(self, didLoad: responseBody) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension CommunitySetupsTests {

    /// Waits for an uploader completion, at most 5 seconds
    static func wait<T>(_ start: (@escaping (T) -> Void) -> Void) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var value: T?
        start { result in value = result; semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 5)
        return value
    }

    static func sharingTests(scratch: URL) {

        //
        // Endpoint
        //

        expect(CommunitySharingEndpoint.workerURL == "https://mmf-community.buildfolio.workers.dev", "the endpoint constant is the deployed Worker")
        expect(CommunitySharingEndpoint.url == CommunitySharingEndpoint.url(from: CommunitySharingEndpoint.workerURL), "the endpoint is the constant")
        expect(CommunitySharingEndpoint.url(from: "https://example.invalid/community") == nil, "the placeholder counts as not configured")
        expect(CommunitySharingEndpoint.url(from: "http://worker.example.com") == nil, "plain HTTP is refused")
        expect(CommunitySharingEndpoint.url(from: "") == nil, "an empty URL is refused")
        expect(CommunitySharingEndpoint.url(from: "https://mmf-community.someone.workers.dev") != nil, "an HTTPS Worker URL is accepted")

        //
        // Switch
        //

        let suite = "CommunitySharingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(!CommunityConsent.isEnabled(defaults), "the switch is off by default")
        CommunityConsent.setEnabled(true, defaults)
        expect(CommunityConsent.isEnabled(defaults), "the switch turns on")
        CommunityConsent.setEnabled(false, defaults)
        expect(!CommunityConsent.isEnabled(defaults), "the switch turns off")

        let testEndpoint = URL(string: "https://worker.test")!
        expect(CommunitySharingAvailability.current(enabled: false, endpoint: testEndpoint) == .switchOff, "switch off: sharing unavailable, even with an endpoint")
        expect(CommunitySharingAvailability.current(enabled: true, endpoint: nil) == .notConfigured, "no endpoint: sharing unavailable")
        expect(CommunitySharingAvailability.current(enabled: true, endpoint: testEndpoint) == .available, "switch on and endpoint set: sharing available")

        //
        // Sensitive apps
        //

        for id in ["com.apple.Health", "com.cardify.tinder", "com.bumble.app", "com.intuit.QuickBooks", "com.example.MyBank", "org.example.BibleReader",
                   "com.example.cryptowallet", "com.example.Dating", "com.example.ElectionTracker", "COM.PAYPAL.desktop"] {
            expect(CommunitySensitiveApps.isSensitive(id), "sensitive: \(id)")
        }
        for id in ["com.google.Chrome", "com.microsoft.teams2", "com.apple.finder", "com.apple.Safari", "us.zoom.xos", "com.tinyspeck.slackmacgap",
                   "com.spotify.client", "com.figma.Desktop", "com.microsoft.VSCode", "com.matchbox.app"] {
            expect(!CommunitySensitiveApps.isSensitive(id), "not sensitive: \(id)")
        }

        //
        // Submission builder
        //

        let tabRows = [row(), row(button: 5, keycode: 14, flags: 0x120000), row(button: 3, duration: "hold", level: 2, keycode: 46, flags: 0x40000)]
        guard case .success(let submission) = CommunitySubmission.build(bundleID: chrome, title: "Tab switching", tabRows: tabRows) else {
            expect(false, "a valid tab builds a submission")
            return
        }
        expect(submission.rows.count == 3, "all three rows are in the submission")
        let object = (try? JSONSerialization.jsonObject(with: submission.body)) as? [String: Any] ?? [:]
        expect(Set(object.keys) == ["schemaVersion", "bundleID", "title", "rows"], "the submission has only the four repository keys: \(object.keys.sorted())")
        expect(submission.json == String(decoding: submission.body, as: UTF8.self), "the preview text is the body")
        if case .setup(let parsed) = CommunitySetupValidator.parse(submission.body, fileName: "x.json") {
            expect(parsed.rows.count == 3 && parsed.rejectedRows == 0, "the body passes the phase 1 validator")
        } else {
            expect(false, "the body passes the phase 1 validator")
        }
        for forbidden in ["License", "State", "licenseStateCacheHash", "Remaps", "appVersion", "serial", "hostname"] {
            expect(!submission.json.contains(forbidden), "the body doesn't contain \(forbidden)")
        }

        /// Keys outside the allowed ones make the row invalid, so they can never be copied
        var leaky = row()
        leaky["License"] = ["licenseStateCacheHash_AgainstDeviceUID": "abc"]
        expect(CommunitySubmission.build(bundleID: chrome, title: "Other", tabRows: [row(), leaky]).problem == .invalidRows(1), "a row with a License key is refused")
        expect(CommunitySubmission.build(bundleID: chrome, title: "Other", tabRows: [row(keycode: 12, flags: 0x100000)]).problem == .invalidRows(1), "a denylisted key combination is refused")
        expect(CommunitySubmission.build(bundleID: chrome, title: "Other", tabRows: [row(), row(keycode: 128)]).problem == .invalidRows(1), "keycode 128 is refused, and nothing is sent")
        expect(CommunitySubmission.build(bundleID: chrome, title: "Other", tabRows: [row(flags: 0x800000)]).problem == .invalidRows(1), "a flag outside 0x1E0000 is refused")
        expect(CommunitySubmission.build(bundleID: chrome, title: "Other", tabRows: [row(type: "symbolicHotkey")]).problem == .invalidRows(1), "another effect type is refused")
        expect(CommunitySubmission.build(bundleID: chrome, title: "Other", tabRows: []).problem == .noRows, "an empty tab is refused")
        expect(CommunitySubmission.build(bundleID: chrome, title: "Other", tabRows: Array(repeating: row(), count: 21)).problem == .tooManyRows(21), "21 rows are refused")
        expect(CommunitySubmission.build(bundleID: chrome, title: "My title", tabRows: [row()]).problem == .invalidTitle, "a free-text title is refused")
        expect(CommunitySubmission.build(bundleID: "com.apple.Health", title: "Other", tabRows: [row(app: "com.apple.Health")]).problem == .sensitiveApp, "a sensitive app is refused")
        expect(CommunitySubmission.build(bundleID: "a b", title: "Other", tabRows: [row(app: "a b")]).problem == .invalidBundleID, "an invalid bundle ID is refused")

        //
        // Delete token store
        //

        let storeURL = scratch.appendingPathComponent("Application Support/\(SharedSetupStore.fileName)")
        let store = SharedSetupStore(url: storeURL)
        expect(store.records().isEmpty, "a missing file is an empty list")
        let record = SharedSetupRecord(id: "rec_1", bundleID: chrome, title: "Tab switching", sharedAt: Date(timeIntervalSince1970: 1_800_000_000), deleteToken: "tok_secret")
        do {
            try store.add(record)
            try store.add(SharedSetupRecord(id: "rec_2", bundleID: "com.apple.finder", title: "Other", sharedAt: Date(timeIntervalSince1970: 1_800_000_100), deleteToken: "tok_2"))
            expect(SharedSetupStore(url: storeURL).records() == [record, SharedSetupRecord(id: "rec_2", bundleID: "com.apple.finder", title: "Other", sharedAt: Date(timeIntervalSince1970: 1_800_000_100), deleteToken: "tok_2")], "records survive a reload")
            let permissions = (try? FileManager.default.attributesOfItem(atPath: storeURL.path)[.posixPermissions] as? Int) ?? 0
            expect(permissions == 0o600, "the token file is readable by this user only: \(String(permissions, radix: 8))")
            try store.remove(id: "rec_1")
            expect(store.records().map { $0.id } == ["rec_2"], "a record is removed by ID")
        } catch {
            expect(false, "the store writes its file: \(error)")
        }
        expect(!"\(record)".contains("tok_secret") && !String(describing: [record]).contains("tok_secret") && !String(reflecting: record).contains("tok_secret"), "printing a record never shows its token")
        try? Data("not json".utf8).write(to: storeURL)
        expect(store.records().isEmpty, "a broken file is an empty list, not a crash")

        //
        // Uploader
        //

        let session = CommunityUploader.makeSession(protocolClasses: [StubWorker.self])
        let off = CommunityUploader(endpoint: testEndpoint, isEnabled: { false }, session: session)
        let unconfigured = CommunityUploader(endpoint: CommunitySharingEndpoint.url(from: "https://example.invalid/community"), isEnabled: { true }, session: session)
        let on = CommunityUploader(endpoint: testEndpoint, isEnabled: { true }, session: session)

        StubWorker.reset()
        let offResult = wait { off.submit(submission, completion: $0) }
        let unconfiguredResult = wait { unconfigured.submit(submission, completion: $0) }
        expect(offResult.map { if case .failure(.switchOff) = $0 { return true } else { return false } } == true, "switch off: submit fails with switchOff")
        expect(unconfiguredResult.map { if case .failure(.notConfigured) = $0 { return true } else { return false } } == true, "placeholder endpoint: submit fails with notConfigured")
        expect(StubWorker.count == 0, "switch off or no endpoint: zero requests (\(StubWorker.count))")

        /// Withdrawing stays possible with the switch off
        StubWorker.reset(status: 204)
        let offDelete = wait { off.delete(id: "rec_1", token: "tok_secret", completion: $0) }
        expect(offDelete.map { if case .success = $0 { return true } else { return false } } == true && StubWorker.count == 1, "switch off: delete still reaches the server")
        let unconfiguredDelete = wait { unconfigured.delete(id: "rec_1", token: "tok_secret", completion: $0) }
        expect(unconfiguredDelete.map { if case .failure(.notConfigured) = $0 { return true } else { return false } } == true && StubWorker.count == 1, "placeholder endpoint: delete sends nothing")

        StubWorker.reset(status: 201)
        let sent = wait { on.submit(submission, completion: $0) }
        if case .success(let receipt)? = sent {
            expect(receipt == CommunityUploader.Receipt(id: "rec_1", deleteToken: "tok_secret"), "the receipt holds the ID and the token")
        } else {
            expect(false, "submit succeeds against the stub")
        }
        StubWorker.lock.lock(); let requests = StubWorker.requests; StubWorker.lock.unlock()
        expect(requests.count == 1, "one request is sent")
        if let request = requests.first {
            expect(request.url.absoluteString == "https://worker.test/submit" && request.method == "POST", "POST to /submit: \(request.url)")
            expect(request.body == submission.body, "the request body is exactly the preview")
            expect(request.headers["Content-Type"] == "application/json", "JSON content type")
            let extra = Set(request.headers.keys.map { $0.lowercased() }).subtracting(["content-type", "content-length", "accept", "accept-language", "accept-encoding", "user-agent"])
            expect(extra.isEmpty, "no other headers are set by the app: \(extra.sorted())")
            expect(request.headers["Authorization"] == nil && request.headers["Cookie"] == nil, "no credentials or cookies")
        }

        StubWorker.reset(status: 204)
        let deleted = wait { on.delete(id: "rec_1", token: "tok_secret", completion: $0) }
        expect(deleted.map { if case .success = $0 { return true } else { return false } } == true, "delete succeeds on 204")
        StubWorker.lock.lock(); let deleteRequest = StubWorker.requests.first; StubWorker.lock.unlock()
        if let deleteRequest, let body = try? JSONSerialization.jsonObject(with: deleteRequest.body) as? [String: String] {
            expect(deleteRequest.url.absoluteString == "https://worker.test/delete" && body == ["id": "rec_1", "token": "tok_secret"], "delete sends only the ID and the token")
        } else {
            expect(false, "delete sends a JSON body")
        }

        StubWorker.reset(status: 404)
        let missing = wait { on.delete(id: "rec_1", token: "wrong", completion: $0) }
        expect(missing.map { if case .failure(.notFound) = $0 { return true } else { return false } } == true, "delete reports notFound on 404")

        StubWorker.reset(status: 422)
        let rejected = wait { on.submit(submission, completion: $0) }
        expect(rejected.map { if case .failure(.rejected) = $0 { return true } else { return false } } == true, "a 422 is reported as rejected")

        expect(CommunityUploader.receipt(from: Data("{\"id\":\"x\"}".utf8)) == nil, "a response without a token is not a receipt")
    }
}

extension Result where Failure == CommunitySubmission.Problem {
    var problem: CommunitySubmission.Problem? {
        if case .failure(let problem) = self { return problem }
        return nil
    }
}
