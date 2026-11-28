import Foundation

let feed = URL(string: "https://example.com/feed.xml")!
let other = URL(string: "https://example.org/feed.xml")!
let playlist = SmartPlaylist(name: "Offline commute", feeds: [feed], downloadedOnly: true, maxMinutes: 30)

precondition(playlist.includes(feed: feed, played: false, downloaded: true, duration: 1_800))
precondition(!playlist.includes(feed: other, played: false, downloaded: true, duration: 1_800))
precondition(!playlist.includes(feed: feed, played: true, downloaded: true, duration: 1_800))
precondition(!playlist.includes(feed: feed, played: false, downloaded: false, duration: 1_800))
precondition(!playlist.includes(feed: feed, played: false, downloaded: true, duration: 1_801))
precondition(!playlist.includes(feed: feed, played: false, downloaded: true, duration: 0))
precondition(SmartPlaylist().includes(feed: other, played: false, downloaded: false, duration: 0))

let saved = try JSONEncoder().encode(playlist)
let reloaded = try JSONDecoder().decode(SmartPlaylist.self, from: saved)
precondition(playlist == reloaded)

let date = Date(timeIntervalSince1970: 100)
let completed = ListeningSyncRevision(id: "aaa", date: date, change: .playback(key: "episode", position: 0, played: true))
let restarted = ListeningSyncRevision(id: "bbb", date: date.addingTimeInterval(1),
                                      change: .playback(key: "episode", position: 0, played: false))
precondition(restarted.change.key == completed.change.key)
precondition(restarted.isNewer(than: completed))
precondition(!completed.isNewer(than: restarted))

let edit = ListeningSyncRevision(id: "aaa", date: date, change: .playlist(id: playlist.id, value: playlist))
let deleted = ListeningSyncRevision(id: "bbb", date: date, change: .playlist(id: playlist.id, value: nil))
let payload = try JSONEncoder().encode(deleted)
let received = try JSONDecoder().decode(ListeningSyncRevision.self, from: payload)
precondition(received.change.key == edit.change.key)
precondition(received.isNewer(than: edit))
guard case .playlist(let id, nil) = received.change, id == playlist.id else {
    fatalError("Expected playlist deletion to survive sync encoding")
}
print("Smart playlist and listening sync checks passed")
