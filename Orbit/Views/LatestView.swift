import SwiftData
import SwiftUI

struct LatestView: View {
    @Binding var tab: AppTab
    @Environment(\.modelContext) private var context
    @Query(sort: \Episode.pubDate, order: .reverse) private var episodes: [Episode]

    private var subscribed: [Episode] {
        episodes.filter { $0.podcast?.isSubscribed == true }
    }

    private var followsAnything: Bool {
        episodes.contains { $0.podcast?.isSubscribed == true }
    }

    private var inProgress: [Episode] {
        subscribed.filter(\.isInProgress)
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    private var latest: [Episode] {
        let resuming = Set(inProgress.map(\.key))
        return subscribed.filter { !resuming.contains($0.key) }.prefix(80).map { $0 }
    }

    var body: some View {
        Group {
            if !followsAnything {
                EmptyLibraryView { tab = .search }
            } else {
                List {
                    if !inProgress.isEmpty {
                        Section("Continue") {
                            ForEach(inProgress) { EpisodeRow(episode: $0, showsPodcast: true) }
                        }
                    }
                    Section(inProgress.isEmpty ? "" : "New") {
                        ForEach(latest) { EpisodeRow(episode: $0, showsPodcast: true) }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 0)
                .refreshable { await FeedService.refreshAll(context: context) }
            }
        }
        .navigationTitle("Latest")
    }
}

struct EmptyLibraryView: View {
    let findPodcasts: () -> Void
    @Environment(\.theme) private var theme
    @State private var showsImport = false

    var body: some View {
        ContentUnavailableView {
            LogoView(theme: theme)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.bottom, 8)
            Text("No Shows")
        } description: {
            Text("All your shows appear here.")
        } actions: {
            Button("Find Podcasts", action: findPodcasts)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AccentTheme.onColor)
            Button("Import from Another App") { showsImport = true }
        }
        .sheet(isPresented: $showsImport) { ImportView() }
    }
}
