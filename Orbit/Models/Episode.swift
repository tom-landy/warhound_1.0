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
    /// File name inside DownloadManager.directory. Stored as a name, not a path,
    /// because the app container path changes between installs.
    var localFileName: String?
    var downloadedAt: Date?
    var fileSize: Int = 0
    /// Position in Up Next; nil when not queued. Lower plays first.
    var queueOrder: Double?
    /// Podcasting 2.0 chapters file, if the feed has one.
    var chaptersURL: URL?
    var chaptersData: Data?
    var chaptersChecked: Bool = false
    /// The episode's web page, for sharing.
    var webURL: URL?
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

    var isDownloaded: Bool { localFileName != nil }

    var isQueued: Bool { queueOrder != nil }

    /// What to share: the episode page, else the show's site, else the audio file.
    var shareURL: URL { webURL ?? podcast?.websiteURL ?? audioURL }

    var chapters: [Chapter] {
        guard let chaptersData else { return [] }
        return (try? JSONDecoder().decode([Chapter].self, from: chaptersData)) ?? []
    }

    var localFileURL: URL? {
        localFileName.map { DownloadManager.directory.appendingPathComponent($0) }
    }
}
