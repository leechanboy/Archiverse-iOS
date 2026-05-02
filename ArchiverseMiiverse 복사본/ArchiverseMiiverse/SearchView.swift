import SwiftUI

enum SearchScope: String, CaseIterable {
    case users = "Users"
    case communities = "Communities"
    case posts = "Posts"
}

struct SearchView: View {
    let api: ArchiverseAPI

    @State private var searchText = ""
    @State private var scope: SearchScope = .users
    @State private var users: [ArchiverseUser] = []
    @State private var communities: [ArchiverseCommunity] = []
    @State private var posts: [ArchiversePost] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var needsArchiveUnlock = false
    @State private var showArchiveUnlockSheet = false
    @State private var selectedPost: ArchiversePost?
    @State private var selectedUserTarget: UserProfileTarget?

    var body: some View {
        MiiverseScreen(
            title: "Search",
            subtitle: "Browse NNIDs, communities, and archived post entries with the Wii U style intact."
        ) {
            SearchFieldCard(prompt: placeholderText, text: $searchText) {
                Task {
                    await performSearch()
                }
            }

            MiiverseSegmentedControl(
                options: SearchScope.allCases,
                selection: $scope
            ) { $0.rawValue }

            if let errorMessage {
                MiiverseStatusBanner(text: errorMessage, tint: .orange)
            }

            if needsArchiveUnlock {
                ArchiveUnlockPromptCard(
                    message: "Search results are blocked until Cloudflare verification is refreshed."
                ) {
                    showArchiveUnlockSheet = true
                }
            }

            if isSearching {
                MiiverseCard {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(MiiversePalette.green)
                        Text("Searching Archiverse...")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiiversePalette.text)
                    }
                }
            } else if !hasSearched {
                EmptyArchiveView(
                    title: "Find Something Familiar",
                    message: "Try a NNID, a game title, or a community name. The search view follows Archiverse's existing public API."
                )
            } else {
                resultsView
            }
        }
        .navigationTitle("Search")
        .sheet(isPresented: $showArchiveUnlockSheet) {
            ArchiveUnlockView {
                Task {
                    await performSearch()
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

    private var placeholderText: String {
        switch scope {
        case .users:
            return "Search Users by NNID"
        case .communities:
            return "Search Communities"
        case .posts:
            return "Search Posts"
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        switch scope {
        case .users:
            if users.isEmpty {
                if !needsArchiveUnlock {
                    EmptyArchiveView(title: "No Users", message: "No matching NNIDs were returned for this search.")
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(users) { user in
                        NavigationLink {
                            UserProfileView(api: api, userID: user.nnid ?? user.id, initialUser: user)
                        } label: {
                            MiiverseCard {
                                HStack(spacing: 14) {
                                    RemoteImageView(
                                        url: user.avatarURL,
                                        cornerRadius: 20,
                                        aspectRatio: 1,
                                        thumbnailSize: CGSize(width: 76, height: 76),
                                        fallbackSystemImage: "person.crop.square.fill"
                                    )
                                    .frame(width: 76, height: 76)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(user.miiName)
                                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                                            .foregroundStyle(MiiversePalette.text)

                                        Text(user.nnid ?? "Unknown NNID")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(MiiversePalette.greenDark)

                                        Text(user.bio?.nilIfEmpty ?? "No bio archived.")
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundStyle(MiiversePalette.secondaryText)
                                            .lineLimit(2)

                                        HStack(spacing: 8) {
                                            MiiverseStatPill(title: "Followers", value: ArchiveFormatters.number(user.numFollowers))
                                            MiiverseStatPill(title: "Posts", value: ArchiveFormatters.number(user.numPosts))
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .communities:
            if communities.isEmpty {
                if !needsArchiveUnlock {
                    EmptyArchiveView(title: "No Communities", message: "No matching communities were returned for this search.")
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(communities) { community in
                        NavigationLink {
                            CommunityDetailView(api: api, titleID: community.titleID, gameID: community.gameID, initialCommunity: community)
                        } label: {
                            MiiverseCard {
                                HStack(spacing: 14) {
                                    RemoteImageView(
                                        url: community.iconURL ?? community.bannerURL,
                                        cornerRadius: 20,
                                        aspectRatio: 1,
                                        thumbnailSize: CGSize(width: 76, height: 76),
                                        fallbackSystemImage: "gamecontroller.fill"
                                    )
                                    .frame(width: 76, height: 76)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(community.communityTitle)
                                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                                            .foregroundStyle(MiiversePalette.text)

                                        Text(community.gameTitle)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(MiiversePalette.greenDark)

                                        Text(community.badge ?? "Community")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(MiiversePalette.secondaryText)

                                        HStack(spacing: 8) {
                                            MiiverseStatPill(title: "Posts", value: ArchiveFormatters.number(community.numPosts))
                                            MiiverseStatPill(title: "Region", value: community.region)
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .posts:
            if posts.isEmpty {
                if !needsArchiveUnlock {
                    EmptyArchiveView(
                        title: "No Post Results",
                        message: "The open-source Archiverse repo currently exposes post search very conservatively, so some queries may return empty results."
                    )
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(posts) { post in
                        MiiverseCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    MiiverseProfileLinkLabel(
                                        title: post.miiName,
                                        subtitle: nil,
                                        action: post.nnid.map { nnid in
                                            { selectedUserTarget = UserProfileTarget(userID: nnid) }
                                        }
                                    )
                                    Spacer()
                                    Text(ArchiveFormatters.archiveDate(post.dateString))
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(MiiversePalette.secondaryText)
                                }

                                Text(post.headline)
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                                    .foregroundStyle(MiiversePalette.text)

                                Text(post.detailText)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
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
                }
            }
        }
    }

    @MainActor
    private func performSearch() async {
        let query = searchText.trimmed
        guard query.count >= 2 else {
            errorMessage = "Please enter at least two characters to search."
            return
        }

        isSearching = true
        hasSearched = true
        errorMessage = nil
        needsArchiveUnlock = false
        defer { isSearching = false }

        do {
            clearResultsForCurrentScope()
            switch scope {
            case .users:
                users = try await api.searchUsers(query: query)
            case .communities:
                communities = try await api.searchCommunities(query: query)
            case .posts:
                posts = try await api.searchPosts(query: query)
            }
            errorMessage = nil
        } catch {
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before search results can be loaded."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearResultsForCurrentScope() {
        switch scope {
        case .users:
            users = []
        case .communities:
            communities = []
        case .posts:
            posts = []
        }
    }
}
