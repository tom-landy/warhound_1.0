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
    /// Current speed. If the show has its own speed, changing this updates that show;
    /// otherwise it changes the default for all shows.
    var speed: Float = 1.0 {
        didSet {
            player.defaultRate = speed
            if isPlaying { player.rate = speed }
            if let podcast = episode?.podcast, podcast.playbackSpeed != nil {
                podcast.playbackSpeed = speed
            } else {
                UserDefaults.standard.set(speed, forKey: "playbackSpeed")
            }
            updateNowPlaying()
        }
    }
    var isScrubbing = false
    var showsFullPlayer = false

    enum SleepTimer: Equatable {
        case off
        case at(Date)
        case endOfEpisode
    }

    private(set) var sleepTimer: SleepTimer = .off
    private(set) var chapters: [Chapter] = []

    var defaultSpeed: Float {
        let saved = UserDefaults.standard.float(forKey: "playbackSpeed")
        return saved > 0 ? saved : 1.0
    }

    var currentChapterIndex: Int? {
        chapters.lastIndex { $0.start <= currentTime + 0.5 }
    }

    var currentChapter: Chapter? { currentChapterIndex.map { chapters[$0] } }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var syncedSeekID: UUID?
    private var lastSynced: (key: String, position: Double)?
    private var lastSaved: Date = .distantPast
    private var artwork: MPMediaItemArtwork?
    private var sleepTask: Task<Void, Never>?
    // Listening stats, flushed every 30 seconds and on pause or episode change.
    private var pendingListened: Double = 0
    private var pendingContent: Double = 0
    private var lastTickAt: Date?
    private static let lastEpisodeKey = "lastEpisodeKey"

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
        if isCurrent(episode), !episode.isPlayed {
            togglePlayPause()
            return
        }
        load(episode, autoplay: true)
    }

    func isCurrent(_ episode: Episode) -> Bool { self.episode?.key == episode.key }

    /// Plays an episode from a point, e.g. a timestamp tapped in its notes.
    func play(_ episode: Episode, from seconds: TimeInterval) {
        if isCurrent(episode), !episode.isPlayed {
            seek(to: seconds)
            if !isPlaying { resume() }
        } else {
            episode.isPlayed = false
            episode.playbackPosition = seconds
            load(episode, autoplay: true)
        }
    }

    /// Plays an episode by its key (from a widget or the watch).
    func play(key: String) {
        guard let context = AppEnvironment.container?.mainContext else { return }
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let found = try? context.fetch(descriptor).first else { return }
        if isCurrent(found), !found.isPlayed { resume() } else { load(found, autoplay: true) }
    }

    func load(_ episode: Episode, autoplay: Bool) {
        saveProgress()
        flushStats()
        self.episode = episode
        syncedSeekID = nil
        UserDefaults.standard.set(episode.key, forKey: Self.lastEpisodeKey)
        if episode.isPlayed {
            episode.isPlayed = false
            episode.playbackPosition = 0
            ListeningSync.shared.recordPlayback([episode])
        }
        episode.lastPlayedAt = .now
        episode.queueOrder = nil // it's playing now, so it leaves Up Next
        speed = episode.podcast?.playbackSpeed ?? defaultSpeed
        // Skip the intro on a fresh start.
        let intro = Double(episode.podcast?.skipIntro ?? 0)
        if episode.playbackPosition < intro { episode.playbackPosition = intro }
        duration = episode.duration
        currentTime = episode.playbackPosition
        artwork = nil
        loadArtwork(for: episode)
        chapters = episode.chapters
        if !episode.chaptersChecked { loadChapters(for: episode) }

        let local = episode.localFileURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        let item = AVPlayerItem(url: local ?? episode.audioURL)
        observeEnd(of: item)
        player.replaceCurrentItem(with: item)
        if episode.playbackPosition > 0 {
            player.seek(to: CMTime(seconds: episode.playbackPosition, preferredTimescale: 600))
        }
        Task {
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite, d.seconds > 0,
               self.player.currentItem === item {
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
        WidgetSync.schedule()
    }

    func togglePlayPause() {
        guard episode != nil else { return }
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        if let episode, episode.isPlayed {
            load(episode, autoplay: true)
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: speed)
    }

    func pause() {
        player.pause()
        saveProgress()
        flushStats()
    }

    /// Puts the last episode back in the player (paused) after the app was closed.
    func restoreLastEpisode() {
        guard episode == nil, let key = UserDefaults.standard.string(forKey: Self.lastEpisodeKey),
              let context = AppEnvironment.container?.mainContext else { return }
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let saved = try? context.fetch(descriptor).first, !saved.isPlayed else { return }
        load(saved, autoplay: false)
    }

    private func flushStats(finished: Int = 0) {
        defer { pendingListened = 0; pendingContent = 0 }
        guard let episode, let context = AppEnvironment.container?.mainContext else { return }
        ListeningStats.record(episode, listened: pendingListened, content: pendingContent, finished: finished, context: context)
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func seek(to time: TimeInterval) {
        let target = max(0, duration > 0 ? min(time, duration - 1) : time)
        syncedSeekID = nil
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in
                self?.saveProgress()
                self?.updateNowPlaying()
            }
        }
    }

    // MARK: - Up Next

    /// Episodes queued after the current one, in play order.
    func queue() -> [Episode] {
        guard let context = AppEnvironment.container?.mainContext else { return [] }
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.queueOrder != nil },
                                                  sortBy: [SortDescriptor(\.queueOrder)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func playNext(_ episode: Episode) {
        guard !isCurrent(episode) else { return }
        episode.queueOrder = (queue().first?.queueOrder ?? 0) - 1
        saveQueue()
    }

    func addToQueue(_ episode: Episode) {
        guard !isCurrent(episode) else { return }
        episode.queueOrder = (queue().last?.queueOrder ?? 0) + 1
        saveQueue()
    }

    func removeFromQueue(_ episode: Episode) {
        episode.queueOrder = nil
        saveQueue()
    }

    func moveQueue(from source: IndexSet, to destination: Int) {
        var items = queue()
        items.move(fromOffsets: source, toOffset: destination)
        for (index, episode) in items.enumerated() { episode.queueOrder = Double(index) }
        saveQueue()
    }

    /// Play the selection first, then continue with the rest of the existing queue.
    func playInOrder(_ episodes: [Episode]) {
        guard let first = episodes.first else { return }
        let selected = Set(episodes.map(\.key))
        let remaining = queue().filter { !selected.contains($0.key) }
        if !isCurrent(first) || first.isPlayed {
            load(first, autoplay: true)
        } else {
            first.queueOrder = nil
            resume()
        }
        for (index, episode) in (Array(episodes.dropFirst()) + remaining).enumerated() {
            episode.queueOrder = Double(index)
        }
        saveQueue()
    }

    func clearQueue() {
        for episode in queue() { episode.queueOrder = nil }
        saveQueue()
    }

    /// Starts the first episode in Up Next. Returns false if Up Next is empty.
    @discardableResult
    func playNextInQueue() -> Bool {
        guard let next = queue().first(where: { !isCurrent($0) }) else { return false }
        load(next, autoplay: true)
        return true
    }

    private func saveQueue() {
        try? AppEnvironment.container?.mainContext.save()
        announce()
    }

    // MARK: - Sleep timer

    func setSleepTimer(_ timer: SleepTimer) {
        sleepTask?.cancel()
        sleepTask = nil
        player.volume = 1
        sleepTimer = timer
        guard case .at(let date) = timer else { return }
        sleepTask = Task { [weak self] in
            let fade: TimeInterval = 8
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow - fade)))
            guard !Task.isCancelled, let self else { return }
            // Fade out rather than cut off mid-sentence.
            let steps = 16
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                self.player.volume = Float(steps - step) / Float(steps)
                try? await Task.sleep(for: .seconds(fade / Double(steps)))
            }
            guard !Task.isCancelled else { return }
            self.pause()
            self.setSleepTimer(.off)
        }
    }

    func setSleepTimer(minutes: Int) {
        setSleepTimer(.at(.now.addingTimeInterval(TimeInterval(minutes * 60))))
    }

    // MARK: - Chapters

    func seek(to chapter: Chapter) {
        seek(to: chapter.start)
        if !isPlaying { resume() }
    }

    private func loadChapters(for episode: Episode) {
        let key = episode.key
        let audio = episode.audioURL
        let local = episode.localFileURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        let chaptersURL = episode.chaptersURL
        Task {
            let found = await Chapters.load(audio: audio, localFile: local, chaptersURL: chaptersURL)
            episode.chaptersData = found.isEmpty ? nil : try? JSONEncoder().encode(found)
            episode.chaptersChecked = true
            try? episode.modelContext?.save()
            if self.episode?.key == key { self.chapters = found }
        }
    }

    // MARK: - Internals

    private func tick(_ seconds: TimeInterval) {
        if isPlaying && !isBuffering {
            let now = Date.now
            if let last = lastTickAt {
                let elapsed = min(2, now.timeIntervalSince(last))
                pendingListened += elapsed
                pendingContent += elapsed * Double(speed)
            }
            lastTickAt = now
            if pendingListened >= 30 { flushStats() }
        } else {
            lastTickAt = nil
        }
        guard seconds.isFinite, !isScrubbing, syncedSeekID == nil else { return }
        currentTime = seconds
        // Each save refreshes every list on screen, so not too often. Pause and episode
        // changes save straight away.
        if Date.now.timeIntervalSince(lastSaved) > 20 { saveProgress(sync: false) }
    }

    /// Saves the position locally. `sync` sends it to iCloud too: on pause, episode change and
    /// backgrounding, but not on the periodic save during playback (too chatty on poor signal).
    func saveProgress(sync: Bool = true) {
        lastSaved = .now
        guard let episode, !episode.isPlayed else { return }
        if episode.playbackPosition != currentTime {
            episode.playbackPosition = currentTime
            try? episode.modelContext?.save()
        }
        guard sync, lastSynced?.key != episode.key || lastSynced?.position != currentTime else { return }
        lastSynced = (episode.key, currentTime)
        ListeningSync.shared.recordPlayback([episode])
    }

    /// Defer a remote update while this item is actively playing on this device.
    func applySyncedPlayback(to episode: Episode, position: Double, played: Bool) -> Bool {
        let current = isCurrent(episode)
        guard !current || player.timeControlStatus == .paused else { return false }
        let position = played || !position.isFinite ? 0 : max(0, position)
        guard episode.playbackPosition != position || episode.isPlayed != played else { return true }
        episode.playbackPosition = position
        episode.isPlayed = played
        if current {
            currentTime = position
            lastSaved = .now
            let seekID = UUID()
            syncedSeekID = seekID
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) { [weak self] _ in
                Task { @MainActor in
                    if self?.syncedSeekID == seekID { self?.syncedSeekID = nil }
                }
            }
            updateNowPlaying()
            announce()
        }
        return true
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let episode = self.episode else { return }
                episode.isPlayed = true
                episode.playbackPosition = 0
                try? episode.modelContext?.save()
                ListeningSync.shared.recordPlayback([episode])
                self.currentTime = 0
                DownloadManager.shared.episodePlayed(episode)
                self.flushStats(finished: 1)
                if self.sleepTimer == .endOfEpisode {
                    self.setSleepTimer(.off)
                } else {
                    self.playNextInQueue()
                }
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
