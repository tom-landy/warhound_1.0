import CarPlay
import SwiftData
import UIKit

/// CarPlay screen: Latest, Downloaded and Library tabs, plus the system Now Playing screen.
/// Needs Apple's CarPlay audio entitlement to appear in a real car. Until then it runs in
/// Xcode's CarPlay Simulator (simulator builds use Config/CarPlay-Simulator.entitlements).
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private let latest = CPListTemplate(title: "Latest", sections: [])
    private let downloaded = CPListTemplate(title: "Downloaded", sections: [])
    private let library = CPListTemplate(title: "Library", sections: [])
    private var observers: [NSObjectProtocol] = []
    private var reloadTask: Task<Void, Never>?
    private static let artwork = NSCache<NSURL, UIImage>()

    private var player: AudioPlayer { .shared }
    private var context: ModelContext? { AppEnvironment.container?.mainContext }
    private var itemLimit: Int { min(40, CPListTemplate.maximumItemCount) }

    // CarPlay calls these on the main thread, but the protocol isn't marked @MainActor.
    nonisolated func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated { connect(interfaceController) }
    }

    nonisolated func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated { disconnect() }
    }

    private func connect(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        latest.tabTitle = "Latest"
        latest.tabImage = UIImage(systemName: "clock")
        latest.emptyViewTitleVariants = ["Nothing New"]
        latest.emptyViewSubtitleVariants = ["Follow shows on your iPhone"]
        downloaded.tabTitle = "Downloaded"
        downloaded.tabImage = UIImage(systemName: "arrow.down.circle")
        downloaded.emptyViewTitleVariants = ["No Downloads"]
        downloaded.emptyViewSubtitleVariants = ["Download episodes on your iPhone to play them without signal"]
        library.tabTitle = "Library"
        library.tabImage = UIImage(systemName: "square.grid.2x2")
        library.emptyViewTitleVariants = ["No Shows Yet"]

        // With no signal, open on what can actually play.
        let tabs = CPTabBarTemplate(templates: [latest, downloaded, library])
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
        if !hasSignal(), !downloadedEpisodes().isEmpty { tabs.select(downloaded) }

        configureNowPlaying()
        reload()
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .orbitPlaybackChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        })
    }

    private func disconnect() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        self.interfaceController = nil
    }

    // MARK: - Content

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    private func reload() {
        guard let context else { return }
        var recent = FetchDescriptor<Episode>(sortBy: [SortDescriptor(\.pubDate, order: .reverse)])
        recent.fetchLimit = 400
        let episodes = ((try? context.fetch(recent)) ?? []).filter { $0.podcast?.isSubscribed == true }

        let inProgress = episodes.filter(\.isInProgress)
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        let fresh = episodes.filter { !$0.isPlayed && !$0.isInProgress }
        var sections: [CPListSection] = []
        if !inProgress.isEmpty {
            sections.append(CPListSection(items: items(Array(inProgress.prefix(5))), header: "Continue", sectionIndexTitle: nil))
        }
        sections.append(CPListSection(items: items(Array(fresh.prefix(itemLimit - min(5, inProgress.count)))),
                                      header: inProgress.isEmpty ? nil : "New", sectionIndexTitle: nil))
        latest.updateSections(sections)

        downloaded.updateSections([CPListSection(items: items(downloadedEpisodes()))])

        let shows = ((try? context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed },
                                                                   sortBy: [SortDescriptor(\.title)])))) ?? []
        library.updateSections([CPListSection(items: shows.prefix(itemLimit).map(showItem))])
    }

    private func downloadedEpisodes() -> [Episode] {
        guard let context else { return [] }
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.localFileName != nil },
                                                  sortBy: [SortDescriptor(\.pubDate, order: .reverse)])
        descriptor.fetchLimit = itemLimit
        return (try? context.fetch(descriptor)) ?? []
    }

    private func items(_ episodes: [Episode]) -> [CPListItem] {
        episodes.map { episode in
            let item = CPListItem(text: episode.title, detailText: detail(episode),
                                  image: UIImage(systemName: "waveform"))
            // A cloud marks episodes that need signal.
            item.accessoryType = episode.isDownloaded ? .none : .cloud
            item.isPlaying = player.isCurrent(episode) && player.isPlaying
            item.playingIndicatorLocation = .trailing
            if episode.isInProgress { item.playbackProgress = episode.progress }
            let key = episode.key
            item.handler = { [weak self] _, completion in
                MainActor.assumeIsolated { self?.play(key) }
                completion()
            }
            loadArtwork(episode.displayArtwork) { item.setImage($0) }
            return item
        }
    }

    private func showItem(_ podcast: Podcast) -> CPListItem {
        let unplayed = podcast.episodes.lazy.filter { !$0.isPlayed }.count
        let item = CPListItem(text: podcast.title, detailText: unplayed > 0 ? "\(unplayed) unplayed" : podcast.author,
                              image: UIImage(systemName: "waveform"))
        item.accessoryType = .disclosureIndicator
        let feed = podcast.feedURL
        item.handler = { [weak self] _, completion in
            MainActor.assumeIsolated { self?.openShow(feed) }
            completion()
        }
        loadArtwork(podcast.artworkURL) { item.setImage($0) }
        return item
    }

    private func openShow(_ feed: URL) {
        guard let podcast = try? context?.fetch(FetchDescriptor<Podcast>()).first(where: { $0.feedURL == feed }) else { return }
        let template = CPListTemplate(title: podcast.title,
                                      sections: [CPListSection(items: items(Array(podcast.sortedEpisodes.prefix(itemLimit))))])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func detail(_ e: Episode) -> String {
        var parts = [e.podcast?.title ?? "", e.pubDate.episodeDate]
        if e.isInProgress { parts.append(e.remaining.spoken + " left") } else if e.duration > 0 { parts.append(e.duration.spoken) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Playback

    private func play(_ key: String) {
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let episode = try? context?.fetch(descriptor).first else { return }
        if player.isCurrent(episode) { player.resume() } else { player.play(episode) }
        showNowPlaying()
    }

    private func showNowPlaying() {
        guard let interfaceController, !(interfaceController.topTemplate is CPNowPlayingTemplate) else { return }
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    private func configureNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = false
        nowPlaying.isAlbumArtistButtonEnabled = false
        let rate = CPNowPlayingPlaybackRateButton { _ in
            MainActor.assumeIsolated {
                let speeds = AudioPlayer.speeds
                let player = AudioPlayer.shared
                let index = speeds.firstIndex(of: player.speed) ?? 1
                player.speed = speeds[(index + 1) % speeds.count]
            }
        }
        nowPlaying.updateNowPlayingButtons([rate])
    }

    // MARK: - Helpers

    private func hasSignal() -> Bool {
        // Cheap heuristic: if no feed has refreshed in the last few minutes, assume we're offline.
        guard let context else { return true }
        let shows = (try? context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed }))) ?? []
        return shows.contains { ($0.lastRefreshed ?? .distantPast) > .now.addingTimeInterval(-6 * 3600) }
    }

    private func loadArtwork(_ url: URL?, apply: @escaping (UIImage) -> Void) {
        guard let url else { return }
        if let cached = Self.artwork.object(forKey: url as NSURL) { apply(cached); return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
            let size = CPListItem.maximumImageSize
            let scaled = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            Self.artwork.setObject(scaled, forKey: url as NSURL)
            apply(scaled)
        }
    }
}
