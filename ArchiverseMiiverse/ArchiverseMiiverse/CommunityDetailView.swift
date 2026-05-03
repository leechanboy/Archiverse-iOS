import SwiftUI

enum CommunitySortMode: String, CaseIterable {
    case popular = "Popular"
    case recent = "Recent"
}

struct CommunityDetailView: View {
    @EnvironmentObject private var archiveSettings: ArchiveSettingsStore

    let api: ArchiverseAPI
    let titleID: String
    let gameID: String
    let initialCommunity: ArchiverseCommunity?

    @State private var community: ArchiverseCommunity?
    @State private var posts: [ArchiversePost] = []
    @State private var sortMode: CommunitySortMode = .popular
    @State private var currentPage = 1
    @State private var canLoadMorePosts = true
    @State private var isLoadingPosts = false
    @State private var isLoadingMorePosts = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var needsArchiveUnlock = false
    @State private var showArchiveUnlockSheet = false
    @State private var selectedPost: ArchiversePost?
    @State private var selectedUserTarget: UserProfileTarget?

    private var filteredPosts: [ArchiversePost] {
        ArchiveDateFilter.filter(
            posts: posts,
            cutoffDate: archiveSettings.selectedArchiveDate
        )
    }

    init(api: ArchiverseAPI, titleID: String, gameID: String, initialCommunity: ArchiverseCommunity? = nil) {
        self.api = api
        self.titleID = titleID
        self.gameID = gameID
        self.initialCommunity = initialCommunity
        _community = State(initialValue: initialCommunity)
    }

    var body: some View {
        ZStack {
            MiiverseWallpaper()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let community {
                        header(community)
                    }

                    if community != nil || !filteredPosts.isEmpty {
                        MiiverseSegmentedControl(
                            options: CommunitySortMode.allCases,
                            selection: $sortMode
                        ) { $0.rawValue }
                    }

                    if let errorMessage {
                        MiiverseStatusBanner(text: errorMessage, tint: .orange)
                    }

                    if needsArchiveUnlock {
                        ArchiveUnlockPromptCard(
                            message: "Community data is blocked until Cloudflare verification is refreshed."
                        ) {
                            showArchiveUnlockSheet = true
                        }
                    }

                    if filteredPosts.isEmpty, isLoadingPosts {
                        MiiverseCard {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(MiiversePalette.green)
                                Text("Loading community posts...")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(MiiversePalette.text)
                            }
                        }
                    } else if filteredPosts.isEmpty {
                        if !needsArchiveUnlock {
                            EmptyArchiveView(
                                title: "No Posts Returned",
                                message: archiveSettings.isArchiveDateFilterEnabled
                                    ? "No posts match the current archive date filter for this community."
                                    : "This community did not return any visible posts for the selected sort."
                            )
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredPosts) { post in
                                MiiverseCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            MiiverseProfileLinkLabel(
                                                title: post.miiName,
                                                subtitle: nil,
                                                titleFont: .system(size: 15, weight: .heavy, design: .rounded),
                                                action: post.nnid.map { nnid in
                                                    { selectedUserTarget = UserProfileTarget(userID: nnid) }
                                                }
                                            )
                                            Spacer(minLength: 8)
                                            Text(ArchiveFormatters.archiveDate(post.dateString))
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .foregroundStyle(MiiversePalette.secondaryText)
                                        }

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
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .miiverseContentColumn(maxWidth: 960)
            }
        }
        .navigationTitle(community?.communityTitle ?? "Community")
        .miiverseNavigationChrome()
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadCommunity()
        }
        .onChange(of: sortMode) { _, _ in
            Task {
                await loadPosts(reset: true)
            }
        }
        .onChange(of: archiveSettings.selectedArchiveDate) { _, _ in
            guard hasLoaded else { return }
            Task {
                await loadPosts(reset: true)
            }
        }
        .sheet(isPresented: $showArchiveUnlockSheet) {
            ArchiveUnlockView {
                Task {
                    await loadCommunity()
                }
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(api: api, initialPost: post)
        }
        .navigationDestination(item: $selectedUserTarget) { target in
            UserProfileView(api: api, userID: target.userID)
        }
    }

    private func header(_ community: ArchiverseCommunity) -> some View {
        MiiverseCard {
            VStack(alignment: .leading, spacing: 14) {
                RemoteImageView(
                    url: community.bannerURL,
                    cornerRadius: 22,
                    frameHeight: 220,
                    thumbnailSize: CGSize(width: 340, height: 220),
                    scaling: .fit,
                    fallbackSystemImage: "sparkles.tv.fill"
                )

                HStack(alignment: .top, spacing: 14) {
                    RemoteImageView(
                        url: community.iconURL ?? community.bannerURL,
                        cornerRadius: 18,
                        aspectRatio: 1,
                        thumbnailSize: CGSize(width: 82, height: 82),
                        fallbackSystemImage: "gamecontroller.fill"
                    )
                    .frame(width: 82, height: 82)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(community.communityTitle)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(MiiversePalette.text)

                        Text(community.gameTitle)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiiversePalette.greenDark)

                        Text(community.badge ?? "Miiverse community archive")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(MiiversePalette.secondaryText)
                    }
                }

                HStack(spacing: 8) {
                    MiiverseStatPill(title: "Posts", value: ArchiveFormatters.number(community.numPosts))
                    MiiverseStatPill(title: "Region", value: community.region)
                    MiiverseStatPill(title: "Title ID", value: community.titleID)
                }
            }
        }
    }

    @MainActor
    private func loadCommunity() async {
        if community != nil {
            errorMessage = nil
            needsArchiveUnlock = false
            await loadPosts(reset: true)
            return
        }

        do {
            community = try await api.fetchCommunity(titleID: titleID, gameID: gameID)
            errorMessage = nil
            needsArchiveUnlock = false
        } catch {
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before this community can be loaded."
                return
            } else {
                errorMessage = error.localizedDescription
                return
            }
        }

        await loadPosts(reset: true)
    }

    @MainActor
    private func loadPosts(reset: Bool) async {
        guard !isLoadingPosts else { return }
        isLoadingPosts = true

        if reset {
            currentPage = 1
            canLoadMorePosts = true
            isLoadingMorePosts = false
            posts = []
        } else {
            isLoadingMorePosts = true
        }

        defer {
            isLoadingPosts = false
            isLoadingMorePosts = false
        }

        let apiSortMode = sortMode == .popular ? "popular" : "recent"

        do {
            let fetchedPosts = try await api.fetchCommunityPosts(
                titleID: titleID,
                gameID: gameID,
                sortMode: apiSortMode,
                page: currentPage,
                beforeDate: archiveSettings.selectedArchiveDate
            )

            if reset {
                posts = fetchedPosts
            } else {
                posts.append(contentsOf: fetchedPosts)
            }

            if fetchedPosts.isEmpty {
                canLoadMorePosts = false
            } else {
                currentPage += 1
            }

            errorMessage = nil
            needsArchiveUnlock = false
        } catch {
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before community posts can be loaded."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadMorePosts() async {
        guard canLoadMorePosts else { return }
        await loadPosts(reset: false)
    }
}
