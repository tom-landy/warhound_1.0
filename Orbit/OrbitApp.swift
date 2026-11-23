import SwiftData
import SwiftUI

@main
struct OrbitApp: App {
    @State private var player = AudioPlayer()
    @AppStorage(AccentTheme.storageKey) private var theme: AccentTheme = .orange
    private let container: ModelContainer

    init() {
        let demo = ProcessInfo.processInfo.arguments.contains("-demo")
        let config = ModelConfiguration(isStoredInMemoryOnly: demo)
        do {
            container = try ModelContainer(for: Podcast.self, Episode.self, configurations: config)
        } catch {
            fatalError("Could not open the library: \(error)")
        }
        if demo { DemoData.seed(container.mainContext) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .environment(\.theme, theme)
                .tint(theme.color)
        }
        .modelContainer(container)
    }
}
