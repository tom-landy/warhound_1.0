import SwiftUI
import WatchKit

struct WatchRootView: View {
    @Environment(PhoneLink.self) private var link
    /// `-demoPage 1` opens on a list, for screenshots.
    @State private var page = UserDefaults.standard.integer(forKey: "demoPage")

    var body: some View {
        TabView(selection: $page) {
            // The system Now Playing controls: play/pause, skip, volume on the Digital Crown.
            NowPlayingView()
                .tag(0)
            EpisodeList(title: "Latest", episodes: link.state?.latest ?? [], empty: "Follow shows in Orbit on iPhone.") {
                page = 0
            }
            .tag(1)
            EpisodeList(title: "Downloaded", episodes: link.state?.downloaded ?? [], empty: "Download episodes on iPhone to play offline.") {
                page = 0
            }
            .tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct EpisodeList: View {
    let title: String
    let episodes: [WatchEpisode]
    let empty: String
    let didPlay: () -> Void
    @Environment(PhoneLink.self) private var link

    var body: some View {
        NavigationStack {
            List {
                if let error = link.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if link.state == nil {
                    Text("Open Orbit on iPhone to connect.")
                        .foregroundStyle(.secondary)
                } else if episodes.isEmpty {
                    Text(empty)
                        .foregroundStyle(.secondary)
                }
                ForEach(episodes) { episode in
                    Button {
                        link.play(episode)
                        didPlay()
                    } label: {
                        EpisodeRow(episode: episode, playing: link.state?.nowPlayingKey == episode.key && link.state?.isPlaying == true)
                    }
                }
            }
            .navigationTitle(title)
        }
    }
}

private struct EpisodeRow: View {
    let episode: WatchEpisode
    let playing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(episode.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 4) {
                if playing {
                    Image(systemName: "waveform")
                        .foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative)
                } else if episode.downloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                }
                Text(subtitle)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        guard episode.remaining > 0 else { return episode.show }
        let mins = Int((episode.remaining / 60).rounded())
        let time = mins < 60 ? "\(max(1, mins))m" : "\(mins / 60)h \(mins % 60)m"
        return "\(time) · \(episode.show)"
    }
}
