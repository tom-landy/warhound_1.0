import AppIntents
import CoreSpotlight
import SwiftData

// Siri phrases and Shortcuts actions. Play/pause and skip live in WidgetShared/PlaybackIntents.swift.

struct ResumeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Resume"
    static let description = IntentDescription("Resumes the last episode.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AudioPlayer.shared.restoreLastEpisode()
        AudioPlayer.shared.resume()
        return .result()
    }
}

struct PauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause"

    @MainActor
    func perform() async throws -> some IntentResult {
        AudioPlayer.shared.pause()
        return .result()
    }
}

struct PlayUpNextIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Up Next"
    static let description = IntentDescription("Plays the next episode in Up Next.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AudioPlayer.shared.playNextInQueue() else { return .result(dialog: "Up Next is empty.") }
        return .result(dialog: "Playing \(AudioPlayer.shared.episode?.title ?? "Up Next").")
    }
}

struct PlayLatestIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Latest Episode"
    static let description = IntentDescription("Plays the newest unplayed episode from the shows you follow.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = AppEnvironment.container?.mainContext else { return .result(dialog: "Orbit isn't ready.") }
        var descriptor = FetchDescriptor<Episode>(sortBy: [SortDescriptor(\.pubDate, order: .reverse)])
        descriptor.fetchLimit = 200
        let latest = ((try? context.fetch(descriptor)) ?? []).first { $0.podcast?.isSubscribed == true && !$0.isPlayed }
        guard let latest else { return .result(dialog: "No new episodes.") }
        AudioPlayer.shared.load(latest, autoplay: true)
        return .result(dialog: "Playing \(latest.title).")
    }
}

enum SleepDuration: String, AppEnum {
    case fifteen, thirty, sixty, endOfEpisode, off

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep Timer"
    static let caseDisplayRepresentations: [SleepDuration: DisplayRepresentation] = [
        .fifteen: "15 Minutes", .thirty: "30 Minutes", .sixty: "60 Minutes",
        .endOfEpisode: "End of Episode", .off: "Off",
    ]
}

struct SleepTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Sleep Timer"
    static let openAppWhenRun = false

    @Parameter(title: "Duration", requestValueDialog: "For how long?")
    var duration: SleepDuration

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let player = AudioPlayer.shared
        switch duration {
        case .fifteen: player.setSleepTimer(minutes: 15)
        case .thirty: player.setSleepTimer(minutes: 30)
        case .sixty: player.setSleepTimer(minutes: 60)
        case .endOfEpisode: player.setSleepTimer(.endOfEpisode)
        case .off: player.setSleepTimer(.off)
        }
        return .result(dialog: IntentDialog(stringLiteral: duration == .off ? "Sleep timer off." : "Sleep timer set."))
    }
}

// MARK: - Shows by name ("Play ATP in Orbit")

struct ShowEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static let defaultQuery = ShowQuery()

    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct ShowQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ShowEntity] {
        await Self.followed().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ShowEntity] {
        let wanted = string.lowercased()
        return await Self.followed().filter { $0.title.lowercased().contains(wanted) }
    }

    func suggestedEntities() async throws -> [ShowEntity] {
        await Self.followed()
    }

    @MainActor
    static func followed() -> [ShowEntity] {
        guard let context = AppEnvironment.container?.mainContext else { return [] }
        let shows = (try? context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed },
                                                                  sortBy: [SortDescriptor(\.title)]))) ?? []
        return shows.map { ShowEntity(id: $0.feedURL.absoluteString, title: $0.title) }
    }
}

struct PlayShowIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Show"
    static let description = IntentDescription("Plays a show you follow: the episode you're partway through, otherwise the newest.")

    @Parameter(title: "Show", requestValueDialog: "Which show?")
    var show: ShowEntity

    init() {}
    init(show: ShowEntity) { self.show = show }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = AppEnvironment.container?.mainContext,
              let podcast = try? context.fetch(FetchDescriptor<Podcast>()).first(where: { $0.feedURL.absoluteString == show.id })
        else { return .result(dialog: "Couldn't find that show.") }
        let episodes = podcast.sortedEpisodes
        guard let episode = episodes.first(where: \.isInProgress) ?? episodes.first(where: { !$0.isPlayed }) ?? episodes.first
        else { return .result(dialog: "\(podcast.title) has no episodes.") }
        let player = AudioPlayer.shared
        if player.isCurrent(episode) { player.resume() } else { player.load(episode, autoplay: true) }
        return .result(dialog: "Playing \(episode.title).")
    }
}

// MARK: - Episodes

struct EpisodeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Episode"
    static let defaultQuery = EpisodeQuery()

    var id: String
    var title: String
    var show: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(show)")
    }

    @MainActor init(_ episode: Episode) {
        id = episode.key
        title = episode.title
        show = episode.podcast?.title ?? ""
    }

    init(id: String, title: String, show: String) {
        self.id = id
        self.title = title
        self.show = show
    }
}

struct EpisodeQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [EpisodeEntity] {
        await MainActor.run {
            identifiers.compactMap { key in Self.episode(key).map(EpisodeEntity.init) }
        }
    }

    func entities(matching string: String) async throws -> [EpisodeEntity] {
        let wanted = string.lowercased()
        return await MainActor.run {
            Self.recent(limit: 400)
                .filter { $0.title.lowercased().contains(wanted) || ($0.podcast?.title.lowercased().contains(wanted) ?? false) }
                .prefix(25).map(EpisodeEntity.init)
        }
    }

    func suggestedEntities() async throws -> [EpisodeEntity] {
        await MainActor.run {
            let queued = AudioPlayer.shared.queue()
            let fresh = Self.recent(limit: 200).filter { !$0.isPlayed && !$0.isQueued }.prefix(15)
            return (queued + fresh).map(EpisodeEntity.init)
        }
    }

    @MainActor static func episode(_ key: String) -> Episode? {
        guard let context = AppEnvironment.container?.mainContext else { return nil }
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor static func recent(limit: Int) -> [Episode] {
        guard let context = AppEnvironment.container?.mainContext else { return [] }
        var descriptor = FetchDescriptor<Episode>(sortBy: [SortDescriptor(\.pubDate, order: .reverse)])
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.podcast?.isSubscribed == true }
    }

    @MainActor static func podcast(_ show: ShowEntity) -> Podcast? {
        try? AppEnvironment.container?.mainContext.fetch(FetchDescriptor<Podcast>())
            .first { $0.feedURL.absoluteString == show.id }
    }
}

struct PlayEpisodeEntityIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Episode"

    @Parameter(title: "Episode") var episode: EpisodeEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AudioPlayer.shared.play(key: episode.id)
        return .result()
    }
}

enum QueuePosition: String, AppEnum {
    case next, last

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Position"
    static let caseDisplayRepresentations: [QueuePosition: DisplayRepresentation] = [
        .next: "Play Next", .last: "End of Up Next",
    ]
}

struct AddToUpNextIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Up Next"

    @Parameter(title: "Episode") var episode: EpisodeEntity
    @Parameter(title: "Position", default: .last) var position: QueuePosition

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let found = EpisodeQuery.episode(episode.id) else { return .result(dialog: "Couldn't find that episode.") }
        if position == .next { AudioPlayer.shared.playNext(found) } else { AudioPlayer.shared.addToQueue(found) }
        return .result(dialog: "Added \(found.title) to Up Next.")
    }
}

struct AddLatestToUpNextIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Latest Episode to Up Next"
    static let description = IntentDescription("Adds a show's newest unplayed episode to Up Next.")

    @Parameter(title: "Show", requestValueDialog: "Which show?") var show: ShowEntity

    init() {}
    init(show: ShowEntity) { self.show = show }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let podcast = EpisodeQuery.podcast(show),
              let latest = podcast.sortedEpisodes.first(where: { !$0.isPlayed }) ?? podcast.sortedEpisodes.first
        else { return .result(dialog: "Couldn't find that show.") }
        AudioPlayer.shared.addToQueue(latest)
        return .result(dialog: "Added \(latest.title) to Up Next.")
    }
}

struct MarkPlayedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark as Played"

    @Parameter(title: "Episode") var episode: EpisodeEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        if let found = EpisodeQuery.episode(episode.id) {
            found.isPlayed = true
            found.playbackPosition = 0
            found.queueOrder = nil
            DownloadManager.shared.episodePlayed(found)
            try? found.modelContext?.save()
            ListeningSync.shared.recordPlayback([found])
        }
        return .result()
    }
}

enum SpeedOption: String, AppEnum {
    case x08 = "0.8", x10 = "1", x12 = "1.2", x15 = "1.5", x175 = "1.75", x20 = "2"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Speed"
    static let caseDisplayRepresentations: [SpeedOption: DisplayRepresentation] = [
        .x08: DisplayRepresentation(title: "0.8×", synonyms: ["0.8", "point eight"]),
        .x10: DisplayRepresentation(title: "1×", synonyms: ["normal", "1", "normal speed"]),
        .x12: DisplayRepresentation(title: "1.2×", synonyms: ["1.2"]),
        .x15: DisplayRepresentation(title: "1.5×", synonyms: ["1.5", "one and a half"]),
        .x175: DisplayRepresentation(title: "1.75×", synonyms: ["1.75"]),
        .x20: DisplayRepresentation(title: "2×", synonyms: ["2", "double", "double speed"]),
    ]

    var value: Float { Float(rawValue) ?? 1 }
}

struct SetSpeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Playback Speed"

    @Parameter(title: "Speed", requestValueDialog: "Which speed?") var speed: SpeedOption

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AudioPlayer.shared.speed = speed.value
        return .result(dialog: "Speed set to \(NowPlayingView.speedLabel(speed.value)).")
    }
}

struct DownloadNewEpisodesIntent: AppIntent {
    static let title: LocalizedStringResource = "Download New Episodes"
    static let description = IntentDescription("Checks your shows and downloads their latest episodes. Useful as an automation when you get home.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = AppEnvironment.container?.mainContext else { return .result(dialog: "Orbit isn't ready.") }
        await FeedService.refreshAll(context: context)
        return .result(dialog: "Checking for new episodes. Downloads continue in the background.")
    }
}

// MARK: - Opening from Spotlight

struct OpenShowIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Show"
    @Parameter(title: "Show") var target: ShowEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActions.shared.open = SpotlightIndex.showPrefix + target.id
        return .result()
    }
}

struct OpenEpisodeIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Episode"
    @Parameter(title: "Episode") var target: EpisodeEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActions.shared.open = SpotlightIndex.episodePrefix + target.id
        return .result()
    }
}

@available(iOS 18.0, *)
extension ShowEntity: IndexedEntity {}

@available(iOS 18.0, *)
extension EpisodeEntity: IndexedEntity {}

struct OrbitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayShowIntent(),
                    phrases: ["Play \(\.$show) in \(.applicationName)", "Listen to \(\.$show) in \(.applicationName)"],
                    shortTitle: "Play Show", systemImageName: "play.square.stack")
        AppShortcut(intent: ResumeIntent(),
                    phrases: ["Resume \(.applicationName)", "Continue listening in \(.applicationName)"],
                    shortTitle: "Resume", systemImageName: "play.fill")
        AppShortcut(intent: PlayUpNextIntent(),
                    phrases: ["Play Up Next in \(.applicationName)"],
                    shortTitle: "Play Up Next", systemImageName: "list.bullet")
        AppShortcut(intent: PlayLatestIntent(),
                    phrases: ["Play the latest episode in \(.applicationName)", "Play something new in \(.applicationName)"],
                    shortTitle: "Play Latest", systemImageName: "sparkles")
        AppShortcut(intent: PauseIntent(),
                    phrases: ["Pause \(.applicationName)"],
                    shortTitle: "Pause", systemImageName: "pause.fill")
        AppShortcut(intent: SleepTimerIntent(),
                    phrases: ["Set a sleep timer in \(.applicationName)"],
                    shortTitle: "Sleep Timer", systemImageName: "moon.zzz")
        AppShortcut(intent: AddLatestToUpNextIntent(),
                    phrases: ["Add the latest \(\.$show) to Up Next in \(.applicationName)",
                              "Queue the latest \(\.$show) in \(.applicationName)"],
                    shortTitle: "Add Latest to Up Next", systemImageName: "text.line.last.and.arrowtriangle.forward")
        AppShortcut(intent: SetSpeedIntent(),
                    phrases: ["Change the speed in \(.applicationName)", "Set \(.applicationName) speed"],
                    shortTitle: "Set Speed", systemImageName: "gauge.with.dots.needle.67percent")
        AppShortcut(intent: DownloadNewEpisodesIntent(),
                    phrases: ["Download new episodes in \(.applicationName)", "Check for new episodes in \(.applicationName)"],
                    shortTitle: "Download New", systemImageName: "arrow.down.circle")
        AppShortcut(intent: SkipForwardIntent(),
                    phrases: ["Skip forward in \(.applicationName)"],
                    shortTitle: "Skip Forward", systemImageName: "goforward.30")
    }
}
