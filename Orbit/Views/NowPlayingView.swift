import AVKit
import SwiftUI

struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var scrubTime: TimeInterval = 0
    @State private var showsNotes = false
    @State private var showsUpNext = DemoData.isActive && UserDefaults.standard.bool(forKey: "demoUpNext")
    @State private var showsChapters = DemoData.isActive && UserDefaults.standard.bool(forKey: "demoChapters")

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
            .sheet(isPresented: $showsUpNext) { UpNextView() }
            .sheet(isPresented: $showsChapters) { ChaptersView() }
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
        HStack {
            speedMenu
            Spacer()
            sleepMenu
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

    private var speedMenu: some View {
        @Bindable var player = player
        let podcast = player.episode?.podcast
        return Menu {
            Picker("Speed", selection: $player.speed) {
                ForEach(AudioPlayer.speeds, id: \.self) { s in
                    Text(Self.speedLabel(s)).tag(s)
                }
            }
            if let podcast {
                Section {
                    if podcast.playbackSpeed != nil {
                        Button("Use Default Speed for This Show") {
                            podcast.playbackSpeed = nil
                            player.speed = player.defaultSpeed
                        }
                    } else {
                        Button("Keep This Speed for This Show") {
                            podcast.playbackSpeed = player.speed
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(Self.speedLabel(player.speed))
                if podcast?.playbackSpeed != nil {
                    Circle().fill(.tint).frame(width: 5, height: 5)
                }
            }
            .font(.subheadline.weight(.bold).monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.white.opacity(0.1), in: Capsule())
        }
        .accessibilityLabel("Speed \(Self.speedLabel(player.speed))")
    }

    private var sleepMenu: some View {
        Menu {
            Button("Off") { player.setSleepTimer(.off) }
            Button("15 Minutes") { player.setSleepTimer(minutes: 15) }
            Button("30 Minutes") { player.setSleepTimer(minutes: 30) }
            Button("60 Minutes") { player.setSleepTimer(minutes: 60) }
            Button("End of Episode") { player.setSleepTimer(.endOfEpisode) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: player.sleepTimer == .off ? "moon.zzz" : "moon.zzz.fill")
                    .font(.title3)
                switch player.sleepTimer {
                case .off:
                    EmptyView()
                case .endOfEpisode:
                    Text("End").font(.caption.weight(.semibold))
                case .at(let date):
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(max(0, date.timeIntervalSinceNow).clock)
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                }
            }
            .foregroundStyle(player.sleepTimer == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Sleep Timer")
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(episode.title).font(.title2.bold())
                    Text([episode.pubDate.episodeDate, episode.duration.spoken].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(episode.summary.isEmpty ? "No episode notes." : episode.summary)
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
