import SwiftUI

// Player controls shared by the iPhone player and the iPad layout.

struct ScrubberView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var scrubTime: TimeInterval = 0

    private var displayedTime: TimeInterval {
        player.isScrubbing ? scrubTime : player.currentTime
    }

    var body: some View {
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
            .accessibilityLabel("Position")
            .accessibilityValue("\(displayedTime.spoken.isEmpty ? "0 min" : displayedTime.spoken) of \(player.duration.spoken)")
            HStack {
                Text(displayedTime.clock)
                Spacer()
                Text("-" + max(0, player.duration - displayedTime).clock)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

}

struct SpeedMenuButton: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        @Bindable var player = player
        let podcast = player.episode?.podcast
        return Menu {
            Picker("Speed", selection: $player.speed) {
                ForEach(AudioPlayer.speeds, id: \.self) { s in
                    Text(NowPlayingView.speedLabel(s)).tag(s)
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
                Text(NowPlayingView.speedLabel(player.speed))
                if podcast?.playbackSpeed != nil {
                    Circle().fill(.tint).frame(width: 5, height: 5)
                }
            }
            .font(.subheadline.weight(.bold).monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.1), in: Capsule())
        }
        .accessibilityLabel("Speed \(NowPlayingView.speedLabel(player.speed))")
    }

}

struct SleepMenuButton: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
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
        .accessibilityValue(sleepDescription)
    }

    private var sleepDescription: String {
        switch player.sleepTimer {
        case .off: "Off"
        case .endOfEpisode: "End of episode"
        case .at(let date): "\(max(0, date.timeIntervalSinceNow).spoken) left"
        }
    }

}
