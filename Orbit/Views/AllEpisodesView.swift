import SwiftData
import SwiftUI

/// Every episode from the shows you follow, newest first.
struct AllEpisodesView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", unplayed = "Unplayed", downloaded = "Downloaded"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Episode.pubDate, order: .reverse) private var episodes: [Episode]
    @AppStorage("allEpisodesFilter") private var filter: Filter = .all

    private var shown: [Episode] {
        episodes.filter { episode in
            guard episode.podcast?.isSubscribed == true else { return false }
            switch filter {
            case .all: return true
            case .unplayed: return !episode.isPlayed
            case .downloaded: return episode.isDownloaded
            }
        }
    }

    var body: some View {
        let list = shown
        List {
            ForEach(list) { EpisodeRow(episode: $0, showsPodcast: true) }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .overlay {
            if list.isEmpty {
                ContentUnavailableView(filter == .downloaded ? "No Downloads" : "No Episodes",
                                       systemImage: "list.bullet",
                                       description: Text("Episodes from the shows you follow appear here, newest first."))
            }
        }
        .navigationTitle("All Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await FeedService.refreshAll(context: context) }
    }
}
