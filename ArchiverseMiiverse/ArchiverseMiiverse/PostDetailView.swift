import SwiftUI
import Translation
import UIKit

struct PostDetailView: View {
    @EnvironmentObject private var yeahStore: YeahStore
    @EnvironmentObject private var archiveSettings: ArchiveSettingsStore

    let api: ArchiverseAPI
    let initialPost: ArchiversePost

    @State private var post: ArchiversePost
    @State private var replies: [ArchiverseReply] = []
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var needsArchiveUnlock = false
    @State private var showArchiveUnlockSheet = false
    @State private var isPreparingShare = false
    @State private var shareImageFile: PostShareImageFile?
    @State private var translatedDetailText: String?
    @State private var translationErrorMessage: String?
    @State private var isTranslatingPostText = false
    @State private var showSystemTranslationSheet = false
    @State private var pendingInlineTranslationText: String?
    @State private var inlineTranslationRequestID = UUID()

    private var filteredReplies: [ArchiverseReply] {
        ArchiveDateFilter.filter(
            replies: replies,
            cutoffDate: archiveSettings.selectedArchiveDate
        )
    }

    init(api: ArchiverseAPI, initialPost: ArchiversePost) {
        self.api = api
        self.initialPost = initialPost
        _post = State(initialValue: initialPost)
    }

    var body: some View {
        ZStack {
            MiiverseWallpaper()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    postCard

                    if let errorMessage {
                        MiiverseStatusBanner(text: errorMessage, tint: .orange)
                    }

                    if needsArchiveUnlock {
                        ArchiveUnlockPromptCard(
                            message: "Post details are blocked until Cloudflare verification is refreshed."
                        ) {
                            showArchiveUnlockSheet = true
                        }
                    }

                    MiiverseSectionHeader(title: "Comments", systemImage: "text.bubble.fill")

                    if filteredReplies.isEmpty {
                        EmptyArchiveView(
                            title: "No Comments Loaded",
                            message: archiveSettings.isArchiveDateFilterEnabled
                                ? "No comments match the current archive date filter."
                                : "This post has no visible replies in the current response, or the archive request did not complete."
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredReplies) { reply in
                                replyCard(reply)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .miiverseContentColumn(maxWidth: 960)
            }

            if #available(iOS 18.0, *),
               let pendingInlineTranslationText {
                PostInlineTranslationTaskView(
                    requestID: inlineTranslationRequestID,
                    sourceText: pendingInlineTranslationText,
                    targetLanguage: targetTranslationLanguage
                ) { result, sourceText in
                    handleInlineTranslationResult(result, sourceText: sourceText)
                }
            }
        }
        .navigationTitle(post.communityTitle ?? "Post")
        .miiverseNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await prepareShareImage()
                    }
                } label: {
                    if isPreparingShare {
                        ProgressView()
                            .tint(MiiversePalette.greenDark)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparingShare)
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadDetails()
        }
        .sheet(isPresented: $showArchiveUnlockSheet) {
            ArchiveUnlockView {
                Task {
                    await loadDetails()
                }
            }
        }
        .sheet(item: $shareImageFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .translationPresentation(
            isPresented: $showSystemTranslationSheet,
            text: translationPresentationText
        ) { replacementText in
            applyTranslatedText(replacementText, sourceText: translationPresentationText)
        }
    }

    private var postCard: some View {
        MiiverseCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    RemoteImageView(
                        url: post.avatarURL,
                        cornerRadius: 18,
                        aspectRatio: 1,
                        thumbnailSize: CGSize(width: 62, height: 62),
                        fallbackSystemImage: "person.crop.circle.fill"
                    )
                    .frame(width: 62, height: 62)

                    if let nnid = post.nnid {
                        NavigationLink {
                            UserProfileView(api: api, userID: nnid)
                        } label: {
                            MiiverseProfileLinkLabel(
                                title: post.miiName,
                                subtitle: nnid,
                                titleFont: .system(size: 20, weight: .heavy, design: .rounded),
                                subtitleFont: .system(size: 13, weight: .bold, design: .rounded),
                                action: nil
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        MiiverseProfileLinkLabel(
                            title: post.miiName,
                            subtitle: "Unknown NNID",
                            titleFont: .system(size: 20, weight: .heavy, design: .rounded),
                            subtitleFont: .system(size: 13, weight: .bold, design: .rounded),
                            action: nil
                        )
                    }

                    Spacer(minLength: 0)

                    Text(ArchiveFormatters.archiveDate(post.dateString))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)
                }

                if let communityTitle = post.communityTitle {
                    Text(communityTitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(MiiversePalette.greenDark)
                }

                if let displayTitle = post.displayTitle {
                    Text(displayTitle)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)
                }

                Text(post.detailText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)

                if translatablePostText != nil {
                    translationSection
                }

                if !post.mediaAssets.isEmpty {
                    PostMediaPreview(
                        post: post,
                        height: 420,
                        cornerRadius: 22,
                        scalingOverride: .fit
                    )
                }

                HStack(spacing: 8) {
                    MiiverseYeahButton(post: post)
                    MiiverseStatPill(title: "Replies", value: ArchiveFormatters.number(post.numReplies))
                    MiiverseStatPill(title: "Played", value: post.isPlayed ? "Yes" : "No")
                }
            }
        }
    }

    @ViewBuilder
    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task {
                    await requestPostTranslation()
                }
            } label: {
                HStack(spacing: 10) {
                    if isTranslatingPostText {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Text(isTranslatingPostText ? "Translating…" : "Translate to System Language")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MiiversePalette.greenLight, MiiversePalette.greenDark],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isTranslatingPostText)

            if let translationErrorMessage {
                MiiverseStatusBanner(text: translationErrorMessage, tint: .orange)
            }

            if let translatedDetailText {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Translated", systemImage: "globe")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.greenDark)

                    Text(translatedDetailText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(MiiversePalette.greenLight.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(MiiversePalette.greenDark.opacity(0.22), lineWidth: 1)
                )
            }
        }
    }

    private func replyCard(_ reply: ArchiverseReply) -> some View {
        let isOriginalPoster = isOriginalPosterReply(reply)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImageView(
                    url: reply.avatarURL,
                    cornerRadius: 16,
                    aspectRatio: 1,
                    thumbnailSize: CGSize(width: 52, height: 52),
                    fallbackSystemImage: "person.fill"
                )
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let nnid = reply.nnid {
                            NavigationLink {
                                UserProfileView(api: api, userID: nnid)
                            } label: {
                                HStack(spacing: 8) {
                                    MiiverseProfileLinkLabel(
                                        title: reply.miiName,
                                        subtitle: nil,
                                        titleFont: .system(size: 15, weight: .heavy, design: .rounded),
                                        action: nil
                                    )

                                    if isOriginalPoster {
                                        originalPosterBadge
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack(spacing: 8) {
                                MiiverseProfileLinkLabel(
                                    title: reply.miiName,
                                    subtitle: nil,
                                    titleFont: .system(size: 15, weight: .heavy, design: .rounded),
                                    action: nil
                                )

                                if isOriginalPoster {
                                    originalPosterBadge
                                }
                            }
                        }
                        Spacer(minLength: 8)
                        Text(ArchiveFormatters.archiveDate(reply.dateString))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(MiiversePalette.secondaryText)
                    }

                    Text(reply.text?.nilIfEmpty ?? "Reply body unavailable.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)

                    ReplyMediaPreview(
                        reply: reply,
                        height: 260,
                        cornerRadius: 18
                    )

                    HStack(spacing: 8) {
                        MiiverseStatPill(title: "Yeahs", value: ArchiveFormatters.number(reply.numYeahs))
                        MiiverseStatPill(title: "Played", value: reply.isPlayed ? "Yes" : "No")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isOriginalPoster ? MiiversePalette.greenLight.opacity(0.18) : MiiversePalette.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isOriginalPoster ? MiiversePalette.greenDark.opacity(0.45) : MiiversePalette.line,
                    lineWidth: 1
                )
        )
        .shadow(color: MiiversePalette.cardShadow, radius: 14, x: 0, y: 8)
    }

    private var originalPosterBadge: some View {
        Text("OP")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(MiiversePalette.greenDark)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(MiiversePalette.greenLight.opacity(0.22))
            )
    }

    private func isOriginalPosterReply(_ reply: ArchiverseReply) -> Bool {
        if let replyNNID = reply.nnid?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           let postNNID = post.nnid?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return replyNNID.caseInsensitiveCompare(postNNID) == .orderedSame
        }

        let replyName = reply.miiName.trimmingCharacters(in: .whitespacesAndNewlines)
        let postName = post.miiName.trimmingCharacters(in: .whitespacesAndNewlines)
        return replyName.caseInsensitiveCompare(postName) == .orderedSame
    }

    private var translatablePostText: String? {
        post.text?.trimmed.nilIfEmpty
    }

    private var translationPresentationText: String {
        translatablePostText ?? ""
    }

    private var targetTranslationLanguage: Locale.Language? {
        Locale.Language.systemLanguages.first
    }

    @MainActor
    private func requestPostTranslation() async {
        guard let sourceText = translatablePostText else { return }

        translationErrorMessage = nil
        isTranslatingPostText = false

        if #available(iOS 18.0, *) {
            translatedDetailText = nil
            pendingInlineTranslationText = sourceText
            inlineTranslationRequestID = UUID()
            isTranslatingPostText = true
        } else {
            showSystemTranslationSheet = true
        }
    }

    @MainActor
    private func handleInlineTranslationResult(_ result: Result<String, Error>, sourceText: String) {
        isTranslatingPostText = false
        pendingInlineTranslationText = nil

        switch result {
        case .success(let translatedText):
            applyTranslatedText(translatedText, sourceText: sourceText)
        case .failure:
            showSystemTranslationSheet = true
        }
    }

    @MainActor
    private func applyTranslatedText(_ translatedText: String, sourceText: String) {
        let normalizedSource = sourceText.trimmed
        let normalizedTranslation = translatedText.trimmed

        guard let value = normalizedTranslation.nilIfEmpty else {
            translatedDetailText = nil
            translationErrorMessage = "The translator did not return usable text for this post."
            return
        }

        if value.caseInsensitiveCompare(normalizedSource) == .orderedSame {
            translatedDetailText = nil
            translationErrorMessage = "This post already appears to match the system language."
            return
        }

        translatedDetailText = value
        translationErrorMessage = nil
    }

    @MainActor
    private func prepareShareImage() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            let snapshot = try await PostShareSnapshot.load(for: post)
            guard let image = renderShareImage(from: snapshot) else {
                throw ArchiverseShareError.renderFailed
            }

            let fileURL = try saveShareImage(image, postID: post.rawID ?? post.id)
            shareImageFile = PostShareImageFile(url: fileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func renderShareImage(from snapshot: PostShareSnapshot) -> UIImage? {
        let renderer = ImageRenderer(
            content: PostShareCanvas(snapshot: snapshot)
        )
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    private func saveShareImage(_ image: UIImage, postID: String) throws -> URL {
        guard let data = image.pngData() else {
            throw ArchiverseShareError.encodeFailed
        }

        let safePostID = postID.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("archiverse-post-\(safePostID).png")

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    private func loadDetails() async {
        let currentPostID = post.rawID ?? post.id
        let shouldRefreshPost = post.nnid == nil || post.communityTitle == nil

        translatedDetailText = nil
        translationErrorMessage = nil
        pendingInlineTranslationText = nil
        isTranslatingPostText = false

        do {
            let fetchedReplies = try await api.fetchReplies(postID: currentPostID)
            replies = fetchedReplies.filter { !$0.doNotShow }
            errorMessage = nil
            needsArchiveUnlock = false
        } catch {
            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before this post's comments can be refreshed."
            } else {
                errorMessage = error.localizedDescription
            }
        }

        guard shouldRefreshPost else { return }

        do {
            let refreshedPost = try await api.fetchPost(id: currentPostID)
            post = refreshedPost
            yeahStore.refreshIfLiked(refreshedPost)
            if errorMessage == nil {
                needsArchiveUnlock = false
            }
        } catch {
            if errorMessage != nil {
                return
            }

            if let apiError = error as? ArchiverseAPIError, apiError.requiresArchiveUnlock {
                needsArchiveUnlock = true
                errorMessage = "Cloudflare verification is required before this post can be fully refreshed."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

@available(iOS 18.0, *)
private struct PostInlineTranslationTaskView: View {
    let requestID: UUID
    let sourceText: String
    let targetLanguage: Locale.Language?
    let onResult: @MainActor (Result<String, Error>, String) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .id(requestID)
            .translationTask(source: nil, target: targetLanguage) { session in
                do {
                    let response = try await session.translate(sourceText)
                    onResult(.success(response.targetText), sourceText)
                } catch {
                    onResult(.failure(error), sourceText)
                }
            }
    }
}

private enum ArchiverseShareError: LocalizedError {
    case renderFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Failed to render the post share image."
        case .encodeFailed:
            return "Failed to save the generated share image."
        }
    }
}

private struct PostShareImageFile: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

private struct PostShareSnapshot {
    let post: ArchiversePost
    let avatarImage: UIImage?
    let mediaItems: [PostShareMediaItem]

    static func load(for post: ArchiversePost) async throws -> PostShareSnapshot {
        async let avatarImage = loadImage(url: post.avatarURL)

        let mediaItems = await withTaskGroup(of: PostShareMediaItem.self) { group in
            for asset in post.mediaAssets {
                group.addTask {
                    let image = await loadImage(url: asset.url)
                    return PostShareMediaItem(asset: asset, image: image)
                }
            }

            var results: [PostShareMediaItem] = []
            for await item in group {
                results.append(item)
            }

            return results.sorted { lhs, rhs in
                post.mediaAssets.firstIndex(of: lhs.asset) ?? 0 < post.mediaAssets.firstIndex(of: rhs.asset) ?? 0
            }
        }

        return PostShareSnapshot(
            post: post,
            avatarImage: await avatarImage,
            mediaItems: mediaItems
        )
    }

    private static func loadImage(url: URL?) async -> UIImage? {
        guard let url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

private struct PostShareMediaItem: Identifiable {
    let asset: ArchiverseMediaAsset
    let image: UIImage?

    var id: String {
        asset.id
    }
}

private struct PostShareCanvas: View {
    let snapshot: PostShareSnapshot

    var body: some View {
        ZStack {
            MiiverseWallpaper()

            VStack(spacing: 0) {
                PostShareCardView(snapshot: snapshot)
                    .frame(width: 720)
            }
            .padding(28)
        }
        .frame(width: 776)
    }
}

private struct PostShareCardView: View {
    let snapshot: PostShareSnapshot

    var body: some View {
        MiiverseCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ShareSnapshotImageView(
                        image: snapshot.avatarImage,
                        cornerRadius: 20,
                        aspectRatio: 1,
                        frameHeight: 76,
                        scaling: .fill,
                        fallbackSystemImage: "person.crop.circle.fill"
                    )
                    .frame(width: 76, height: 76)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.post.miiName)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(MiiversePalette.text)

                        Text(snapshot.post.nnid ?? "Unknown NNID")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiiversePalette.greenDark)

                        Text(ArchiveFormatters.archiveDate(snapshot.post.dateString))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(MiiversePalette.secondaryText)
                    }

                    Spacer(minLength: 0)
                }

                if let communityTitle = snapshot.post.communityTitle {
                    Text(communityTitle)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.greenDark)
                }

                Text(snapshot.post.headline)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(MiiversePalette.text)

                Text(snapshot.post.detailText)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)

                if !snapshot.mediaItems.isEmpty {
                    ShareSnapshotMediaStack(items: snapshot.mediaItems)
                }

                HStack(spacing: 10) {
                    MiiverseStatPill(title: "Yeahs", value: ArchiveFormatters.number(snapshot.post.numYeahs))
                    MiiverseStatPill(title: "Replies", value: ArchiveFormatters.number(snapshot.post.numReplies))
                    MiiverseStatPill(title: "Played", value: snapshot.post.isPlayed ? "Yes" : "No")
                }

                Text("Shared from Archiverse Miiverse")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct ShareSnapshotMediaStack: View {
    let items: [PostShareMediaItem]

    private var previewHeight: CGFloat {
        items.count > 1 ? 220 : 280
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    if items.count > 1 {
                        Text(item.asset.label)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiiversePalette.greenDark)
                    }

                    ShareSnapshotImageView(
                        image: item.image,
                        cornerRadius: 22,
                        aspectRatio: nil,
                        frameHeight: previewHeight,
                        scaling: .fit,
                        fallbackSystemImage: item.asset.fallbackSystemImage
                    )
                }
            }
        }
    }
}

private struct ShareSnapshotImageView: View {
    let image: UIImage?
    let cornerRadius: CGFloat
    let aspectRatio: CGFloat?
    let frameHeight: CGFloat
    let scaling: RemoteImageScaling
    let fallbackSystemImage: String

    var body: some View {
        let baseView = Group {
            if let image {
                switch scaling {
                case .fill:
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                case .fit:
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                }
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.white, MiiversePalette.shell],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: fallbackSystemImage)
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(MiiversePalette.green.opacity(0.45))
                }
            }
        }

        Group {
            if let aspectRatio {
                baseView.aspectRatio(
                    aspectRatio,
                    contentMode: scaling == .fit ? .fit : .fill
                )
            } else {
                baseView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: frameHeight)
        .background(Color.white.opacity(0.6))
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(MiiversePalette.line, lineWidth: 1)
        )
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
