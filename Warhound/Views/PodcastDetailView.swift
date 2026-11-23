import SwiftData
import SwiftUI

struct PodcastDetailView: View {
    @Bindable var podcast: Podcast
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
    @State private var expanded = false
    @State private var hidePlayed = false

    private var episodes: [Episode] {
        let all = podcast.sortedEpisodes
        return hidePlayed ? all.filter { !$0.isPlayed } : all
    }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))

            Section {
                ForEach(episodes) { EpisodeRow(episode: $0) }
            } header: {
                HStack {
                    Text("\(episodes.count) episodes")
                    Spacer()
                    Button(hidePlayed ? "Show all" : "Hide played") {
                        withAnimation { hidePlayed.toggle() }
                    }
                    .font(.subheadline)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { try? await FeedService.refresh(podcast, context: context) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        for e in podcast.episodes { e.isPlayed = true; e.playbackPosition = 0 }
                    } label: { Label("Mark all as played", systemImage: "checkmark.circle") }
                    Button {
                        UIPasteboard.general.url = podcast.feedURL
                    } label: { Label("Copy feed link", systemImage: "link") }
                    if podcast.isSubscribed {
                        Button(role: .destructive) { podcast.isSubscribed = false } label: {
                            Label("Unfollow", systemImage: "minus.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ArtworkView(url: podcast.artworkURL, seed: podcast.title, cornerRadius: 16)
                .frame(width: 200, height: 200)
                .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
            VStack(spacing: 4) {
                Text(podcast.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if !podcast.author.isEmpty {
                    Text(podcast.author)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
            }
            Button {
                withAnimation(.snappy) {
                    podcast.isSubscribed.toggle()
                    podcast.subscribedAt = podcast.isSubscribed ? .now : nil
                    try? context.save()
                }
            } label: {
                Label(podcast.isSubscribed ? "Following" : "Follow",
                      systemImage: podcast.isSubscribed ? "checkmark" : "plus")
                    .font(.headline)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(podcast.isSubscribed ? Color.white.opacity(0.15) : theme.color)
            .foregroundStyle(podcast.isSubscribed ? Color.primary : Color.black)
            .contentTransition(.symbolEffect(.replace))

            if !podcast.summary.isEmpty {
                Text(podcast.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { withAnimation { expanded.toggle() } }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
