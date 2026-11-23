import SwiftData
import SwiftUI

struct LibraryView: View {
    @Binding var tab: AppTab
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }, sort: \Podcast.title)
    private var podcasts: [Podcast]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        Group {
            if podcasts.isEmpty {
                EmptyLibraryView { tab = .search }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(podcasts) { podcast in
                            NavigationLink(value: podcast) {
                                LibraryCell(podcast: podcast)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    podcast.isSubscribed = false
                                } label: {
                                    Label("Unfollow", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                    .padding()
                }
                .refreshable { await FeedService.refreshAll(context: context) }
            }
        }
        .navigationTitle("Library")
        .settingsButton()
        .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
    }
}

private struct LibraryCell: View {
    let podcast: Podcast

    private var unplayed: Int { podcast.episodes.lazy.filter { !$0.isPlayed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: podcast.artworkURL, seed: podcast.title, cornerRadius: 12)
                .overlay(alignment: .topTrailing) {
                    if unplayed > 0 {
                        Text(unplayed > 99 ? "99+" : "\(unplayed)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.tint, in: Capsule())
                            .padding(8)
                    }
                }
            Text(podcast.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(podcast.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
