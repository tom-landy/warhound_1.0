import SwiftUI

struct EpisodeRow: View {
    let episode: Episode
    var showsPodcast = false
    @Environment(AudioPlayer.self) private var player
    @Environment(\.theme) private var theme
    @State private var showsNotes = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsPodcast {
                ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 8)
                    .frame(width: 60, height: 60)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(episode.title)
                    .font(.headline)
                    .foregroundStyle(episode.isPlayed ? .secondary : .primary)
                    .lineLimit(2)
                if !episode.summary.isEmpty {
                    Text(episode.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                PlayCapsule(episode: episode)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { showsNotes = true }
        .sheet(isPresented: $showsNotes) { EpisodeNotesView(episode: episode) }
        .swipeActions(edge: .leading) {
            Button {
                episode.isPlayed.toggle()
                if episode.isPlayed { episode.playbackPosition = 0 }
            } label: {
                Label(episode.isPlayed ? "Unplayed" : "Played",
                      systemImage: episode.isPlayed ? "circle" : "checkmark.circle")
            }
            .tint(theme.color)
        }
    }

    private var header: String {
        let date = episode.pubDate.episodeDate.uppercased()
        guard showsPodcast, let title = episode.podcast?.title else { return date }
        return "\(date) · \(title.uppercased())"
    }
}

/// The pill under each episode: play/pause plus time left.
struct PlayCapsule: View {
    let episode: Episode
    @Environment(AudioPlayer.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let current = player.isCurrent(episode)
        let playing = current && player.isPlaying
        Button {
            player.play(episode)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .contentTransition(.symbolEffect(.replace))
                if progress > 0 {
                    ProgressView(value: progress)
                        .frame(width: 36)
                        .tint(.primary)
                }
                Text(label)
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(current ? Color.black : theme.color)
            .background(current ? theme.color : theme.color.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "Pause \(episode.title)" : "Play \(episode.title)")
    }

    private var progress: Double {
        player.isCurrent(episode) && player.duration > 0 ? player.currentTime / player.duration : episode.isInProgress ? episode.progress : 0
    }

    private var label: String {
        if episode.isPlayed && !player.isCurrent(episode) { return "Played" }
        let duration = player.isCurrent(episode) && player.duration > 0 ? player.duration : episode.duration
        let position = player.isCurrent(episode) ? player.currentTime : episode.playbackPosition
        if position > 5, duration > 0 { return (duration - position).spoken + " left" }
        return duration > 0 ? duration.spoken : "Play"
    }
}
