import AVFoundation
import SwiftUI

struct OpeningSplashView: View {
    @Binding var isPresented: Bool

    @State private var hasStarted = false
    @State private var isDismissing = false
    @State private var introOpacity = 0.0
    @State private var introScale: CGFloat = 0.94
    @State private var globeIsFloating = false
    @State private var starsArePulsing = false
    @State private var loadingProgress: CGFloat = 0
    @State private var audioPlayer = OpeningThemePlayer()

    var body: some View {
        GeometryReader { geometry in
            let metrics = OpeningSplashMetrics(
                size: geometry.size
            )

            ZStack {
                openingBackground

                VStack(spacing: metrics.verticalSpacing) {
                    Spacer(minLength: metrics.topInset)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        openingScene(date: context.date, metrics: metrics)
                    }
                    .frame(maxWidth: metrics.sceneWidth, minHeight: metrics.sceneHeight, maxHeight: metrics.sceneHeight)

                    footer(metrics: metrics)
                        .frame(maxWidth: metrics.footerWidth)

                    Spacer(minLength: metrics.bottomInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, metrics.horizontalPadding)
                .opacity(introOpacity)
                .scaleEffect(introScale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                Task {
                    await dismiss()
                }
            }
        }
        .task {
            await runOpeningSequence()
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }

    private var openingBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    MiiversePalette.shell.opacity(0.96),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Image("miiverse-opening-reference")
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 18)
                .opacity(0.13)
                .blur(radius: 12)

            OpeningStarsLayer(isAnimating: starsArePulsing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func openingScene(date: Date, metrics: OpeningSplashMetrics) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let globeSize = min(
                metrics.isLandscape
                ? min(size.width * 0.28, size.height * 0.72)
                : min(size.width * 0.55, size.height * 0.42),
                228
            )
            let globeCenter = CGPoint(
                x: size.width * 0.5,
                y: size.height * (metrics.isLandscape ? 0.4 : 0.42)
            )

            ZStack {
                OpeningGlobeView(date: date)
                    .frame(width: globeSize, height: globeSize)
                    .position(x: globeCenter.x, y: globeCenter.y + (globeIsFloating ? -8 : 8))
                    .shadow(color: Color.black.opacity(0.12), radius: 28, x: 0, y: 22)

                ForEach(OpeningCityLayout.allCases) { city in
                    OpeningCityCluster(city: city, date: date, isLandscape: metrics.isLandscape)
                        .position(city.labelPosition(in: size, isLandscape: metrics.isLandscape))
                        .opacity(introOpacity)
                }

                ForEach(OpeningCityLayout.allCases) { city in
                    OpeningMiiMarker(color: city.markerColor)
                        .position(
                            city.markerPosition(
                                from: globeCenter,
                                globeSize: globeSize,
                                isLandscape: metrics.isLandscape,
                                isFloating: globeIsFloating
                            )
                        )
                        .shadow(color: city.markerColor.opacity(0.28), radius: 10, x: 0, y: 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: metrics.sceneWidth, height: metrics.sceneHeight)
    }

    @ViewBuilder
    private func footer(metrics: OpeningSplashMetrics) -> some View {
        Group {
            if metrics.prefersStackedFooter {
                VStack(alignment: .leading, spacing: 16) {
                    footerCopy(metrics: metrics)

                    HStack {
                        Spacer(minLength: 0)
                        footerLogo(metrics: metrics)
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 20) {
                    footerCopy(metrics: metrics)

                    Spacer(minLength: 12)

                    footerLogo(metrics: metrics)
                }
            }
        }
        .padding(.horizontal, metrics.footerHorizontalPadding)
        .padding(.vertical, metrics.footerVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(MiiversePalette.paper.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(MiiversePalette.line, lineWidth: 1)
        )
        .shadow(color: MiiversePalette.cardShadow, radius: 16, x: 0, y: 10)
    }

    private func footerCopy(metrics: OpeningSplashMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loading Archiverse...")
                .font(.system(size: metrics.footerTitleFontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(MiiversePalette.text)

            Text("Wii U-style opening screen with the original startup theme.")
                .font(.system(size: metrics.footerBodyFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(MiiversePalette.secondaryText)
                .lineLimit(metrics.isLandscape ? 1 : nil)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                let width = proxy.size.width

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.82))

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MiiversePalette.greenLight, MiiversePalette.greenDark],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(18, width * loadingProgress))
                }
            }
            .frame(height: metrics.progressHeight)

            Text("Tap anywhere to skip")
                .font(.system(size: metrics.footerCaptionFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(MiiversePalette.secondaryText.opacity(0.88))
        }
    }

    private func footerLogo(metrics: OpeningSplashMetrics) -> some View {
        Image("archiverse-logo")
            .resizable()
            .scaledToFit()
            .frame(width: metrics.logoWidth)
            .shadow(color: MiiversePalette.greenLight.opacity(0.2), radius: 14, x: 0, y: 8)
    }

    @MainActor
    private func runOpeningSequence() async {
        guard !hasStarted else { return }
        hasStarted = true

        audioPlayer.play()

        withAnimation(.spring(response: 0.72, dampingFraction: 0.86)) {
            introOpacity = 1
            introScale = 1
        }

        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            globeIsFloating = true
        }

        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            starsArePulsing = true
        }

        withAnimation(.linear(duration: 4.2)) {
            loadingProgress = 1
        }

        try? await Task.sleep(for: .seconds(4.8))
        await dismiss()
    }

    @MainActor
    private func dismiss() async {
        guard !isDismissing else { return }
        isDismissing = true

        audioPlayer.stop()

        withAnimation(.easeInOut(duration: 0.42)) {
            introOpacity = 0
            introScale = 1.03
        }

        try? await Task.sleep(for: .milliseconds(420))
        isPresented = false
    }
}

private struct OpeningSplashMetrics {
    let size: CGSize

    var isLandscape: Bool {
        size.width > size.height
    }

    var horizontalPadding: CGFloat {
        size.width < 390 ? 14 : 20
    }

    var availableWidth: CGFloat {
        max(0, size.width - (horizontalPadding * 2))
    }

    var availableHeight: CGFloat {
        max(0, size.height)
    }

    var topInset: CGFloat {
        isLandscape ? 6 : (availableHeight < 760 ? 18 : 28)
    }

    var bottomInset: CGFloat {
        isLandscape ? 6 : 18
    }

    var verticalSpacing: CGFloat {
        isLandscape ? 12 : 24
    }

    var prefersStackedFooter: Bool {
        !isLandscape && availableWidth < 430
    }

    var footerWidth: CGFloat {
        min(availableWidth, 640)
    }

    var footerReservedHeight: CGFloat {
        if isLandscape {
            return 96
        }

        return prefersStackedFooter ? 182 : 132
    }

    var sceneWidth: CGFloat {
        min(availableWidth, isLandscape ? 620 : 560)
    }

    var sceneHeight: CGFloat {
        let maxHeight = availableHeight - topInset - bottomInset - verticalSpacing - footerReservedHeight
        return max(190, min(maxHeight, isLandscape ? 250 : 430))
    }

    var footerHorizontalPadding: CGFloat {
        if isLandscape {
            return 18
        }

        return availableWidth < 390 ? 18 : 22
    }

    var footerVerticalPadding: CGFloat {
        if isLandscape {
            return 14
        }

        return availableWidth < 390 ? 16 : 18
    }

    var footerTitleFontSize: CGFloat {
        if isLandscape {
            return 15
        }

        return availableWidth < 390 ? 16 : 18
    }

    var footerBodyFontSize: CGFloat {
        if isLandscape {
            return 11
        }

        return availableWidth < 390 ? 12 : 13
    }

    var footerCaptionFontSize: CGFloat {
        if isLandscape {
            return 10
        }

        return availableWidth < 390 ? 10 : 11
    }

    var progressHeight: CGFloat {
        availableWidth < 390 ? 12 : 14
    }

    var logoWidth: CGFloat {
        if isLandscape {
            return min(availableWidth * 0.18, 122)
        }

        return prefersStackedFooter ? min(availableWidth * 0.44, 148) : min(availableWidth * 0.32, 170)
    }
}

private struct OpeningGlobeView: View {
    let date: Date

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.62, green: 0.96, blue: 0.94),
                            Color(red: 0.38, green: 0.88, blue: 0.92),
                            Color(red: 0.27, green: 0.79, blue: 0.86)
                        ],
                        center: .init(x: 0.42, y: 0.34),
                        startRadius: 16,
                        endRadius: 180
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.65), lineWidth: 2)
                )

            OpeningContinentOverlay()
                .padding(22)

            VStack(spacing: 0) {
                Text(OpeningSplashFormatter.mainTime(date))
                    .font(.system(size: 34, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(OpeningSplashFormatter.mainPeriod(date))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .offset(x: 48, y: -4)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 4)
        }
    }
}

private struct OpeningContinentOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.94, blue: 0.44))
                    .frame(width: width * 0.4, height: height * 0.18)
                    .rotationEffect(.degrees(-10))
                    .offset(x: width * 0.14, y: -height * 0.24)

                RoundedRectangle(cornerRadius: width * 0.1, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.94, blue: 0.44))
                    .frame(width: width * 0.5, height: height * 0.21)
                    .rotationEffect(.degrees(-18))
                    .offset(x: width * 0.02, y: height * 0.1)

                RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.94, blue: 0.44))
                    .frame(width: width * 0.18, height: height * 0.12)
                    .rotationEffect(.degrees(22))
                    .offset(x: -width * 0.14, y: -height * 0.04)

                RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.94, blue: 0.44))
                    .frame(width: width * 0.24, height: height * 0.1)
                    .rotationEffect(.degrees(28))
                    .offset(x: -width * 0.18, y: height * 0.22)
            }
            .blur(radius: 0.4)
        }
    }
}

private enum OpeningCityLayout: String, CaseIterable, Identifiable {
    case moscow
    case london
    case newYork
    case vancouver
    case sydney
    case tokyo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moscow: return "Moscow"
        case .london: return "London"
        case .newYork: return "New York"
        case .vancouver: return "Vancouver"
        case .sydney: return "Sydney"
        case .tokyo: return "Tokyo"
        }
    }

    var timeZoneIdentifier: String {
        switch self {
        case .moscow: return "Europe/Moscow"
        case .london: return "Europe/London"
        case .newYork: return "America/New_York"
        case .vancouver: return "America/Vancouver"
        case .sydney: return "Australia/Sydney"
        case .tokyo: return "Asia/Tokyo"
        }
    }

    var markerColor: Color {
        switch self {
        case .moscow: return Color(red: 0.98, green: 0.77, blue: 0.32)
        case .london: return Color(red: 0.99, green: 0.62, blue: 0.34)
        case .newYork: return Color(red: 0.21, green: 0.18, blue: 0.17)
        case .vancouver: return Color(red: 0.64, green: 0.56, blue: 0.34)
        case .sydney: return Color(red: 0.17, green: 0.17, blue: 0.17)
        case .tokyo: return Color(red: 0.24, green: 0.20, blue: 0.18)
        }
    }

    func labelPosition(in size: CGSize, isLandscape: Bool) -> CGPoint {
        switch self {
        case .moscow:
            return CGPoint(
                x: size.width * (isLandscape ? 0.31 : 0.2),
                y: size.height * (isLandscape ? 0.18 : 0.21)
            )
        case .london:
            return CGPoint(
                x: size.width * (isLandscape ? 0.63 : 0.72),
                y: size.height * (isLandscape ? 0.1 : 0.1)
            )
        case .newYork:
            return CGPoint(
                x: size.width * (isLandscape ? 0.78 : 0.83),
                y: size.height * (isLandscape ? 0.46 : 0.29)
            )
        case .vancouver:
            return CGPoint(
                x: size.width * (isLandscape ? 0.74 : 0.77),
                y: size.height * (isLandscape ? 0.84 : 0.63)
            )
        case .sydney:
            return CGPoint(
                x: size.width * (isLandscape ? 0.53 : 0.52),
                y: size.height * (isLandscape ? 0.95 : 0.86)
            )
        case .tokyo:
            return CGPoint(
                x: size.width * (isLandscape ? 0.26 : 0.24),
                y: size.height * (isLandscape ? 0.7 : 0.59)
            )
        }
    }

    func markerPosition(from center: CGPoint, globeSize: CGFloat, isLandscape: Bool, isFloating: Bool) -> CGPoint {
        let verticalShift = isFloating ? -8.0 : 8.0
        let offset: CGSize

        switch self {
        case .moscow:
            offset = CGSize(width: -globeSize * 0.55, height: -globeSize * 0.14 + verticalShift)
        case .london:
            offset = CGSize(width: globeSize * 0.14, height: -globeSize * 0.54 + verticalShift)
        case .newYork:
            offset = CGSize(width: globeSize * (isLandscape ? 0.53 : 0.55), height: -globeSize * 0.06 + verticalShift)
        case .vancouver:
            offset = CGSize(width: globeSize * 0.38, height: globeSize * 0.42 + verticalShift)
        case .sydney:
            offset = CGSize(width: -globeSize * 0.02, height: globeSize * 0.6 + verticalShift)
        case .tokyo:
            offset = CGSize(width: -globeSize * 0.48, height: globeSize * 0.32 + verticalShift)
        }

        return CGPoint(x: center.x + offset.width, y: center.y + offset.height)
    }
}

private struct OpeningCityCluster: View {
    let city: OpeningCityLayout
    let date: Date
    let isLandscape: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(city.title)
                .font(.system(size: isLandscape ? 11 : 13, weight: .medium, design: .rounded))
                .foregroundStyle(MiiversePalette.secondaryText)
                .minimumScaleFactor(0.8)

            Capsule(style: .continuous)
                .fill(MiiversePalette.green)
                .frame(width: isLandscape ? 62 : 70, height: 2)

            Text(OpeningSplashFormatter.cityTime(date, timeZoneIdentifier: city.timeZoneIdentifier))
                .font(.system(size: isLandscape ? 18 : 21, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MiiversePalette.text)
        }
        .frame(width: isLandscape ? 96 : 108)
    }
}

private struct OpeningMiiMarker: View {
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1.6)
                )

            Capsule(style: .continuous)
                .fill(color)
                .frame(width: 6, height: 13)
        }
    }
}

private struct OpeningStarsLayer: View {
    let isAnimating: Bool

    private let stars: [OpeningStar] = [
        .init(x: 0.12, y: 0.14, size: 20, delay: 0.0),
        .init(x: 0.29, y: 0.05, size: 11, delay: 0.2),
        .init(x: 0.79, y: 0.1, size: 16, delay: 0.4),
        .init(x: 0.88, y: 0.2, size: 10, delay: 0.55),
        .init(x: 0.08, y: 0.31, size: 12, delay: 0.72),
        .init(x: 0.93, y: 0.39, size: 15, delay: 0.15),
        .init(x: 0.18, y: 0.52, size: 14, delay: 0.28),
        .init(x: 0.85, y: 0.6, size: 10, delay: 0.61),
        .init(x: 0.11, y: 0.75, size: 16, delay: 0.43),
        .init(x: 0.27, y: 0.88, size: 11, delay: 0.52),
        .init(x: 0.73, y: 0.82, size: 14, delay: 0.33),
        .init(x: 0.91, y: 0.88, size: 18, delay: 0.08)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(stars) { star in
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: star.size, height: star.size)
                    .foregroundStyle(MiiversePalette.greenLight.opacity(isAnimating ? 0.9 : 0.42))
                    .scaleEffect(isAnimating ? 1.0 : 0.7)
                    .animation(
                        .easeInOut(duration: 1.4)
                        .repeatForever(autoreverses: true)
                        .delay(star.delay),
                        value: isAnimating
                    )
                    .position(x: proxy.size.width * star.x, y: proxy.size.height * star.y)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct OpeningStar: Identifiable {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let delay: Double

    var id: String {
        "\(x)-\(y)-\(size)"
    }
}

private enum OpeningSplashFormatter {
    static func cityTime(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func mainTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func mainPeriod(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

private final class OpeningThemePlayer {
    private var player: AVAudioPlayer?

    func play() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "miiverse-opening-theme", withExtension: "mp3") else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.72
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            self.player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
