import AppIntents

// Audio intents run in the app's process, so the widget's buttons drive the real player.
// The widget extension compiles them too (WIDGET_EXTENSION), where they do nothing.

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses the current episode.")

    func perform() async throws -> some IntentResult {
        await IntentBridge.toggle()
        return .result()
    }
}

struct SkipForwardIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Skip Forward"

    func perform() async throws -> some IntentResult {
        await IntentBridge.skip(30)
        return .result()
    }
}

struct SkipBackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Skip Back"

    func perform() async throws -> some IntentResult {
        await IntentBridge.skip(-15)
        return .result()
    }
}

struct PlayEpisodeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Episode"
    static let isDiscoverable = false

    @Parameter(title: "Episode") var key: String

    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        await IntentBridge.play(key)
        return .result()
    }
}

enum IntentBridge {
    #if WIDGET_EXTENSION
    static func toggle() async {}
    static func skip(_ seconds: Double) async {}
    static func play(_ key: String) async {}
    #else
    @MainActor static func toggle() async {
        AudioPlayer.shared.restoreLastEpisode()
        AudioPlayer.shared.togglePlayPause()
    }

    @MainActor static func skip(_ seconds: Double) async {
        AudioPlayer.shared.skip(by: seconds)
    }

    @MainActor static func play(_ key: String) async {
        AudioPlayer.shared.play(key: key)
    }
    #endif
}
