import SwiftData
import SwiftUI
import UIKit

@main
struct OrbitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ListeningSync.enabledKey) private var syncEnabled = false
    @State private var player = AudioPlayer.shared
    @AppStorage(AccentTheme.storageKey) private var theme: AccentTheme = .orange
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    private let container: ModelContainer

    init() {
        UserDefaults.standard.register(defaults: [
            DownloadManager.wifiOnlyKey: true,
            DownloadManager.removePlayedKey: true,
            DownloadManager.keepPerShowKey: 1,
        ])
        let demo = DemoData.isActive
        let config = ModelConfiguration(isStoredInMemoryOnly: demo, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: Podcast.self, Episode.self, ListeningDay.self, configurations: config)
        } catch {
            fatalError("Could not open the library: \(error)")
        }
        AppEnvironment.container = container
        DownloadManager.shared.configure(context: container.mainContext)
        WatchSync.shared.start(context: container.mainContext)
        if !demo { SpotlightIndex.schedule(context: container.mainContext) }
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
                .preferredColorScheme(appearance.colorScheme)
                // Sync when Orbit opens or comes back; CloudKit pushes cover changes in between.
                .task(id: syncEnabled && scenePhase == .active) {
                    guard syncEnabled, scenePhase == .active, !DemoData.isActive else { return }
                    await ListeningSync.shared.sync()
                }
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [container] in
            await BackgroundRefresh.run(container)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                player.saveProgress()
                BackgroundRefresh.schedule()
                QuickActions.shared.update()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Silent CloudKit pushes for Listening Sync. Shows nothing and asks no permission.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            let handled = await ListeningSync.shared.handleRemoteNotification(userInfo)
            completionHandler(handled ? .newData : .noData)
        }
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        guard session.role == .windowApplication else {
            // CarPlay: use the configuration from Info.plist.
            return UISceneConfiguration(name: "CarPlay", sessionRole: session.role)
        }
        if let item = options.shortcutItem {
            MainActor.assumeIsolated { QuickActions.shared.handle(item.type) }
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = OrbitSceneDelegate.self
        return configuration
    }

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
