import AppIntents
import SwiftUI
import WidgetKit

// Widget layouts. Shared with the app so they can be previewed there.

struct WidgetArtwork: View {
    let file: String?
    var corner: CGFloat = 10
    var accent: Color

    var body: some View {
        Group {
            if let file, let url = WidgetStore.artworkURL(file), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "waveform").font(.title3.weight(.semibold)).foregroundStyle(accent.opacity(0.7))
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Progress that keeps moving while playing, without the app updating the widget.
struct WidgetProgress: View {
    let episode: WidgetEpisode
    let snapshot: WidgetSnapshot
    let accent: Color

    var body: some View {
        Group {
            if snapshot.isPlaying, episode.duration > 0 {
                let rate = Double(max(snapshot.speed, 0.1))
                let start = snapshot.updatedAt.addingTimeInterval(-episode.position / rate)
                let end = snapshot.updatedAt.addingTimeInterval(episode.remaining / rate)
                ProgressView(timerInterval: start...max(end, start.addingTimeInterval(1)),
                             countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
            } else {
                ProgressView(value: episode.progress)
            }
        }
        .progressViewStyle(.linear)
        .tint(accent)
    }
}

struct NowPlayingWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    private var accent: Color { Color(widgetHex: snapshot.accent) }

    var body: some View {
        if let episode = snapshot.nowPlaying {
            switch family {
            case .accessoryCircular: circular(episode)
            case .accessoryRectangular: rectangular(episode)
            case .accessoryInline: Label(episode.title, systemImage: snapshot.isPlaying ? "waveform" : "pause.fill")
            case .systemMedium: medium(episode)
            default: small(episode)
            }
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform").font(.title2).foregroundStyle(accent)
            if family != .accessoryCircular && family != .accessoryInline {
                Text("Nothing Playing").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playButton(size: CGFloat) -> some View {
        Button(intent: TogglePlaybackIntent()) {
            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                .background(accent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(snapshot.isPlaying ? "Pause" : "Play")
    }

    private func small(_ episode: WidgetEpisode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                WidgetArtwork(file: episode.artworkFile, corner: 10, accent: accent)
                    .frame(width: 52, height: 52)
                Spacer()
                playButton(size: 40)
            }
            Spacer(minLength: 0)
            Text(episode.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(episode.show)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            WidgetProgress(episode: episode, snapshot: snapshot, accent: accent)
        }
    }

    private func medium(_ episode: WidgetEpisode) -> some View {
        HStack(spacing: 14) {
            WidgetArtwork(file: episode.artworkFile, corner: 14, accent: accent)
                .frame(width: 118, height: 118)
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.show.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 2)
                WidgetProgress(episode: episode, snapshot: snapshot, accent: accent)
                HStack {
                    Button(intent: SkipBackIntent()) {
                        Image(systemName: "gobackward.15").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back 15 Seconds")
                    Spacer()
                    playButton(size: 42)
                    Spacer()
                    Button(intent: SkipForwardIntent()) {
                        Image(systemName: "goforward.30").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Forward 30 Seconds")
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private func rectangular(_ episode: WidgetEpisode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(episode.show).font(.caption2.weight(.semibold)).lineLimit(1)
            Text(episode.title).font(.caption).lineLimit(1)
            ProgressView(value: episode.progress).progressViewStyle(.linear)
        }
        .widgetAccentable()
    }

    private func circular(_ episode: WidgetEpisode) -> some View {
        Button(intent: TogglePlaybackIntent()) {
            Gauge(value: episode.progress) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
        .buttonStyle(.plain)
    }
}

struct UpNextWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    private var accent: Color { Color(widgetHex: snapshot.accent) }

    var body: some View {
        let rows = family == .systemLarge ? 5 : 3
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
            HStack {
                Text("Up Next").font(.headline)
                Spacer()
                Image(systemName: "list.bullet").foregroundStyle(accent)
            }
            if family == .systemLarge, let current = snapshot.nowPlaying {
                row(current, playing: true)
                Divider()
            }
            if snapshot.upNext.isEmpty {
                Spacer()
                Text("Up Next Is Empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(snapshot.upNext.prefix(rows), id: \.key) { row($0, playing: false) }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func row(_ episode: WidgetEpisode, playing: Bool) -> some View {
        if playing {
            Button(intent: TogglePlaybackIntent()) { rowContent(episode, playing: true) }
                .buttonStyle(.plain)
        } else {
            Button(intent: PlayEpisodeIntent(key: episode.key)) { rowContent(episode, playing: false) }
                .buttonStyle(.plain)
        }
    }

    private func rowContent(_ episode: WidgetEpisode, playing: Bool) -> some View {
            HStack(spacing: 10) {
                WidgetArtwork(file: episode.artworkFile, corner: 6, accent: accent)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(episode.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(episode.show).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if playing {
                    Image(systemName: snapshot.isPlaying ? "waveform" : "pause.fill")
                        .font(.caption)
                        .foregroundStyle(accent)
                } else {
                    Text(Self.minutes(episode.remaining))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
    }

    private static func minutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(max(1, m))m"
    }
}
