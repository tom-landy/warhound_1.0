import SwiftData
import SwiftUI

@main
struct WarhoundApp: App {
    @State private var player = AudioPlayer()
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
                .tint(.accentColor)
        }
        .modelContainer(container)
    }
}
