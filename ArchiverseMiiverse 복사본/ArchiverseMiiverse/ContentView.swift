import SwiftUI

enum AppTab: Hashable {
    case home
    case search
    case yeahs
}

struct ContentView: View {
    let api: ArchiverseAPI

    @State private var selectedTab: AppTab = .home
    @State private var showsOpeningSplash = true

    var body: some View {
        Group {
            if showsOpeningSplash {
                OpeningSplashView(isPresented: $showsOpeningSplash)
                    .transition(.opacity)
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        HomeView(api: api, selectedTab: $selectedTab)
                    }
                    .tag(AppTab.home)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }

                    NavigationStack {
                        SearchView(api: api)
                    }
                    .tag(AppTab.search)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                    NavigationStack {
                        YeahsView(api: api)
                    }
                    .tag(AppTab.yeahs)
                    .tabItem {
                        Label("Yeahs", systemImage: "hand.thumbsup.fill")
                    }
                }
                .tint(MiiversePalette.green)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: showsOpeningSplash)
        .task {
            await ArchiveAccessBootstrap.prewarmArchiveSession()
        }
    }
}

struct YeahsView: View {
    @EnvironmentObject private var yeahStore: YeahStore

    let api: ArchiverseAPI

    @State private var selectedPost: ArchiversePost?
    @State private var selectedUserTarget: UserProfileTarget?

    var body: some View {
        MiiverseScreen(
            title: "Yeahs",
            subtitle: "Posts you marked with a local Yeah are collected here."
        ) {
            if yeahStore.likedPosts.isEmpty {
                EmptyArchiveView(
                    title: "No Yeah'd Posts Yet",
                    message: "Tap the Yeah button on any post and it will appear here."
                )
            } else {
                MiiverseCard {
                    HStack(spacing: 10) {
                        MiiverseStatPill(title: "Saved Posts", value: ArchiveFormatters.number(yeahStore.likedPosts.count))
                        MiiverseStatPill(title: "Mode", value: "Local")
                    }
                }

                LazyVStack(spacing: 12) {
                    ForEach(yeahStore.likedPosts) { post in
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
                                        height: 220
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
        }
        .navigationTitle("Yeahs")
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(api: api, initialPost: post)
        }
        .navigationDestination(item: $selectedUserTarget) { target in
            UserProfileView(api: api, userID: target.userID)
        }
    }
}
