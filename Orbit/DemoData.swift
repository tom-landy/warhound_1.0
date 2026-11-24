import SwiftData
import SwiftUI

/// Sample library for screenshots and previews. Launch with `-demo`, optionally
/// `-demoTab library|search|latest`, `-demoPlayer YES` to open the full player,
/// `-demoSettings YES` to open Settings, `-demoImport YES` to open the import screen,
/// `-demoUpNext YES` / `-demoChapters YES` (with `-demoPlayer YES`) for those sheets,
/// and `-accentTheme blue` (any theme) to change colour.
@MainActor
enum DemoData {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func seed(_ context: ModelContext) {
        let shows: [(String, String, [String])] = [
            ("The Long Game", "Harbour Audio", ["Why nobody finishes the marathon", "Compound interest, explained badly", "The case for boring"]),
            ("Painted Armies", "Tabletop Weekly", ["Batch painting 40 knights", "Basing that doesn't look like basing", "Contrast paints, two years on"]),
            ("Night Shift", "Ferro Media", ["The last lighthouse keeper", "Inside a 24-hour bakery"]),
            ("Field Notes", "Open Air", ["Swifts over the city", "A year of moths"]),
            ("Small Engines", "Garage Radio", ["Carburettors without tears"]),
            ("Second Opinion", "Clinic Talk", ["What a GP actually checks"]),
        ]
        var day = 0
        for (i, (title, author, eps)) in shows.enumerated() {
            let podcast = Podcast(feedURL: URL(string: "https://example.com/feed/\(i)")!, title: title, author: author,
                                  summary: "A demo show used for screenshots. \(author) makes it every week.")
            podcast.isSubscribed = true
            context.insert(podcast)
            for (j, ep) in eps.enumerated() {
                let e = Episode(key: "demo-\(i)-\(j)", guid: "\(i)-\(j)", title: ep,
                                summary: "In this episode we get into \(ep.lowercased()), with listener questions at the end.",
                                pubDate: .now.addingTimeInterval(Double(-86400 * day - 3600 * i)),
                                duration: Double(1800 + 600 * ((i + j) % 5)),
                                audioURL: URL(string: "https://example.com/audio/\(i)-\(j).mp3")!, artworkURL: nil)
                if i == 1 && j == 0 {
                    e.playbackPosition = 1260
                    e.lastPlayedAt = .now
                    e.chaptersChecked = true
                    e.chaptersData = try? JSONEncoder().encode([
                        Chapter(start: 0, title: "Intro"),
                        Chapter(start: 95, title: "Listener questions"),
                        Chapter(start: 610, title: "Priming and undercoats"),
                        Chapter(start: 1180, title: "Speed painting the rank and file"),
                        Chapter(start: 1720, title: "Basing in bulk"),
                        Chapter(start: 2140, title: "Wrap-up"),
                    ])
                }
                if (i == 0 && j == 1) || (i == 3 && j == 0) || (i == 4 && j == 0) { e.queueOrder = Double(i) }
                if i == 2 && j == 1 { e.isPlayed = true }
                if (i == 0 && j < 2) || (i == 1 && j == 0) || i == 3 {
                    e.localFileName = "demo-\(i)-\(j).mp3"
                    e.downloadedAt = .now
                    e.fileSize = 38_000_000 + 9_000_000 * j
                }
                context.insert(e)
                e.podcast = podcast
                day += 1
            }
        }
        try? context.save()
    }

    /// Loads a paused episode into the player and returns the tab to show, if one was asked for.
    static func apply(player: AudioPlayer, context: ModelContext) -> AppTab? {
        let defaults = UserDefaults.standard
        DownloadManager.shared.showDemoProgress("demo-0-2", 0.62)
        DownloadManager.shared.showDemoProgress("demo-2-0", -1)
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.key == "demo-1-0" })
        descriptor.fetchLimit = 1
        if let episode = try? context.fetch(descriptor).first {
            player.load(episode, autoplay: false)
            if defaults.bool(forKey: "demoPlayer") { player.showsFullPlayer = true }
        }
        return defaults.string(forKey: "demoTab").flatMap(AppTab.init(rawValue:))
    }
}
