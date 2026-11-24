import Foundation

// Compiled into both the iPhone and the watch app. Keep it Foundation-only.

struct WatchEpisode: Codable, Identifiable, Hashable {
    let key: String
    let title: String
    let show: String
    let remaining: Double
    let downloaded: Bool
}

/// Everything the watch shows, sent from the phone as one application-context update.
struct WatchState: Codable {
    var nowPlayingKey: String?
    var nowPlayingTitle: String?
    var isPlaying = false
    var latest: [WatchEpisode] = []
    var downloaded: [WatchEpisode] = []
}

enum WatchMessage {
    static let stateKey = "state"
    static let commandKey = "command"
    static let episodeKey = "episode"

    enum Command: String {
        case play, toggle, back, forward
    }

    static func encode(_ state: WatchState) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(state) else { return [:] }
        return [stateKey: data]
    }

    static func decode(_ context: [String: Any]) -> WatchState? {
        guard let data = context[stateKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchState.self, from: data)
    }
}
