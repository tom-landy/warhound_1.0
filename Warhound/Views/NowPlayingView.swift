import AVKit
import SwiftUI

struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var scrubTime: TimeInterval = 0
    @State private var showsNotes = false

    var body: some View {
        if let episode = player.episode {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 18)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                    .scaleEffect(player.isPlaying ? 1 : 0.86)
                    .animation(.spring(duration: 0.45, bounce: 0.25), value: player.isPlaying)
                    .padding(.horizontal, 32)

                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.pubDate.episodeDate.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(episode.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    Text(episode.podcast?.title ?? "")
                        .font(.body)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                scrubber
                    .padding(.top, 20)

                transport
                    .padding(.top, 12)

                accessories
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background { backdrop(episode) }
            .presentationDragIndicator(.visible)
            .sheet(isPresented: $showsNotes) {
                EpisodeNotesView(episode: episode)
            }
        }
    }

    // MARK: - Pieces

    private var displayedTime: TimeInterval {
        player.isScrubbing ? scrubTime : player.currentTime
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { displayedTime }, set: { scrubTime = $0 }),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                if editing {
                    scrubTime = player.currentTime
                    player.isScrubbing = true
                } else {
                    player.seek(to: scrubTime)
                    player.isScrubbing = false
                }
            })
            HStack {
                Text(displayedTime.clock)
                Spacer()
                Text("-" + max(0, player.duration - displayedTime).clock)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack {
            Spacer()
            Button { player.skip(by: -AudioPlayer.skipBack) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 32, weight: .medium))
            }
            .accessibilityLabel("Back 15 seconds")
            Spacer()
            Button { player.togglePlayPause() } label: {
                ZStack {
                    Circle().fill(.tint).frame(width: 78, height: 78)
                    if player.isBuffering {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.black)
                            .offset(x: player.isPlaying ? 0 : 3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { player.skip(by: AudioPlayer.skipForward) } label: {
                Image(systemName: "goforward.30").font(.system(size: 32, weight: .medium))
            }
            .accessibilityLabel("Forward 30 seconds")
            Spacer()
        }
        .buttonStyle(.plain)
    }

    private var accessories: some View {
        @Bindable var player = player
        return HStack {
            Menu {
                Picker("Speed", selection: $player.speed) {
                    ForEach(AudioPlayer.speeds, id: \.self) { s in
                        Text(Self.speedLabel(s)).tag(s)
                    }
                }
            } label: {
                Text(Self.speedLabel(player.speed))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            Spacer()
            RoutePicker()
                .frame(width: 44, height: 44)
            Spacer()
            Button { showsNotes = true } label: {
                Image(systemName: "text.alignleft")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Episode notes")
        }
        .foregroundStyle(.secondary)
    }

    private func backdrop(_ episode: Episode) -> some View {
        ZStack {
            Color.black
            ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 0)
                .scaledToFill()
                .blur(radius: 80)
                .opacity(0.55)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    static func speedLabel(_ s: Float) -> String {
        let text = s == s.rounded() ? String(format: "%.0f", s) : String(format: "%g", s)
        return text + "×"
    }
}

private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .secondaryLabel
        view.activeTintColor = UIColor(named: "AccentColor")
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct EpisodeNotesView: View {
    let episode: Episode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(episode.title).font(.title2.bold())
                    Text([episode.pubDate.episodeDate, episode.duration.spoken].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(episode.summary.isEmpty ? "No notes for this episode." : episode.summary)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
