import Foundation
import Combine

enum ArchiverseMediaKind: String, Hashable {
    case drawing
    case screenshot
}

struct ArchiverseMediaAsset: Hashable, Identifiable {
    let kind: ArchiverseMediaKind
    let url: URL

    var id: String {
        "\(kind.rawValue)-\(url.absoluteString)"
    }

    var label: String {
        switch kind {
        case .drawing:
            return "Drawing"
        case .screenshot:
            return "Screenshot"
        }
    }

    var prefersContainedScaling: Bool {
        true
    }

    var fallbackSystemImage: String {
        kind == .drawing ? "pencil.and.scribble" : "photo.fill"
    }
}

struct ArchiversePost: Codable, Hashable, Identifiable {
    let rawID: String?
    let miiName: String
    let nnid: String?
    let miiURLString: String?
    let numYeahs: Int
    let numReplies: Int
    let title: String?
    let text: String?
    let drawingURLString: String?
    let screenshotURLString: String?
    let videoURLString: String?
    let communityTitle: String?
    let communityIconURLString: String?
    let gameID: String?
    let titleID: String?
    let isSpoiler: Bool
    let isPlayed: Bool
    let dateString: String?
    let doNotShow: Bool
    let webArchiveURLString: String?
    let warcLocationURLString: String?

    enum CodingKeys: String, CodingKey {
        case rawID = "ID"
        case miiName = "MiiName"
        case nnid = "NNID"
        case miiURLString = "MiiUrl"
        case numYeahs = "NumYeahs"
        case numReplies = "NumReplies"
        case title = "Title"
        case text = "Text"
        case drawingURLString = "DrawingUrl"
        case screenshotURLString = "ScreenshotUrl"
        case videoURLString = "VideoUrl"
        case communityTitle = "CommunityTitle"
        case communityIconURLString = "CommunityIconUrl"
        case gameID = "GameID"
        case titleID = "TitleID"
        case isSpoiler = "IsSpoiler"
        case isPlayed = "IsPlayed"
        case dateString = "Date"
        case doNotShow = "DoNotShow"
        case webArchiveURLString = "WebArchiveUrl"
        case warcLocationURLString = "WarcLocationUrl"
    }

    var id: String {
        rawID ?? [nnid, miiName, dateString].compactMap { $0 }.joined(separator: "-")
    }

    var headline: String {
        (title?.trimmed.nilIfEmpty ?? text?.trimmed.nilIfEmpty) ?? "Untitled post"
    }

    var displayTitle: String? {
        guard let title = title?.trimmed.nilIfEmpty else { return nil }

        if let text = text?.trimmed.nilIfEmpty, title == text {
            return nil
        }

        return title
    }

    var detailText: String {
        if let title = title?.trimmed.nilIfEmpty,
           let text = text?.trimmed.nilIfEmpty,
           title != text {
            return text
        }
        return (text?.trimmed.nilIfEmpty ?? "Archived Miiverse post")
    }

    var avatarURL: URL? {
        URL(string: miiURLString ?? "")
    }

    var drawingURL: URL? {
        URL(string: drawingURLString ?? "")
    }

    var screenshotURL: URL? {
        URL(string: screenshotURLString ?? "")
    }

    var communityIconURL: URL? {
        URL(string: communityIconURLString ?? "")
    }

    var mediaAssets: [ArchiverseMediaAsset] {
        var items: [ArchiverseMediaAsset] = []

        if let drawingURL {
            items.append(ArchiverseMediaAsset(kind: .drawing, url: drawingURL))
        }

        if let screenshotURL {
            items.append(ArchiverseMediaAsset(kind: .screenshot, url: screenshotURL))
        }

        return items
    }

    var primaryMediaURL: URL? {
        mediaAssets.first?.url
    }

    var prefersContainedMedia: Bool {
        mediaAssets.first?.prefersContainedScaling ?? false
    }

    var previewFallbackSystemImage: String {
        mediaAssets.first?.fallbackSystemImage ?? "photo.fill"
    }
}

struct ArchiverseReply: Decodable, Hashable, Identifiable {
    let rawID: String?
    let miiName: String
    let nnid: String?
    let miiURLString: String?
    let numYeahs: Int
    let text: String?
    let drawingURLString: String?
    let screenshotURLString: String?
    let replyingToID: String?
    let isSpoiler: Bool
    let isPlayed: Bool
    let dateString: String?
    let doNotShow: Bool
    let warcLocationURLString: String?

    enum CodingKeys: String, CodingKey {
        case rawID = "ID"
        case miiName = "MiiName"
        case nnid = "NNID"
        case miiURLString = "MiiUrl"
        case numYeahs = "NumYeahs"
        case text = "Text"
        case drawingURLString = "DrawingUrl"
        case screenshotURLString = "ScreenshotUrl"
        case replyingToID = "ReplyingToID"
        case isSpoiler = "IsSpoiler"
        case isPlayed = "IsPlayed"
        case dateString = "Date"
        case doNotShow = "DoNotShow"
        case warcLocationURLString = "WarcLocationUrl"
    }

    var id: String {
        rawID ?? [nnid, dateString, text].compactMap { $0 }.joined(separator: "-")
    }

    var avatarURL: URL? {
        URL(string: miiURLString ?? "")
    }

    var drawingURL: URL? {
        URL(string: drawingURLString ?? "")
    }

    var screenshotURL: URL? {
        URL(string: screenshotURLString ?? "")
    }

    var mediaAssets: [ArchiverseMediaAsset] {
        var items: [ArchiverseMediaAsset] = []

        if let drawingURL {
            items.append(ArchiverseMediaAsset(kind: .drawing, url: drawingURL))
        }

        if let screenshotURL {
            items.append(ArchiverseMediaAsset(kind: .screenshot, url: screenshotURL))
        }

        return items
    }

    var primaryMediaURL: URL? {
        mediaAssets.first?.url
    }

    var prefersContainedMedia: Bool {
        mediaAssets.first?.prefersContainedScaling ?? false
    }

    var previewFallbackSystemImage: String {
        mediaAssets.first?.fallbackSystemImage ?? "photo.fill"
    }
}

struct ArchiverseUser: Decodable, Hashable, Identifiable {
    let nnid: String?
    let miiName: String
    let miiURLString: String?
    let bio: String?
    let bannerURLString: String?
    let country: String?
    let numFollowers: Int?
    let numFollowing: Int?
    let numFriends: Int?
    let numPosts: Int?
    let birthday: String?
    let doNotShow: Bool
    let webArchiveURLString: String?
    let warcLocationURLString: String?

    enum CodingKeys: String, CodingKey {
        case nnid = "NNID"
        case miiName = "MiiName"
        case miiURLString = "MiiUrl"
        case bio = "Bio"
        case bannerURLString = "BannerUrl"
        case country = "Country"
        case numFollowers = "NumFollowers"
        case numFollowing = "NumFollowing"
        case numFriends = "NumFriends"
        case numPosts = "NumPosts"
        case birthday = "Birthday"
        case doNotShow = "DoNotShow"
        case webArchiveURLString = "WebArchiveUrl"
        case warcLocationURLString = "WarcLocationUrl"
    }

    var id: String {
        nnid ?? miiName
    }

    var avatarURL: URL? {
        URL(string: miiURLString ?? "")
    }

    var bannerURL: URL? {
        URL(string: bannerURLString ?? "")
    }
}

struct ArchiverseCommunity: Decodable, Hashable, Identifiable {
    let gameID: String
    let titleID: String
    let communityTitle: String
    let communityBannerURLString: String?
    let communityIconURLString: String?
    let badge: String?
    let gameTitle: String
    let numPosts: Int
    let region: String
    let webArchiveURLString: String?

    enum CodingKeys: String, CodingKey {
        case gameID = "GameID"
        case titleID = "TitleID"
        case communityTitle = "CommunityTitle"
        case communityBannerURLString = "CommunityBanner"
        case communityIconURLString = "CommunityIconUrl"
        case badge = "Badge"
        case gameTitle = "GameTitle"
        case numPosts = "NumPosts"
        case region = "Region"
        case webArchiveURLString = "WebArchiveUrl"
    }

    var id: String {
        "\(titleID)-\(gameID)"
    }

    var bannerURL: URL? {
        URL(string: communityBannerURLString ?? "")
    }

    var iconURL: URL? {
        URL(string: communityIconURLString ?? "")
    }
}

struct UserReplyFeedItem: Decodable, Hashable, Identifiable {
    let reply: ArchiverseReply
    let post: ArchiversePost?

    var id: String {
        reply.id
    }
}

struct UserProfileTarget: Hashable, Identifiable {
    let userID: String

    var id: String {
        userID
    }
}

enum ArchiveDateFilter {
    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardDateFormatter = ISO8601DateFormatter()

    static func normalizedCutoffDate(_ date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? date
    }

    static func apiValue(from date: Date) -> String {
        standardDateFormatter.string(from: normalizedCutoffDate(date))
    }

    static func includes(_ archiveDateString: String?, cutoffDate: Date?) -> Bool {
        guard let cutoffDate else { return true }
        guard let archiveDate = archiveDate(from: archiveDateString) else { return true }
        return archiveDate <= normalizedCutoffDate(cutoffDate)
    }

    static func filter(posts: [ArchiversePost], cutoffDate: Date?) -> [ArchiversePost] {
        guard let cutoffDate else { return posts }
        return posts.filter { includes($0.dateString, cutoffDate: cutoffDate) }
    }

    static func filter(replies: [ArchiverseReply], cutoffDate: Date?) -> [ArchiverseReply] {
        guard let cutoffDate else { return replies }
        return replies.filter { includes($0.dateString, cutoffDate: cutoffDate) }
    }

    static func filter(replyFeed: [UserReplyFeedItem], cutoffDate: Date?) -> [UserReplyFeedItem] {
        guard let cutoffDate else { return replyFeed }
        return replyFeed.filter { includes($0.reply.dateString, cutoffDate: cutoffDate) }
    }

    private static func archiveDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        if let date = fractionalDateFormatter.date(from: value) {
            return date
        }

        return standardDateFormatter.date(from: value)
    }
}

final class ArchiveSettingsStore: ObservableObject {
    @Published private(set) var selectedArchiveDate: Date?

    private let defaults: UserDefaults
    private static let archiveDateDefaultsKey = "archiverse.settings.archiveDate"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedArchiveDate = defaults.object(forKey: Self.archiveDateDefaultsKey) as? Date
    }

    var isArchiveDateFilterEnabled: Bool {
        selectedArchiveDate != nil
    }

    func setArchiveDateFilterEnabled(_ isEnabled: Bool) {
        if isEnabled {
            updateArchiveDate(selectedArchiveDate ?? Date())
        } else {
            selectedArchiveDate = nil
            defaults.removeObject(forKey: Self.archiveDateDefaultsKey)
        }
    }

    func updateArchiveDate(_ date: Date) {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        selectedArchiveDate = normalizedDate
        defaults.set(normalizedDate, forKey: Self.archiveDateDefaultsKey)
    }
}

struct LikedPostEntry: Codable, Hashable, Identifiable {
    let id: String
    var post: ArchiversePost
    let likedAt: Date

    init(post: ArchiversePost, likedAt: Date = Date()) {
        self.id = post.id
        self.post = post
        self.likedAt = likedAt
    }
}

final class YeahStore: ObservableObject {
    @Published private(set) var entries: [LikedPostEntry] = []

    private let defaults: UserDefaults
    private static let defaultsKey = "archiverse.yeah.entries"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var likedPosts: [ArchiversePost] {
        entries
            .sorted { $0.likedAt > $1.likedAt }
            .map(\.post)
    }

    func isLiked(_ post: ArchiversePost) -> Bool {
        entryIndex(for: post.id) != nil
    }

    func displayedYeahCount(for post: ArchiversePost) -> Int {
        post.numYeahs + (isLiked(post) ? 1 : 0)
    }

    func toggleYeah(for post: ArchiversePost) {
        if let index = entryIndex(for: post.id) {
            entries.remove(at: index)
            persist()
            return
        }

        entries.insert(LikedPostEntry(post: post), at: 0)
        persist()
    }

    func sendYeah(for post: ArchiversePost) {
        guard let index = entryIndex(for: post.id) else {
            entries.insert(LikedPostEntry(post: post), at: 0)
            persist()
            return
        }

        if entries[index].post != post {
            entries[index].post = post
            persist()
        }
    }

    func removeYeah(for post: ArchiversePost) {
        guard let index = entryIndex(for: post.id) else { return }
        entries.remove(at: index)
        persist()
    }

    func refreshIfLiked(_ post: ArchiversePost) {
        guard let index = entryIndex(for: post.id) else { return }
        guard entries[index].post != post else { return }

        entries[index].post = post
        persist()
    }

    private func entryIndex(for postID: String) -> Int? {
        entries.firstIndex { $0.id == postID }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return }

        do {
            entries = try JSONDecoder().decode([LikedPostEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }
}

enum MockArchiveData {
    static let featuredPosts: [ArchiversePost] = [
        ArchiversePost(
            rawID: "mock-post-1",
            miiName: "InklingFan",
            nnid: "InklingFan",
            miiURLString: nil,
            numYeahs: 1842,
            numReplies: 98,
            title: "Plaza Sketch",
            text: "I missed drawing for the plaza every day, so this iPhone version brings that warm Miiverse vibe back.",
            drawingURLString: nil,
            screenshotURLString: nil,
            videoURLString: nil,
            communityTitle: "Splatoon Community",
            communityIconURLString: nil,
            gameID: "1001",
            titleID: "5001",
            isSpoiler: false,
            isPlayed: true,
            dateString: "2017-11-06T11:15:00Z",
            doNotShow: false,
            webArchiveURLString: nil,
            warcLocationURLString: nil
        ),
        ArchiversePost(
            rawID: "mock-post-2",
            miiName: "RetroLuma",
            nnid: "RetroLuma",
            miiURLString: nil,
            numYeahs: 967,
            numReplies: 41,
            title: "Remember the green header?",
            text: "That bright Wii U Miiverse chrome is the whole reason this port feels nostalgic.",
            drawingURLString: nil,
            screenshotURLString: nil,
            videoURLString: nil,
            communityTitle: "Nintendo Land",
            communityIconURLString: nil,
            gameID: "1002",
            titleID: "5002",
            isSpoiler: false,
            isPlayed: true,
            dateString: "2017-10-22T03:30:00Z",
            doNotShow: false,
            webArchiveURLString: nil,
            warcLocationURLString: nil
        )
    ]

    static let recentPosts: [ArchiversePost] = [
        featuredPosts[0],
        featuredPosts[1],
        ArchiversePost(
            rawID: "mock-post-3",
            miiName: "MiiArchivist",
            nnid: "MiiArchivist",
            miiURLString: nil,
            numYeahs: 530,
            numReplies: 13,
            title: nil,
            text: "Archiverse keeps the little moments alive: plaza chatter, doodles, replies, and surprise discoveries.",
            drawingURLString: nil,
            screenshotURLString: nil,
            videoURLString: nil,
            communityTitle: "Wii U Plaza",
            communityIconURLString: nil,
            gameID: "1003",
            titleID: "5003",
            isSpoiler: false,
            isPlayed: false,
            dateString: "2017-09-12T14:00:00Z",
            doNotShow: false,
            webArchiveURLString: nil,
            warcLocationURLString: nil
        )
    ]

    static let communities: [ArchiverseCommunity] = [
        ArchiverseCommunity(
            gameID: "1001",
            titleID: "5001",
            communityTitle: "Splatoon Community",
            communityBannerURLString: nil,
            communityIconURLString: nil,
            badge: "Main Community",
            gameTitle: "Splatoon",
            numPosts: 124_500,
            region: "Worldwide",
            webArchiveURLString: nil
        ),
        ArchiverseCommunity(
            gameID: "1002",
            titleID: "5002",
            communityTitle: "Nintendo Land",
            communityBannerURLString: nil,
            communityIconURLString: nil,
            badge: nil,
            gameTitle: "Nintendo Land",
            numPosts: 86_230,
            region: "America",
            webArchiveURLString: nil
        ),
        ArchiverseCommunity(
            gameID: "1003",
            titleID: "5003",
            communityTitle: "Super Mario 3D World",
            communityBannerURLString: nil,
            communityIconURLString: nil,
            badge: nil,
            gameTitle: "Super Mario 3D World",
            numPosts: 97_540,
            region: "Europe",
            webArchiveURLString: nil
        )
    ]

    static let user = ArchiverseUser(
        nnid: "InklingFan",
        miiName: "InklingFan",
        miiURLString: nil,
        bio: "Wii U plaza sketcher and Miiverse archive enjoyer.",
        bannerURLString: nil,
        country: "Hidden",
        numFollowers: 128,
        numFollowing: 74,
        numFriends: 40,
        numPosts: 341,
        birthday: "Unknown",
        doNotShow: false,
        webArchiveURLString: nil,
        warcLocationURLString: nil
    )

    static let replies: [ArchiverseReply] = [
        ArchiverseReply(
            rawID: "mock-reply-1",
            miiName: "PlazaKid",
            nnid: "PlazaKid",
            miiURLString: nil,
            numYeahs: 45,
            text: "This feels exactly like browsing Miiverse on the GamePad again.",
            drawingURLString: nil,
            screenshotURLString: nil,
            replyingToID: "mock-post-1",
            isSpoiler: false,
            isPlayed: false,
            dateString: "2017-11-06T13:10:00Z",
            doNotShow: false,
            warcLocationURLString: nil
        ),
        ArchiverseReply(
            rawID: "mock-reply-2",
            miiName: "MuseumFox",
            nnid: "MuseumFox",
            miiURLString: nil,
            numYeahs: 19,
            text: "Love that the cards still have the rounded Miiverse softness.",
            drawingURLString: nil,
            screenshotURLString: nil,
            replyingToID: "mock-post-1",
            isSpoiler: false,
            isPlayed: false,
            dateString: "2017-11-06T13:45:00Z",
            doNotShow: false,
            warcLocationURLString: nil
        )
    ]

    static let replyFeed: [UserReplyFeedItem] = [
        UserReplyFeedItem(reply: replies[0], post: featuredPosts[0]),
        UserReplyFeedItem(reply: replies[1], post: featuredPosts[1])
    ]
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
