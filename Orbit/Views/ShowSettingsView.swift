import SwiftUI

struct ShowSettingsView: View {
    @Bindable var podcast: Podcast
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss

    private static let introOptions = [0, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Playback Speed", selection: speedBinding) {
                        Text("Default (\(NowPlayingView.speedLabel(player.defaultSpeed)))").tag(Float?.none)
                        ForEach(AudioPlayer.speeds, id: \.self) { speed in
                            Text(NowPlayingView.speedLabel(speed)).tag(Float?.some(speed))
                        }
                    }
                    Picker("Skip Intro", selection: $podcast.skipIntro) {
                        ForEach(Self.introOptions, id: \.self) { seconds in
                            Text(Self.introLabel(seconds)).tag(seconds)
                        }
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Skip Intro starts new episodes this many seconds in.")
                }
                Section("Downloads") {
                    Toggle("Keep Latest Downloaded", isOn: $podcast.autoDownload)
                }
            }
            .navigationTitle(podcast.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var speedBinding: Binding<Float?> {
        Binding {
            podcast.playbackSpeed
        } set: { new in
            podcast.playbackSpeed = new
            // Apply straight away if this show is playing.
            if player.episode?.podcast?.feedURL == podcast.feedURL {
                player.speed = new ?? player.defaultSpeed
            }
        }
    }

    private static func introLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Off"
        case ..<60: "\(seconds) Seconds"
        case 60: "1 Minute"
        case 90: "1 Minute 30 Seconds"
        default: "\(seconds / 60) Minutes"
        }
    }
}
