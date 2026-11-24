import SwiftUI

struct MiniPlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let episode = player.episode {
            HStack(spacing: 12) {
                ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 8)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(episode.podcast?.title ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .contentTransition(.symbolEffect(.replace))
                }
                Button {
                    player.skip(by: AudioPlayer.skipForward)
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 12, y: 4)
            }
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Capsule()
                        .fill(.tint)
                        .frame(width: geo.size.width * progress, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 14)
                .padding(.bottom, 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { player.showsFullPlayer = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(player.isPlaying ? "Playing" : "Paused"): \(episode.title), \(episode.podcast?.title ?? "")")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the player")
            .accessibilityAction { player.showsFullPlayer = true }
            .accessibilityAction(named: player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
            .accessibilityAction(named: "Forward 30 Seconds") { player.skip(by: AudioPlayer.skipForward) }
            .accessibilityAction(named: "Back 15 Seconds") { player.skip(by: -AudioPlayer.skipBack) }
        }
    }

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(1, player.currentTime / player.duration)
    }
}
