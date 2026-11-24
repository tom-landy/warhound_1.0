import SwiftData
import SwiftUI

/// Full-width iPad. Landscape: downloaded shows and the player on the left, episode notes in the
/// middle, chapters on the right. Portrait: shows, player and chapters down the left; notes fill the rest.
struct IPadRootView: View {
    @Binding var sheet: IPadSheet?
    @Binding var openShow: Podcast?
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            HStack(spacing: 12) {
                VStack(spacing: 12) {
                    DownloadedShowsPanel(sheet: $sheet, openShow: $openShow)
                    if portrait {
                        // Portrait: artwork, then chapters, then the controls at the bottom.
                        NowPlayingCard(part: .artwork, sheet: $sheet)
                        ChaptersPanel().frame(height: min(300, geo.size.height * 0.25))
                        if player.episode != nil { NowPlayingCard(part: .controls, sheet: $sheet) }
                    } else {
                        NowPlayingCard(part: .full, sheet: $sheet)
                    }
                }
                .frame(width: 300)

                MiddlePanel(openShow: $openShow)
                if !portrait {
                    ChaptersPanel().frame(width: 320)
                }
            }
            .padding(12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

enum IPadSheet: String, Identifiable {
    case latest, allEpisodes, library, search, upNext, settings, downloads, stats
    var id: String { rawValue }
}

/// Rounded panel used throughout the iPad layout.
private struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PanelLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

// MARK: - Left: downloaded shows

private struct DownloadedShowsPanel: View {
    @Binding var sheet: IPadSheet?
    @Binding var openShow: Podcast?
    @Query(filter: #Predicate<Episode> { $0.localFileName != nil }) private var downloaded: [Episode]

    private var shows: [(podcast: Podcast, count: Int)] {
        let grouped = Dictionary(grouping: downloaded.compactMap(\.podcast), by: \.feedURL)
        return grouped.values.compactMap { list in list.first.map { ($0, list.count) } }
            .sorted { $0.podcast.title.localizedCaseInsensitiveCompare($1.podcast.title) == .orderedAscending }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloaded").font(.title3.bold())
                    Spacer()
                    Menu {
                        Button { sheet = .latest } label: { Label("Latest", systemImage: "clock") }
                        Button { sheet = .allEpisodes } label: { Label("All Episodes", systemImage: "list.bullet") }
                        Button { sheet = .library } label: { Label("Library", systemImage: "square.grid.2x2") }
                        Button { sheet = .search } label: { Label("Search", systemImage: "magnifyingglass") }
                        Button { sheet = .downloads } label: { Label("Downloads", systemImage: "arrow.down.circle") }
                        Button { sheet = .stats } label: { Label("Stats", systemImage: "chart.bar") }
                        Divider()
                        Button { sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More")
                }
                .padding(.leading, 4)

                if shows.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No Downloads").font(.headline)
                        Text("Shows appear here once episodes download.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Open Library") { sheet = .library }
                    }
                    .padding(4)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(shows, id: \.podcast.feedURL) { item in
                                ShowRow(podcast: item.podcast, count: item.count,
                                        selected: openShow?.feedURL == item.podcast.feedURL) {
                                    openShow = item.podcast
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

private struct ShowRow: View {
    let podcast: Podcast
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ArtworkView(url: podcast.artworkURL, seed: podcast.title, cornerRadius: 9)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(podcast.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(count == 1 ? "1 episode" : "\(count) episodes").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(podcast.title), \(count == 1 ? "1 episode" : "\(count) episodes") downloaded")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Left: player card

private struct NowPlayingCard: View {
    enum Part { case full, artwork, controls }

    let part: Part
    @Binding var sheet: IPadSheet?
    private var large: Bool { part != .full }
    @Environment(AudioPlayer.self) private var player
    @ScaledMetric(relativeTo: .title) private var playSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if part != .controls { PanelLabel(text: "Now Playing") }
            if let episode = player.episode {
                if part == .artwork {
                    ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 14)
                        .frame(maxWidth: 190)
                        .frame(maxWidth: .infinity)
                    titles(episode)
                } else if part == .controls {
                    EmptyView()
                } else {
                    HStack(spacing: 12) {
                        ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 12)
                            .frame(width: 72, height: 72)
                        titles(episode)
                    }
                }
                if part != .artwork {
                ScrubberView()
                HStack {
                    if !large { SpeedMenuButton().foregroundStyle(.secondary) }
                    Spacer()
                    Button { player.skip(by: -AudioPlayer.skipBack) } label: {
                        Image(systemName: "gobackward.15").font(.title2).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back 15 Seconds")
                    Spacer()
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: min(playSize, 80) * 0.4, weight: .bold))
                            .foregroundStyle(AccentTheme.onColor)
                            .frame(width: min(playSize, 80), height: min(playSize, 80))
                            .background(.tint, in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Spacer()
                    Button { player.skip(by: AudioPlayer.skipForward) } label: {
                        Image(systemName: "goforward.30").font(.title2).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Forward 30 Seconds")
                    Spacer()
                    if !large { SleepMenuButton().foregroundStyle(.secondary) }
                }
                .buttonStyle(.plain)
                if large {
                    HStack {
                        SpeedMenuButton()
                        Spacer()
                        SleepMenuButton()
                        Spacer()
                        upNextButton
                    }
                    .foregroundStyle(.secondary) // grey like the iPhone player; the sleep icon turns accent when set
                }
                }
            } else if part != .controls {
                Text("Nothing Playing").font(.headline)
                Text("Choose an episode from a show on the left.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func titles(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text((episode.podcast?.title ?? "").uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .lineLimit(1)
            Text(episode.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
        }
    }

    private var upNextButton: some View {
        Button { sheet = .upNext } label: {
            Image(systemName: "list.bullet").font(.title3).frame(width: 44, height: 44)
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("Up Next")
    }
}

// MARK: - Middle: notes, or a show's episodes

private struct MiddlePanel: View {
    @Binding var openShow: Podcast?
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        Panel {
            if let podcast = openShow {
                NavigationStack {
                    PodcastDetailView(podcast: podcast)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    openShow = nil
                                } label: {
                                    Label("Episode Notes", systemImage: "chevron.backward")
                                }
                            }
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .id(podcast.feedURL)
            } else if let episode = player.episode {
                EpisodeNotesPanel(episode: episode)
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "waveform",
                                       description: Text("Choose a show on the left to see its episodes."))
            }
        }
    }
}

private struct EpisodeNotesPanel: View {
    let episode: Episode
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PanelLabel(text: "Episode Notes")
                Text(episode.title).font(.title.bold())
                Text([episode.podcast?.title ?? "", episode.pubDate.episodeDate, episode.duration.spoken]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if !player.isCurrent(episode) {
                        Button { player.addToQueue(episode) } label: {
                            Label("Add to Up Next", systemImage: "text.line.last.and.arrowtriangle.forward")
                        }
                    }
                    ShareLink(item: episode.shareURL, subject: Text(episode.title),
                              message: Text("\(episode.podcast?.title ?? "") – \(episode.title)")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.bordered)
                Divider()
                Text(episode.summary.isEmpty ? AttributedString("No episode notes.") : episode.summary.linkified)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Right: chapters

private struct ChaptersPanel: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                PanelLabel(text: "Chapters").padding(.horizontal, 8)
                if player.chapters.isEmpty {
                    Text(player.episode == nil ? "Nothing playing." : "This episode has no chapters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(player.chapters.enumerated()), id: \.offset) { index, chapter in
                                    let current = index == player.currentChapterIndex
                                    Button { player.seek(to: chapter) } label: {
                                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                                            Text(chapter.start.clock)
                                                .font(.footnote.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .frame(minWidth: 48, alignment: .leading)
                                            Text(chapter.title.isEmpty ? "Chapter \(index + 1)" : chapter.title)
                                                .font(.subheadline.weight(current ? .semibold : .regular))
                                                .foregroundStyle(current ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                                .multilineTextAlignment(.leading)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.vertical, 9)
                                        .padding(.horizontal, 8)
                                        .background(current ? Color.primary.opacity(0.08) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .id(index)
                                    .accessibilityAddTraits(current ? .isSelected : [])
                                }
                            }
                        }
                        .onChange(of: player.currentChapterIndex) { _, index in
                            if let index { withAnimation { proxy.scrollTo(index, anchor: .center) } }
                        }
                    }
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 10)
        }
    }
}

extension String {
    /// Plain text with any web addresses made tappable.
    var linkified: AttributedString {
        var result = AttributedString(self)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        let ns = self as NSString
        for match in detector.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            guard let url = match.url, let range = Range(match.range, in: self),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
        }
        return result
    }
}
