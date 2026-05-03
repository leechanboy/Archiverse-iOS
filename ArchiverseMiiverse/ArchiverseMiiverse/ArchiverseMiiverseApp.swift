import SwiftUI
import UIKit

@MainActor
final class ArchiverseRuntime {
    static let shared = ArchiverseRuntime()

    let api = ArchiverseAPI()
    let yeahStore = YeahStore()
    let archiveSettings = ArchiveSettingsStore()
    let airPlay = AirPlaySessionController()

    private init() {
        airPlay.configureStores(
            yeahStore: yeahStore,
            archiveSettings: archiveSettings
        )
    }
}

final class ArchiverseApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )

        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = ArchiverseExternalDisplaySceneDelegate.self
        }

        return configuration
    }
}

final class ArchiverseExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let runtime = ArchiverseRuntime.shared
        runtime.airPlay.externalSceneDidConnect()

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = UIHostingController(
            rootView: AirPlayExternalDisplayShell()
                .environmentObject(runtime.airPlay)
                .environmentObject(runtime.yeahStore)
                .environmentObject(runtime.archiveSettings)
        )
        window.rootViewController?.view.backgroundColor = .black
        self.window = window
        window.isHidden = false
    }

    func sceneDidActivate(_ scene: UIScene) {
        ArchiverseRuntime.shared.airPlay.externalSceneDidConnect()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        ArchiverseRuntime.shared.airPlay.externalSceneDidConnect()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ArchiverseRuntime.shared.airPlay.externalSceneDidDisconnect()
        window = nil
    }
}

@main
struct ArchiverseMiiverseApp: App {
    @UIApplicationDelegateAdaptor(ArchiverseApplicationDelegate.self) private var appDelegate
    private let runtime = ArchiverseRuntime.shared
    @StateObject private var yeahStore = ArchiverseRuntime.shared.yeahStore
    @StateObject private var archiveSettings = ArchiverseRuntime.shared.archiveSettings

    var body: some Scene {
        WindowGroup {
            ContentView(api: runtime.api, airPlay: runtime.airPlay)
                .environmentObject(yeahStore)
                .environmentObject(archiveSettings)
        }
    }
}
