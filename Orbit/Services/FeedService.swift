import Foundation
import SwiftData

@MainActor
enum FeedService {
    /// Returns the stored podcast for a feed, fetching and storing it first if it's new.
    static func podcast(for feedURL: URL, context: ModelContext) async throws -> Podcast {
        if let existing = try find(feedURL, context: context) {
            if existing.lastRefreshed == nil || existing.lastRefreshed! < .now.addingTimeInterval(-15 * 60) {
                try? await refresh(existing, context: context)
            }
            return existing
        }
        let parsed = try await fetch(feedURL)
        let podcast = Podcast(feedURL: feedURL, title: parsed.title, author: parsed.author,
                              summary: parsed.summary.plainText, artworkURL: parsed.artworkURL)
        context.insert(podcast)
        merge(parsed, into: podcast, context: context)
        try context.save()
        await fillMissingArtwork(podcast)
        return podcast
    }

    private static func fillMissingArtwork(_ podcast: Podcast) async {
        guard podcast.artworkURL == nil, let art = await PodcastSearch.artworkFallback(for: podcast.title) else { return }
        podcast.artworkURL = art
        try? podcast.modelContext?.save()
    }

    /// Downloads each followed show's newest unplayed episodes, up to the per-show setting.
    /// Runs after every refresh, so it also catches shows that were just imported.
    static func keepLatestDownloaded(context: ModelContext) {
        let perShow = max(1, UserDefaults.standard.integer(forKey: DownloadManager.keepPerShowKey))
        let descriptor = FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed && $0.autoDownload })
        for podcast in (try? context.fetch(descriptor)) ?? [] {
            for episode in podcast.sortedEpisodes.lazy.filter({ !$0.isPlayed }).prefix(perShow) where !episode.isDownloaded {
                DownloadManager.shared.download(episode, automatic: true)
            }
        }
    }

    static func refresh(_ podcast: Podcast, context: ModelContext) async throws {
        let parsed = try await fetch(podcast.feedURL)
        if !parsed.title.isEmpty { podcast.title = parsed.title }
        if !parsed.author.isEmpty { podcast.author = parsed.author }
        if !parsed.summary.isEmpty { podcast.summary = parsed.summary.plainText }
        if let art = parsed.artworkURL { podcast.artworkURL = art }
        merge(parsed, into: podcast, context: context)
        try context.save()
        await fillMissingArtwork(podcast)
    }

    static func refreshAll(context: ModelContext) async {
        let descriptor = FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed })
        guard let podcasts = try? context.fetch(descriptor) else { return }
        await withTaskGroup(of: Void.self) { group in
            for podcast in podcasts {
                group.addTask { @MainActor in try? await refresh(podcast, context: context) }
            }
        }
        DownloadManager.shared.cleanUp()
        keepLatestDownloaded(context: context)
        SpotlightIndex.schedule(context: context)
    }

    private static func find(_ feedURL: URL, context: ModelContext) throws -> Podcast? {
        // Filtered in memory: URL comparisons in SwiftData predicates are unreliable.
        try context.fetch(FetchDescriptor<Podcast>()).first { $0.feedURL == feedURL }
    }

    private static func fetch(_ url: URL) async throws -> ParsedFeed {
        var request = URLRequest(url: url)
        request.setValue("Orbit/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try await Task.detached(priority: .userInitiated) { try FeedParser.parse(data) }.value
    }

    @discardableResult
    private static func merge(_ parsed: ParsedFeed, into podcast: Podcast, context: ModelContext) -> [Episode] {
        var added: [Episode] = []
        let existing = Dictionary(podcast.episodes.map { ($0.guid, $0) }, uniquingKeysWith: { a, _ in a })
        for item in parsed.items {
            guard let episode = existing[item.guid] else { continue }
            if episode.chaptersURL == nil, let url = item.chaptersURL {
                episode.chaptersURL = url
                episode.chaptersChecked = false
            }
            if episode.webURL == nil { episode.webURL = item.link }
        }
        let known = Set(existing.keys)
        let prefix = podcast.feedURL.absoluteString + "#"
        for item in parsed.items where !known.contains(item.guid) {
            guard let audio = item.audioURL else { continue }
            let episode = Episode(key: prefix + item.guid, guid: item.guid, title: item.title,
                                  summary: item.summary.plainText, pubDate: item.pubDate ?? .distantPast,
                                  duration: item.duration, audioURL: audio, artworkURL: item.artworkURL)
            episode.chaptersURL = item.chaptersURL
            episode.webURL = item.link
            context.insert(episode)
            episode.podcast = podcast
            added.append(episode)
        }
        if let site = parsed.link { podcast.websiteURL = site }
        podcast.lastRefreshed = .now
        return added
    }
}
