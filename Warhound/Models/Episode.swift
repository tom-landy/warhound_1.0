import Foundation
import SwiftData

@Model
final class Episode {
    /// Feed URL + item guid, so guids that repeat across feeds don't collide.
    @Attribute(.unique) var key: String
    var guid: String
    var title: String
    var summary: String
    var pubDate: Date
    var duration: TimeInterval
    var audioURL: URL
    var artworkURL: URL?
    var playbackPosition: TimeInterval = 0
    var isPlayed: Bool = false
    var lastPlayedAt: Date?
    var podcast: Podcast?

    init(key: String, guid: String, title: String, summary: String, pubDate: Date,
         duration: TimeInterval, audioURL: URL, artworkURL: URL?) {
        self.key = key
        self.guid = guid
        self.title = title
        self.summary = summary
        self.pubDate = pubDate
        self.duration = duration
        self.audioURL = audioURL
        self.artworkURL = artworkURL
    }

    var displayArtwork: URL? { artworkURL ?? podcast?.artworkURL }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, playbackPosition / duration)
    }

    var isInProgress: Bool { !isPlayed && playbackPosition > 5 }

    var remaining: TimeInterval { max(0, duration - playbackPosition) }
}
