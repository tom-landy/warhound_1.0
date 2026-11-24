import AppIntents
import SwiftUI
import WidgetKit

@main
struct OrbitWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        UpNextWidget()
        if #available(iOS 18.0, *) {
            PlayPauseControl()
        }
    }
}

struct OrbitEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// The app reloads widgets whenever playback or Up Next changes, so one entry is enough.
struct OrbitProvider: TimelineProvider {
    func placeholder(in context: Context) -> OrbitEntry {
        OrbitEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (OrbitEntry) -> Void) {
        completion(OrbitEntry(date: .now, snapshot: context.isPreview ? .sample : (WidgetStore.read() ?? WidgetSnapshot())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OrbitEntry>) -> Void) {
        let entry = OrbitEntry(date: .now, snapshot: WidgetStore.read() ?? WidgetSnapshot())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.nowPlayingKind, provider: OrbitProvider()) { entry in
            NowPlayingEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("The current episode, with playback controls.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private struct NowPlayingEntryView: View {
    let entry: OrbitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NowPlayingWidgetView(snapshot: entry.snapshot, family: family)
            .containerBackground(for: .widget) { WidgetBackground() }
    }
}

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.upNextKind, provider: OrbitProvider()) { entry in
            UpNextEntryView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("The next episodes in Up Next.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct UpNextEntryView: View {
    let entry: OrbitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        UpNextWidgetView(snapshot: entry.snapshot, family: family)
            .containerBackground(for: .widget) { WidgetBackground() }
    }
}

private struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(widgetHex: 0x23262D), Color(widgetHex: 0x0C0D10)], startPoint: .top, endPoint: .bottom)
    }
}

@available(iOS 18.0, *)
struct PlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "PlayPause") {
            ControlWidgetButton(action: TogglePlaybackIntent()) {
                Label("Play/Pause", systemImage: "playpause.fill")
            }
        }
        .displayName("Play/Pause")
        .description("Plays or pauses the current episode in Orbit.")
    }
}
