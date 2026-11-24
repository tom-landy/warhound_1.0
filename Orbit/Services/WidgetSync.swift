import CryptoKit
import Foundation
import SwiftData
import UIKit
import WidgetKit

/// Writes what the widgets show and asks iOS to redraw them.
/// Does nothing until the App Group is enabled (paid developer account).
@MainActor
enum WidgetSync {
    private static var task: Task<Void, Never>?

    static func schedule() {
        guard WidgetStore.container != nil else { return }
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await write()
        }
    }

    private static func write() async {
        let player = AudioPlayer.shared
        let theme = AccentTheme(rawValue: UserDefaults.standard.string(forKey: AccentTheme.storageKey) ?? "") ?? .orange
        var snapshot = WidgetSnapshot()
        snapshot.isPlaying = player.isPlaying
        snapshot.speed = player.speed
        snapshot.updatedAt = .now
        snapshot.accent = theme.hexValues.base
        snapshot.accentTop = theme.hexValues.top
        snapshot.accentBottom = theme.hexValues.bottom
        if let episode = player.episode {
            snapshot.nowPlaying = await summary(episode, position: player.currentTime, duration: player.duration)
        }
        for episode in player.queue().prefix(5) {
            snapshot.upNext.append(await summary(episode, position: episode.playbackPosition, duration: episode.duration))
        }
        WidgetStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func summary(_ e: Episode, position: Double, duration: Double) async -> WidgetEpisode {
        WidgetEpisode(key: e.key, title: e.title, show: e.podcast?.title ?? "",
                      artworkFile: await artwork(e.displayArtwork), position: position, duration: duration)
    }

    /// Small copies of artwork in the shared container; widgets can't load images from the network.
    private static func artwork(_ url: URL?) async -> String? {
        guard let url else { return nil }
        let name = Insecure.MD5.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
        guard let destination = WidgetStore.artworkURL(name) else { return nil }
        if FileManager.default.fileExists(atPath: destination.path) { return name }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: 240, height: 240)
        let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? small.jpegData(compressionQuality: 0.8)?.write(to: destination)
        return name
    }
}
