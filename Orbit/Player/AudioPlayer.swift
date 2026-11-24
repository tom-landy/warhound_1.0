import AVFoundation
import MediaPlayer
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class AudioPlayer {
    /// One player for the phone UI, CarPlay and the watch.
    static let shared = AudioPlayer()
    static let speeds: [Float] = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0]
    static let skipBack: TimeInterval = 15
    static let skipForward: TimeInterval = 30

    private(set) var episode: Episode?
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var speed: Float = 1.0 {
        didSet {
            player.defaultRate = speed
            if isPlaying { player.rate = speed }
            UserDefaults.standard.set(speed, forKey: "playbackSpeed")
            updateNowPlaying()
        }
    }
    var isScrubbing = false
    var showsFullPlayer = false

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var lastSaved: Date = .distantPast
    private var artwork: MPMediaItemArtwork?

    init() {
        let saved = UserDefaults.standard.float(forKey: "playbackSpeed")
        speed = saved > 0 ? saved : 1.0
        player.defaultRate = speed
        configureSession()
        configureRemoteCommands()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.isPlaying = status != .paused
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
                self?.updateNowPlaying()
                self?.announce()
            }
        })
    }

    // MARK: - Transport

    func play(_ episode: Episode) {
        if self.episode?.key == episode.key {
            togglePlayPause()
            return
        }
        load(episode, autoplay: true)
    }

    func isCurrent(_ episode: Episode) -> Bool { self.episode?.key == episode.key }

    func load(_ episode: Episode, autoplay: Bool) {
        saveProgress()
        self.episode = episode
        if episode.isPlayed { episode.isPlayed = false; episode.playbackPosition = 0 }
        episode.lastPlayedAt = .now
        duration = episode.duration
        currentTime = episode.playbackPosition
        artwork = nil
        loadArtwork(for: episode)

        let local = episode.localFileURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        let item = AVPlayerItem(url: local ?? episode.audioURL)
        observeEnd(of: item)
        player.replaceCurrentItem(with: item)
        if episode.playbackPosition > 0 {
            player.seek(to: CMTime(seconds: episode.playbackPosition, preferredTimescale: 600))
        }
        Task {
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite, d.seconds > 0 {
                self.duration = d.seconds
                if episode.duration == 0 { episode.duration = d.seconds }
                self.updateNowPlaying()
            }
        }
        if autoplay {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.playImmediately(atRate: speed)
        }
        updateNowPlaying()
        announce()
    }

    /// Tells CarPlay and the watch that what's playing changed.
    private func announce() {
        NotificationCenter.default.post(name: .orbitPlaybackChanged, object: nil)
        WatchSync.shared.schedulePush()
    }

    func togglePlayPause() {
        guard episode != nil else { return }
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: speed)
    }

    func pause() {
        player.pause()
        saveProgress()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func seek(to time: TimeInterval) {
        let target = max(0, duration > 0 ? min(time, duration - 1) : time)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in
                self?.saveProgress()
                self?.updateNowPlaying()
            }
        }
    }

    // MARK: - Internals

    private func tick(_ seconds: TimeInterval) {
        guard seconds.isFinite, !isScrubbing else { return }
        currentTime = seconds
        if Date.now.timeIntervalSince(lastSaved) > 5 { saveProgress() }
    }

    private func saveProgress() {
        guard let episode else { return }
        episode.playbackPosition = currentTime
        try? episode.modelContext?.save()
        lastSaved = .now
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let episode = self.episode else { return }
                episode.isPlayed = true
                episode.playbackPosition = 0
                try? episode.modelContext?.save()
                self.currentTime = 0
                DownloadManager.shared.episodePlayed(episode)
            }
        }
    }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForward)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: Self.skipForward) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBack)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: -Self.skipBack) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let episode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: episode.podcast?.title ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(speed),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Built outside the main actor: MediaPlayer calls the handler on a background queue.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func loadArtwork(for episode: Episode) {
        guard let url = episode.displayArtwork else { return }
        let key = episode.key
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  self.episode?.key == key else { return }
            self.artwork = Self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }
}

extension Notification.Name {
    static let orbitPlaybackChanged = Notification.Name("orbitPlaybackChanged")
}
