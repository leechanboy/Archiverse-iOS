import Foundation

enum ArchiverseAPIError: LocalizedError {
    case invalidResponse
    case server(message: String)
    case browserVerificationRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The archive returned a page instead of valid API data. Reauthenticate Cloudflare and try again."
        case .server(let message):
            return message
        case .browserVerificationRequired:
            return "Archiverse is currently behind a browser verification page. The app will open the verification flow automatically and retry."
        }
    }

    var requiresArchiveUnlock: Bool {
        if case .browserVerificationRequired = self {
            return true
        }
        if case .invalidResponse = self {
            return true
        }
        return false
    }
}

private struct APIErrorPayload: Decodable {
    let error: String
}

enum ArchiveCacheRetentionPolicy {
    static let staleInterval: TimeInterval = 7 * 24 * 60 * 60

    private static let apiCacheLastAccessKey = "ArchiverseMiiverse.APICacheLastAccess"
    private static let imageCacheLastAccessKey = "ArchiverseMiiverse.ImageCacheLastAccess"

    static func makeAPICache() -> URLCache {
        let cache = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 96 * 1024 * 1024,
            diskPath: "archiverse-miiverse-api"
        )
        purgeURLCacheIfNeeded(cache, lastAccessKey: apiCacheLastAccessKey)
        touchAPICache()
        return cache
    }

    static func makeImageCache() -> URLCache {
        let cache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "archiverse-miiverse-images"
        )
        purgeURLCacheIfNeeded(cache, lastAccessKey: imageCacheLastAccessKey)
        touchImageCache()
        return cache
    }

    static func touchAPICache() {
        UserDefaults.standard.set(Date(), forKey: apiCacheLastAccessKey)
    }

    static func touchImageCache() {
        UserDefaults.standard.set(Date(), forKey: imageCacheLastAccessKey)
    }

    static func clearAPICache() {
        let cache = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 96 * 1024 * 1024,
            diskPath: "archiverse-miiverse-api"
        )
        cache.removeAllCachedResponses()
        UserDefaults.standard.removeObject(forKey: apiCacheLastAccessKey)
    }

    static func clearImageCache() {
        let cache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "archiverse-miiverse-images"
        )
        cache.removeAllCachedResponses()
        UserDefaults.standard.removeObject(forKey: imageCacheLastAccessKey)
    }

    static func isExpired(_ lastAccessDate: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastAccessDate) > staleInterval
    }

    static func cachesDirectoryURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static func purgeURLCacheIfNeeded(_ cache: URLCache, lastAccessKey: String) {
        guard let lastAccessDate = UserDefaults.standard.object(forKey: lastAccessKey) as? Date else {
            return
        }

        guard isExpired(lastAccessDate) else {
            return
        }

        cache.removeAllCachedResponses()
    }
}

struct ArchiverseAPI {
    private let baseURL = URL(string: "https://archiverse.pretendo.network/api")!
    private let session: URLSession
    private let decoder: JSONDecoder

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = false
        configuration.urlCache = ArchiveCacheRetentionPolicy.makeAPICache()

        return URLSession(configuration: configuration)
    }()

    init(session: URLSession = ArchiverseAPI.defaultSession) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchHomepageDrawings() async throws -> [ArchiversePost] {
        let posts: [ArchiversePost] = try await fetch(
            path: "posts",
            queryItems: [
                URLQueryItem(name: "sort_mode", value: "popular"),
                URLQueryItem(name: "only_drawings", value: "true"),
                URLQueryItem(name: "page", value: "1")
            ]
        )
        await ArchiversePostCache.shared.store(posts)
        return posts
    }

    func fetchRandomPosts() async throws -> [ArchiversePost] {
        let posts: [ArchiversePost] = try await fetch(
            path: "posts",
            queryItems: [
                // The public posts API rejects bare sort_mode=recent unless a user_id or title/game pair is supplied.
                // Use the generic popular feed here so Home can load through the same public endpoint shape that remains valid.
                URLQueryItem(name: "sort_mode", value: "popular"),
                URLQueryItem(name: "page", value: "1")
            ]
        )
        await ArchiversePostCache.shared.store(posts)
        return posts
    }

    func fetchCommunities(page: Int = 1) async throws -> [ArchiverseCommunity] {
        try await fetch(path: "communities", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }

    func searchCommunities(query: String) async throws -> [ArchiverseCommunity] {
        try await fetch(path: "communities", queryItems: [URLQueryItem(name: "search", value: query)])
    }

    func searchUsers(query: String) async throws -> [ArchiverseUser] {
        try await fetch(path: "users", queryItems: [URLQueryItem(name: "search", value: query)])
    }

    func searchPosts(query: String) async throws -> [ArchiversePost] {
        let posts: [ArchiversePost] = try await fetch(path: "posts", queryItems: [URLQueryItem(name: "search", value: query)])
        await ArchiversePostCache.shared.store(posts)
        return posts
    }

    func fetchPost(id: String) async throws -> ArchiversePost {
        if let cachedPost = await ArchiversePostCache.shared.post(for: id) {
            return cachedPost
        }

        let post: ArchiversePost = try await fetch(path: "post/\(id)")
        await ArchiversePostCache.shared.store(post)
        return post
    }

    func fetchReplies(postID: String, sortMode: String = "newest", page: Int = 1) async throws -> [ArchiverseReply] {
        try await fetch(
            path: "replies",
            queryItems: [
                URLQueryItem(name: "post_id", value: postID),
                URLQueryItem(name: "sort_mode", value: sortMode),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        )
    }

    func fetchUser(id: String) async throws -> ArchiverseUser {
        try await fetch(path: "user/\(id)")
    }

    func fetchUserPosts(userID: String, sortMode: String = "recent", page: Int = 1) async throws -> [ArchiversePost] {
        let posts: [ArchiversePost] = try await fetch(
            path: "posts",
            queryItems: [
                URLQueryItem(name: "user_id", value: userID),
                URLQueryItem(name: "sort_mode", value: sortMode),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        )
        await ArchiversePostCache.shared.store(posts)
        return posts
    }

    func fetchUserReplies(userID: String, sortMode: String = "newest", page: Int = 1, includePost: Bool = true) async throws -> [UserReplyFeedItem] {
        try await fetch(
            path: "userReplies",
            queryItems: [
                URLQueryItem(name: "user_id", value: userID),
                URLQueryItem(name: "sort_mode", value: sortMode),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "include_post", value: includePost ? "true" : "false")
            ]
        )
    }

    func fetchCommunity(titleID: String, gameID: String) async throws -> ArchiverseCommunity {
        try await fetch(path: "community/\(titleID)/\(gameID)")
    }

    func fetchCommunityPosts(titleID: String, gameID: String, sortMode: String = "popular", page: Int = 1) async throws -> [ArchiversePost] {
        let posts: [ArchiversePost] = try await fetch(
            path: "posts",
            queryItems: [
                URLQueryItem(name: "title_id", value: titleID),
                URLQueryItem(name: "game_id", value: gameID),
                URLQueryItem(name: "sort_mode", value: sortMode),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        )
        await ArchiversePostCache.shared.store(posts)
        return posts
    }

    private func fetch<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let requestURL = url(path: path, queryItems: queryItems)
        let cacheKey = requestURL.absoluteString
        ArchiveCacheRetentionPolicy.touchAPICache()

        if let cachedResponse = await ArchiverseResponseCache.shared.response(for: cacheKey) {
            return try decodeResponseBody(
                T.self,
                data: cachedResponse.data,
                contentType: cachedResponse.contentType
            )
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = true
        request.setValue(ArchiveAccessBootstrap.requestUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/html;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(ArchiveAccessBootstrap.homeURL.absoluteString, forHTTPHeaderField: "Referer")

        if let cookieHeader = ArchiveAccessBootstrap.cookieHeader(for: requestURL) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ArchiverseAPIError.invalidResponse
        }

        let encounteredCloudflareChallenge = ArchiveAccessBootstrap.isCloudflareChallenge(httpResponse: httpResponse, data: data)
        if encounteredCloudflareChallenge || httpResponse.statusCode == 403 {
            return try await fetchUsingBrowserSession(from: requestURL)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = (try? decoder.decode(APIErrorPayload.self, from: data).error) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw ArchiverseAPIError.server(message: message)
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "content-type") ?? ""
        let decoded: T = try decodeResponseBody(
            T.self,
            data: data,
            contentType: contentType
        )

        await ArchiverseResponseCache.shared.store(
            data: data,
            contentType: contentType,
            for: cacheKey
        )

        return decoded
    }

    private func fetchUsingBrowserSession<T: Decodable>(from requestURL: URL) async throws -> T {
        let browserResponse = try await ArchiveBrowserSession.shared.fetch(url: requestURL)

        if browserResponse.isCloudflareChallenge {
            throw ArchiverseAPIError.browserVerificationRequired
        }

        guard (200 ..< 300).contains(browserResponse.statusCode) else {
            let message = (try? decoder.decode(APIErrorPayload.self, from: browserResponse.bodyData).error) ?? HTTPURLResponse.localizedString(forStatusCode: browserResponse.statusCode)
            throw ArchiverseAPIError.server(message: message)
        }

        let decoded: T = try decodeResponseBody(
            T.self,
            data: browserResponse.bodyData,
            contentType: browserResponse.contentType
        )

        await ArchiverseResponseCache.shared.store(
            data: browserResponse.bodyData,
            contentType: browserResponse.contentType,
            for: requestURL.absoluteString
        )

        return decoded
    }

    private func decodeResponseBody<T: Decodable>(_ type: T.Type, data: Data, contentType: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? ""

            if ArchiveAccessBootstrap.isCloudflareChallenge(contentType: contentType, body: body) {
                throw ArchiverseAPIError.browserVerificationRequired
            }

            throw ArchiverseAPIError.invalidResponse
        }
    }

    private func url(path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }
}

private actor ArchiverseResponseCache {
    static let shared = ArchiverseResponseCache()

    private struct Entry: Codable {
        let data: Data
        let contentType: String
        var lastAccessDate: Date
    }

    private let storageURL = ArchiveCacheRetentionPolicy.cachesDirectoryURL()
        .appendingPathComponent("archiverse-response-cache.json")
    private var entries: [String: Entry] = [:]

    init() {
        guard let data = try? Data(contentsOf: storageURL) else {
            return
        }

        guard let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            try? FileManager.default.removeItem(at: storageURL)
            return
        }

        entries = decoded.filter { !ArchiveCacheRetentionPolicy.isExpired($0.value.lastAccessDate) }

        if entries.count != decoded.count,
           let encoded = try? JSONEncoder().encode(entries) {
            try? encoded.write(to: storageURL, options: .atomic)
        }
    }

    func response(for key: String) -> (data: Data, contentType: String)? {
        pruneExpiredEntries()

        guard var entry = entries[key] else {
            return nil
        }

        entry.lastAccessDate = Date()
        entries[key] = entry
        persist()
        return (entry.data, entry.contentType)
    }

    func store(data: Data, contentType: String, for key: String) {
        entries[key] = Entry(
            data: data,
            contentType: contentType,
            lastAccessDate: Date()
        )
        persist()
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
    }

    private func pruneExpiredEntries() {
        let beforeCount = entries.count
        entries = entries.filter { !ArchiveCacheRetentionPolicy.isExpired($0.value.lastAccessDate) }

        if entries.count != beforeCount {
            persist()
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL) else {
            return
        }

        guard let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            try? FileManager.default.removeItem(at: storageURL)
            return
        }

        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }

        try? data.write(to: storageURL, options: .atomic)
    }
}

private actor ArchiversePostCache {
    static let shared = ArchiversePostCache()

    private struct Entry: Codable {
        let post: ArchiversePost
        var lastAccessDate: Date
    }

    private let storageURL = ArchiveCacheRetentionPolicy.cachesDirectoryURL()
        .appendingPathComponent("archiverse-post-cache.json")
    private var entries: [String: Entry] = [:]

    init() {
        guard let data = try? Data(contentsOf: storageURL) else {
            return
        }

        guard let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            try? FileManager.default.removeItem(at: storageURL)
            return
        }

        entries = decoded.filter { !ArchiveCacheRetentionPolicy.isExpired($0.value.lastAccessDate) }

        if entries.count != decoded.count,
           let encoded = try? JSONEncoder().encode(entries) {
            try? encoded.write(to: storageURL, options: .atomic)
        }
    }

    func post(for id: String) -> ArchiversePost? {
        pruneExpiredEntries()

        guard var entry = entries[id] else {
            return nil
        }

        entry.lastAccessDate = Date()
        entries[id] = entry
        persist()
        return entry.post
    }

    func store(_ post: ArchiversePost) {
        entries[post.id] = Entry(post: post, lastAccessDate: Date())

        if let rawID = post.rawID, rawID != post.id {
            entries[rawID] = Entry(post: post, lastAccessDate: Date())
        }

        persist()
    }

    func store(_ posts: [ArchiversePost]) {
        let now = Date()
        for post in posts {
            entries[post.id] = Entry(post: post, lastAccessDate: now)

            if let rawID = post.rawID, rawID != post.id {
                entries[rawID] = Entry(post: post, lastAccessDate: now)
            }
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
    }

    private func pruneExpiredEntries() {
        let beforeCount = entries.count
        entries = entries.filter { !ArchiveCacheRetentionPolicy.isExpired($0.value.lastAccessDate) }

        if entries.count != beforeCount {
            persist()
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL) else {
            return
        }

        guard let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            try? FileManager.default.removeItem(at: storageURL)
            return
        }

        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }

        try? data.write(to: storageURL, options: .atomic)
    }
}
