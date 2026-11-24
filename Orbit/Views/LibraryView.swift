import SwiftData
import SwiftUI

struct LibraryView: View {
    @Binding var tab: AppTab
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }, sort: \Podcast.title)
    private var podcasts: [Podcast]

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        Group {
            if podcasts.isEmpty {
                EmptyLibraryView { tab = .search }
            } else {
                ScrollView {
                    NavigationLink {
                        AllEpisodesView()
                    } label: {
                        HStack {
                            Label("All Episodes", systemImage: "list.bullet")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 14) {
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StatsView()
                } label: {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("Stats")
            }
        }
        .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
    }
}

private struct LibraryCell: View {
    let podcast: Podcast

    private var unplayed: Int { podcast.episodes.lazy.filter { !$0.isPlayed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ArtworkView(url: podcast.artworkURL, seed: podcast.title, cornerRadius: 12)
                .overlay(alignment: .topTrailing) {
                    if unplayed > 0 {
                        Text(unplayed > 99 ? "99+" : "\(unplayed)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(AccentTheme.onColor)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([podcast.title, podcast.author, unplayed > 0 ? "\(unplayed) unplayed" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}
