import AVKit
import Combine
import SwiftUI
import UIKit

enum AirPlayTVSection: String, CaseIterable, Hashable, Identifiable {
    case home
    case search
    case communities
    case yeahs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Activity Feed"
        case .search:
            return "Search"
        case .communities:
            return "Communities"
        case .yeahs:
            return "Yeahs"
        case .settings:
            return "Settings"
        }
    }

    var shortTitle: String {
        switch self {
        case .home:
            return "Feed"
        case .search:
            return "Search"
        case .communities:
            return "Comms"
        case .yeahs:
            return "Yeahs"
        case .settings:
            return "Setup"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "dot.radiowaves.left.and.right"
        case .search:
            return "magnifyingglass"
        case .communities:
            return "person.3.fill"
        case .yeahs:
            return "hand.thumbsup.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

enum AirPlaySearchScope: String, CaseIterable, Hashable, Identifiable {
    case posts
    case communities
    case users

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum AirPlayRemoteDirection {
    case up
    case down
    case left
    case right
}

enum AirPlayTVScreen: Hashable {
    case feedRoot
    case searchRoot
    case communitiesRoot
    case yeahsRoot
    case settingsRoot
    case communityDetail(String)
    case userProfile(String)
    case postDetail(String)
}

enum AirPlayRemoteFocusItem: Hashable {
    case section(AirPlayTVSection)
    case searchField
    case searchScope(AirPlaySearchScope)
    case communitySort(CommunitySortMode)
    case userContent(UserContentMode)
    case post(String)
    case community(String)
    case user(String)
    case postAuthor(String)
    case postCommunity(String)
    case postYeah
    case reply(String)
    case userReply(String)
    case settingsRefresh
    case loadMoreFeed
    case loadMoreCommunities
    case loadMoreCommunityPosts
    case loadMoreUserPosts
    case loadMoreUserReplies
    case loadMoreReplies
}

@MainActor
final class AirPlaySessionController: ObservableObject {
    @Published var selectedSection: AirPlayTVSection = .home
    @Published var searchScope: AirPlaySearchScope = .posts
    @Published var communitySortMode: CommunitySortMode = .popular
    @Published var userContentMode: UserContentMode = .posts
    @Published var searchQuery = ""

    @Published private(set) var featuredPosts: [ArchiversePost] = []
    @Published private(set) var recentPosts: [ArchiversePost] = []
    @Published private(set) var communities: [ArchiverseCommunity] = []
    @Published private(set) var communityPosts: [ArchiversePost] = []
    @Published private(set) var searchedPosts: [ArchiversePost] = []
    @Published private(set) var searchedCommunities: [ArchiverseCommunity] = []
    @Published private(set) var searchedUsers: [ArchiverseUser] = []
    @Published private(set) var selectedUserPosts: [ArchiversePost] = []
    @Published private(set) var selectedUserReplies: [UserReplyFeedItem] = []
    @Published private(set) var selectedPostReplies: [ArchiverseReply] = []

    @Published private(set) var errorMessage: String?
    @Published private(set) var needsArchiveUnlock = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingCommunityPosts = false
    @Published private(set) var isLoadingMoreFeed = false
    @Published private(set) var isLoadingMoreCommunities = false
    @Published private(set) var isLoadingMoreCommunityPosts = false
    @Published private(set) var isLoadingUserPosts = false
    @Published private(set) var isLoadingMoreUserPosts = false
    @Published private(set) var isLoadingUserReplies = false
    @Published private(set) var isLoadingMoreUserReplies = false
    @Published private(set) var isLoadingSelectedPost = false
    @Published private(set) var isLoadingMoreReplies = false
    @Published private(set) var isRouteConnected = false
    @Published private(set) var isExternalDisplayActive = false
    @Published private(set) var routeActivationNonce = UUID()
    @Published private(set) var navigationPath: [AirPlayTVScreen] = [.feedRoot]
    @Published private(set) var focusedItem: AirPlayRemoteFocusItem = .section(.home)
    @Published var isSearchKeyboardPresented = false

    @Published var isPresentingBroadcast = false
    @Published var selectedPost: ArchiversePost?
    @Published var selectedCommunity: ArchiverseCommunity?
    @Published var selectedUser: ArchiverseUser?

    private var currentFeedPage = 1
    private var canLoadMoreFeed = false
    private var currentCommunitiesPage = 1
    private var canLoadMoreCommunities = false
    private var currentCommunityPostsPage = 1
    private var canLoadMoreCommunityPosts = false
    private var currentUserPostsPage = 1
    private var canLoadMoreUserPosts = false
    private var currentUserRepliesPage = 1
    private var canLoadMoreUserReplies = false
    private var currentPostRepliesPage = 1
    private var canLoadMorePostReplies = false

    private var hasLoaded = false
    private var storeBindings: Set<AnyCancellable> = []
    private weak var yeahStore: YeahStore?
    private weak var archiveSettings: ArchiveSettingsStore?
    private var lastFocusedItemByScreen: [AirPlayTVScreen: AirPlayRemoteFocusItem] = [:]

    init() {}

    var filteredFeaturedPosts: [ArchiversePost] {
        filterPosts(featuredPosts)
    }

    var filteredRecentPosts: [ArchiversePost] {
        filterPosts(recentPosts)
    }

    var filteredCommunityPosts: [ArchiversePost] {
        filterPosts(communityPosts)
    }

    var filteredSelectedUserPosts: [ArchiversePost] {
        filterPosts(selectedUserPosts)
    }

    var filteredSelectedUserReplies: [UserReplyFeedItem] {
        ArchiveDateFilter.filter(replyFeed: selectedUserReplies, cutoffDate: archiveSettings?.selectedArchiveDate)
    }

    var filteredSelectedPostReplies: [ArchiverseReply] {
        ArchiveDateFilter.filter(replies: selectedPostReplies, cutoffDate: archiveSettings?.selectedArchiveDate)
    }

    var filteredSearchedPosts: [ArchiversePost] {
        filterPosts(searchedPosts)
    }

    var filteredLikedPosts: [ArchiversePost] {
        filterPosts(yeahStore?.likedPosts ?? [])
    }

    var allPosts: [ArchiversePost] {
        deduplicatedPosts(filteredFeaturedPosts + filteredRecentPosts)
    }

    var canLoadMoreFeedItems: Bool {
        canLoadMoreFeed
    }

    var canLoadMoreCommunityItems: Bool {
        canLoadMoreCommunities
    }

    var canLoadMoreCurrentCommunityPosts: Bool {
        canLoadMoreCommunityPosts
    }

    var canLoadMoreCurrentUserPosts: Bool {
        canLoadMoreUserPosts
    }

    var canLoadMoreCurrentUserReplies: Bool {
        canLoadMoreUserReplies
    }

    var canLoadMoreCurrentPostReplies: Bool {
        canLoadMorePostReplies
    }

    var visibleCommunities: [ArchiverseCommunity] {
        communities
    }

    var visibleCommunityPosts: [ArchiversePost] {
        Array(filteredCommunityPosts.prefix(10))
    }

    var visibleUserPosts: [ArchiversePost] {
        Array(filteredSelectedUserPosts.prefix(10))
    }

    var selectedArchiveCutoffLabel: String {
        guard let date = archiveSettings?.selectedArchiveDate else {
            return "Archive cutoff: Off"
        }

        return "Archive cutoff: \(Self.settingsDateFormatter.string(from: date))"
    }

    var routeStatusText: String {
        if isExternalDisplayActive {
            return "TV connected"
        }
        if isRouteConnected {
            return "Display route detected"
        }
        return "No TV connected"
    }

    var routeInstructionText: String {
        if isExternalDisplayActive {
            return "TV output is live on the external display. This device is acting as the remote controller."
        }
        if isRouteConnected {
            return "A display route is connected. Start the TV broadcast to move the TV UI to the external display."
        }
        return "No AirPlay display is connected. Starting the broadcast opens a local TV preview on this device."
    }

    var isRemoteMode: Bool {
        isPresentingBroadcast && isRouteConnected
    }

    var isLocalTVPreviewMode: Bool {
        isPresentingBroadcast && !isRouteConnected
    }

    var currentScreen: AirPlayTVScreen {
        navigationPath.last ?? rootScreen(for: selectedSection)
    }

    var currentScreenRoot: AirPlayTVScreen {
        rootScreen(for: selectedSection)
    }

    func configureStores(yeahStore: YeahStore, archiveSettings: ArchiveSettingsStore) {
        let didChangeYeahStore = self.yeahStore !== yeahStore
        let didChangeArchiveSettings = self.archiveSettings !== archiveSettings

        self.yeahStore = yeahStore
        self.archiveSettings = archiveSettings

        guard didChangeYeahStore || didChangeArchiveSettings else { return }

        storeBindings.removeAll()

        yeahStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &storeBindings)

        archiveSettings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &storeBindings)
    }

    func refreshIfNeeded(using api: ArchiverseAPI) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh(using: api)
    }

    func refresh(using api: ArchiverseAPI) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        needsArchiveUnlock = false
        currentFeedPage = 1
        currentCommunitiesPage = 1
        defer { isLoading = false }

        async let featuredResult = attempt { try await api.fetchHomepageDrawings(page: 1) }
        async let recentResult = attempt { try await api.fetchRandomPosts(page: 1) }
        async let communitiesResult = attempt { try await api.fetchCommunities(page: 1) }

        let featured = await featuredResult
        let recent = await recentResult
        let fetchedCommunities = await communitiesResult

        var failures: [String] = []
        var requiresArchiveUnlock = false

        switch featured {
        case .success(let posts):
            featuredPosts = posts
        case .failure(let error):
            failures.append("Featured Drawings: \(error.localizedDescription)")
            requiresArchiveUnlock = requiresArchiveUnlock || error.requiresArchiveUnlock
        }

        switch recent {
        case .success(let posts):
            recentPosts = posts
            canLoadMoreFeed = !posts.isEmpty
        case .failure(let error):
            failures.append("Archive Feed: \(error.localizedDescription)")
            requiresArchiveUnlock = requiresArchiveUnlock || error.requiresArchiveUnlock
            canLoadMoreFeed = false
        }

        switch fetchedCommunities {
        case .success(let items):
            communities = items
            canLoadMoreCommunities = !items.isEmpty
        case .failure(let error):
            failures.append("Communities: \(error.localizedDescription)")
            requiresArchiveUnlock = requiresArchiveUnlock || error.requiresArchiveUnlock
            canLoadMoreCommunities = false
        }

        if selectedCommunity == nil || !communities.contains(where: { $0.id == selectedCommunity?.id }) {
            selectedCommunity = communities.first
        }

        if selectedPost == nil || !allPosts.contains(where: { $0.id == selectedPost?.id }) {
            selectedPost = allPosts.first
        }

        if let selectedCommunity {
            await loadCommunityPosts(for: selectedCommunity, using: api)
        }

        if let selectedPost {
            await loadSelectedPostData(for: selectedPost, using: api)
        }

        ensureNavigationState()
        normalizeFocusedItem()

        if requiresArchiveUnlock {
            needsArchiveUnlock = true
            errorMessage = "Cloudflare verification is required before the TV screen can load live archive data."
            return
        }

        if !failures.isEmpty && featuredPosts.isEmpty && recentPosts.isEmpty && communities.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        } else if !failures.isEmpty {
            errorMessage = "Some TV sections did not finish loading."
        }
    }

    func beginBroadcast(using api: ArchiverseAPI) async {
        if featuredPosts.isEmpty && recentPosts.isEmpty && communities.isEmpty {
            await refresh(using: api)
        }

        ensureNavigationState()
        normalizeFocusedItem()
        isPresentingBroadcast = true
        isExternalDisplayActive = isRouteConnected

        if isRouteConnected {
            routeActivationNonce = UUID()
        }
    }

    func stopBroadcast() {
        isPresentingBroadcast = false
        isExternalDisplayActive = false
        isSearchKeyboardPresented = false
    }

    func selectSection(_ section: AirPlayTVSection) {
        selectedSection = section
        navigationPath = [rootScreen(for: section)]
        normalizeFocusedItem(preferred: .section(section))
    }

    func selectPost(_ post: ArchiversePost) {
        selectedPost = post
        pushScreen(.postDetail(post.id))
        normalizeFocusedItem(preferred: defaultFocusForPost(post))
    }

    func selectPost(_ post: ArchiversePost, using api: ArchiverseAPI) async {
        selectPost(post)
        await loadSelectedPostData(for: post, using: api)
    }

    func toggleYeahOnSelectedPost() {
        guard let selectedPost else { return }
        yeahStore?.toggleYeah(for: selectedPost)
        objectWillChange.send()
    }

    func selectCommunity(_ community: ArchiverseCommunity, using api: ArchiverseAPI) async {
        selectedCommunity = community
        pushScreen(.communityDetail(community.id))
        normalizeFocusedItem(preferred: .communitySort(communitySortMode))
        await loadCommunityPosts(for: community, using: api)
    }

    func selectUser(_ user: ArchiverseUser, using api: ArchiverseAPI) async {
        selectedCommunity = nil
        do {
            selectedUser = try await api.fetchUser(id: user.nnid ?? user.miiName)
        } catch {
            selectedUser = user
        }
        pushScreen(.userProfile(selectedUser?.id ?? user.id))
        normalizeFocusedItem(preferred: .userContent(userContentMode))
        await loadSelectedUserContent(using: api)
    }

    func runSearch(using api: ArchiverseAPI) async {
        let query = searchQuery.trimmed
        guard !query.isEmpty else {
            searchedPosts = []
            searchedCommunities = []
            searchedUsers = []
            return
        }

        guard !isSearching else { return }
        isSearching = true
        errorMessage = nil
        needsArchiveUnlock = false
        defer { isSearching = false }

        do {
            switch searchScope {
            case .posts:
                let posts = try await api.searchPosts(query: query)
                searchedPosts = posts
                searchedCommunities = []
                searchedUsers = []
            case .communities:
                let items = try await api.searchCommunities(query: query)
                searchedCommunities = items
                searchedPosts = []
                searchedUsers = []
            case .users:
                let users = try await api.searchUsers(query: query)
                searchedUsers = users
                searchedPosts = []
                searchedCommunities = []
            }
            navigationPath = [rootScreen(for: .search)]
            normalizeFocusedItem(preferred: .searchField)
        } catch {
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before search can load TV results."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func externalSceneDidConnect() {
        isRouteConnected = true

        if isPresentingBroadcast {
            isExternalDisplayActive = true
            routeActivationNonce = UUID()
        }
    }

    func externalSceneDidDisconnect() {
        isRouteConnected = false
        isExternalDisplayActive = false
    }

    func moveFocus(_ direction: AirPlayRemoteDirection) {
        let rows = focusRows()
        guard !rows.isEmpty else { return }

        let current = focusedItem
        let currentRow = rows.firstIndex(where: { $0.contains(current) }) ?? 0
        let currentColumn = rows[currentRow].firstIndex(of: current) ?? 0

        var nextRow = currentRow
        var nextColumn = currentColumn

        switch direction {
        case .up:
            nextRow = max(0, currentRow - 1)
        case .down:
            nextRow = min(rows.count - 1, currentRow + 1)
        case .left:
            nextColumn = max(0, currentColumn - 1)
        case .right:
            nextColumn = min(rows[currentRow].count - 1, currentColumn + 1)
        }

        nextColumn = min(nextColumn, rows[nextRow].count - 1)
        focusedItem = rows[nextRow][nextColumn]
        persistFocusedItem(focusedItem)
    }

    func setFocusedItem(_ item: AirPlayRemoteFocusItem) {
        focusedItem = item
        persistFocusedItem(item)
    }

    func goBack() {
        isSearchKeyboardPresented = false

        if navigationPath.count > 1 {
            navigationPath.removeLast()
        } else {
            navigationPath = [rootScreen(for: selectedSection)]
        }

        let targetScreen = currentScreen
        normalizeFocusedItem(preferred: lastFocusedItemByScreen[targetScreen])
    }

    func goHome() {
        isSearchKeyboardPresented = false
        navigationPath = [rootScreen(for: selectedSection)]
        normalizeFocusedItem(preferred: .section(selectedSection))
    }

    func activateFocusedItem(using api: ArchiverseAPI) async {
        switch focusedItem {
        case .section(let section):
            selectSection(section)
        case .searchField:
            isSearchKeyboardPresented = true
        case .searchScope(let scope):
            searchScope = scope
            if !searchQuery.trimmed.isEmpty {
                await runSearch(using: api)
            } else {
                normalizeFocusedItem(preferred: .searchScope(scope))
            }
        case .communitySort(let mode):
            await setCommunitySortMode(mode, using: api)
        case .userContent(let mode):
            await setUserContentMode(mode, using: api)
        case .post(let postID):
            guard let post = findPost(id: postID) else { return }
            await selectPost(post, using: api)
        case .community(let communityID):
            guard let community = findCommunity(id: communityID) else { return }
            await selectCommunity(community, using: api)
        case .user(let userID):
            guard let user = findUser(id: userID) else { return }
            await selectUser(user, using: api)
        case .postAuthor(let userID):
            guard let post = selectedPost else { return }
            await openUser(
                userID: userID,
                displayName: post.miiName,
                avatarURLString: post.miiURLString,
                using: api
            )
        case .postCommunity(let communityID):
            guard let post = selectedPost,
                  let titleID = post.titleID,
                  let gameID = post.gameID else { return }
            await openCommunity(
                id: communityID,
                titleID: titleID,
                gameID: gameID,
                title: post.communityTitle ?? "Community",
                iconURLString: post.communityIconURLString,
                using: api
            )
        case .postYeah:
            toggleYeahOnSelectedPost()
        case .reply(let replyID):
            guard let reply = selectedPostReplies.first(where: { $0.id == replyID }) else { return }
            let userID = reply.nnid?.nilIfEmpty ?? reply.miiName
            await openUser(
                userID: userID,
                displayName: reply.miiName,
                avatarURLString: reply.miiURLString,
                using: api
            )
        case .userReply(let replyID):
            guard let item = selectedUserReplies.first(where: { $0.id == replyID }),
                  let post = item.post else { return }
            await selectPost(post, using: api)
        case .settingsRefresh:
            await refresh(using: api)
        case .loadMoreFeed:
            await loadMoreFeed(using: api)
        case .loadMoreCommunities:
            await loadMoreCommunities(using: api)
        case .loadMoreCommunityPosts:
            await loadMoreCommunityPosts(using: api)
        case .loadMoreUserPosts:
            await loadMoreUserPosts(using: api)
        case .loadMoreUserReplies:
            await loadMoreUserReplies(using: api)
        case .loadMoreReplies:
            await loadMoreSelectedPostReplies(using: api)
        }
    }

    func setCommunitySortMode(_ mode: CommunitySortMode, using api: ArchiverseAPI) async {
        guard communitySortMode != mode else { return }
        communitySortMode = mode

        if let selectedCommunity {
            await loadCommunityPosts(for: selectedCommunity, using: api)
        }

        normalizeFocusedItem(preferred: .communitySort(mode))
    }

    func setUserContentMode(_ mode: UserContentMode, using api: ArchiverseAPI) async {
        guard userContentMode != mode else { return }
        userContentMode = mode
        await loadSelectedUserContent(using: api)
        normalizeFocusedItem(preferred: .userContent(mode))
    }

    private func loadCommunityPosts(for community: ArchiverseCommunity, using api: ArchiverseAPI) async {
        guard !isLoadingCommunityPosts else { return }
        isLoadingCommunityPosts = true
        defer { isLoadingCommunityPosts = false }
        currentCommunityPostsPage = 1

        do {
            let posts = try await api.fetchCommunityPosts(
                titleID: community.titleID,
                gameID: community.gameID,
                sortMode: communitySortMode == .popular ? "popular" : "recent",
                page: 1,
                beforeDate: archiveSettings?.selectedArchiveDate
            )
            communityPosts = posts
            canLoadMoreCommunityPosts = !posts.isEmpty
            normalizeFocusedItem()
        } catch {
            communityPosts = []
            canLoadMoreCommunityPosts = false
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before community posts can load on TV."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadUserPosts(for user: ArchiverseUser, using api: ArchiverseAPI) async {
        guard let userID = user.nnid ?? user.miiName.nilIfEmpty else { return }
        guard !isLoadingUserPosts else { return }
        isLoadingUserPosts = true
        defer { isLoadingUserPosts = false }
        currentUserPostsPage = 1

        do {
            let posts = try await api.fetchUserPosts(
                userID: userID,
                sortMode: "recent",
                page: 1,
                beforeDate: archiveSettings?.selectedArchiveDate
            )
            selectedUserPosts = posts
            canLoadMoreUserPosts = !posts.isEmpty
            normalizeFocusedItem()
        } catch {
            selectedUserPosts = []
            canLoadMoreUserPosts = false
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before user posts can load on TV."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadUserReplies(for user: ArchiverseUser, using api: ArchiverseAPI) async {
        guard let userID = user.nnid ?? user.miiName.nilIfEmpty else { return }
        guard !isLoadingUserReplies else { return }
        isLoadingUserReplies = true
        defer { isLoadingUserReplies = false }
        currentUserRepliesPage = 1

        do {
            selectedUserReplies = try await api.fetchUserReplies(userID: userID)
            canLoadMoreUserReplies = !selectedUserReplies.isEmpty
            normalizeFocusedItem()
        } catch {
            selectedUserReplies = []
            canLoadMoreUserReplies = false
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before user replies can load on TV."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadSelectedUserContent(using api: ArchiverseAPI) async {
        guard let selectedUser else { return }

        switch userContentMode {
        case .posts:
            await loadUserPosts(for: selectedUser, using: api)
        case .replies:
            await loadUserReplies(for: selectedUser, using: api)
        }
    }

    private func loadSelectedPostData(for post: ArchiversePost, using api: ArchiverseAPI) async {
        guard !isLoadingSelectedPost else { return }
        isLoadingSelectedPost = true
        defer { isLoadingSelectedPost = false }

        let currentPostID = post.rawID ?? post.id
        let shouldRefreshPost = post.nnid == nil || post.communityTitle == nil
        currentPostRepliesPage = 1

        do {
            selectedPostReplies = try await api.fetchReplies(postID: currentPostID).filter { !$0.doNotShow }
            errorMessage = nil
            needsArchiveUnlock = false
            canLoadMorePostReplies = !selectedPostReplies.isEmpty
            normalizeFocusedItem()
        } catch {
            selectedPostReplies = []
            canLoadMorePostReplies = false
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before TV comments can be refreshed."
            } else {
                errorMessage = error.localizedDescription
            }
        }

        guard shouldRefreshPost else { return }

        do {
            let refreshedPost = try await api.fetchPost(id: currentPostID)
            selectedPost = refreshedPost
            yeahStore?.refreshIfLiked(refreshedPost)
            if errorMessage == nil {
                needsArchiveUnlock = false
            }
        } catch {
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                if errorMessage == nil {
                    errorMessage = "Cloudflare verification is required before this TV post can be fully refreshed."
                }
            } else if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMoreFeed(using api: ArchiverseAPI) async {
        guard canLoadMoreFeed, !isLoadingMoreFeed else { return }
        isLoadingMoreFeed = true
        defer { isLoadingMoreFeed = false }

        let nextPage = currentFeedPage + 1

        do {
            let posts = try await api.fetchRandomPosts(page: nextPage)
            guard !posts.isEmpty else {
                canLoadMoreFeed = false
                return
            }

            let existingPostIDs = Set(recentPosts.map(\.id))
            let appendedPosts = posts.filter { !existingPostIDs.contains($0.id) }
            recentPosts = deduplicatedPosts(recentPosts + posts)
            currentFeedPage = nextPage
            canLoadMoreFeed = true
            if let firstVisiblePostID = filterPosts(appendedPosts).first?.id {
                normalizeFocusedItem(preferred: .post(firstVisiblePostID))
            } else {
                normalizeFocusedItem(preferred: .loadMoreFeed)
            }
        } catch {
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before more feed posts can load on TV."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMoreCommunities(using api: ArchiverseAPI) async {
        guard canLoadMoreCommunities, !isLoadingMoreCommunities else { return }
        isLoadingMoreCommunities = true
        defer { isLoadingMoreCommunities = false }

        let nextPage = currentCommunitiesPage + 1

        do {
            let items = try await api.fetchCommunities(page: nextPage)
            guard !items.isEmpty else {
                canLoadMoreCommunities = false
                return
            }

            var seen = Set(communities.map(\.id))
            let appendedCommunities = items.filter { seen.insert($0.id).inserted }
            communities.append(contentsOf: appendedCommunities)
            currentCommunitiesPage = nextPage
            canLoadMoreCommunities = true
            if let firstCommunityID = appendedCommunities.first?.id {
                normalizeFocusedItem(preferred: .community(firstCommunityID))
            } else {
                normalizeFocusedItem(preferred: .loadMoreCommunities)
            }
        } catch {
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before more communities can load on TV."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMoreCommunityPosts(using api: ArchiverseAPI) async {
        guard let community = selectedCommunity,
              canLoadMoreCommunityPosts,
              !isLoadingMoreCommunityPosts else { return }
        isLoadingMoreCommunityPosts = true
        defer { isLoadingMoreCommunityPosts = false }

        let nextPage = currentCommunityPostsPage + 1

        do {
            let posts = try await api.fetchCommunityPosts(
                titleID: community.titleID,
                gameID: community.gameID,
                sortMode: communitySortMode == .popular ? "popular" : "recent",
                page: nextPage,
                beforeDate: archiveSettings?.selectedArchiveDate
            )
            guard !posts.isEmpty else {
                canLoadMoreCommunityPosts = false
                return
            }

            let existingPostIDs = Set(communityPosts.map(\.id))
            let appendedPosts = posts.filter { !existingPostIDs.contains($0.id) }
            communityPosts = deduplicatedPosts(communityPosts + posts)
            currentCommunityPostsPage = nextPage
            canLoadMoreCommunityPosts = true
            if let firstVisiblePostID = filterPosts(appendedPosts).first?.id {
                normalizeFocusedItem(preferred: .post(firstVisiblePostID))
            } else {
                normalizeFocusedItem(preferred: .loadMoreCommunityPosts)
            }
        } catch {
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before more community posts can load on TV."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMoreUserPosts(using api: ArchiverseAPI) async {
        guard let user = selectedUser,
              let userID = user.nnid ?? user.miiName.nilIfEmpty,
              canLoadMoreUserPosts,
              !isLoadingMoreUserPosts else { return }
        isLoadingMoreUserPosts = true
        defer { isLoadingMoreUserPosts = false }

        let nextPage = currentUserPostsPage + 1

        do {
            let posts = try await api.fetchUserPosts(
                userID: userID,
                sortMode: "recent",
                page: nextPage,
                beforeDate: archiveSettings?.selectedArchiveDate
            )
            guard !posts.isEmpty else {
                canLoadMoreUserPosts = false
                return
            }

            let existingPostIDs = Set(selectedUserPosts.map(\.id))
            let appendedPosts = posts.filter { !existingPostIDs.contains($0.id) }
            selectedUserPosts = deduplicatedPosts(selectedUserPosts + posts)
            currentUserPostsPage = nextPage
            canLoadMoreUserPosts = true
            if let firstVisiblePostID = filterPosts(appendedPosts).first?.id {
                normalizeFocusedItem(preferred: .post(firstVisiblePostID))
            } else {
                normalizeFocusedItem(preferred: .loadMoreUserPosts)
            }
        } catch {
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before more user posts can load on TV."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMoreUserReplies(using api: ArchiverseAPI) async {
        guard let user = selectedUser,
              let userID = user.nnid ?? user.miiName.nilIfEmpty,
              canLoadMoreUserReplies,
              !isLoadingMoreUserReplies else { return }
        isLoadingMoreUserReplies = true
        defer { isLoadingMoreUserReplies = false }

        let nextPage = currentUserRepliesPage + 1

        do {
            let replies = try await api.fetchUserReplies(userID: userID, page: nextPage)
            guard !replies.isEmpty else {
                canLoadMoreUserReplies = false
                return
            }

            var seen = Set(selectedUserReplies.map(\.id))
            let appendedReplies = replies.filter { seen.insert($0.id).inserted }
            selectedUserReplies.append(contentsOf: appendedReplies)
            currentUserRepliesPage = nextPage
            canLoadMoreUserReplies = true
            if let firstVisibleReplyID = ArchiveDateFilter.filter(
                replyFeed: appendedReplies,
                cutoffDate: archiveSettings?.selectedArchiveDate
            ).first?.id {
                normalizeFocusedItem(preferred: .userReply(firstVisibleReplyID))
            } else {
                normalizeFocusedItem(preferred: .loadMoreUserReplies)
            }
        } catch {
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before more user replies can load on TV."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMoreSelectedPostReplies(using api: ArchiverseAPI) async {
        guard let post = selectedPost,
              canLoadMorePostReplies,
              !isLoadingMoreReplies else { return }
        isLoadingMoreReplies = true
        defer { isLoadingMoreReplies = false }

        let nextPage = currentPostRepliesPage + 1
        let currentPostID = post.rawID ?? post.id

        do {
            let replies = try await api.fetchReplies(postID: currentPostID, page: nextPage).filter { !$0.doNotShow }
            guard !replies.isEmpty else {
                canLoadMorePostReplies = false
                return
            }

            var seen = Set(selectedPostReplies.map(\.id))
            let appendedReplies = replies.filter { seen.insert($0.id).inserted }
            selectedPostReplies.append(contentsOf: appendedReplies)
            currentPostRepliesPage = nextPage
            canLoadMorePostReplies = true
            if let firstVisibleReplyID = ArchiveDateFilter.filter(
                replies: appendedReplies,
                cutoffDate: archiveSettings?.selectedArchiveDate
            ).first?.id {
                normalizeFocusedItem(preferred: .reply(firstVisibleReplyID))
            } else {
                normalizeFocusedItem(preferred: .loadMoreReplies)
            }
        } catch {
            if error.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before more comments can load on TV."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rootScreen(for section: AirPlayTVSection) -> AirPlayTVScreen {
        switch section {
        case .home:
            return .feedRoot
        case .search:
            return .searchRoot
        case .communities:
            return .communitiesRoot
        case .yeahs:
            return .yeahsRoot
        case .settings:
            return .settingsRoot
        }
    }

    private func ensureNavigationState() {
        if navigationPath.isEmpty {
            navigationPath = [rootScreen(for: selectedSection)]
        }
    }

    private func pushScreen(_ screen: AirPlayTVScreen) {
        ensureNavigationState()

        if navigationPath.last == screen {
            return
        }

        navigationPath.append(screen)
    }

    private func normalizeFocusedItem(preferred: AirPlayRemoteFocusItem? = nil) {
        let rows = focusRows()
        guard !rows.isEmpty else { return }

        if let preferred, rows.contains(where: { $0.contains(preferred) }) {
            focusedItem = preferred
            persistFocusedItem(preferred)
            return
        }

        if rows.contains(where: { $0.contains(focusedItem) }) {
            persistFocusedItem(focusedItem)
            return
        }

        focusedItem = rows[0][0]
        persistFocusedItem(focusedItem)
    }

    private func persistFocusedItem(_ item: AirPlayRemoteFocusItem, on screen: AirPlayTVScreen? = nil) {
        lastFocusedItemByScreen[screen ?? currentScreen] = item
    }

    private func focusRows() -> [[AirPlayRemoteFocusItem]] {
        var rows: [[AirPlayRemoteFocusItem]] = [
            AirPlayTVSection.allCases.map { .section($0) }
        ]

        switch currentScreen {
        case .feedRoot:
            rows.append(contentsOf: filteredFeedPosts.map { [.post($0.id)] })
            if canLoadMoreFeedItems {
                rows.append([.loadMoreFeed])
            }
        case .searchRoot:
            rows.append([.searchField])
            rows.append(AirPlaySearchScope.allCases.map { .searchScope($0) })
            switch searchScope {
            case .posts:
                rows.append(contentsOf: filteredSearchedPosts.map { [.post($0.id)] })
            case .communities:
                rows.append(contentsOf: searchedCommunities.map { [.community($0.id)] })
            case .users:
                rows.append(contentsOf: searchedUsers.map { [.user($0.id)] })
            }
        case .communitiesRoot:
            rows.append(contentsOf: visibleCommunities.map { [.community($0.id)] })
            if canLoadMoreCommunityItems {
                rows.append([.loadMoreCommunities])
            }
        case .communityDetail:
            rows.append(CommunitySortMode.allCases.map { .communitySort($0) })
            rows.append(contentsOf: filteredCommunityPosts.map { [.post($0.id)] })
            if canLoadMoreCurrentCommunityPosts {
                rows.append([.loadMoreCommunityPosts])
            }
        case .yeahsRoot:
            rows.append(contentsOf: filteredLikedPosts.map { [.post($0.id)] })
        case .settingsRoot:
            rows.append([.settingsRefresh])
        case .userProfile:
            rows.append(UserContentMode.allCases.map { .userContent($0) })
            switch userContentMode {
            case .posts:
                rows.append(contentsOf: filteredSelectedUserPosts.map { [.post($0.id)] })
                if canLoadMoreCurrentUserPosts {
                    rows.append([.loadMoreUserPosts])
                }
            case .replies:
                rows.append(contentsOf: filteredSelectedUserReplies.map { [.userReply($0.id)] })
                if canLoadMoreCurrentUserReplies {
                    rows.append([.loadMoreUserReplies])
                }
            }
        case .postDetail:
            var headerRow: [AirPlayRemoteFocusItem] = []
            if let userID = selectedPost?.nnid?.nilIfEmpty ?? selectedPost?.miiName.nilIfEmpty {
                headerRow.append(.postAuthor(userID))
            }
            if let post = selectedPost,
               let titleID = post.titleID,
               let gameID = post.gameID {
                headerRow.append(.postCommunity("\(titleID)-\(gameID)"))
            }
            if !headerRow.isEmpty {
                rows.append(headerRow)
            }
            rows.append([.postYeah])
            rows.append(contentsOf: filteredSelectedPostReplies.map { [.reply($0.id)] })
            if canLoadMoreCurrentPostReplies {
                rows.append([.loadMoreReplies])
            }
        }

        return rows.filter { !$0.isEmpty }
    }

    private var filteredFeedPosts: [ArchiversePost] {
        deduplicatedPosts(filteredFeaturedPosts + filteredRecentPosts)
    }

    private func defaultFocusForPost(_ post: ArchiversePost) -> AirPlayRemoteFocusItem {
        if let userID = post.nnid?.nilIfEmpty ?? post.miiName.nilIfEmpty {
            return .postAuthor(userID)
        }
        return .postYeah
    }

    private func findPost(id: String) -> ArchiversePost? {
        let pools = [
            filteredFeedPosts,
            filteredCommunityPosts,
            filteredSelectedUserPosts,
            filteredSearchedPosts,
            filteredLikedPosts
        ]
        return pools.joined().first(where: { $0.id == id })
            ?? (selectedPost?.id == id ? selectedPost : nil)
    }

    private func findCommunity(id: String) -> ArchiverseCommunity? {
        let pools = [communities, searchedCommunities]
        return pools.joined().first(where: { $0.id == id }) ?? selectedCommunity
    }

    private func findUser(id: String) -> ArchiverseUser? {
        searchedUsers.first(where: { $0.id == id }) ?? selectedUser
    }

    private func openUser(
        userID: String,
        displayName: String,
        avatarURLString: String?,
        using api: ArchiverseAPI
    ) async {
        let placeholder = ArchiverseUser(
            nnid: userID,
            miiName: displayName,
            miiURLString: avatarURLString,
            bio: nil,
            bannerURLString: nil,
            country: nil,
            numFollowers: nil,
            numFollowing: nil,
            numFriends: nil,
            numPosts: nil,
            birthday: nil,
            doNotShow: false,
            webArchiveURLString: nil,
            warcLocationURLString: nil
        )
        await selectUser(placeholder, using: api)
    }

    private func openCommunity(
        id: String,
        titleID: String,
        gameID: String,
        title: String,
        iconURLString: String?,
        using api: ArchiverseAPI
    ) async {
        let community = findCommunity(id: id) ?? ArchiverseCommunity(
            gameID: gameID,
            titleID: titleID,
            communityTitle: title,
            communityBannerURLString: nil,
            communityIconURLString: iconURLString,
            badge: nil,
            gameTitle: title,
            numPosts: 0,
            region: "Archive",
            webArchiveURLString: nil
        )
        await selectCommunity(community, using: api)
    }

    private func filterPosts(_ posts: [ArchiversePost]) -> [ArchiversePost] {
        ArchiveDateFilter.filter(posts: posts, cutoffDate: archiveSettings?.selectedArchiveDate)
    }

    private func deduplicatedPosts(_ posts: [ArchiversePost]) -> [ArchiversePost] {
        var seen: Set<String> = []
        return posts.filter { seen.insert($0.id).inserted }
    }

    private func attempt<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private static let settingsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct AirPlayControlView: View {
    @EnvironmentObject private var airPlay: AirPlaySessionController
    @EnvironmentObject private var yeahStore: YeahStore
    @EnvironmentObject private var archiveSettings: ArchiveSettingsStore

    let api: ArchiverseAPI

    @State private var showArchiveUnlockSheet = false

    var body: some View {
        MiiverseScreen(
            title: "AirPlay",
            subtitle: "Open the TV broadcast here. When a TV connects, this device switches into a remote controller."
        ) {
            controlCard

            if let errorMessage = airPlay.errorMessage {
                MiiverseStatusBanner(
                    text: errorMessage,
                    tint: airPlay.needsArchiveUnlock ? .orange : MiiversePalette.badgeBlue
                )
            }

            if airPlay.needsArchiveUnlock {
                ArchiveUnlockPromptCard(
                    message: "The TV screen could not load live archive data. Refresh Cloudflare verification and try again."
                ) {
                    showArchiveUnlockSheet = true
                }
            }

            previewCard
        }
        .navigationTitle("AirPlay")
        .task {
            airPlay.configureStores(yeahStore: yeahStore, archiveSettings: archiveSettings)
            await airPlay.refreshIfNeeded(using: api)
        }
        .refreshable {
            await airPlay.refresh(using: api)
        }
        .sheet(isPresented: $showArchiveUnlockSheet) {
            ArchiveUnlockView {
                Task {
                    await airPlay.refresh(using: api)
                }
            }
        }
    }

    private var controlCard: some View {
        MiiverseCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    routeStatusPill

                    Spacer(minLength: 0)

                    if airPlay.isExternalDisplayActive {
                        Text("TV Live")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(MiiversePalette.greenDark)
                            )
                    }
                }

                Text(airPlay.routeInstructionText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                routePickerButton

                HStack(spacing: 12) {
                    MiiversePrimaryButton(
                        title: "Start TV Broadcast",
                        systemImage: "airplayvideo"
                    ) {
                        Task {
                            await airPlay.beginBroadcast(using: api)
                        }
                    }

                    if airPlay.isPresentingBroadcast {
                        Button {
                            airPlay.stopBroadcast()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Stop")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(MiiversePalette.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(MiiversePalette.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var previewCard: some View {
        MiiverseCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("TV Preview")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)

                    Spacer(minLength: 0)

                    Text(airPlay.selectedSection.title)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.greenDark)
                }

                AirPlayTVStageView(
                    api: api,
                    interactive: false,
                    fillsDisplay: false,
                    showsCloseButton: false
                )
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(MiiversePalette.line, lineWidth: 1)
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var routeStatusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(airPlay.isRouteConnected ? MiiversePalette.green : Color.orange)
                .frame(width: 10, height: 10)

            Text(airPlay.routeStatusText)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(MiiversePalette.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.84))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(MiiversePalette.line, lineWidth: 1)
        )
    }

    private var routePickerButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.84))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MiiversePalette.line, lineWidth: 1)

            HStack(spacing: 12) {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(MiiversePalette.greenDark)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose AirPlay Display")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)

                    Text("If a TV is connected while the broadcast is open, the phone switches to the remote UI automatically.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .allowsHitTesting(false)

            AirPlayRoutePickerControl()
                .opacity(0.02)
        }
        .frame(height: 78)
    }
}

struct AirPlayBroadcastShellView: View {
    @EnvironmentObject private var airPlay: AirPlaySessionController
    @EnvironmentObject private var yeahStore: YeahStore
    @EnvironmentObject private var archiveSettings: ArchiveSettingsStore
    @Environment(\.dismiss) private var dismiss

    let api: ArchiverseAPI
    @State private var showArchiveUnlockSheet = false

    var body: some View {
        Group {
            if airPlay.isRemoteMode {
                AirPlayRemoteControlView(api: api)
            } else {
                AirPlayLocalPreviewHost(api: api)
            }
        }
        .task {
            airPlay.configureStores(yeahStore: yeahStore, archiveSettings: archiveSettings)
        }
        .overlay(alignment: .top) {
            if airPlay.needsArchiveUnlock {
                ArchiveUnlockPromptCard(
                    message: "TV broadcast cannot load live archive data until Cloudflare verification is refreshed.",
                    buttonTitle: "Reauthenticate Now"
                ) {
                    showArchiveUnlockSheet = true
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .frame(maxWidth: 520)
            }
        }
        .onChange(of: airPlay.needsArchiveUnlock) { _, needsUnlock in
            if needsUnlock {
                showArchiveUnlockSheet = true
            }
        }
        .onChange(of: airPlay.isPresentingBroadcast) { _, isPresented in
            if !isPresented {
                dismiss()
            }
        }
        .sheet(isPresented: $showArchiveUnlockSheet) {
            ArchiveUnlockView {
                Task {
                    await airPlay.refresh(using: api)
                }
            }
        }
    }
}

private struct AirPlayLocalPreviewHost: View {
    @EnvironmentObject private var airPlay: AirPlaySessionController

    let api: ArchiverseAPI

    @State private var showSplash = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showSplash {
                OpeningSplashView(
                    isPresented: $showSplash,
                    playsTheme: true,
                    showsSkipHint: true,
                    layoutMode: .immersive
                )
            } else {
                VStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Local TV Preview")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Connect a TV at any time. This view will switch to the remote controller automatically.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.78))
                        }

                        Spacer(minLength: 0)

                        Button {
                            airPlay.stopBroadcast()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "xmark")
                                Text("Close")
                            }
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)

                    AirPlayTVStageView(
                        api: api,
                        interactive: true,
                        fillsDisplay: false,
                        showsCloseButton: false
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
        }
    }
}

struct AirPlayExternalDisplayShell: View {
    @EnvironmentObject private var airPlay: AirPlaySessionController

    @State private var showSplash = false

    var body: some View {
        ZStack {
            if airPlay.isPresentingBroadcast {
                AirPlayTVStageView(
                    api: ArchiverseAPI(),
                    interactive: false,
                    fillsDisplay: true,
                    showsCloseButton: false
                )

                if showSplash {
                    OpeningSplashView(
                        isPresented: $showSplash,
                        playsTheme: true,
                        showsSkipHint: false,
                        layoutMode: .immersive
                    )
                }
            } else {
                externalIdleState
            }
        }
        .ignoresSafeArea()
        .onAppear {
            showSplash = airPlay.isPresentingBroadcast
        }
        .onChange(of: airPlay.isPresentingBroadcast) { _, isPresenting in
            showSplash = isPresenting
        }
        .onChange(of: airPlay.routeActivationNonce) { _, _ in
            if airPlay.isPresentingBroadcast {
                showSplash = true
            }
        }
    }

    private var externalIdleState: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.08, blue: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 22) {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 92, weight: .black))
                    .foregroundStyle(MiiversePalette.green)

                Text("Archiverse TV Ready")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Start TV Broadcast on iPhone to show the Miiverse archive interface here.")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(maxWidth: 760)
            }
            .padding(40)
        }
    }
}

private struct AirPlayRemoteControlView: View {
    @EnvironmentObject private var airPlay: AirPlaySessionController

    let api: ArchiverseAPI
    @State private var searchDraft = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                remoteBackdrop.ignoresSafeArea()

                VStack {
                    Spacer(minLength: 0)

                    remoteBody(size: geometry.size)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, geometry.size.width < 430 ? 18 : 24)
                .padding(.vertical, 18)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { airPlay.isSearchKeyboardPresented },
                set: { airPlay.isSearchKeyboardPresented = $0 }
            )
        ) {
            NavigationStack {
                Form {
                    Section("Search Query") {
                        TextField("Search the archive", text: $searchDraft)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .onSubmit {
                                submitSearch()
                            }
                    }
                }
                .navigationTitle("Search TV")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            airPlay.isSearchKeyboardPresented = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Search") {
                            submitSearch()
                        }
                    }
                }
            }
        }
        .onAppear {
            searchDraft = airPlay.searchQuery
        }
        .onChange(of: airPlay.isSearchKeyboardPresented) { _, isPresented in
            if isPresented {
                searchDraft = airPlay.searchQuery
            }
        }
    }

    private var remoteBackdrop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.10, blue: 0.08),
                Color(red: 0.03, green: 0.05, blue: 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func remoteBody(size: CGSize) -> some View {
        VStack(spacing: size.width < 430 ? 16 : 20) {
            HStack {
                Spacer(minLength: 0)

                remoteButtonLabel("EXIT", diameter: size.width < 430 ? 52 : 58, tint: .red) {
                    airPlay.stopBroadcast()
                }
            }

            remoteTopBezel

            HStack(alignment: .center, spacing: size.width < 430 ? 18 : 24) {
                remoteDirectionalPad(size: size)
                remoteActionCluster(size: size)
            }

            remoteCenterRow(size: size)
            remoteBottomRow(size: size)
            remoteLEDs
        }
        .padding(.horizontal, size.width < 430 ? 22 : 28)
        .padding(.top, 18)
        .padding(.bottom, 28)
        .frame(maxWidth: min(size.width - 8, 360))
        .background(
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            MiiversePalette.paper,
                            Color.white.opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.26), radius: 28, x: 0, y: 18)
    }

    private var remoteTopBezel: some View {
        VStack(spacing: 12) {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.88))
                .frame(width: 94, height: 10)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Circle().fill(Color.gray.opacity(0.6)).frame(width: 7, height: 7)
                Circle().fill(Color.gray.opacity(0.45)).frame(width: 7, height: 7)
                Circle().fill(Color.gray.opacity(0.3)).frame(width: 7, height: 7)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func remoteDirectionalPad(size: CGSize) -> some View {
        VStack(spacing: 10) {
            remoteButtonLabel("▲", diameter: size.width < 430 ? 66 : 72, tint: MiiversePalette.greenDark) {
                airPlay.moveFocus(.up)
            }

            HStack(spacing: 10) {
                remoteButtonLabel("◀", diameter: size.width < 430 ? 66 : 72, tint: MiiversePalette.greenDark) {
                    airPlay.moveFocus(.left)
                }
                remoteButtonLabel("▶", diameter: size.width < 430 ? 66 : 72, tint: MiiversePalette.greenDark) {
                    airPlay.moveFocus(.right)
                }
            }

            remoteButtonLabel("▼", diameter: size.width < 430 ? 66 : 72, tint: MiiversePalette.greenDark) {
                airPlay.moveFocus(.down)
            }
        }
    }

    private func remoteActionCluster(size: CGSize) -> some View {
        VStack(spacing: 16) {
            remoteButtonLabel("A", diameter: size.width < 430 ? 102 : 112, tint: MiiversePalette.green) {
                Task {
                    await airPlay.activateFocusedItem(using: api)
                }
            }

            remoteButtonLabel("B", diameter: size.width < 430 ? 74 : 82, tint: MiiversePalette.badgeBlue) {
                airPlay.goBack()
            }
        }
    }

    private func remoteCenterRow(size: CGSize) -> some View {
        HStack(spacing: 14) {
            remoteOvalButton("HOME", width: size.width < 430 ? 128 : 144, tint: MiiversePalette.greenDark) {
                airPlay.goHome()
            }

            if airPlay.needsArchiveUnlock {
                remoteButtonLabel("!", diameter: size.width < 430 ? 56 : 60, tint: .orange) {
                    Task {
                        await airPlay.refresh(using: api)
                    }
                }
            }
        }
    }

    private func remoteBottomRow(size: CGSize) -> some View {
        HStack(spacing: 14) {
            remoteOvalButton("TV", width: size.width < 430 ? 88 : 96, tint: MiiversePalette.badgeBlue) {
                airPlay.selectSection(.home)
            }

            remoteOvalButton("SYNC", width: size.width < 430 ? 128 : 144, tint: MiiversePalette.greenDark) {
                Task {
                    await airPlay.refresh(using: api)
                }
            }
        }
    }

    private var remoteLEDs: some View {
        HStack(spacing: 10) {
            ForEach(Array(AirPlayTVSection.allCases.enumerated()), id: \.offset) { index, section in
                Capsule(style: .continuous)
                    .fill(airPlay.selectedSection == section ? MiiversePalette.greenDark : Color.gray.opacity(0.24))
                    .frame(width: 34, height: 8)
                    .overlay(
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(airPlay.selectedSection == section ? .white : MiiversePalette.secondaryText)
                    )
            }
        }
    }

    private func remoteButtonLabel(
        _ title: String,
        diameter: CGFloat,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: diameter * 0.34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.96), tint.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.62), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.22), radius: 8, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func remoteOvalButton(
        _ title: String,
        width: CGFloat,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: width, height: 52)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.96), tint.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.22), radius: 8, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func submitSearch() {
        airPlay.searchQuery = searchDraft
        airPlay.isSearchKeyboardPresented = false
        Task {
            await airPlay.runSearch(using: api)
        }
    }
}

private struct AirPlayTVStageView: View {
    @EnvironmentObject private var airPlay: AirPlaySessionController

    let api: ArchiverseAPI
    let interactive: Bool
    let fillsDisplay: Bool
    let showsCloseButton: Bool
    private let designCanvas = CGSize(width: 1280, height: 720)

    var body: some View {
        GeometryReader { geometry in
            let metrics = AirPlayTVMetrics(size: designCanvas)
            let scale = resolvedScale(for: geometry.size)

            ZStack {
                Color.black.ignoresSafeArea()

                tvCanvas(metrics: metrics)
                    .frame(width: designCanvas.width, height: designCanvas.height)
                    .scaleEffect(scale, anchor: .center)
                    .shadow(
                        color: fillsDisplay ? .clear : Color.black.opacity(0.34),
                        radius: fillsDisplay ? 0 : 18,
                        x: 0,
                        y: fillsDisplay ? 0 : 10
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func resolvedScale(for availableSize: CGSize) -> CGFloat {
        let horizontalInset = fillsDisplay ? 0.0 : 20.0
        let verticalInset = fillsDisplay ? 0.0 : 20.0
        let widthScale = max(0.1, (availableSize.width - horizontalInset * 2) / designCanvas.width)
        let heightScale = max(0.1, (availableSize.height - verticalInset * 2) / designCanvas.height)
        return min(widthScale, heightScale)
    }

    private func tvCanvas(metrics: AirPlayTVMetrics) -> some View {
        ZStack {
            tvBackground

            HStack(alignment: .top, spacing: metrics.scaled(18)) {
                tvSidebar(metrics: metrics)

                VStack(spacing: metrics.scaled(14)) {
                    tvHeader(metrics: metrics)
                    tvScreenBody(metrics: metrics)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(metrics.outerPadding)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: fillsDisplay ? 0 : 30, style: .continuous)
        )
    }

    private var tvBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 0.97),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                HStack(spacing: proxy.size.width / 14) {
                    ForEach(0..<13, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.gray.opacity(0.08))
                            .frame(width: proxy.size.width / 62)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            GeometryReader { proxy in
                ForEach(0..<32, id: \.self) { index in
                    Circle()
                        .fill(MiiversePalette.greenLight.opacity(index.isMultiple(of: 3) ? 0.18 : 0.10))
                        .frame(width: CGFloat((index % 3) + 4), height: CGFloat((index % 3) + 4))
                        .position(
                            x: CGFloat((index * 83) % Int(proxy.size.width)),
                            y: CGFloat((index * 57) % Int(proxy.size.height))
                        )
                }
            }
        }
    }

    private func tvSidebar(metrics: AirPlayTVMetrics) -> some View {
        VStack(spacing: metrics.scaled(12)) {
            VStack(spacing: metrics.scaled(8)) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: metrics.scaled(34), weight: .black))
                    .foregroundStyle(Color.gray.opacity(0.72))

                Text("User Menu")
                    .font(.system(size: metrics.scaled(15), weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, metrics.scaled(12))

            ForEach(AirPlayTVSection.allCases) { section in
                tvSidebarButton(section, metrics: metrics)
            }

            Spacer(minLength: 0)

            if airPlay.currentScreen != airPlay.currentScreenRoot {
                VStack(spacing: metrics.scaled(6)) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: metrics.scaled(26), weight: .black))
                        .foregroundStyle(Color.gray.opacity(0.72))

                    Text("Back")
                        .font(.system(size: metrics.scaled(14), weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, metrics.scaled(12))
            }
        }
        .padding(.horizontal, metrics.scaled(14))
        .padding(.vertical, metrics.scaled(16))
        .frame(width: metrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: metrics.scaled(34), style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.scaled(34), style: .continuous)
                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: metrics.scaled(18), x: metrics.scaled(4), y: metrics.scaled(8))
    }

    private func tvSidebarButton(_ section: AirPlayTVSection, metrics: AirPlayTVMetrics) -> some View {
        tvFocusButton(
            focus: .section(section),
            cornerRadius: metrics.scaled(22),
            metrics: metrics
        ) {
            airPlay.selectSection(section)
        } label: {
            VStack(spacing: metrics.scaled(8)) {
                Image(systemName: section.systemImage)
                    .font(.system(size: metrics.scaled(28), weight: .black))
                    .foregroundStyle(
                        airPlay.selectedSection == section
                        ? MiiversePalette.green
                        : Color.gray.opacity(0.7)
                    )

                Text(section.title)
                    .font(.system(size: metrics.scaled(14), weight: .medium, design: .rounded))
                    .foregroundStyle(
                        airPlay.selectedSection == section
                        ? MiiversePalette.greenDark
                        : MiiversePalette.secondaryText
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, metrics.scaled(12))
            .background(
                RoundedRectangle(cornerRadius: metrics.scaled(22), style: .continuous)
                    .fill(
                        airPlay.selectedSection == section
                        ? MiiversePalette.greenLight.opacity(0.26)
                        : Color.clear
                    )
            )
        }
    }

    private func tvHeader(metrics: AirPlayTVMetrics) -> some View {
        HStack(spacing: metrics.scaled(12)) {
            VStack(alignment: .leading, spacing: metrics.scaled(4)) {
                Text(tvHeaderTitle)
                    .font(.system(size: metrics.scaled(27), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(tvHeaderSubtitle)
                    .font(.system(size: metrics.scaled(12), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(airPlay.isExternalDisplayActive ? "AirPlay Live" : "Local Preview")
                .font(.system(size: metrics.scaled(12), weight: .heavy, design: .rounded))
                .foregroundStyle(MiiversePalette.greenDark)
                .padding(.horizontal, metrics.scaled(12))
                .padding(.vertical, metrics.scaled(8))
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.94))
                )
        }
        .padding(.horizontal, metrics.contentInset)
        .frame(height: metrics.topBarHeight)
        .background(
            LinearGradient(
                colors: [
                    MiiversePalette.greenLight,
                    MiiversePalette.green,
                    MiiversePalette.greenDark
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(
            RoundedRectangle(cornerRadius: metrics.scaled(24), style: .continuous)
        )
    }

    private func tvScreenBody(metrics: AirPlayTVMetrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: metrics.gap) {
                    Color.clear
                        .frame(height: 1)
                        .id("tv-scroll-top")

                    switch airPlay.currentScreen {
                    case .feedRoot:
                        tvFeedRoot(metrics: metrics)
                    case .searchRoot:
                        tvSearchRoot(metrics: metrics)
                    case .communitiesRoot:
                        tvCommunitiesRoot(metrics: metrics)
                    case .yeahsRoot:
                        tvYeahsRoot(metrics: metrics)
                    case .settingsRoot:
                        tvSettingsRoot(metrics: metrics)
                    case .communityDetail:
                        tvCommunityDetail(metrics: metrics)
                    case .userProfile:
                        tvUserDetail(metrics: metrics)
                    case .postDetail:
                        tvPostDetail(metrics: metrics)
                    }
                }
                .padding(.bottom, metrics.scaled(20))
            }
            .scrollIndicators(.hidden)
            .padding(metrics.scaled(16))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: metrics.scaled(24), style: .continuous)
                    .fill(Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.scaled(24), style: .continuous)
                    .stroke(Color.gray.opacity(0.16), lineWidth: 1)
            )
            .onChange(of: airPlay.focusedItem) { _, item in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(tvScrollID(for: item), anchor: .center)
                }
            }
            .onChange(of: airPlay.currentScreen) { _, _ in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo("tv-scroll-top", anchor: .top)
                }
            }
        }
    }

    private func tvFeedRoot(metrics: AirPlayTVMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.gap) {
            tvSectionHeader("Activity Feed", systemImage: "dot.radiowaves.left.and.right", metrics: metrics)
            tvPostList(airPlay.allPosts, emptyTitle: "No archive posts", metrics: metrics)
            if airPlay.canLoadMoreFeedItems {
                tvLoadMoreButton(
                    focus: .loadMoreFeed,
                    title: "Load More Posts",
                    isLoading: airPlay.isLoadingMoreFeed,
                    metrics: metrics
                ) {
                    Task {
                        await airPlay.activateFocusedItem(using: api)
                    }
                }
            }
        }
    }

    private func tvSearchRoot(metrics: AirPlayTVMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.gap) {
            AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(18)) {
                VStack(alignment: .leading, spacing: metrics.scaled(14)) {
                    tvFocusButton(
                        focus: .searchField,
                        cornerRadius: metrics.scaled(20),
                        metrics: metrics
                    ) {
                        airPlay.isSearchKeyboardPresented = true
                    } label: {
                        HStack(spacing: metrics.scaled(12)) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: metrics.scaled(18), weight: .bold))
                                .foregroundStyle(MiiversePalette.greenDark)

                            VStack(alignment: .leading, spacing: metrics.scaled(4)) {
                                Text(airPlay.searchQuery.trimmed.isEmpty ? "Search the archive" : airPlay.searchQuery)
                                    .font(.system(size: metrics.scaled(18), weight: .heavy, design: .rounded))
                                    .foregroundStyle(
                                        airPlay.searchQuery.trimmed.isEmpty
                                        ? MiiversePalette.secondaryText
                                        : MiiversePalette.text
                                    )
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)

                                Text("Press A on the remote to type on iPhone")
                                    .font(.system(size: metrics.scaled(12), weight: .medium, design: .rounded))
                                    .foregroundStyle(MiiversePalette.secondaryText)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(metrics.scaled(16))
                        .background(
                            RoundedRectangle(cornerRadius: metrics.scaled(20), style: .continuous)
                                .fill(Color.white)
                        )
                    }

                    HStack(spacing: metrics.scaled(12)) {
                        ForEach(AirPlaySearchScope.allCases) { scope in
                            tvFocusButton(
                                focus: .searchScope(scope),
                                cornerRadius: metrics.scaled(18),
                                metrics: metrics
                            ) {
                                Task {
                                    await airPlay.activateFocusedItem(using: api)
                                }
                            } label: {
                                Text(scope.title)
                                    .font(.system(size: metrics.scaled(14), weight: .heavy, design: .rounded))
                                    .foregroundStyle(airPlay.searchScope == scope ? .white : MiiversePalette.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, metrics.scaled(12))
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                airPlay.searchScope == scope
                                                ? MiiversePalette.greenDark
                                                : MiiversePalette.greenLight.opacity(0.28)
                                            )
                                    )
                            }
                        }
                    }
                }
            }

            switch airPlay.searchScope {
            case .posts:
                tvPostList(airPlay.filteredSearchedPosts, emptyTitle: "No post results", metrics: metrics)
            case .communities:
                tvCommunityList(airPlay.searchedCommunities, emptyTitle: "No community results", metrics: metrics)
            case .users:
                tvUserList(airPlay.searchedUsers, emptyTitle: "No user results", metrics: metrics)
            }
        }
    }

    private func tvCommunitiesRoot(metrics: AirPlayTVMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.gap) {
            tvSectionHeader("Communities", systemImage: "person.3.fill", metrics: metrics)
            tvCommunityList(airPlay.visibleCommunities, emptyTitle: "No communities", metrics: metrics)
            if airPlay.canLoadMoreCommunityItems {
                tvLoadMoreButton(
                    focus: .loadMoreCommunities,
                    title: "Load More Communities",
                    isLoading: airPlay.isLoadingMoreCommunities,
                    metrics: metrics
                ) {
                    Task {
                        await airPlay.activateFocusedItem(using: api)
                    }
                }
            }
        }
    }

    private func tvYeahsRoot(metrics: AirPlayTVMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.gap) {
            tvSectionHeader("Yeah'd Posts", systemImage: "hand.thumbsup.fill", metrics: metrics)
            tvPostList(airPlay.filteredLikedPosts, emptyTitle: "No liked posts yet", metrics: metrics)
        }
    }

    private func tvSettingsRoot(metrics: AirPlayTVMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.gap) {
            AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(22)) {
                Text("Broadcast Status")
                    .font(.system(size: metrics.scaled(24), weight: .heavy, design: .rounded))
                    .foregroundStyle(MiiversePalette.text)

                tvTag(
                    airPlay.routeStatusText,
                    tint: airPlay.isRouteConnected ? MiiversePalette.green : .orange,
                    metrics: metrics
                )

                Text(airPlay.routeInstructionText)
                    .font(.system(size: metrics.scaled(16), weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(airPlay.selectedArchiveCutoffLabel)
                    .font(.system(size: metrics.scaled(15), weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)
            }

            tvFocusButton(
                focus: .settingsRefresh,
                cornerRadius: metrics.scaled(22),
                metrics: metrics
            ) {
                Task {
                    await airPlay.refresh(using: api)
                }
            } label: {
                HStack(spacing: metrics.scaled(12)) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("Refresh Live Archive Data")
                }
                .font(.system(size: metrics.scaled(18), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, metrics.scaled(18))
                .background(
                    RoundedRectangle(cornerRadius: metrics.scaled(22), style: .continuous)
                        .fill(MiiversePalette.greenDark)
                )
            }
        }
    }

    @ViewBuilder
    private func tvPostList(
        _ posts: [ArchiversePost],
        emptyTitle: String,
        metrics: AirPlayTVMetrics
    ) -> some View {
        if posts.isEmpty {
            tvEmptyState(emptyTitle, metrics: metrics)
        } else {
            ForEach(posts) { post in
                tvFocusButton(focus: .post(post.id), cornerRadius: metrics.scaled(24), metrics: metrics) {
                    Task {
                        await airPlay.selectPost(post, using: api)
                    }
                } label: {
                    tvPostCard(post, metrics: metrics)
                }
            }
        }
    }

    @ViewBuilder
    private func tvCommunityList(
        _ items: [ArchiverseCommunity],
        emptyTitle: String,
        metrics: AirPlayTVMetrics
    ) -> some View {
        if items.isEmpty {
            tvEmptyState(emptyTitle, metrics: metrics)
        } else {
            ForEach(items) { community in
                tvFocusButton(focus: .community(community.id), cornerRadius: metrics.scaled(24), metrics: metrics) {
                    Task {
                        await airPlay.selectCommunity(community, using: api)
                    }
                } label: {
                    tvCommunityCard(community, metrics: metrics)
                }
            }
        }
    }

    @ViewBuilder
    private func tvUserList(
        _ users: [ArchiverseUser],
        emptyTitle: String,
        metrics: AirPlayTVMetrics
    ) -> some View {
        if users.isEmpty {
            tvEmptyState(emptyTitle, metrics: metrics)
        } else {
            ForEach(users) { user in
                tvFocusButton(focus: .user(user.id), cornerRadius: metrics.scaled(24), metrics: metrics) {
                    Task {
                        await airPlay.selectUser(user, using: api)
                    }
                } label: {
                    tvUserCard(user, metrics: metrics)
                }
            }
        }
    }

    @ViewBuilder
    private func tvPostDetail(metrics: AirPlayTVMetrics) -> some View {
        if let post = airPlay.selectedPost {
            VStack(alignment: .leading, spacing: metrics.gap) {
                AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(22)) {
                    HStack(alignment: .top, spacing: metrics.scaled(16)) {
                        RemoteImageView(
                            url: post.avatarURL,
                            cornerRadius: metrics.scaled(24),
                            aspectRatio: 1,
                            thumbnailSize: CGSize(width: 150, height: 150),
                            fallbackSystemImage: "person.crop.circle.fill"
                        )
                        .frame(width: metrics.scaled(88), height: metrics.scaled(88))

                        VStack(alignment: .leading, spacing: metrics.scaled(6)) {
                            Text(post.miiName)
                                .font(.system(size: metrics.scaled(28), weight: .black, design: .rounded))
                                .foregroundStyle(MiiversePalette.text)
                                .lineLimit(1)

                            Text(post.nnid ?? "Unknown NNID")
                                .font(.system(size: metrics.scaled(14), weight: .bold, design: .rounded))
                                .foregroundStyle(MiiversePalette.greenDark)
                                .lineLimit(1)

                            Text(ArchiveFormatters.archiveDate(post.dateString))
                                .font(.system(size: metrics.scaled(13), weight: .medium, design: .rounded))
                                .foregroundStyle(MiiversePalette.secondaryText)
                        }

                        Spacer(minLength: 0)
                    }

                    if let communityTitle = post.communityTitle {
                        Text(communityTitle)
                            .font(.system(size: metrics.scaled(13), weight: .bold, design: .rounded))
                            .foregroundStyle(MiiversePalette.greenDark)
                    }

                    if let displayTitle = post.displayTitle {
                        Text(displayTitle)
                            .font(.system(size: metrics.scaled(26), weight: .black, design: .rounded))
                            .foregroundStyle(MiiversePalette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(post.detailText)
                        .font(.system(size: metrics.scaled(17), weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if !post.mediaAssets.isEmpty {
                        PostMediaPreview(
                            post: post,
                            height: metrics.detailMediaHeight,
                            cornerRadius: metrics.scaled(24),
                            scalingOverride: .fit
                        )
                    }

                    HStack(spacing: metrics.scaled(12)) {
                        tvFocusButton(
                            focus: .postAuthor(post.nnid?.nilIfEmpty ?? post.miiName),
                            cornerRadius: metrics.scaled(18),
                            metrics: metrics
                        ) {
                            Task {
                                await airPlay.activateFocusedItem(using: api)
                            }
                        } label: {
                            Text("Open Profile")
                                .font(.system(size: metrics.scaled(14), weight: .heavy, design: .rounded))
                                .foregroundStyle(MiiversePalette.text)
                                .padding(.horizontal, metrics.scaled(16))
                                .padding(.vertical, metrics.scaled(12))
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white)
                                )
                        }

                        if let titleID = post.titleID, let gameID = post.gameID {
                            tvFocusButton(
                                focus: .postCommunity("\(titleID)-\(gameID)"),
                                cornerRadius: metrics.scaled(18),
                                metrics: metrics
                            ) {
                                Task {
                                    await airPlay.activateFocusedItem(using: api)
                                }
                            } label: {
                                Text("Open Community")
                                    .font(.system(size: metrics.scaled(14), weight: .heavy, design: .rounded))
                                    .foregroundStyle(MiiversePalette.text)
                                    .padding(.horizontal, metrics.scaled(16))
                                    .padding(.vertical, metrics.scaled(12))
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.white)
                                    )
                            }
                        }

                        Spacer(minLength: 0)

                        tvFocusButton(
                            focus: .postYeah,
                            cornerRadius: metrics.scaled(18),
                            metrics: metrics
                        ) {
                            airPlay.toggleYeahOnSelectedPost()
                        } label: {
                            HStack(spacing: metrics.scaled(8)) {
                                Image(systemName: "hand.thumbsup.fill")
                                Text("Yeah")
                            }
                            .font(.system(size: metrics.scaled(14), weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, metrics.scaled(16))
                            .padding(.vertical, metrics.scaled(12))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(MiiversePalette.greenDark)
                            )
                        }
                    }

                    HStack(spacing: metrics.scaled(8)) {
                        MiiverseStatPill(title: "Yeahs", value: displayedYeahCount(for: post))
                        MiiverseStatPill(title: "Replies", value: ArchiveFormatters.number(post.numReplies))
                        MiiverseStatPill(title: "Played", value: post.isPlayed ? "Yes" : "No")
                    }
                }

                tvSectionHeader("Comments", systemImage: "text.bubble.fill", metrics: metrics)

                if airPlay.isLoadingSelectedPost && airPlay.filteredSelectedPostReplies.isEmpty {
                    AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(22)) {
                        ProgressView()
                            .tint(MiiversePalette.green)
                    }
                } else if airPlay.filteredSelectedPostReplies.isEmpty {
                    tvEmptyState("No visible comments on this post", metrics: metrics)
                } else {
                    ForEach(airPlay.filteredSelectedPostReplies) { reply in
                        tvReplyCard(reply, originalPost: post, metrics: metrics)
                    }
                }

                if airPlay.canLoadMoreCurrentPostReplies {
                    tvLoadMoreButton(
                        focus: .loadMoreReplies,
                        title: "Load More Comments",
                        isLoading: airPlay.isLoadingMoreReplies,
                        metrics: metrics
                    ) {
                        Task {
                            await airPlay.activateFocusedItem(using: api)
                        }
                    }
                }
            }
        } else {
            tvEmptyState("Pick a post from the current section", metrics: metrics)
        }
    }

    @ViewBuilder
    private func tvCommunityDetail(metrics: AirPlayTVMetrics) -> some View {
        if let community = airPlay.selectedCommunity {
            VStack(alignment: .leading, spacing: metrics.gap) {
                AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(22)) {
                    RemoteImageView(
                        url: community.bannerURL,
                        cornerRadius: metrics.scaled(24),
                        frameHeight: metrics.communityBannerHeight,
                        thumbnailSize: CGSize(width: 920, height: 280),
                        scaling: .fit,
                        fallbackSystemImage: "sparkles.tv.fill"
                    )

                    HStack(alignment: .top, spacing: metrics.scaled(16)) {
                        RemoteImageView(
                            url: community.iconURL ?? community.bannerURL,
                            cornerRadius: metrics.scaled(22),
                            aspectRatio: 1,
                            thumbnailSize: CGSize(width: 150, height: 150),
                            fallbackSystemImage: "gamecontroller.fill"
                        )
                        .frame(width: metrics.scaled(90), height: metrics.scaled(90))

                        VStack(alignment: .leading, spacing: metrics.scaled(6)) {
                            Text(community.communityTitle)
                                .font(.system(size: metrics.scaled(28), weight: .black, design: .rounded))
                                .foregroundStyle(MiiversePalette.text)
                                .lineLimit(2)

                            Text(community.gameTitle)
                                .font(.system(size: metrics.scaled(15), weight: .heavy, design: .rounded))
                                .foregroundStyle(MiiversePalette.greenDark)
                                .lineLimit(1)

                            Text(community.badge ?? "Miiverse community archive")
                                .font(.system(size: metrics.scaled(14), weight: .medium, design: .rounded))
                                .foregroundStyle(MiiversePalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: metrics.scaled(8)) {
                        MiiverseStatPill(title: "Posts", value: ArchiveFormatters.number(community.numPosts))
                        MiiverseStatPill(title: "Region", value: community.region)
                        MiiverseStatPill(title: "Title ID", value: community.titleID)
                    }
                }

                HStack(spacing: metrics.scaled(12)) {
                    ForEach(CommunitySortMode.allCases, id: \.self) { mode in
                        tvFocusButton(
                            focus: .communitySort(mode),
                            cornerRadius: metrics.scaled(18),
                            metrics: metrics
                        ) {
                            Task {
                                await airPlay.setCommunitySortMode(mode, using: api)
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: metrics.scaled(14), weight: .heavy, design: .rounded))
                                .foregroundStyle(airPlay.communitySortMode == mode ? .white : MiiversePalette.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, metrics.scaled(12))
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(
                                            airPlay.communitySortMode == mode
                                            ? MiiversePalette.greenDark
                                            : MiiversePalette.greenLight.opacity(0.28)
                                        )
                                )
                        }
                    }
                }

                if airPlay.isLoadingCommunityPosts && airPlay.filteredCommunityPosts.isEmpty {
                    AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(22)) {
                        ProgressView()
                            .tint(MiiversePalette.green)
                    }
                } else {
                    tvPostList(airPlay.filteredCommunityPosts, emptyTitle: "No community posts", metrics: metrics)
                }

                if airPlay.canLoadMoreCurrentCommunityPosts {
                    tvLoadMoreButton(
                        focus: .loadMoreCommunityPosts,
                        title: "Load More Community Posts",
                        isLoading: airPlay.isLoadingMoreCommunityPosts,
                        metrics: metrics
                    ) {
                        Task {
                            await airPlay.activateFocusedItem(using: api)
                        }
                    }
                }
            }
        } else {
            tvEmptyState("Pick a community from the current section", metrics: metrics)
        }
    }

    @ViewBuilder
    private func tvUserDetail(metrics: AirPlayTVMetrics) -> some View {
        if let user = airPlay.selectedUser {
            VStack(alignment: .leading, spacing: metrics.gap) {
                AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(22)) {
                    RemoteImageView(
                        url: user.bannerURL,
                        cornerRadius: metrics.scaled(24),
                        frameHeight: metrics.scaled(170),
                        thumbnailSize: CGSize(width: 920, height: 170),
                        fallbackSystemImage: "sparkles"
                    )

                    HStack(alignment: .top, spacing: metrics.scaled(16)) {
                        RemoteImageView(
                            url: user.avatarURL,
                            cornerRadius: metrics.scaled(22),
                            aspectRatio: 1,
                            thumbnailSize: CGSize(width: 150, height: 150),
                            fallbackSystemImage: "person.crop.circle.fill"
                        )
                        .frame(width: metrics.scaled(88), height: metrics.scaled(88))

                        VStack(alignment: .leading, spacing: metrics.scaled(6)) {
                            Text(user.miiName)
                                .font(.system(size: metrics.scaled(28), weight: .black, design: .rounded))
                                .foregroundStyle(MiiversePalette.text)
                                .lineLimit(1)

                            Text(user.nnid ?? user.id)
                                .font(.system(size: metrics.scaled(14), weight: .heavy, design: .rounded))
                                .foregroundStyle(MiiversePalette.greenDark)
                                .lineLimit(1)

                            Text(user.bio?.nilIfEmpty ?? "No bio archived.")
                                .font(.system(size: metrics.scaled(15), weight: .medium, design: .rounded))
                                .foregroundStyle(MiiversePalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: metrics.scaled(8)) {
                        MiiverseStatPill(title: "Followers", value: ArchiveFormatters.number(user.numFollowers))
                        MiiverseStatPill(title: "Following", value: ArchiveFormatters.number(user.numFollowing))
                        MiiverseStatPill(title: "Friends", value: ArchiveFormatters.number(user.numFriends))
                        MiiverseStatPill(title: "Posts", value: ArchiveFormatters.number(user.numPosts))
                    }
                }

                HStack(spacing: metrics.scaled(12)) {
                    ForEach(UserContentMode.allCases, id: \.self) { mode in
                        tvFocusButton(
                            focus: .userContent(mode),
                            cornerRadius: metrics.scaled(18),
                            metrics: metrics
                        ) {
                            Task {
                                await airPlay.setUserContentMode(mode, using: api)
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: metrics.scaled(14), weight: .heavy, design: .rounded))
                                .foregroundStyle(airPlay.userContentMode == mode ? .white : MiiversePalette.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, metrics.scaled(12))
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(
                                            airPlay.userContentMode == mode
                                            ? MiiversePalette.greenDark
                                            : MiiversePalette.greenLight.opacity(0.28)
                                        )
                                )
                        }
                    }
                }

                if airPlay.userContentMode == .posts {
                    if airPlay.isLoadingUserPosts && airPlay.filteredSelectedUserPosts.isEmpty {
                        AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(22)) {
                            ProgressView()
                                .tint(MiiversePalette.green)
                        }
                    } else {
                        tvPostList(airPlay.filteredSelectedUserPosts, emptyTitle: "No posts for this user", metrics: metrics)
                    }

                    if airPlay.canLoadMoreCurrentUserPosts {
                        tvLoadMoreButton(
                            focus: .loadMoreUserPosts,
                            title: "Load More User Posts",
                            isLoading: airPlay.isLoadingMoreUserPosts,
                            metrics: metrics
                        ) {
                            Task {
                                await airPlay.activateFocusedItem(using: api)
                            }
                        }
                    }
                } else {
                    if airPlay.isLoadingUserReplies && airPlay.filteredSelectedUserReplies.isEmpty {
                        AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(22)) {
                            ProgressView()
                                .tint(MiiversePalette.green)
                        }
                    } else if airPlay.filteredSelectedUserReplies.isEmpty {
                        tvEmptyState("No replies for this user", metrics: metrics)
                    } else {
                        ForEach(airPlay.filteredSelectedUserReplies) { item in
                            tvUserReplyCard(item, metrics: metrics)
                        }
                    }

                    if airPlay.canLoadMoreCurrentUserReplies {
                        tvLoadMoreButton(
                            focus: .loadMoreUserReplies,
                            title: "Load More Replies",
                            isLoading: airPlay.isLoadingMoreUserReplies,
                            metrics: metrics
                        ) {
                            Task {
                                await airPlay.activateFocusedItem(using: api)
                            }
                        }
                    }
                }
            }
        } else {
            tvEmptyState("Pick a user from the current section", metrics: metrics)
        }
    }

    private func tvSectionHeader(_ title: String, systemImage: String, metrics: AirPlayTVMetrics) -> some View {
        HStack(spacing: metrics.scaled(8)) {
            Image(systemName: systemImage)
                .font(.system(size: metrics.scaled(14), weight: .bold))

            Text(title)
                .font(.system(size: metrics.scaled(14), weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.scaled(14))
        .padding(.vertical, metrics.scaled(9))
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [MiiversePalette.greenLight, MiiversePalette.green],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }

    private func tvTag(_ text: String, tint: Color, metrics: AirPlayTVMetrics) -> some View {
        Text(text)
            .font(.system(size: metrics.scaled(12), weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, metrics.scaled(11))
            .padding(.vertical, metrics.scaled(6))
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
            )
    }

    private func tvEmptyState(_ title: String, metrics: AirPlayTVMetrics) -> some View {
        VStack(spacing: metrics.scaled(10)) {
            Image(systemName: "tray.fill")
                .font(.system(size: metrics.scaled(30), weight: .bold))
                .foregroundStyle(MiiversePalette.green)

            Text(title)
                .font(.system(size: metrics.scaled(18), weight: .heavy, design: .rounded))
                .foregroundStyle(MiiversePalette.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.scaled(28))
    }

    private func tvLoadMoreButton(
        focus: AirPlayRemoteFocusItem,
        title: String,
        isLoading: Bool,
        metrics: AirPlayTVMetrics,
        action: @escaping () -> Void
    ) -> some View {
        tvFocusButton(
            focus: focus,
            cornerRadius: metrics.scaled(24),
            metrics: metrics,
            action: action
        ) {
            HStack(spacing: metrics.scaled(12)) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: metrics.scaled(18), weight: .black))
                }

                Text(isLoading ? "Loading…" : title)
                    .font(.system(size: metrics.scaled(18), weight: .heavy, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, metrics.scaled(20))
            .padding(.vertical, metrics.scaled(18))
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: metrics.scaled(24), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MiiversePalette.green, MiiversePalette.greenDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
        }
    }

    private func tvPostCard(_ post: ArchiversePost, metrics: AirPlayTVMetrics) -> some View {
        AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(18)) {
            HStack(alignment: .center, spacing: metrics.scaled(18)) {
                RemoteImageView(
                    url: post.primaryMediaURL ?? post.avatarURL,
                    cornerRadius: metrics.scaled(22),
                    aspectRatio: 4 / 3,
                    thumbnailSize: CGSize(width: 420, height: 315),
                    scaling: post.prefersContainedMedia ? .fit : .fill,
                    fallbackSystemImage: post.previewFallbackSystemImage
                )
                .frame(width: metrics.listThumbnailWidth, height: metrics.listThumbnailHeight)

                VStack(alignment: .leading, spacing: metrics.scaled(8)) {
                    HStack(alignment: .center, spacing: metrics.scaled(8)) {
                        Text(post.miiName)
                            .font(.system(size: metrics.scaled(16), weight: .heavy, design: .rounded))
                            .foregroundStyle(MiiversePalette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(ArchiveFormatters.archiveDate(post.dateString))
                            .font(.system(size: metrics.scaled(11), weight: .semibold, design: .rounded))
                            .foregroundStyle(MiiversePalette.secondaryText)
                            .lineLimit(1)
                    }

                    Text(post.headline)
                        .font(.system(size: metrics.scaled(21), weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    if let communityTitle = post.communityTitle {
                        Text(communityTitle)
                            .font(.system(size: metrics.scaled(13), weight: .bold, design: .rounded))
                            .foregroundStyle(MiiversePalette.greenDark)
                            .lineLimit(1)
                    }

                    Text(post.detailText)
                        .font(.system(size: metrics.scaled(14), weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)
                        .lineLimit(3)
                        .minimumScaleFactor(0.9)

                    HStack(spacing: metrics.scaled(8)) {
                        tvTag("\(displayedYeahCount(for: post)) Yeahs", tint: MiiversePalette.green, metrics: metrics)
                        tvTag("\(ArchiveFormatters.number(post.numReplies)) Replies", tint: MiiversePalette.badgeBlue, metrics: metrics)
                    }
                }

                Spacer(minLength: 0)

                tvArrowAccessory(metrics: metrics)
            }
        }
    }

    private func tvCommunityCard(_ community: ArchiverseCommunity, metrics: AirPlayTVMetrics) -> some View {
        AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(18)) {
            HStack(alignment: .center, spacing: metrics.scaled(18)) {
                RemoteImageView(
                    url: community.iconURL ?? community.bannerURL,
                    cornerRadius: metrics.scaled(22),
                    aspectRatio: 1,
                    thumbnailSize: CGSize(width: 200, height: 200),
                    fallbackSystemImage: "gamecontroller.fill"
                )
                .frame(width: metrics.scaled(96), height: metrics.scaled(96))

                VStack(alignment: .leading, spacing: metrics.scaled(8)) {
                    Text(community.communityTitle)
                        .font(.system(size: metrics.scaled(22), weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(community.gameTitle)
                        .font(.system(size: metrics.scaled(14), weight: .bold, design: .rounded))
                        .foregroundStyle(MiiversePalette.greenDark)
                        .lineLimit(1)

                    HStack(spacing: metrics.scaled(8)) {
                        tvTag(community.region, tint: MiiversePalette.badgeBlue, metrics: metrics)
                        tvTag("\(ArchiveFormatters.number(community.numPosts)) posts", tint: MiiversePalette.green, metrics: metrics)
                    }
                }

                Spacer(minLength: 0)

                tvArrowAccessory(metrics: metrics)
            }
        }
    }

    private func tvUserCard(_ user: ArchiverseUser, metrics: AirPlayTVMetrics) -> some View {
        AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(18)) {
            HStack(alignment: .center, spacing: metrics.scaled(18)) {
                RemoteImageView(
                    url: user.avatarURL,
                    cornerRadius: metrics.scaled(22),
                    aspectRatio: 1,
                    thumbnailSize: CGSize(width: 200, height: 200),
                    fallbackSystemImage: "person.crop.circle.fill"
                )
                .frame(width: metrics.scaled(96), height: metrics.scaled(96))

                VStack(alignment: .leading, spacing: metrics.scaled(8)) {
                    Text(user.miiName)
                        .font(.system(size: metrics.scaled(22), weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)
                        .lineLimit(1)
                    if let nnid = user.nnid?.nilIfEmpty {
                        Text(nnid)
                            .font(.system(size: metrics.scaled(14), weight: .bold, design: .rounded))
                            .foregroundStyle(MiiversePalette.greenDark)
                            .lineLimit(1)
                    }
                    Text(user.bio?.nilIfEmpty ?? "No bio archived.")
                        .font(.system(size: metrics.scaled(14), weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                tvArrowAccessory(metrics: metrics)
            }
        }
    }

    private func tvReplyCard(_ reply: ArchiverseReply, originalPost: ArchiversePost, metrics: AirPlayTVMetrics) -> some View {
        tvFocusButton(focus: .reply(reply.id), cornerRadius: metrics.scaled(24), metrics: metrics) {
            Task {
                await airPlay.activateFocusedItem(using: api)
            }
        } label: {
            AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(18)) {
                VStack(alignment: .leading, spacing: metrics.scaled(12)) {
                    HStack(alignment: .top, spacing: metrics.scaled(14)) {
                        RemoteImageView(
                            url: reply.avatarURL,
                            cornerRadius: metrics.scaled(20),
                            aspectRatio: 1,
                            thumbnailSize: CGSize(width: 120, height: 120),
                            fallbackSystemImage: "person.crop.circle.fill"
                        )
                        .frame(width: metrics.scaled(74), height: metrics.scaled(74))

                        VStack(alignment: .leading, spacing: metrics.scaled(4)) {
                            HStack(spacing: metrics.scaled(8)) {
                                Text(reply.miiName)
                                    .font(.system(size: metrics.scaled(18), weight: .heavy, design: .rounded))
                                    .foregroundStyle(MiiversePalette.text)
                                    .lineLimit(1)
                                if isOriginalPosterReply(reply, originalPost: originalPost) {
                                    tvTag("OP", tint: MiiversePalette.greenDark, metrics: metrics)
                                }
                            }

                            Text(reply.nnid ?? "Unknown NNID")
                                .font(.system(size: metrics.scaled(12), weight: .bold, design: .rounded))
                                .foregroundStyle(MiiversePalette.greenDark)
                                .lineLimit(1)

                            Text(ArchiveFormatters.archiveDate(reply.dateString))
                                .font(.system(size: metrics.scaled(11), weight: .medium, design: .rounded))
                                .foregroundStyle(MiiversePalette.secondaryText)
                        }
                    }

                    Text(reply.text?.nilIfEmpty ?? "Reply body unavailable.")
                        .font(.system(size: metrics.scaled(15), weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !reply.mediaAssets.isEmpty {
                        ReplyMediaPreview(reply: reply, height: metrics.scaled(230))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: metrics.scaled(24), style: .continuous)
                    .fill(
                        isOriginalPosterReply(reply, originalPost: originalPost)
                        ? MiiversePalette.greenLight.opacity(0.18)
                        : Color.clear
                    )
            )
        }
    }

    private func tvUserReplyCard(_ item: UserReplyFeedItem, metrics: AirPlayTVMetrics) -> some View {
        tvFocusButton(focus: .userReply(item.id), cornerRadius: metrics.scaled(24), metrics: metrics) {
            Task {
                await airPlay.activateFocusedItem(using: api)
            }
        } label: {
            AirPlayTVPanel(metrics: metrics, padding: metrics.scaled(18)) {
                VStack(alignment: .leading, spacing: metrics.scaled(12)) {
                    Text(item.reply.text?.nilIfEmpty ?? "Reply body unavailable.")
                        .font(.system(size: metrics.scaled(15), weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.reply.mediaAssets.isEmpty {
                        ReplyMediaPreview(reply: item.reply, height: metrics.scaled(220))
                    }

                    if let post = item.post {
                        VStack(alignment: .leading, spacing: metrics.scaled(6)) {
                            Text("In reply to \(post.miiName)")
                                .font(.system(size: metrics.scaled(12), weight: .heavy, design: .rounded))
                                .foregroundStyle(MiiversePalette.greenDark)
                            Text(post.headline)
                                .font(.system(size: metrics.scaled(16), weight: .heavy, design: .rounded))
                                .foregroundStyle(MiiversePalette.text)
                                .lineLimit(2)
                            Text(post.detailText)
                                .font(.system(size: metrics.scaled(13), weight: .medium, design: .rounded))
                                .foregroundStyle(MiiversePalette.secondaryText)
                                .lineLimit(2)
                        }
                        .padding(metrics.scaled(14))
                        .background(
                            RoundedRectangle(cornerRadius: metrics.scaled(18), style: .continuous)
                                .fill(Color.white.opacity(0.82))
                        )
                    }
                }
            }
        }
    }

    private func tvFocusButton<Label: View>(
        focus: AirPlayRemoteFocusItem,
        cornerRadius: CGFloat,
        metrics: AirPlayTVMetrics,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            guard interactive else { return }
            airPlay.setFocusedItem(focus)
            action()
        } label: {
            label()
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            airPlay.focusedItem == focus ? MiiversePalette.greenDark : Color.clear,
                            lineWidth: airPlay.focusedItem == focus ? metrics.scaled(4) : 0
                        )
                )
                .shadow(
                    color: airPlay.focusedItem == focus
                        ? MiiversePalette.greenDark.opacity(0.18)
                        : .clear,
                    radius: metrics.scaled(10),
                    x: 0,
                    y: metrics.scaled(4)
                )
                .id(tvScrollID(for: focus))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(interactive)
    }

    private func tvArrowAccessory(metrics: AirPlayTVMetrics) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: metrics.scaled(56), height: metrics.scaled(56))
                .shadow(color: Color.black.opacity(0.12), radius: metrics.scaled(6), x: 0, y: metrics.scaled(4))

            Image(systemName: "chevron.right")
                .font(.system(size: metrics.scaled(18), weight: .black))
                .foregroundStyle(MiiversePalette.green)
        }
    }

    private func tvScrollID(for focus: AirPlayRemoteFocusItem) -> String {
        switch focus {
        case .section:
            return "tv-scroll-top"
        case .searchField:
            return "tv-focus-search-field"
        case .searchScope(let scope):
            return "tv-focus-search-scope-\(scope.rawValue)"
        case .communitySort(let mode):
            return "tv-focus-community-sort-\(mode.rawValue)"
        case .userContent(let mode):
            return "tv-focus-user-content-\(mode.rawValue)"
        case .post(let id):
            return "tv-focus-post-\(id)"
        case .community(let id):
            return "tv-focus-community-\(id)"
        case .user(let id):
            return "tv-focus-user-\(id)"
        case .postAuthor(let id):
            return "tv-focus-post-author-\(id)"
        case .postCommunity(let id):
            return "tv-focus-post-community-\(id)"
        case .postYeah:
            return "tv-focus-post-yeah"
        case .reply(let id):
            return "tv-focus-reply-\(id)"
        case .userReply(let id):
            return "tv-focus-user-reply-\(id)"
        case .settingsRefresh:
            return "tv-focus-settings-refresh"
        case .loadMoreFeed:
            return "tv-focus-load-more-feed"
        case .loadMoreCommunities:
            return "tv-focus-load-more-communities"
        case .loadMoreCommunityPosts:
            return "tv-focus-load-more-community-posts"
        case .loadMoreUserPosts:
            return "tv-focus-load-more-user-posts"
        case .loadMoreUserReplies:
            return "tv-focus-load-more-user-replies"
        case .loadMoreReplies:
            return "tv-focus-load-more-replies"
        }
    }

    private func isOriginalPosterReply(_ reply: ArchiverseReply, originalPost: ArchiversePost) -> Bool {
        if let originalNNID = originalPost.nnid?.nilIfEmpty,
           let replyNNID = reply.nnid?.nilIfEmpty {
            return originalNNID == replyNNID
        }

        return originalPost.miiName == reply.miiName
    }

    private func displayedYeahCount(for post: ArchiversePost) -> String {
        if airPlay.filteredLikedPosts.contains(where: { $0.id == post.id }) {
            return ArchiveFormatters.number(post.numYeahs + 1)
        }
        return ArchiveFormatters.number(post.numYeahs)
    }

    private var tvHeaderTitle: String {
        switch airPlay.currentScreen {
        case .feedRoot:
            return "Activity Feed"
        case .searchRoot:
            return "Search Archive"
        case .communitiesRoot:
            return "Communities"
        case .yeahsRoot:
            return "Yeah'd Posts"
        case .settingsRoot:
            return "TV Settings"
        case .communityDetail:
            return airPlay.selectedCommunity?.communityTitle ?? "Community"
        case .userProfile:
            return airPlay.selectedUser?.miiName ?? "User Profile"
        case .postDetail:
            return airPlay.selectedPost?.headline ?? "Post"
        }
    }

    private var tvHeaderSubtitle: String {
        switch airPlay.currentScreen {
        case .feedRoot:
            return "Browse archived posts in a TV-first Miiverse layout."
        case .searchRoot:
            return "Search posts, communities, and users from the remote."
        case .communitiesRoot:
            return "Pick a community and open its TV community screen."
        case .yeahsRoot:
            return "Liked archive posts stay available here."
        case .settingsRoot:
            return "Broadcast status and archive filter status."
        case .communityDetail:
            return "Community view with archive posts."
        case .userProfile:
            return "User profile with posts and replies."
        case .postDetail:
            return "Post detail with comments."
        }
    }
}

private struct AirPlayTVPanel<Content: View>: View {
    let metrics: AirPlayTVMetrics
    let padding: CGFloat
    let content: Content

    init(metrics: AirPlayTVMetrics, padding: CGFloat, @ViewBuilder content: () -> Content) {
        self.metrics = metrics
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.gap) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: metrics.scaled(24), style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.scaled(24), style: .continuous)
                .stroke(MiiversePalette.line.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: metrics.scaled(10), x: 0, y: metrics.scaled(6))
    }
}

private struct AirPlayTVMetrics {
    let size: CGSize

    var scale: CGFloat {
        max(0.86, min(size.width / 1280, size.height / 720))
    }

    var displayEdgeInset: CGFloat { scaled(12) }
    var outerPadding: CGFloat { scaled(18) }
    var contentInset: CGFloat { scaled(20) }
    var gap: CGFloat { scaled(16) }
    var sidebarWidth: CGFloat { scaled(154) }
    var selectionRailWidth: CGFloat { min(max(scaled(330), size.width * 0.28), scaled(430)) }
    var detailWidth: CGFloat { min(max(scaled(430), size.width * 0.34), scaled(520)) }
    var topBarHeight: CGFloat { scaled(82) }
    var detailMediaHeight: CGFloat { scaled(312) }
    var communityBannerHeight: CGFloat { scaled(196) }
    var listThumbnailSize: CGFloat { scaled(138) }
    var listThumbnailWidth: CGFloat { scaled(220) }
    var listThumbnailHeight: CGFloat { scaled(165) }

    func scaled(_ value: CGFloat) -> CGFloat {
        value * scale
    }
}

private struct AirPlayRoutePickerControl: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = UIColor(red: 0.20, green: 0.57, blue: 0.08, alpha: 1)
        view.activeTintColor = UIColor(red: 0.31, green: 0.76, blue: 0.12, alpha: 1)
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private extension Error {
    var requiresArchiveUnlock: Bool {
        (self as? ArchiverseAPIError)?.requiresArchiveUnlock ?? false
    }
}
