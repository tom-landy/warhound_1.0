import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Follows every show in an OPML file exported from another podcast app.
@MainActor
@Observable
final class Importer {
    enum Phase { case idle, importing, done }

    var phase: Phase = .idle
    var total = 0
    var finished = 0
    var added = 0
    var alreadyFollowing = 0
    var failures: [OPMLFeed] = []
    var current = ""
    var error: String?

    func run(file: URL, context: ModelContext) async {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        do {
            let feeds = try OPML.parse(Data(contentsOf: file))
            guard !feeds.isEmpty else {
                error = "No shows found. Choose an OPML file."
                return
            }
            await run(feeds: feeds, context: context)
        } catch {
            self.error = "This file can't be read. Choose an OPML file."
        }
    }

    func run(feeds: [OPMLFeed], context: ModelContext) async {
        phase = .importing
        total = feeds.count
        finished = 0; added = 0; alreadyFollowing = 0; failures = []; error = nil
        // A few at a time: quick on good signal, doesn't swamp a weak one.
        for batch in stride(from: 0, to: feeds.count, by: 4).map({ Array(feeds[$0..<min($0 + 4, feeds.count)]) }) {
            await withTaskGroup(of: Void.self) { group in
                for feed in batch {
                    group.addTask { @MainActor in
                        self.current = feed.title
                        do {
                            let podcast = try await FeedService.podcast(for: feed.url, context: context)
                            if podcast.isSubscribed {
                                self.alreadyFollowing += 1
                            } else {
                                podcast.setFollowing(true)
                                self.added += 1
                            }
                        } catch {
                            self.failures.append(feed)
                        }
                        self.finished += 1
                    }
                }
            }
        }
        try? context.save()
        FeedService.keepLatestDownloaded(context: context)
        phase = .done
    }
}

struct ImportView: View {
    var file: URL?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var importer = Importer()
    @State private var picking = false
    @State private var markedPlayed = false

    var body: some View {
        NavigationStack {
            Group {
                switch importer.phase {
                case .idle: instructions
                case .importing: progress
                case .done: summary
                }
            }
            .navigationTitle("Import Shows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(importer.phase == .done ? "Done" : "Close") { dismiss() }
                        .disabled(importer.phase == .importing)
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.opml, .xml, .text]) { result in
                if case .success(let url) = result { start(url) }
            }
            .task {
                if let file { start(file) }
            }
        }
        .interactiveDismissDisabled(importer.phase == .importing)
    }

    private func start(_ url: URL) {
        Task { await importer.run(file: url, context: context) }
    }

    private var instructions: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import from Another App")
                        .font(.title3.bold())
                    Text("Export an OPML file from your current podcast app, then choose it here. You can also open an OPML file in Orbit from Files or the share sheet.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Button {
                    picking = true
                } label: {
                    Label("Choose OPML File", systemImage: "doc.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AccentTheme.onColor)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if let error = importer.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section("Where to Find the Export") {
                HowTo(app: "Overcast", steps: "Settings → Export OPML (or overcast.fm → Account → Export OPML)")
                HowTo(app: "Pocket Casts", steps: "Profile → Settings → Import & Export → Export podcasts")
                HowTo(app: "Castro", steps: "Settings → User Data → Export Subscriptions")
                HowTo(app: "Spotify", steps: "Not supported. Add shows using Search.")
                HowTo(app: "Apple Podcasts", steps: "Not supported. Add shows using Search.")
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 18) {
            ProgressView(value: Double(importer.finished), total: Double(max(importer.total, 1)))
                .tint(theme.color)
            Text("\(importer.finished) of \(importer.total)")
                .font(.title2.bold().monospacedDigit())
            Text(importer.current)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("Keep Orbit open until the import finishes. The latest episode of each show will download on Wi-Fi.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxHeight: .infinity)
    }

    private var summary: some View {
        List {
            Section {
                Button {
                    FeedService.markAllPlayed(keepLatest: true, context: context)
                    markedPlayed = true
                } label: {
                    Label(markedPlayed ? "Older Episodes Marked as Played" : "Mark Older Episodes as Played",
                          systemImage: markedPlayed ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .disabled(markedPlayed)
            } footer: {
                Text("Keeps each show's latest episode unplayed, so only new episodes show as new.")
            }
            Section {
                LabeledContent("Now Following", value: "\(importer.added)")
                if importer.alreadyFollowing > 0 {
                    LabeledContent("Already Following", value: "\(importer.alreadyFollowing)")
                }
                if !importer.failures.isEmpty {
                    LabeledContent("Couldn't Load", value: "\(importer.failures.count)")
                }
            }
            if !importer.failures.isEmpty {
                Section {
                    ForEach(importer.failures, id: \.url) { feed in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.title)
                            Text(feed.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Button("Retry") {
                        let retry = importer.failures
                        Task { await importer.run(feeds: retry, context: context) }
                    }
                } header: {
                    Text("Couldn't Load")
                } footer: {
                    Text("Check your connection and try again. Some feeds may no longer exist.")
                }
            }
        }
    }
}

private struct HowTo: View {
    let app: String
    let steps: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(app).font(.subheadline.weight(.semibold))
            Text(steps).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct ImportRequest: Identifiable {
    let id = UUID()
    var file: URL?
}
