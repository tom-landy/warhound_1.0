import SwiftData
import SwiftUI

struct EpisodeRow: View {
    let episode: Episode
    var showsPodcast = false
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.theme) private var theme
    @State private var showsNotes = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsPodcast {
                ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 8)
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
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
                HStack {
                    PlayCapsule(episode: episode)
                    Spacer()
                    DownloadButton(episode: episode)
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { showsNotes = true }
        // VoiceOver: one element per episode; double-tap plays, the rest are actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { player.play(episode) }
        .accessibilityAction(named: player.isCurrent(episode) && player.isPlaying ? "Pause" : "Play") { player.play(episode) }
        .accessibilityAction(named: "Episode Notes") { showsNotes = true }
        .accessibilityAction(named: episode.isQueued ? "Remove from Up Next" : "Add to Up Next") {
            if episode.isQueued { player.removeFromQueue(episode) } else { player.addToQueue(episode) }
        }
        .accessibilityAction(named: "Play Next") { player.playNext(episode) }
        .accessibilityAction(named: episode.isDownloaded ? "Remove Download" : "Download") {
            if episode.isDownloaded { downloads.remove(episode) } else { downloads.download(episode) }
        }
        .accessibilityAction(named: episode.isPlayed ? "Mark as Unplayed" : "Mark as Played") {
            togglePlayed()
        }
        .sheet(isPresented: $showsNotes) { EpisodeNotesView(episode: episode) }
        .contextMenu {
            if !player.isCurrent(episode) {
                Button { player.playNext(episode) } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                if episode.isQueued {
                    Button { player.removeFromQueue(episode) } label: {
                        Label("Remove from Up Next", systemImage: "minus.circle")
                    }
                } else {
                    Button { player.addToQueue(episode) } label: {
                        Label("Add to Up Next", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                }
            }
            ShareLink(item: episode.shareURL, subject: Text(episode.title),
                      message: Text("\(episode.podcast?.title ?? "") – \(episode.title)")) {
                Label("Share Episode", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button {
                togglePlayed()
            } label: {
                Label(episode.isPlayed ? "Mark as Unplayed" : "Mark as Played",
                      systemImage: episode.isPlayed ? "circle" : "checkmark.circle")
            }
            if episode.isDownloaded {
                Button(role: .destructive) { downloads.remove(episode) } label: {
                    Label("Remove Download", systemImage: "trash")
                }
            } else if downloads.state(episode) == .none || downloads.state(episode) == .failed {
                Button { downloads.download(episode) } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if !player.isCurrent(episode) && !episode.isQueued {
                Button { player.addToQueue(episode) } label: {
                    Label("Up Next", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
                .tint(.indigo)
            }
            Button {
                togglePlayed()
            } label: {
                Label(episode.isPlayed ? "Unplayed" : "Played",
                      systemImage: episode.isPlayed ? "circle" : "checkmark.circle")
            }
            .tint(theme.color)
        }
        .swipeActions(edge: .trailing) {
            if episode.isDownloaded {
                // Not .destructive: that role holds the row at the edge waiting for it to be
                // deleted, and here the episode stays in the list.
                Button { withAnimation(.snappy) { downloads.remove(episode) } } label: {
                    Label("Remove", systemImage: "trash")
                }
                .tint(.red)
            } else if downloads.state(episode) == .none || downloads.state(episode) == .failed {
                Button { downloads.download(episode) } label: {
                    Label("Download", systemImage: "arrow.down")
                }
                .tint(theme.color)
            }
        }
    }

    private var accessibilityText: String {
        var parts = [episode.title]
        if showsPodcast, let show = episode.podcast?.title { parts.append(show) }
        parts.append(episode.pubDate.episodeDate)
        if player.isCurrent(episode) { parts.append(player.isPlaying ? "Playing" : "Paused") }
        if episode.isPlayed {
            parts.append("Played")
        } else if episode.isInProgress {
            parts.append("\(episode.remaining.spoken) left")
        } else if episode.duration > 0 {
            parts.append(episode.duration.spoken)
        }
        if episode.isDownloaded { parts.append("Downloaded") }
        if episode.isQueued { parts.append("In Up Next") }
        return parts.joined(separator: ", ")
    }

    private func togglePlayed() {
        episode.isPlayed.toggle()
        if episode.isPlayed {
            episode.playbackPosition = 0
            downloads.episodePlayed(episode)
        }
        try? episode.modelContext?.save()
        ListeningSync.shared.recordPlayback([episode])
    }

    private var header: String {
        let date = (episode.isQueued ? "UP NEXT · " : "") + episode.pubDate.episodeDate.uppercased()
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
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(current ? AccentTheme.onColor : theme.color)
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
