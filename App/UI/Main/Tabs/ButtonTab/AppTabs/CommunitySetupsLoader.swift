//
// --------------------------------------------------------------------------
// CommunitySetupsLoader.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import Foundation

/// Downloads the community setups and caches them in the app's Application Support folder (not in the config file).
///     It only runs when the user clicks "Community setups", and only while the "Community setups" switch is on. Nothing runs in the background.
///     Uploading is separate, in CommunitySharing.swift.
/// The repository has no index file, so the loader lists the `setups` folder with the GitHub contents API (works without a token)
///     and downloads the files that changed since the last time from raw.githubusercontent.com.
///     All files are downloaded, so a request never names an app. The unauthenticated API allows 60 requests an hour, so:
///     the cache is used without asking the server for `freshFor`, and after that the listing is asked for with its ETag (a 304 isn't counted).
final class CommunitySetupsLoader {

    static let shared = CommunitySetupsLoader()

    /// The whole load gives up after this
    static let timeout: TimeInterval = 10
    /// The cache is used without asking the server while it is younger than this
    static let freshFor: TimeInterval = 15 * 60

    /// Result of a load. `refreshFailed` is true if the server couldn't be reached and the cache is shown instead.
    enum Result {
        case loaded(CommunityIndex, refreshFailed: Bool)
        case failed
    }

    private lazy var session: URLSession = {
        /// Ephemeral: no cookies, no shared URL cache. The ETag is kept in our own cache file.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = CommunitySetupsLoader.timeout
        configuration.timeoutIntervalForResource = CommunitySetupsLoader.timeout
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// Called on the main thread. Loads at most once at a time; a second call while loading waits for the same result.
    private var waiting: [(Result) -> Void] = []

    static var cacheURL: URL? {
        return Locator.mfApplicationSupportFolderURL().appendingPathComponent("CommunitySetupsCache.json")
    }

    //
    // MARK: Loading
    //

    /// Loads the setups. `completion` is called on the main thread.
    func load(completion: @escaping (Result) -> Void) {
        assert(Thread.isMainThread)
        /// Nothing is downloaded while the "Community setups" switch is off
        guard CommunityConsent.isEnabled() else { completion(.failed); return }
        waiting.append(completion)
        if waiting.count > 1 { return }

        let cached = readCache()
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < CommunitySetupsLoader.freshFor {
            finish(.loaded(cached, refreshFailed: false))
            return
        }

        /// Give up after the timeout, even if some downloads are still running
        var done = false
        let finishOnce: (CommunityIndex?) -> Void = { [weak self] index in
            guard !done else { return }
            done = true
            if let index {
                self?.writeCache(index)
                self?.finish(.loaded(index, refreshFailed: false))
            } else if let cached {
                self?.finish(.loaded(cached, refreshFailed: true))
            } else {
                self?.finish(.failed)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CommunitySetupsLoader.timeout + 0.5) { finishOnce(nil) }
        fetch(cached: cached) { index in DispatchQueue.main.async { finishOnce(index) } }
    }

    private func finish(_ result: Result) {
        let callbacks = waiting
        waiting = []
        for callback in callbacks { callback(result) }
    }

    /// Asks for the listing, then downloads the files that are new or changed. nil if anything fails.
    private func fetch(cached: CommunityIndex?, completion: @escaping (CommunityIndex?) -> Void) {

        var request = URLRequest(url: CommunitySource.listingURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let etag = cached?.listingETag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self, error == nil, let response = response as? HTTPURLResponse else { completion(nil); return }

            /// Nothing changed since the cached listing
            if response.statusCode == 304, var cached {
                cached.fetchedAt = Date()
                completion(cached)
                return
            }
            guard response.statusCode == 200, let data,
                  let entries = CommunityIndex.listingEntries(from: data, allowedDownloadPrefix: CommunitySource.downloadPrefix) else { completion(nil); return }
            let etag = response.value(forHTTPHeaderField: "ETag")

            /// Reuse cached files whose SHA is unchanged, download the others
            var files: [CommunityIndex.File?] = Array(repeating: nil, count: entries.count)
            let lock = NSLock()
            let group = DispatchGroup()
            for (i, entry) in entries.enumerated() {
                if let file = cached?.files.first(where: { $0.name == entry.name && $0.sha == entry.sha }) {
                    files[i] = file
                    continue
                }
                group.enter()
                self.session.dataTask(with: entry.downloadURL) { data, response, error in
                    defer { group.leave() }
                    guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data,
                          data.count <= CommunitySetupValidator.maxBytes, let content = String(data: data, encoding: .utf8) else { return }
                    lock.lock()
                    files[i] = CommunityIndex.File(name: entry.name, sha: entry.sha, content: content)
                    lock.unlock()
                }.resume()
            }
            group.notify(queue: .global()) {
                /// A file that couldn't be downloaded fails the whole refresh, so the cache never holds half a listing
                let complete = files.compactMap { $0 }
                guard complete.count == entries.count else { completion(nil); return }
                completion(CommunityIndex(fetchedAt: Date(), listingETag: etag, files: complete))
            }
        }.resume()
    }

    //
    // MARK: Cache
    //

    private func readCache() -> CommunityIndex? {
        guard let url = CommunitySetupsLoader.cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return CommunityIndex.decoded(from: data)
    }

    private func writeCache(_ index: CommunityIndex) {
        guard let url = CommunitySetupsLoader.cacheURL, let data = try? index.encoded() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
