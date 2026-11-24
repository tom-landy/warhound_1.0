import Foundation
import SwiftUI

// Compiled into the iPhone app and the widget extension.

struct WidgetEpisode: Codable, Hashable {
    var key: String
    var title: String
    var show: String
    var artworkFile: String?
    var position: Double
    var duration: Double

    var remaining: Double { max(0, duration - position) }
    var progress: Double { duration > 0 ? min(1, position / duration) : 0 }
}

/// What the widgets show. The app writes it to the shared App Group container.
struct WidgetSnapshot: Codable {
    var nowPlaying: WidgetEpisode?
    var isPlaying = false
    var speed: Float = 1
    var updatedAt = Date()
    var upNext: [WidgetEpisode] = []
    var accent: UInt32 = 0xF26A2A
    var accentTop: UInt32 = 0xFFB25C
    var accentBottom: UInt32 = 0xF2551D

    static let sample = WidgetSnapshot(
        nowPlaying: WidgetEpisode(key: "s1", title: "Batch painting 40 knights", show: "Painted Armies",
                                  artworkFile: nil, position: 1260, duration: 2400),
        isPlaying: true,
        upNext: [
            WidgetEpisode(key: "s2", title: "Compound interest, explained badly", show: "The Long Game", artworkFile: nil, position: 0, duration: 2400),
            WidgetEpisode(key: "s3", title: "Swifts over the city", show: "Field Notes", artworkFile: nil, position: 0, duration: 3000),
            WidgetEpisode(key: "s4", title: "Carburettors without tears", show: "Small Engines", artworkFile: nil, position: 0, duration: 1800),
            WidgetEpisode(key: "s5", title: "The last lighthouse keeper", show: "Night Shift", artworkFile: nil, position: 0, duration: 3300),
        ])
}

enum WidgetStore {
    static let nowPlayingKind = "NowPlaying"
    static let upNextKind = "UpNext"

    /// From Info.plist, so it follows the bundle ID.
    static var groupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "OrbitAppGroup") as? String
    }

    /// nil until the App Group entitlement is enabled (needs a paid developer account).
    static var container: URL? {
        groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    static var snapshotURL: URL? { container?.appendingPathComponent("widget.json") }

    static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func artworkURL(_ file: String) -> URL? {
        container?.appendingPathComponent("Artwork", isDirectory: true).appendingPathComponent(file)
    }
}

extension Color {
    init(widgetHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
