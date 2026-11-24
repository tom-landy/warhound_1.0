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
        return podcast
    }

    static func refresh(_ podcast: Podcast, context: ModelContext) async throws {
        let parsed = try await fetch(podcast.feedURL)
        if !parsed.title.isEmpty { podcast.title = parsed.title }
        if !parsed.author.isEmpty { podcast.author = parsed.author }
        if !parsed.summary.isEmpty { podcast.summary = parsed.summary.plainText }
        if let art = parsed.artworkURL { podcast.artworkURL = art }
        let added = merge(parsed, into: podcast, context: context)
        try context.save()
        if podcast.isSubscribed && podcast.autoDownload {
            // Cap it, so a feed that suddenly republishes its back catalogue doesn't fill the phone.
            for episode in added.sorted(by: { $0.pubDate > $1.pubDate }).prefix(3) {
                DownloadManager.shared.download(episode, automatic: true)
            }
        }
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
        let known = Set(podcast.episodes.map(\.guid))
        let prefix = podcast.feedURL.absoluteString + "#"
        for item in parsed.items where !known.contains(item.guid) {
            guard let audio = item.audioURL else { continue }
            let episode = Episode(key: prefix + item.guid, guid: item.guid, title: item.title,
                                  summary: item.summary.plainText, pubDate: item.pubDate ?? .distantPast,
                                  duration: item.duration, audioURL: audio, artworkURL: item.artworkURL)
            context.insert(episode)
            episode.podcast = podcast
            added.append(episode)
        }
        podcast.lastRefreshed = .now
        return added
    }
}
