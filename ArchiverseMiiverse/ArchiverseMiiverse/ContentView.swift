import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case home
    case search
    case airplay
    case yeahs
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .search:
            return "Search"
        case .airplay:
            return "AirPlay"
        case .yeahs:
            return "Yeahs"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .search:
            return "magnifyingglass"
        case .airplay:
            return "airplayvideo"
        case .yeahs:
            return "hand.thumbsup.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let api: ArchiverseAPI
    @ObservedObject var airPlay: AirPlaySessionController

    @State private var selectedTab: AppTab = .home
    @State private var showsOpeningSplash = true

    var body: some View {
        Group {
            if showsOpeningSplash {
                OpeningSplashView(isPresented: $showsOpeningSplash)
                    .transition(.opacity)
            } else {
                if usesPadInterface {
                    ipadShell
                } else {
                    phoneTabShell
                }
            }
        }
        .animation(.easeInOut(duration: 0.32), value: showsOpeningSplash)
        .fullScreenCover(isPresented: $airPlay.isPresentingBroadcast) {
            AirPlayBroadcastShellView(api: api)
                .environmentObject(airPlay)
        }
        .task {
            await ArchiveAccessBootstrap.prewarmArchiveSession()
        }
    }

    private var usesPadInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var phoneTabShell: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                tabRootView(tab)
                    .tag(tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
            }
        }
        .tint(MiiversePalette.green)
    }

    private var ipadShell: some View {
        NavigationSplitView {
            iPadSidebar
        } detail: {
            tabRootView(selectedTab)
                .id(selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(MiiversePalette.green)
    }

    private var iPadSidebar: some View {
        ZStack {
            MiiverseWallpaper()

            List {
                Section {
                    ForEach(AppTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(selectedTab == tab ? .white : MiiversePalette.greenDark)

                                Text(tab.title)
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(selectedTab == tab ? .white : MiiversePalette.text)

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selectedTab == tab ? MiiversePalette.greenDark : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Archiverse")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(MiiversePalette.text)

                        Text("iPad Archive Browser")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(MiiversePalette.greenDark)
                    }
                    .textCase(nil)
                    .padding(.top, 10)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func tabRootView(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack {
                HomeView(api: api, selectedTab: $selectedTab)
            }
        case .search:
            NavigationStack {
                SearchView(api: api)
            }
        case .airplay:
            NavigationStack {
                AirPlayControlView(api: api)
                    .environmentObject(airPlay)
            }
        case .yeahs:
            NavigationStack {
                YeahsView(api: api)
            }
        case .settings:
            NavigationStack {
                SettingsView()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var archiveSettings: ArchiveSettingsStore

    @State private var isClearingCache = false
    @State private var cacheStatusMessage: String?

    var body: some View {
        MiiverseScreen(
            title: "Settings",
            subtitle: "Choose an archive date filter and manage local cache data."
        ) {
            if let cacheStatusMessage {
                MiiverseStatusBanner(text: cacheStatusMessage, tint: MiiversePalette.badgeBlue)
            }

            MiiverseCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Archive Date")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)

                    Toggle("Use Archive Date Filter", isOn: archiveDateFilterBinding)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tint(MiiversePalette.green)

                    Text("When enabled, posts and replies after the selected day are hidden. User and community post feeds also request older data from the API when possible.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if archiveSettings.isArchiveDateFilterEnabled {
                        DatePicker(
                            "Archive Cutoff",
                            selection: archiveDateSelectionBinding,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(MiiversePalette.green)
                    }
                }
            }

            MiiverseCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Local Cache")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)

                    Text("Clears cached API responses, cached posts, and cached images stored on this device. Cloudflare verification cookies are left intact.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    MiiversePrimaryButton(
                        title: isClearingCache ? "Clearing Cache..." : "Clear Local Cache",
                        systemImage: "trash"
                    ) {
                        guard !isClearingCache else { return }

                        Task {
                            isClearingCache = true
                            await ArchiveCacheController.clearAllCaches()
                            cacheStatusMessage = "Local cache cleared."
                            isClearingCache = false
                        }
                    }
                    .disabled(isClearingCache)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var archiveDateFilterBinding: Binding<Bool> {
        Binding(
            get: { archiveSettings.isArchiveDateFilterEnabled },
            set: { archiveSettings.setArchiveDateFilterEnabled($0) }
        )
    }

    private var archiveDateSelectionBinding: Binding<Date> {
        Binding(
            get: { archiveSettings.selectedArchiveDate ?? Date() },
            set: { archiveSettings.updateArchiveDate($0) }
        )
    }
}

struct YeahsView: View {
    @EnvironmentObject private var yeahStore: YeahStore
    @EnvironmentObject private var archiveSettings: ArchiveSettingsStore

    let api: ArchiverseAPI

    @State private var selectedPost: ArchiversePost?
    @State private var selectedUserTarget: UserProfileTarget?

    private var filteredLikedPosts: [ArchiversePost] {
        ArchiveDateFilter.filter(
            posts: yeahStore.likedPosts,
            cutoffDate: archiveSettings.selectedArchiveDate
        )
    }

    var body: some View {
        MiiverseScreen(
            title: "Yeahs",
            subtitle: "Posts you marked with a local Yeah are collected here."
        ) {
            if filteredLikedPosts.isEmpty {
                EmptyArchiveView(
                    title: "No Yeah'd Posts Yet",
                    message: archiveSettings.isArchiveDateFilterEnabled
                        ? "No local Yeah'd posts match the current archive date filter."
                        : "Tap the Yeah button on any post and it will appear here."
                )
            } else {
                MiiverseCard {
                    HStack(spacing: 10) {
                        MiiverseStatPill(title: "Saved Posts", value: ArchiveFormatters.number(filteredLikedPosts.count))
                        MiiverseStatPill(title: "Mode", value: "Local")
                    }
                }

                LazyVStack(spacing: 12) {
                    ForEach(filteredLikedPosts) { post in
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
