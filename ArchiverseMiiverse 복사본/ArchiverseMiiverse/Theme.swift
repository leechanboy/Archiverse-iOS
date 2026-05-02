import SwiftUI
import UIKit

enum MiiversePalette {
    static let green = Color(red: 0.31, green: 0.76, blue: 0.12)
    static let greenDark = Color(red: 0.20, green: 0.57, blue: 0.08)
    static let greenLight = Color(red: 0.66, green: 0.92, blue: 0.36)
    static let paper = Color(red: 0.98, green: 0.995, blue: 0.97)
    static let shell = Color(red: 0.88, green: 0.96, blue: 0.82)
    static let line = Color(red: 0.73, green: 0.84, blue: 0.66)
    static let text = Color(red: 0.17, green: 0.20, blue: 0.15)
    static let secondaryText = Color(red: 0.38, green: 0.46, blue: 0.34)
    static let badgeBlue = Color(red: 0.11, green: 0.63, blue: 0.84)
    static let cardShadow = Color.black.opacity(0.08)
    static let navigationBarGradient = LinearGradient(
        colors: [
            greenDark.opacity(0.90),
            green.opacity(0.82),
            greenLight.opacity(0.72)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum BundleImageLoader {
    private static let imageCache = NSCache<NSString, UIImage>()

    static func uiImage(named name: String, fileExtension: String? = nil) -> UIImage? {
        let cacheKey = "\(name).\(fileExtension ?? "*")" as NSString
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        if let image = UIImage(named: name) {
            imageCache.setObject(image, forKey: cacheKey)
            return image
        }

        if let fileExtension,
           let path = Bundle.main.path(forResource: name, ofType: fileExtension),
           let image = UIImage(contentsOfFile: path) {
            imageCache.setObject(image, forKey: cacheKey)
            return image
        }

        for candidateExtension in ["png", "jpg", "jpeg"] {
            if let path = Bundle.main.path(forResource: name, ofType: candidateExtension),
               let image = UIImage(contentsOfFile: path) {
                imageCache.setObject(image, forKey: cacheKey)
                return image
            }
        }

        return nil
    }
}

struct MiiverseWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MiiversePalette.greenLight.opacity(0.34),
                    MiiversePalette.shell,
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let step: CGFloat = 38
                for row in stride(from: -step, through: size.height + step, by: step) {
                    for column in stride(from: -step, through: size.width + step, by: step) {
                        let offset = ((Int(row / step) + Int(column / step)) % 2 == 0) ? 8.0 : 22.0
                        let rect = CGRect(x: column + offset, y: row + 12, width: 11, height: 11)
                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(MiiversePalette.line.opacity(0.45)),
                            lineWidth: 1
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct MiiverseScreen<Content: View>: View {
    let title: String
    let subtitle: String
    let showsHeader: Bool
    let content: Content

    init(title: String, subtitle: String, showsHeader: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.showsHeader = showsHeader
        self.content = content()
    }

    var body: some View {
        ZStack {
            MiiverseWallpaper()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if showsHeader {
                        header
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .miiverseNavigationChrome()
    }

    private var header: some View {
        MiiverseCard {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(MiiversePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text("Wii U")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(MiiversePalette.green)
                    )
            }
        }
    }
}

private struct MiiverseNavigationChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiiversePalette.navigationBarGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func miiverseNavigationChrome() -> some View {
        modifier(MiiverseNavigationChromeModifier())
    }
}

struct MiiverseCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.98), MiiversePalette.paper],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(MiiversePalette.line, lineWidth: 1)
        )
        .shadow(color: MiiversePalette.cardShadow, radius: 14, x: 0, y: 8)
    }
}

struct MiiverseSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))

            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
}

struct MiiverseStatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(MiiversePalette.text)

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MiiversePalette.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MiiversePalette.line, lineWidth: 1)
        )
    }
}

struct MiiverseStatusBanner: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct MiiversePrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
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
    }
}

struct MiiverseYeahButton: View {
    @EnvironmentObject private var yeahStore: YeahStore

    let post: ArchiversePost

    private var isLiked: Bool {
        yeahStore.isLiked(post)
    }

    private var displayedCount: String {
        ArchiveFormatters.number(yeahStore.displayedYeahCount(for: post))
    }

    var body: some View {
        Button {
            yeahStore.toggleYeah(for: post)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isLiked ? .white : MiiversePalette.greenDark)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayedCount)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(isLiked ? .white : MiiversePalette.text)

                    Text(isLiked ? "Yeah'd" : "Yeah")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isLiked ? Color.white.opacity(0.9) : MiiversePalette.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isLiked ? MiiversePalette.greenDark : Color.white.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isLiked ? MiiversePalette.greenDark : MiiversePalette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "Remove Yeah" : "Add Yeah")
        .accessibilityValue(displayedCount)
        .onAppear {
            yeahStore.refreshIfLiked(post)
        }
    }
}

struct MiiverseSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option == selection

                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(isSelected ? .white : MiiversePalette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    isSelected
                                    ? LinearGradient(
                                        colors: [MiiversePalette.greenLight, MiiversePalette.green],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    : LinearGradient(
                                        colors: [Color.white, MiiversePalette.shell],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(MiiversePalette.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MiiversePalette.line, lineWidth: 1)
        )
    }
}

struct EmptyArchiveView: View {
    let title: String
    let message: String

    var body: some View {
        MiiverseCard {
            VStack(alignment: .center, spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(MiiversePalette.green)

                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(MiiversePalette.text)

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MiiversePalette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

struct ArchiveUnlockPromptCard: View {
    let message: String
    let buttonTitle: String
    let action: () -> Void

    init(
        message: String = "Live archive data is blocked until Cloudflare verification is refreshed.",
        buttonTitle: String = "Reauthenticate Cloudflare",
        action: @escaping () -> Void
    ) {
        self.message = message
        self.buttonTitle = buttonTitle
        self.action = action
    }

    var body: some View {
        MiiverseCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(MiiversePalette.greenDark)

                    Text("Cloudflare Verification Required")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiiversePalette.text)
                }

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                MiiversePrimaryButton(title: buttonTitle, systemImage: "arrow.clockwise") {
                    action()
                }
            }
        }
    }
}

struct PostMediaPreview: View {
    let post: ArchiversePost
    var width: CGFloat? = nil
    var height: CGFloat = 128
    var cornerRadius: CGFloat = 18
    var scalingOverride: RemoteImageScaling? = nil

    var body: some View {
        if !post.mediaAssets.isEmpty {
            ArchiveMediaPreviewStack(
                items: post.mediaAssets,
                width: width,
                height: height,
                cornerRadius: cornerRadius,
                scalingOverride: scalingOverride
            )
        }
    }
}

struct ReplyMediaPreview: View {
    let reply: ArchiverseReply
    var width: CGFloat? = nil
    var height: CGFloat = 124
    var cornerRadius: CGFloat = 16
    var scalingOverride: RemoteImageScaling? = nil

    var body: some View {
        if !reply.mediaAssets.isEmpty {
            ArchiveMediaPreviewStack(
                items: reply.mediaAssets,
                width: width,
                height: height,
                cornerRadius: cornerRadius,
                scalingOverride: scalingOverride
            )
        }
    }
}

private struct ArchiveMediaPreviewStack: View {
    let items: [ArchiverseMediaAsset]
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat
    var scalingOverride: RemoteImageScaling? = nil

    private var resolvedHeight: CGFloat {
        items.count > 1 ? max(height * 0.78, 104) : height
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    if items.count > 1 {
                        Text(item.label)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiiversePalette.greenDark)
                    }

                    RemoteImageView(
                        url: item.url,
                        cornerRadius: cornerRadius,
                        frameHeight: resolvedHeight,
                        thumbnailSize: CGSize(width: width ?? 340, height: resolvedHeight),
                        scaling: scalingOverride ?? .fit,
                        fallbackSystemImage: item.fallbackSystemImage
                    )
                    .frame(width: width)
                }
            }
        }
    }
}

struct SearchFieldCard: View {
    let prompt: String
    @Binding var text: String
    let submit: () -> Void

    var body: some View {
        MiiverseCard {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MiiversePalette.greenDark)

                TextField(prompt, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(submit)

                Button("Go", action: submit)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(MiiversePalette.green)
                    )
            }
        }
    }
}

struct MiiverseProfileLinkLabel: View {
    let title: String
    let subtitle: String?
    var titleFont: Font = .system(size: 16, weight: .heavy, design: .rounded)
    var subtitleFont: Font = .system(size: 12, weight: .bold, design: .rounded)
    var titleColor: Color = MiiversePalette.text
    var subtitleColor: Color = MiiversePalette.greenDark
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(titleColor)

            if let subtitle {
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(subtitleColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ArchiveFormatters {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let inputDateFormatter = ISO8601DateFormatter()

    private static let outputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func number(_ value: Int?) -> String {
        guard let value else { return "-" }
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func archiveDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "Unknown date" }
        if let date = inputDateFormatter.date(from: value) {
            return outputDateFormatter.string(from: date)
        }
        return value
    }
}
