import SwiftData
import SwiftUI
import UIKit

@main
struct OrbitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = AudioPlayer.shared
    @AppStorage(AccentTheme.storageKey) private var theme: AccentTheme = .orange
    private let container: ModelContainer

    init() {
        UserDefaults.standard.register(defaults: [
            DownloadManager.wifiOnlyKey: true,
            DownloadManager.removePlayedKey: true,
            DownloadManager.keepPerShowKey: 1,
        ])
        let demo = DemoData.isActive
        let config = ModelConfiguration(isStoredInMemoryOnly: demo)
        do {
            container = try ModelContainer(for: Podcast.self, Episode.self, ListeningDay.self, configurations: config)
        } catch {
            fatalError("Could not open the library: \(error)")
        }
        AppEnvironment.container = container
        DownloadManager.shared.configure(context: container.mainContext)
        WatchSync.shared.start(context: container.mainContext)
        if demo {
            DemoData.seed(container.mainContext)
        } else {
            DownloadManager.shared.cleanUp()
            AudioPlayer.shared.restoreLastEpisode()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .environment(DownloadManager.shared)
                .environment(\.theme, theme)
                .tint(theme.color)
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [container] in
            await BackgroundRefresh.run(container)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// iOS relaunches the app in the background when downloads finish while it was closed.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DownloadManager.sessionID else { return completionHandler() }
        MainActor.assumeIsolated {
            DownloadManager.backgroundCompletion = completionHandler
        }
    }
}

/// Shared storage for parts of the app that live outside the SwiftUI scene (CarPlay).
@MainActor
enum AppEnvironment {
    static var container: ModelContainer!
}
