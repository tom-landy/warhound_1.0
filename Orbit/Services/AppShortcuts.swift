import AppIntents
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
        AppShortcut(intent: SkipForwardIntent(),
                    phrases: ["Skip forward in \(.applicationName)"],
                    shortTitle: "Skip Forward", systemImageName: "goforward.30")
    }
}
