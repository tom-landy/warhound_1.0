import AVKit
import SwiftUI

struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var playSize: CGFloat = 78
    @ScaledMetric(relativeTo: .title) private var skipSize: CGFloat = 32
    @State private var showsNotes = false
    @State private var showsUpNext = DemoData.isActive && UserDefaults.standard.bool(forKey: "demoUpNext")
    @State private var showsChapters = DemoData.isActive && UserDefaults.standard.bool(forKey: "demoChapters")

    var body: some View {
        if let episode = player.episode {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 18)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.2), radius: 30, y: 14)
                    .scaleEffect(player.isPlaying || reduceMotion ? 1 : 0.86)
                    .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.25), value: player.isPlaying)
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
                    if let chapter = player.currentChapter {
                        Button { showsChapters = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet.rectangle")
                                Text(chapter.title.isEmpty ? "Chapter \((player.currentChapterIndex ?? 0) + 1)" : chapter.title)
                                    .lineLimit(1)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .accessibilityHint("Shows chapters")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ScrubberView()
                    .padding(.top, 20)

                transport
                    .padding(.top, 12)

                accessories
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: 560) // iPad and wide screens
            .frame(maxWidth: .infinity)
            .background { backdrop(episode) }
            .presentationDragIndicator(.visible)
            .sheet(isPresented: $showsNotes) {
                EpisodeNotesView(episode: episode)
            }
            .sheet(isPresented: $showsUpNext) { UpNextView() }
            .sheet(isPresented: $showsChapters) { ChaptersView() }
        }
    }

    // MARK: - Pieces

    private var transport: some View {
        HStack {
            Spacer()
            Button { player.skip(by: -AudioPlayer.skipBack) } label: {
                Image(systemName: "gobackward.15").font(.system(size: min(skipSize, 48), weight: .medium))
            }
            .accessibilityLabel("Back 15 seconds")
            Spacer()
            Button { player.togglePlayPause() } label: {
                ZStack {
                    Circle().fill(.tint).frame(width: min(playSize, 110), height: min(playSize, 110))
                    if player.isBuffering {
                        ProgressView().tint(AccentTheme.onColor)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: min(playSize, 110) * 0.41, weight: .bold))
                            .foregroundStyle(AccentTheme.onColor)
                            .offset(x: player.isPlaying ? 0 : 3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { player.skip(by: AudioPlayer.skipForward) } label: {
                Image(systemName: "goforward.30").font(.system(size: min(skipSize, 48), weight: .medium))
            }
            .accessibilityLabel("Forward 30 seconds")
            Spacer()
        }
        .buttonStyle(.plain)
    }

    private var accessories: some View {
        HStack {
            SpeedMenuButton()
            Spacer()
            SleepMenuButton()
            Spacer()
            RoutePicker()
                .frame(width: 44, height: 44)
            Spacer()
            Button { showsUpNext = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Up Next")
            Spacer()
            Button { showsNotes = true } label: {
                Image(systemName: "text.alignleft")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Episode Notes")
        }
        .foregroundStyle(.secondary)
    }

    private func backdrop(_ episode: Episode) -> some View {
        ZStack {
            Color(.systemBackground)
            ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 0)
                .scaledToFill()
                .blur(radius: 80)
                .opacity(colorScheme == .dark ? 0.55 : 0.35)
            LinearGradient(colors: [.clear, Color(.systemBackground).opacity(colorScheme == .dark ? 0.75 : 0.6)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    static func speedLabel(_ s: Float) -> String {
        let text = s == s.rounded() ? String(format: "%.0f", s) : String(format: "%g", s)
        return text + "×"
    }
}

private struct RoutePicker: UIViewRepresentable {
    @Environment(\.theme) private var theme

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .secondaryLabel
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = UIColor(theme.color)
    }
}

struct EpisodeNotesView: View {
    let episode: Episode
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss

    private var playing: Bool { player.isCurrent(episode) && player.isPlaying }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(episode.title).font(.title2.bold())
                    Text([episode.pubDate.episodeDate, episode.duration.spoken].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(episode.notesDisplay)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    ShareLink(item: episode.shareURL, subject: Text(episode.title),
                              message: Text("\(episode.podcast?.title ?? "") – \(episode.title)"))
                    Button {
                        player.play(episode)
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(playing ? "Pause" : "Play")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            // Timestamps in the notes jump to that point.
            guard let seconds = Episode.seekSeconds(from: url) else { return .systemAction }
            player.play(episode, from: seconds)
            return .handled
        })
        .presentationDetents([.medium, .large])
    }
}
