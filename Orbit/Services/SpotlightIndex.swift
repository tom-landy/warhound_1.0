@preconcurrency import CoreSpotlight
import SwiftData
import UniformTypeIdentifiers

/// Puts followed shows and recent episodes into iPhone search.
@MainActor
enum SpotlightIndex {
    static let showPrefix = "show:"
    static let episodePrefix = "episode:"
    private static var task: Task<Void, Never>?

    static func schedule(context: ModelContext) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            reindex(context: context)
        }
    }

    private static func reindex(context: ModelContext) {
        let shows = (try? context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed }))) ?? []
        var items: [CSSearchableItem] = shows.map { show in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = show.title
            attributes.contentDescription = show.author.isEmpty ? show.summary : show.author
            attributes.keywords = ["podcast", show.author].filter { !$0.isEmpty }
            return CSSearchableItem(uniqueIdentifier: showPrefix + show.feedURL.absoluteString,
                                    domainIdentifier: "shows", attributeSet: attributes)
        }
        for show in shows {
            for episode in show.sortedEpisodes.prefix(20) {
                let attributes = CSSearchableItemAttributeSet(contentType: .audio)
                attributes.title = episode.title
                attributes.contentDescription = "\(show.title) · \(episode.pubDate.episodeDate)"
                attributes.duration = episode.duration > 0 ? NSNumber(value: episode.duration) : nil
                items.append(CSSearchableItem(uniqueIdentifier: episodePrefix + episode.key,
                                              domainIdentifier: "episodes", attributeSet: attributes))
            }
        }
        OrbitShortcuts.updateAppShortcutParameters()
        let index = CSSearchableIndex.default()
        if #available(iOS 18.0, *) {
            let showEntities = shows.map { ShowEntity(id: $0.feedURL.absoluteString, title: $0.title) }
            let episodeEntities = shows.flatMap { $0.sortedEpisodes.prefix(20) }.map(EpisodeEntity.init)
            Task {
                try? await index.deleteAllSearchableItems()
                try? await index.indexAppEntities(showEntities)
                try? await index.indexAppEntities(episodeEntities)
            }
        } else {
            Task {
                try? await index.deleteAllSearchableItems()
                try? await index.indexSearchableItems(items)
            }
        }
    }
}
