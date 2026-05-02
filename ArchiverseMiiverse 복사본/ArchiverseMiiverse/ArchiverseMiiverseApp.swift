import SwiftUI

@main
struct ArchiverseMiiverseApp: App {
    private let api = ArchiverseAPI()
    @StateObject private var yeahStore = YeahStore()

    var body: some Scene {
        WindowGroup {
            ContentView(api: api)
                .environmentObject(yeahStore)
        }
    }
}
