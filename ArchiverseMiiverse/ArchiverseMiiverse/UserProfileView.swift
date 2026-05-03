import SwiftUI

enum UserContentMode: String, CaseIterable {
    case posts = "Posts"
    case replies = "Replies"
}

struct UserProfileView: View {
    @EnvironmentObject private var archiveSettings: ArchiveSettingsStore

    let api: ArchiverseAPI
    let userID: String
    let initialUser: ArchiverseUser?

    @State private var user: ArchiverseUser?
    @State private var mode: UserContentMode = .posts
    @State private var posts: [ArchiversePost] = []
    @State private var replyFeed: [UserReplyFeedItem] = []
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var needsArchiveUnlock = false
    @State private var showArchiveUnlockSheet = false
    @State private var selectedPost: ArchiversePost?
    @State private var currentPostsPage = 1
    @State private var canLoadMorePosts = false
    @State private var isLoadingPosts = false
    @State private var isLoadingMorePosts = false

    private var filteredPosts: [ArchiversePost] {
        ArchiveDateFilter.filter(
            posts: posts,
            cutoffDate: archiveSettings.selectedArchiveDate
        )
    }

    private var filteredReplyFeed: [UserReplyFeedItem] {
        ArchiveDateFilter.filter(
            replyFeed: replyFeed,
            cutoffDate: archiveSettings.selectedArchiveDate
        )
    }

    init(api: ArchiverseAPI, userID: String, initialUser: ArchiverseUser? = nil) {
        self.api = api
        self.userID = userID
        self.initialUser = initialUser
        _user = State(initialValue: initialUser)
    }

    var body: some View {
        ZStack {
            MiiverseWallpaper()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let user {
                        profileHeader(user)
                    }

                    if user != nil || !posts.isEmpty || !replyFeed.isEmpty {
                        MiiverseSegmentedControl(
                            options: UserContentMode.allCases,
                            selection: $mode
                        ) { $0.rawValue }
                    }

                    if let errorMessage {
                        MiiverseStatusBanner(text: errorMessage, tint: .orange)
                    }

                    if needsArchiveUnlock {
                        ArchiveUnlockPromptCard(
                            message: "Profile data is blocked until Cloudflare verification is refreshed."
                        ) {
                            showArchiveUnlockSheet = true
                        }
                    }

                    if mode == .posts {
                        postList
                    } else {
                        repliesList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .miiverseContentColumn(maxWidth: 960)
            }
        }
        .navigationTitle(user?.miiName ?? userID)
        .miiverseNavigationChrome()
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadUserData()
        }
        .onChange(of: mode) { _, _ in
            Task {
                await loadModeData()
            }
        }
        .onChange(of: archiveSettings.selectedArchiveDate) { _, _ in
            guard hasLoaded else { return }
            Task {
                await loadModeData()
            }
        }
        .sheet(isPresented: $showArchiveUnlockSheet) {
            ArchiveUnlockView {
                Task {
                    await loadUserData()
                }
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(api: api, initialPost: post)
        }
    }

    private func profileHeader(_ user: ArchiverseUser) -> some View {
        MiiverseCard {
            VStack(alignment: .leading, spacing: 14) {
                RemoteImageView(
                    url: user.bannerURL,
                    cornerRadius: 22,
                    frameHeight: 112,
                    thumbnailSize: CGSize(width: 340, height: 112),
                    fallbackSystemImage: "sparkles"
                )

                HStack(alignment: .top, spacing: 14) {
                    RemoteImageView(
                        url: user.avatarURL,
                        cornerRadius: 20,
                        aspectRatio: 1,
                        thumbnailSize: CGSize(width: 82, height: 82),
                        fallbackSystemImage: "person.crop.circle.fill"
                    )
                    .frame(width: 82, height: 82)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.miiName)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(MiiversePalette.text)

                        Text(user.nnid ?? userID)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiiversePalette.greenDark)

                        Text(user.bio?.nilIfEmpty ?? "No bio archived.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(MiiversePalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        MiiverseStatPill(title: "Followers", value: ArchiveFormatters.number(user.numFollowers))
                        MiiverseStatPill(title: "Following", value: ArchiveFormatters.number(user.numFollowing))
                        MiiverseStatPill(title: "Friends", value: ArchiveFormatters.number(user.numFriends))
                        MiiverseStatPill(title: "Posts", value: ArchiveFormatters.number(user.numPosts))
                        MiiverseStatPill(title: "Country", value: user.country ?? "Hidden")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var postList: some View {
        if filteredPosts.isEmpty {
            if !needsArchiveUnlock {
                EmptyArchiveView(
                    title: "No Posts Yet",
                    message: archiveSettings.isArchiveDateFilterEnabled
                        ? "No archived posts match the current archive date filter."
                        : "No archived posts were returned for this user."
                )
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredPosts) { post in
                    MiiverseCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(post.headline)
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundStyle(MiiversePalette.text)

                            Text(post.detailText)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(MiiversePalette.secondaryText)
                                .lineLimit(3)

                            PostMediaPreview(
                                post: post,
                                height: 220
                            )

                            HStack(spacing: 8) {
                                MiiverseYeahButton(post: post)
                                MiiverseStatPill(title: "Replies", value: ArchiveFormatters.number(post.numReplies))
                            }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onTapGesture {
                        selectedPost = post
                    }
                }

                if canLoadMorePosts {
                    MiiversePrimaryButton(
                        title: isLoadingMorePosts ? "Loading More Posts..." : "Load More Posts",
                        systemImage: "arrow.down.circle"
                    ) {
                        guard !isLoadingMorePosts else { return }
                        Task {
                            await loadMorePosts()
                        }
                    }
                    .disabled(isLoadingMorePosts)
                }
            }
        }
    }

    @ViewBuilder
    private var repliesList: some View {
        if filteredReplyFeed.isEmpty {
            if !needsArchiveUnlock {
                EmptyArchiveView(
                    title: "No Replies Yet",
                    message: archiveSettings.isArchiveDateFilterEnabled
                        ? "No archived replies match the current archive date filter."
                        : "No archived replies were returned for this user."
                )
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredReplyFeed) { item in
                    MiiverseCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.reply.text?.nilIfEmpty ?? "Reply body unavailable.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(MiiversePalette.text)

                            ReplyMediaPreview(
                                reply: item.reply,
                                height: 220
                            )

                            if let post = item.post {
                                NavigationLink {
                                    PostDetailView(api: api, initialPost: post)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("In reply to \(post.miiName)")
                                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                                            .foregroundStyle(MiiversePalette.greenDark)

                                        Text(post.headline)
                                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                                            .foregroundStyle(MiiversePalette.text)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.white.opacity(0.8))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(MiiversePalette.line, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 8) {
                                MiiverseStatPill(title: "Yeahs", value: ArchiveFormatters.number(item.reply.numYeahs))
                                MiiverseStatPill(title: "Date", value: ArchiveFormatters.archiveDate(item.reply.dateString))
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func loadUserData() async {
        if user != nil {
            errorMessage = nil
            needsArchiveUnlock = false
            await loadModeData()
            return
        }

        do {
            user = try await api.fetchUser(id: userID)
            errorMessage = nil
            needsArchiveUnlock = false
        } catch {
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before this profile can be loaded."
                return
            } else {
                errorMessage = error.localizedDescription
                return
            }
        }

        await loadModeData()
    }

    @MainActor
    private func loadModeData() async {
        guard !isLoadingPosts else { return }
        isLoadingPosts = true
        defer { isLoadingPosts = false }

        do {
            switch mode {
            case .posts:
                posts = []
                currentPostsPage = 1
                let fetchedPosts = try await api.fetchUserPosts(
                    userID: userID,
                    page: currentPostsPage,
                    beforeDate: archiveSettings.selectedArchiveDate
                )
                posts = fetchedPosts
                canLoadMorePosts = !fetchedPosts.isEmpty
            case .replies:
                replyFeed = []
                replyFeed = try await api.fetchUserReplies(userID: userID)
                canLoadMorePosts = false
            }
            errorMessage = nil
            needsArchiveUnlock = false
        } catch {
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before this user's content can be loaded."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadMorePosts() async {
        guard mode == .posts, canLoadMorePosts, !isLoadingMorePosts else { return }
        isLoadingMorePosts = true
        defer { isLoadingMorePosts = false }

        do {
            let nextPage = currentPostsPage + 1
            let fetchedPosts = try await api.fetchUserPosts(
                userID: userID,
                page: nextPage,
                beforeDate: archiveSettings.selectedArchiveDate
            )

            if fetchedPosts.isEmpty {
                canLoadMorePosts = false
                return
            }

            let existingIDs = Set(posts.map(\.id))
            posts.append(contentsOf: fetchedPosts.filter { !existingIDs.contains($0.id) })
            currentPostsPage = nextPage
            canLoadMorePosts = true
            errorMessage = nil
            needsArchiveUnlock = false
        } catch {
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before more posts can be loaded."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
