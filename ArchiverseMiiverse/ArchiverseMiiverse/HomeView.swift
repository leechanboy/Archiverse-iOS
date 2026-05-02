import SwiftUI

struct HomeView: View {
    let api: ArchiverseAPI
    @Binding var selectedTab: AppTab

    @State private var featuredPosts: [ArchiversePost] = []
    @State private var recentPosts: [ArchiversePost] = []
    @State private var communities: [ArchiverseCommunity] = []
    @State private var errorMessage: String?
    @State private var needsArchiveUnlock = false
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var showArchiveUnlockSheet = false
    @State private var nextCommunitiesPage = 1
    @State private var canLoadMoreCommunities = false
    @State private var isLoadingMoreCommunities = false
    @State private var selectedPost: ArchiversePost?
    @State private var selectedUserTarget: UserProfileTarget?

    var body: some View {
        MiiverseScreen(
            title: "Archiverse",
            subtitle: "Miiverse on iPhone, restyled with the rounded green Wii U warmth."
        ) {
            heroCard

            if let errorMessage {
                MiiverseStatusBanner(text: errorMessage, tint: .orange)
            }

            if needsArchiveUnlock {
                ArchiveUnlockPromptCard(
                    message: "Live home data could not be loaded. Refresh Cloudflare verification and try again."
                ) {
                    showArchiveUnlockSheet = true
                }
            }

            if hasAnyContent {
                sectionHeader("Featured Drawings", systemImage: "scribble.variable")
                featuredScroller

                sectionHeader("Communities", systemImage: "person.3.fill")
                communityList

                sectionHeader("From The Archive", systemImage: "text.bubble.fill")
                recentPostsList
            } else if isLoading {
                MiiverseCard {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(MiiversePalette.green)
                        Text("Loading Archiverse...")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiiversePalette.text)
                    }
                }
            }
        }
        .navigationTitle("Home")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadHome()
        }
        .refreshable {
            await loadHome()
        }
        .sheet(isPresented: $showArchiveUnlockSheet) {
            ArchiveUnlockView {
                Task {
                    await loadHome()
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

    private var heroCard: some View {
        MiiverseCard {
            VStack(alignment: .leading, spacing: 14) {
                Image("archiverse-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 34)

                if UIImage(named: "welcome-image") != nil {
                    Image("welcome-image")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 118)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(MiiversePalette.line, lineWidth: 1)
                        )
                }

                Text("Browse communities, revisit drawings, and open real archived posts from Pretendo's Archiverse.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)

                HStack(spacing: 10) {
                    MiiverseStatPill(title: "Communities", value: communities.isEmpty ? "-" : "\(communities.count)")
                    MiiverseStatPill(title: "Live Mode", value: needsArchiveUnlock ? "Locked" : "API")
                }

                MiiversePrimaryButton(title: "Search The Archive", systemImage: "magnifyingglass") {
                    selectedTab = .search
                }
            }
        }
    }

    private var featuredScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(featuredPosts.prefix(8)) { post in
                    MiiverseCard {
                        VStack(alignment: .leading, spacing: 10) {
                            PostMediaPreview(
                                post: post,
                                width: 214,
                                height: 164,
                                cornerRadius: 18
                            )

                            Text(post.headline)
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundStyle(MiiversePalette.text)
                                .lineLimit(2)

                            Text(post.communityTitle ?? "Unknown community")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(MiiversePalette.greenDark)

                            Text(post.detailText)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(MiiversePalette.secondaryText)
                                .lineLimit(3)

                            HStack(spacing: 8) {
                                MiiverseYeahButton(post: post)
                                MiiverseStatPill(title: "Replies", value: ArchiveFormatters.number(post.numReplies))
                            }
                        }
                    }
                    .frame(width: 246)
                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onTapGesture {
                        selectedPost = post
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
        }
    }

    private var communityList: some View {
        LazyVStack(spacing: 12) {
            ForEach(communities) { community in
                NavigationLink {
                    CommunityDetailView(api: api, titleID: community.titleID, gameID: community.gameID, initialCommunity: community)
                } label: {
                    MiiverseCard {
                        HStack(spacing: 14) {
                            RemoteImageView(
                                url: community.iconURL ?? community.bannerURL,
                                cornerRadius: 18,
                                aspectRatio: 1,
                                thumbnailSize: CGSize(width: 70, height: 70),
                                fallbackSystemImage: "gamecontroller.fill"
                            )
                            .frame(width: 70, height: 70)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(community.communityTitle)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundStyle(MiiversePalette.text)

                                Text(community.gameTitle)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(MiiversePalette.greenDark)

                                HStack(spacing: 8) {
                                    MiiverseStatPill(title: "Posts", value: ArchiveFormatters.number(community.numPosts))
                                    MiiverseStatPill(title: "Region", value: community.region)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if canLoadMoreCommunities {
                MiiversePrimaryButton(
                    title: isLoadingMoreCommunities ? "Loading More Communities..." : "Load More Communities",
                    systemImage: "ellipsis.circle"
                ) {
                    guard !isLoadingMoreCommunities else { return }
                    Task {
                        await loadMoreCommunities()
                    }
                }
                .disabled(isLoadingMoreCommunities)
            }
        }
    }

    private var recentPostsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(recentPosts) { post in
                MiiverseCard {
                    HStack(alignment: .top, spacing: 14) {
                        RemoteImageView(
                            url: post.avatarURL,
                            cornerRadius: 18,
                            aspectRatio: 1,
                            thumbnailSize: CGSize(width: 60, height: 60),
                            fallbackSystemImage: "person.crop.circle.fill"
                        )
                        .frame(width: 60, height: 60)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    MiiverseProfileLinkLabel(
                                        title: post.miiName,
                                        subtitle: nil,
                                        action: post.nnid.map { nnid in
                                            { selectedUserTarget = UserProfileTarget(userID: nnid) }
                                        }
                                    )

                                    Text(post.communityTitle ?? "Unknown community")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(MiiversePalette.greenDark)
                                }

                                Spacer(minLength: 8)

                                Text(ArchiveFormatters.archiveDate(post.dateString))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(MiiversePalette.secondaryText)
                            }

                            Text(post.headline)
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(MiiversePalette.text)
                                .lineLimit(2)

                            Text(post.detailText)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(MiiversePalette.secondaryText)
                                .lineLimit(3)

                            PostMediaPreview(
                                post: post,
                                height: 116
                            )

                            HStack(spacing: 10) {
                                MiiverseYeahButton(post: post)
                                MiiverseStatPill(title: "Replies", value: ArchiveFormatters.number(post.numReplies))
                            }
                        }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture {
                    selectedPost = post
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        MiiverseSectionHeader(title: title, systemImage: systemImage)
            .padding(.leading, 2)
    }

    private var hasAnyContent: Bool {
        !featuredPosts.isEmpty || !recentPosts.isEmpty || !communities.isEmpty
    }

    @MainActor
    private func loadHome() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        needsArchiveUnlock = false
        defer { isLoading = false }

        async let featuredResult = attempt { try await api.fetchHomepageDrawings() }
        async let recentResult = attempt { try await api.fetchRandomPosts() }
        async let communitiesResult = attempt { try await api.fetchCommunities(page: 1) }

        let featured = await featuredResult
        let recent = await recentResult
        let fetchedCommunities = await communitiesResult

        var failures: [String] = []
        var requiresArchiveUnlock = false
        var successfulSections = 0

        switch featured {
        case .success(let posts):
            featuredPosts = posts
            successfulSections += 1
        case .failure(let error):
            failures.append("Featured Drawings: \(error.localizedDescription)")
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                requiresArchiveUnlock = true
            }
        }

        switch recent {
        case .success(let posts):
            recentPosts = posts
            successfulSections += 1
        case .failure(let error):
            failures.append("From The Archive: \(error.localizedDescription)")
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                requiresArchiveUnlock = true
            }
        }

        switch fetchedCommunities {
        case .success(let items):
            communities = items
            nextCommunitiesPage = 2
            canLoadMoreCommunities = !items.isEmpty
            successfulSections += 1
        case .failure(let error):
            failures.append("Communities: \(error.localizedDescription)")
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                requiresArchiveUnlock = true
            }
        }

        if successfulSections == 3 {
            errorMessage = nil
            return
        }

        if requiresArchiveUnlock {
            needsArchiveUnlock = true
            errorMessage = "Cloudflare verification is required before the home feed can be loaded."
            return
        }

        errorMessage = failures.joined(separator: "\n")
    }

    @MainActor
    private func loadMoreCommunities() async {
        guard canLoadMoreCommunities, !isLoadingMoreCommunities else { return }
        isLoadingMoreCommunities = true
        defer { isLoadingMoreCommunities = false }

        do {
            let fetchedCommunities = try await api.fetchCommunities(page: nextCommunitiesPage)

            if fetchedCommunities.isEmpty {
                canLoadMoreCommunities = false
                return
            }

            let existingIDs = Set(communities.map(\.id))
            communities.append(contentsOf: fetchedCommunities.filter { !existingIDs.contains($0.id) })
            nextCommunitiesPage += 1
            needsArchiveUnlock = false
        } catch {
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before more communities can be loaded."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func attempt<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }
}
