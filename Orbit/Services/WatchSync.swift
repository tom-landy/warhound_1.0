import Foundation
import SwiftData
import WatchConnectivity

/// Keeps the watch app's lists current and takes its play commands.
@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()

    private var context: ModelContext?
    private var pushTask: Task<Void, Never>?

    func start(context: ModelContext) {
        guard WCSession.isSupported(), self.context == nil else { return }
        self.context = context
        WCSession.default.delegate = self
        WCSession.default.activate()
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WatchSync.shared.schedulePush() }
        }
    }

    /// Coalesces bursts of changes (a feed refresh saves many times) into one update.
    func schedulePush() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            push()
        }
    }

    private func push() {
        let session = WCSession.default
        guard context != nil, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(WatchMessage.encode(state()))
    }

    private func state() -> WatchState {
        let player = AudioPlayer.shared
        var state = WatchState()
        state.nowPlayingKey = player.episode?.key
        state.nowPlayingTitle = player.episode?.title
        state.isPlaying = player.isPlaying
        var recent = FetchDescriptor<Episode>(sortBy: [SortDescriptor(\.pubDate, order: .reverse)])
        recent.fetchLimit = 300
        let episodes = (try? context?.fetch(recent)) ?? []
        state.latest = episodes.filter { $0.podcast?.isSubscribed == true && !$0.isPlayed }.prefix(25).map(Self.summary)
        state.downloaded = episodes.filter(\.isDownloaded).prefix(25).map(Self.summary)
        return state
    }

    private static func summary(_ e: Episode) -> WatchEpisode {
        WatchEpisode(key: e.key, title: e.title, show: e.podcast?.title ?? "",
                     remaining: e.duration > 0 ? e.remaining : 0, downloaded: e.isDownloaded)
    }

    fileprivate func handle(_ command: WatchMessage.Command, key: String?) {
        let player = AudioPlayer.shared
        switch command {
        case .play:
            guard let key else { return }
            var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.key == key })
            descriptor.fetchLimit = 1
            guard let episode = try? context?.fetch(descriptor).first else { return }
            if player.isCurrent(episode) { player.resume() } else { player.play(episode) }
        case .toggle: player.togglePlayPause()
        case .back: player.skip(by: -AudioPlayer.skipBack)
        case .forward: player.skip(by: AudioPlayer.skipForward)
        }
        schedulePush()
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in WatchSync.shared.schedulePush() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Happens when switching watches. Reactivate for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in WatchSync.shared.schedulePush() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let command = (message[WatchMessage.commandKey] as? String).flatMap(WatchMessage.Command.init(rawValue:))
        let key = message[WatchMessage.episodeKey] as? String
        Task { @MainActor in
            if let command { WatchSync.shared.handle(command, key: key) }
        }
        replyHandler(["ok": command != nil])
    }
}
