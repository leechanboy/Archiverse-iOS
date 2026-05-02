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

struct ArchiverseAPI {
    private let baseURL = URL(string: "https://archiverse.pretendo.network/api")!
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchHomepageDrawings() async throws -> [ArchiversePost] {
        try await fetch(
            path: "posts",
            queryItems: [
                URLQueryItem(name: "sort_mode", value: "popular"),
                URLQueryItem(name: "only_drawings", value: "true"),
                URLQueryItem(name: "page", value: "1")
            ]
        )
    }

    func fetchRandomPosts() async throws -> [ArchiversePost] {
        try await fetch(
            path: "posts",
            queryItems: [
                // The public posts API rejects bare sort_mode=recent unless a user_id or title/game pair is supplied.
                // Use the generic popular feed here so Home can load through the same public endpoint shape that remains valid.
                URLQueryItem(name: "sort_mode", value: "popular"),
                URLQueryItem(name: "page", value: "1")
            ]
        )
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
        try await fetch(path: "posts", queryItems: [URLQueryItem(name: "search", value: query)])
    }

    func fetchPost(id: String) async throws -> ArchiversePost {
        try await fetch(path: "post/\(id)")
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
        try await fetch(
            path: "posts",
            queryItems: [
                URLQueryItem(name: "user_id", value: userID),
                URLQueryItem(name: "sort_mode", value: sortMode),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        )
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
        try await fetch(
            path: "posts",
            queryItems: [
                URLQueryItem(name: "title_id", value: titleID),
                URLQueryItem(name: "game_id", value: gameID),
                URLQueryItem(name: "sort_mode", value: sortMode),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        )
    }

    private func fetch<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let requestURL = url(path: path, queryItems: queryItems)
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

        return try decodeResponseBody(
            T.self,
            data: data,
            contentType: httpResponse.value(forHTTPHeaderField: "content-type") ?? ""
        )
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

        return try decodeResponseBody(
            T.self,
            data: browserResponse.bodyData,
            contentType: browserResponse.contentType
        )
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
