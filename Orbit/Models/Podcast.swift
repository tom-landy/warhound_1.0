import Foundation
import SwiftData

@Model
final class Podcast {
    @Attribute(.unique) var feedURL: URL
    var title: String
    var author: String
    var summary: String
    var artworkURL: URL?
    var isSubscribed: Bool
    var subscribedAt: Date?
    var lastRefreshed: Date?
    /// Download new episodes as they appear.
    var autoDownload: Bool = true
    /// Speed for this show only; nil uses the default speed.
    var playbackSpeed: Float?
    /// Seconds to skip at the start of each episode.
    var skipIntro: Int = 0
    var websiteURL: URL?

    @Relationship(deleteRule: .cascade, inverse: \Episode.podcast)
    var episodes: [Episode] = []

    init(feedURL: URL, title: String, author: String = "", summary: String = "", artworkURL: URL? = nil) {
        self.feedURL = feedURL
        self.title = title
        self.author = author
        self.summary = summary
        self.artworkURL = artworkURL
        self.isSubscribed = false
    }

    var sortedEpisodes: [Episode] {
        episodes.sorted { $0.pubDate > $1.pubDate }
    }
}
