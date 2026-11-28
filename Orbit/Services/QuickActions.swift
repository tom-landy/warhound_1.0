import Observation
import UIKit

/// Home Screen quick actions (touch and hold the app icon).
@MainActor
@Observable
final class QuickActions {
    static let shared = QuickActions()

    enum Action: String {
        case resume, upNext, search
    }

    var pending: Action?
    /// A show or episode to open, from Spotlight or Siri ("show:…" / "episode:…").
    var open: String?

    func handle(_ type: String) {
        pending = Action(rawValue: type.components(separatedBy: ".").last ?? "")
    }

    /// Refreshes the icon menu, so Resume names the current episode.
    func update() {
        var items: [UIApplicationShortcutItem] = []
        if let episode = AudioPlayer.shared.episode {
            items.append(UIApplicationShortcutItem(type: "orbit.resume", localizedTitle: "Resume",
                                                   localizedSubtitle: episode.title,
                                                   icon: UIApplicationShortcutIcon(systemImageName: "play.fill")))
        }
        items.append(UIApplicationShortcutItem(type: "orbit.upNext", localizedTitle: "Up Next", localizedSubtitle: nil,
                                               icon: UIApplicationShortcutIcon(systemImageName: "list.bullet")))
        items.append(UIApplicationShortcutItem(type: "orbit.search", localizedTitle: "Search", localizedSubtitle: nil,
                                               icon: UIApplicationShortcutIcon(systemImageName: "magnifyingglass")))
        UIApplication.shared.shortcutItems = items
    }
}

/// Receives quick actions while the app is running. Set up in AppDelegate.
final class OrbitSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        MainActor.assumeIsolated { QuickActions.shared.handle(shortcutItem.type) }
        completionHandler(true)
    }
}
