import Foundation
import Observation
import WatchConnectivity

/// Talks to Orbit on the iPhone: receives the episode lists, sends play commands.
@MainActor
@Observable
final class PhoneLink: NSObject {
    private(set) var state: WatchState?
    private(set) var reachable = false
    var lastError: String?

    override init() {
        super.init()
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            state = Self.demo
            reachable = true
            return
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func play(_ episode: WatchEpisode) {
        send(.play, key: episode.key)
    }

    func send(_ command: WatchMessage.Command, key: String? = nil) {
        guard !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        var message: [String: Any] = [WatchMessage.commandKey: command.rawValue]
        if let key { message[WatchMessage.episodeKey] = key }
        lastError = nil
        // Wakes Orbit on the phone in the background if it isn't running.
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            let text = error.localizedDescription
            Task { @MainActor in self.lastError = "Couldn't reach your iPhone. \(text)" }
        }
    }

    fileprivate func apply(_ context: [String: Any]) {
        if let decoded = WatchMessage.decode(context) { state = decoded }
    }

    fileprivate func setReachable(_ value: Bool) { reachable = value }

    private static let demo = WatchState(
        nowPlayingKey: "d1", nowPlayingTitle: "Batch painting 40 knights", isPlaying: true,
        latest: [
            WatchEpisode(key: "d1", title: "Batch painting 40 knights", show: "Painted Armies", remaining: 1140, downloaded: true),
            WatchEpisode(key: "d2", title: "Why nobody finishes the marathon", show: "The Long Game", remaining: 1800, downloaded: true),
            WatchEpisode(key: "d3", title: "Compound interest, explained badly", show: "The Long Game", remaining: 2400, downloaded: false),
            WatchEpisode(key: "d4", title: "The last lighthouse keeper", show: "Night Shift", remaining: 3000, downloaded: false),
        ],
        downloaded: [
            WatchEpisode(key: "d1", title: "Batch painting 40 knights", show: "Painted Armies", remaining: 1140, downloaded: true),
            WatchEpisode(key: "d2", title: "Why nobody finishes the marathon", show: "The Long Game", remaining: 1800, downloaded: true),
        ])
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            self.apply(context)
            self.setReachable(reachable)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.setReachable(reachable) }
    }
}
