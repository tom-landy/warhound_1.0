import Foundation

struct ListeningSyncRevision: Codable {
    enum Change: Codable {
        case subscription(feed: URL, followed: Bool)
        case playback(key: String, position: Double, played: Bool)
        case playlist(id: UUID, value: SmartPlaylist?)

        var key: String {
            switch self {
            case .subscription(let feed, _): return "show:" + feed.absoluteString
            case .playback(let key, _, _): return "episode:" + key
            case .playlist(let id, _): return "playlist:" + id.uuidString
            }
        }
    }

    let id: String
    let date: Date
    let change: Change

    func isNewer(than other: ListeningSyncRevision) -> Bool {
        date == other.date ? id > other.id : date > other.date
    }
}
