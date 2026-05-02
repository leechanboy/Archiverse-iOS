import SwiftUI
import UIKit
import ImageIO

enum RemoteImageScaling {
    case fill
    case fit
}

struct RemoteImageView: View {
    let url: URL?
    var cornerRadius: CGFloat = 18
    var aspectRatio: CGFloat? = nil
    var frameHeight: CGFloat? = nil
    var thumbnailSize: CGSize? = nil
    var scaling: RemoteImageScaling = .fill
    var fallbackSystemImage: String = "person.fill"

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let loadedImage {
                renderedImage(from: loadedImage)
            } else {
                ZStack {
                    placeholder

                    if url != nil && isLoading {
                        ProgressView()
                            .tint(MiiversePalette.green)
                    }
                }
            }
        }
        .applyAspectRatio(aspectRatio, scaling: scaling)
        .frame(maxWidth: .infinity)
        .frame(height: frameHeight)
        .background(Color.white.opacity(0.6))
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(MiiversePalette.line, lineWidth: 1)
        )
        .task(id: requestKey) {
            await loadImage()
        }
    }

    private var requestKey: String {
        let urlKey = url?.absoluteString ?? "empty"
        let width = Int(resolvedThumbnailSize.width.rounded())
        let height = Int(resolvedThumbnailSize.height.rounded())
        return "\(urlKey)|\(width)x\(height)"
    }

    private var resolvedThumbnailSize: CGSize {
        guard let thumbnailSize else { return .zero }

        return CGSize(
            width: thumbnailSize.width * displayScale,
            height: thumbnailSize.height * displayScale
        )
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            loadedImage = nil
            isLoading = false
            return
        }

        isLoading = true
        loadedImage = nil

        do {
            let image = try await RemoteImagePipeline.shared.image(
                for: url,
                targetPixelSize: resolvedThumbnailSize
            )

            guard !Task.isCancelled else { return }
            loadedImage = image
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            loadedImage = nil
            isLoading = false
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white, MiiversePalette.shell],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: fallbackSystemImage)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(MiiversePalette.green.opacity(0.45))
        }
    }

    @ViewBuilder
    private func renderedImage(from image: UIImage) -> some View {
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
    }
}

private actor RemoteImagePipeline {
    static let shared = RemoteImagePipeline()

    private let session: URLSession
    private let imageCache = NSCache<NSString, UIImage>()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "archiverse-miiverse-images"
        )

        session = URLSession(configuration: configuration)
        imageCache.countLimit = 200
        imageCache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for url: URL, targetPixelSize: CGSize) async throws -> UIImage {
        let cacheKey = cacheKey(for: url, targetPixelSize: targetPixelSize)

        if let cachedImage = imageCache.object(forKey: cacheKey as NSString) {
            return cachedImage
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let image = Self.decodeImage(data: data, targetPixelSize: targetPixelSize) else {
            throw URLError(.cannotDecodeContentData)
        }

        imageCache.setObject(image, forKey: cacheKey as NSString, cost: cost(for: image))
        return image
    }

    private func cacheKey(for url: URL, targetPixelSize: CGSize) -> String {
        let width = Int(targetPixelSize.width.rounded())
        let height = Int(targetPixelSize.height.rounded())
        return "\(url.absoluteString)|\(width)x\(height)"
    }

    private func cost(for image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels * 4)
    }

    private static func decodeImage(data: Data, targetPixelSize: CGSize) -> UIImage? {
        if targetPixelSize == .zero {
            return UIImage(data: data)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let maxPixelSize = max(targetPixelSize.width, targetPixelSize.height, 96).rounded(.up)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
    }
}

private extension View {
    @ViewBuilder
    func applyAspectRatio(_ ratio: CGFloat?, scaling: RemoteImageScaling) -> some View {
        if let ratio {
            self.aspectRatio(
                ratio,
                contentMode: scaling == .fit ? .fit : .fill
            )
        } else {
            self
        }
    }
}
