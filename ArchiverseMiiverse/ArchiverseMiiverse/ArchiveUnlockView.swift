import SwiftUI
import WebKit

enum ArchiveAccessBootstrap {
    static let host = "archiverse.pretendo.network"
    static let homeURL = URL(string: "https://archiverse.pretendo.network/")!
    static let probeURL = URL(string: "https://archiverse.pretendo.network/api/communities?page=1")!
    static let userAgentDefaultsKey = "ArchiverseMiiverse.ArchiveUserAgent"
    static let fallbackUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static var requestUserAgent: String {
        UserDefaults.standard.string(forKey: userAgentDefaultsKey) ?? fallbackUserAgent
    }

    static func saveUserAgent(_ value: String) {
        UserDefaults.standard.set(value, forKey: userAgentDefaultsKey)
    }

    static func syncCookies(from cookieStore: WKHTTPCookieStore, completion: @escaping (_ syncedCount: Int) -> Void) {
        cookieStore.getAllCookies { cookies in
            cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }

            completion(cookies.count)
        }
    }

    static func cookieHeader(for url: URL) -> String? {
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        guard !cookies.isEmpty else { return nil }

        return cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    static func isCloudflareChallenge(contentType: String, body: String, cfMitigated: String? = nil) -> Bool {
        if cfMitigated?.lowercased() == "challenge" {
            return true
        }

        let lowerContentType = contentType.lowercased()
        let lowerBody = body.lowercased()
        guard lowerContentType.contains("text/html") else {
            return false
        }

        return lowerBody.contains("just a moment") ||
            lowerBody.contains("enable javascript and cookies to continue") ||
            lowerBody.contains("checking your browser before accessing") ||
            lowerBody.contains("/cdn-cgi/challenge-platform/")
    }

    static func isCloudflareChallenge(httpResponse: HTTPURLResponse, data: Data) -> Bool {
        let contentType = httpResponse.value(forHTTPHeaderField: "content-type") ?? ""
        let html = String(data: data, encoding: .utf8) ?? ""
        return isCloudflareChallenge(
            contentType: contentType,
            body: html,
            cfMitigated: httpResponse.value(forHTTPHeaderField: "cf-mitigated")
        )
    }

    static func probeAPIAccess(maxAttempts: Int = 20) async -> Bool {
        for attempt in 1 ... maxAttempts {
            do {
                let browserResponse = try await ArchiveBrowserSession.shared.fetch(url: probeURL)
                if (200 ..< 300).contains(browserResponse.statusCode),
                   !browserResponse.isCloudflareChallenge {
                    saveUserAgent(browserResponse.userAgent)
                    return true
                }
            } catch {
            }

            if attempt < maxAttempts {
                try? await Task.sleep(for: .seconds(1))
            }
        }

        return false
    }
}

struct ArchiveBrowserFetchResult: Decodable {
    let ok: Bool
    let statusCode: Int
    let contentType: String
    let cfMitigated: String
    let body: String
    let userAgent: String
    let networkError: String?

    var isCloudflareChallenge: Bool {
        ArchiveAccessBootstrap.isCloudflareChallenge(
            contentType: contentType,
            body: body,
            cfMitigated: cfMitigated.nilIfEmpty
        )
    }

    var bodyData: Data {
        Data(body.utf8)
    }
}

private struct ArchiveBrowserDocumentSnapshot: Decodable {
    let href: String
    let title: String
    let text: String
    let contentType: String
    let userAgent: String
}

enum ArchiveRoute {
    case home
    case search
    case post(id: String)
    case user(id: String)
    case community(titleID: String, gameID: String)

    var title: String {
        switch self {
        case .home:
            return "Live Archiverse"
        case .search:
            return "Live Search"
        case .post:
            return "Live Post"
        case .user:
            return "Live Profile"
        case .community:
            return "Live Community"
        }
    }

    var url: URL {
        switch self {
        case .home:
            return ArchiveAccessBootstrap.homeURL
        case .search:
            return ArchiveAccessBootstrap.homeURL.appendingPathComponent("search")
        case .post(let id):
            return ArchiveAccessBootstrap.homeURL
                .appendingPathComponent("posts")
                .appendingPathComponent(id)
        case .user(let id):
            return ArchiveAccessBootstrap.homeURL
                .appendingPathComponent("users")
                .appendingPathComponent(id)
        case .community(let titleID, let gameID):
            return ArchiveAccessBootstrap.homeURL
                .appendingPathComponent("titles")
                .appendingPathComponent(titleID)
                .appendingPathComponent(gameID)
        }
    }
}

actor ArchiveBrowserSession {
    static let shared = ArchiveBrowserSession()

    func fetch(url: URL) async throws -> ArchiveBrowserFetchResult {
        let host = await MainActor.run { ArchiveBrowserWebViewHost.shared }
        return try await host.fetch(url: url)
    }
}

@MainActor
private final class ArchiveBrowserWebViewHost: NSObject, WKNavigationDelegate {
    static let shared = ArchiveBrowserWebViewHost()

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isHidden = true
        return webView
    }()

    private var loadContinuation: CheckedContinuation<Void, Error>?

    func makeInteractiveWebView(navigationDelegate: WKNavigationDelegate) -> WKWebView {
        webView.removeFromSuperview()
        webView.navigationDelegate = navigationDelegate
        webView.isHidden = false

        var request = URLRequest(url: ArchiveAccessBootstrap.homeURL)
        request.timeoutInterval = 20
        webView.load(request)

        return webView
    }

    func reclaimVerifiedWebView() {
        webView.navigationDelegate = self
    }

    func fetch(url: URL) async throws -> ArchiveBrowserFetchResult {
        try await ensureHomeLoaded()

        do {
            let script = """
            const requestURL = archiveRequestURL;
            try {
              const response = await fetch(requestURL, {
                credentials: 'include',
                cache: 'no-store',
                headers: {
                  'Accept': 'application/json,text/html;q=0.9,*/*;q=0.8'
                }
              });
              const body = await response.text();
              return JSON.stringify({
                ok: response.ok,
                statusCode: response.status,
                contentType: response.headers.get('content-type') || '',
                cfMitigated: response.headers.get('cf-mitigated') || '',
                body: body,
                userAgent: navigator.userAgent || '',
                networkError: ''
              });
            } catch (error) {
              return JSON.stringify({
                ok: false,
                statusCode: 0,
                contentType: '',
                cfMitigated: '',
                body: '',
                userAgent: navigator.userAgent || '',
                networkError: String(error)
              });
            }
            """

            let rawPayload = try await callAsyncJavaScript(script, arguments: [
                "archiveRequestURL": url.absoluteString
            ])
            guard let payload = rawPayload as? String,
                  let data = payload.data(using: .utf8) else {
                throw ArchiverseAPIError.invalidResponse
            }

            let decoded = try JSONDecoder().decode(ArchiveBrowserFetchResult.self, from: data)
            if let networkError = decoded.networkError?.nilIfEmpty {
                throw ArchiverseAPIError.server(message: networkError)
            }

            ArchiveAccessBootstrap.saveUserAgent(decoded.userAgent)
            return decoded
        } catch {
            let fallbackResult = try await ArchiveBrowserNavigationLoader(url: url).load()
            ArchiveAccessBootstrap.saveUserAgent(fallbackResult.userAgent)
            return fallbackResult
        }
    }

    private func ensureHomeLoaded() async throws {
        if webView.url?.host == ArchiveAccessBootstrap.host {
            return
        }

        var request = URLRequest(url: ArchiveAccessBootstrap.homeURL)
        request.timeoutInterval = 20
        webView.load(request)

        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
        }
    }

    private func callAsyncJavaScript(_ script: String, arguments: [String: Any]) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume(returning: ())
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

}

@MainActor
private final class ArchiveBrowserNavigationLoader: NSObject, WKNavigationDelegate {
    private let url: URL
    private var continuation: CheckedContinuation<ArchiveBrowserFetchResult, Error>?
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isHidden = true
        webView.customUserAgent = ArchiveAccessBootstrap.requestUserAgent
        return webView
    }()

    init(url: URL) {
        self.url = url
        super.init()
    }

    func load() async throws -> ArchiveBrowserFetchResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            self.webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = """
        JSON.stringify({
          href: window.location.href || "",
          title: document.title || "",
          text: document.body ? document.body.innerText : "",
          contentType: document.contentType || "",
          userAgent: navigator.userAgent || ""
        })
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }

            if let error {
                self.finish(with: .failure(error))
                return
            }

            guard let payload = result as? String,
                  let data = payload.data(using: .utf8),
                  let snapshot = try? JSONDecoder().decode(ArchiveBrowserDocumentSnapshot.self, from: data) else {
                self.finish(with: .failure(ArchiverseAPIError.invalidResponse))
                return
            }

            let isChallenge = ArchiveAccessBootstrap.isCloudflareChallenge(
                contentType: snapshot.contentType,
                body: snapshot.text
            )

            let response = ArchiveBrowserFetchResult(
                ok: !isChallenge,
                statusCode: isChallenge ? 403 : 200,
                contentType: snapshot.contentType,
                cfMitigated: isChallenge ? "challenge" : "",
                body: snapshot.text,
                userAgent: snapshot.userAgent,
                networkError: nil
            )

            self.finish(with: .success(response))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<ArchiveBrowserFetchResult, Error>) {
        webView.stopLoading()
        webView.navigationDelegate = nil

        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

struct ArchiveLiveFallbackView: View {
    let route: ArchiveRoute
    let message: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                MiiverseStatusBanner(
                    text: message,
                    tint: MiiversePalette.badgeBlue
                )

                Text("This browser-backed view uses the live Archiverse site directly when native syncing is blocked.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ArchiveRouteWebView(url: route.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(MiiversePalette.line, lineWidth: 1)
                    )
            }
            .padding(16)
            .background(MiiverseWallpaper())
            .navigationTitle(route.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ArchiveRouteWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = ArchiveAccessBootstrap.requestUserAgent
        webView.allowsBackForwardNavigationGestures = true

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            webView.load(request)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
    }
}

struct ArchiveUnlockView: View {
    let onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var statusText = "Loading the Archiverse verification page..."
    @State private var isUnlocked = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                MiiverseStatusBanner(
                    text: statusText,
                    tint: isUnlocked ? MiiversePalette.greenDark : MiiversePalette.badgeBlue
                )

                Text("If a Cloudflare check appears, let it finish in this embedded browser. The app will copy the verified cookies and reuse them for API requests.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MiiversePalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ArchiveChallengeWebView(
                    onStatusChange: { statusText = $0 },
                    onUnlocked: {
                        isUnlocked = true
                        statusText = "Archive access unlocked. Returning to the app..."
                        onUnlocked()
                        dismiss()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(MiiversePalette.line, lineWidth: 1)
                )
            }
            .padding(16)
            .background(MiiverseWallpaper())
            .navigationTitle("Unlock Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                ArchiveBrowserWebViewHost.shared.reclaimVerifiedWebView()
            }
        }
    }
}

private struct ArchiveChallengeSnapshot: Decodable {
    let href: String
    let title: String
    let text: String
    let userAgent: String
}

private struct ArchiveChallengeWebView: UIViewRepresentable {
    let onStatusChange: (String) -> Void
    let onUnlocked: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStatusChange: onStatusChange, onUnlocked: onUnlocked)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = ArchiveBrowserWebViewHost.shared.makeInteractiveWebView(
            navigationDelegate: context.coordinator
        )
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onStatusChange: (String) -> Void
        private let onUnlocked: () -> Void
        weak var webView: WKWebView?
        private var didUnlock = false

        init(onStatusChange: @escaping (String) -> Void, onUnlocked: @escaping () -> Void) {
            self.onStatusChange = onStatusChange
            self.onUnlocked = onUnlocked
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onStatusChange("Opening Archiverse...")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            inspect(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onStatusChange(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onStatusChange(error.localizedDescription)
        }

        private func inspect(_ webView: WKWebView) {
            let script = """
            JSON.stringify({
              href: window.location.href || "",
              title: document.title || "",
              text: document.body ? document.body.innerText.slice(0, 800) : "",
              userAgent: navigator.userAgent || ""
            })
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self,
                      let payload = result as? String,
                      let data = payload.data(using: .utf8),
                      let snapshot = try? JSONDecoder().decode(ArchiveChallengeSnapshot.self, from: data) else {
                    self?.onStatusChange("Waiting for verification to finish...")
                    return
                }

                ArchiveAccessBootstrap.saveUserAgent(snapshot.userAgent)

                let lowerText = snapshot.text.lowercased()
                let lowerTitle = snapshot.title.lowercased()
                let lowerHref = snapshot.href.lowercased()

                let isChallengePage =
                    lowerTitle.contains("just a moment") ||
                    lowerText.contains("enable javascript and cookies to continue") ||
                    lowerHref.contains("/cdn-cgi/challenge-platform/")

                guard !isChallengePage else {
                    self.onStatusChange("Cloudflare verification is still running...")
                    return
                }

                guard lowerHref.contains(ArchiveAccessBootstrap.host) else {
                    self.onStatusChange("Still waiting to return to Archiverse...")
                    return
                }

                guard !self.didUnlock else { return }
                self.didUnlock = true
                self.onStatusChange("Verification passed. Syncing cookies...")

                ArchiveAccessBootstrap.syncCookies(from: webView.configuration.websiteDataStore.httpCookieStore) { cookieCount in
                    Task { [weak self] in
                        guard let self else { return }

                        await MainActor.run {
                            self.onStatusChange("Verification passed. Synced \(cookieCount) browser cookies. Checking live API...")
                        }

                        let apiIsOpen = await ArchiveAccessBootstrap.probeAPIAccess()

                        await MainActor.run {
                            if apiIsOpen {
                                ArchiveBrowserWebViewHost.shared.reclaimVerifiedWebView()
                                self.onUnlocked()
                            } else {
                                self.didUnlock = false
                                self.onStatusChange("Browser verification finished, but the live API is still blocked. Keeping this screen open and waiting for another pass...")
                            }
                        }
                    }
                }
            }
        }
    }
}
