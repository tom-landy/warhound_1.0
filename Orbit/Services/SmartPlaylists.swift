import Foundation
import Observation

@MainActor
@Observable
final class SmartPlaylists {
    static let shared = SmartPlaylists()
    private let storageKey = "smartPlaylists"
    private(set) var items: [SmartPlaylist]

    private init() {
        items = DemoData.isActive ? [] : (UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([SmartPlaylist].self, from: $0) } ?? [])
    }

    func save(_ playlist: SmartPlaylist) {
        apply(playlist, id: playlist.id)
        ListeningSync.shared.recordPlaylist(playlist, id: playlist.id)
    }

    func delete(_ id: UUID) {
        apply(nil, id: id)
        ListeningSync.shared.recordPlaylist(nil, id: id)
    }

    func apply(_ playlist: SmartPlaylist?, id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            if let playlist {
                guard items[index] != playlist else { return }
                items[index] = playlist
            } else {
                items.remove(at: index)
            }
        } else if let playlist {
            items.append(playlist)
        } else {
            return
        }
        if !DemoData.isActive, let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
