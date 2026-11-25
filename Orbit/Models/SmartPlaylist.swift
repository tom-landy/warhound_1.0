import Foundation

struct SmartPlaylist: Codable, Identifiable, Equatable {
    enum EpisodeOrder: String, CaseIterable, Codable {
        case newest = "Newest First"
        case oldest = "Oldest First"
    }

    var id = UUID()
    var name = ""
    var feeds: Set<URL> = []
    var unplayedOnly = true
    var downloadedOnly = false
    var maxMinutes = 0
    var order: EpisodeOrder = .newest

    func includes(feed: URL, played: Bool, downloaded: Bool, duration: TimeInterval) -> Bool {
        (feeds.isEmpty || feeds.contains(feed))
            && (!unplayedOnly || !played)
            && (!downloadedOnly || downloaded)
            && (maxMinutes == 0 || (duration > 0 && duration <= Double(maxMinutes) * 60))
    }
}
