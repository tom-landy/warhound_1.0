import SwiftData
import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var showsAddFeed = false
    @State private var feedText = ""
    @State private var pendingFeed: URL?

    var body: some View {
        List {
            ForEach(results) { result in
                NavigationLink(value: result) {
                    HStack(spacing: 12) {
                        ArtworkView(url: result.artworkUrl600, seed: result.collectionName, cornerRadius: 8)
                            .frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.collectionName)
                                .font(.headline)
                                .lineLimit(2)
                            Text([result.artistName, result.primaryGenreName].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay { placeholder }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Shows")
        .autocorrectionDisabled()
        .task(id: query) { await search() }
        .navigationDestination(for: SearchResult.self) { result in
            if let feed = result.feedUrl { PodcastLoaderView(feedURL: feed) }
        }
        .navigationDestination(item: $pendingFeed) { PodcastLoaderView(feedURL: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsAddFeed = true } label: { Image(systemName: "link.badge.plus") }
                    .accessibilityLabel("Add by feed URL")
            }
        }
        .alert("Add a Feed", isPresented: $showsAddFeed) {
            TextField("https://example.com/feed.xml", text: $feedText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) { feedText = "" }
            Button("Add") {
                if let url = URL(string: feedText.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true {
                    pendingFeed = url
                }
                feedText = ""
            }
        } message: {
            Text("Enter the RSS feed URL of a show, such as a private or members-only feed.")
        }
    }

    @ViewBuilder private var placeholder: some View {
        if isSearching && results.isEmpty {
            ProgressView()
        } else if let error {
            ContentUnavailableView("Search Failed", systemImage: "wifi.exclamationmark", description: Text(error))
        } else if query.isEmpty {
            ContentUnavailableView("Search Podcasts", systemImage: "magnifyingglass",
                                   description: Text("Search for shows, or add a show by its RSS feed URL."))
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count > 1 else { results = []; error = nil; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await PodcastSearch.search(term)
            guard !Task.isCancelled else { return }
            results = found
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Fetches a feed, stores it (unfollowed) and shows its page.
struct PodcastLoaderView: View {
    let feedURL: URL
    @Environment(\.modelContext) private var context
    @State private var podcast: Podcast?
    @State private var error: String?

    var body: some View {
        Group {
            if let podcast {
                PodcastDetailView(podcast: podcast)
            } else if let error {
                ContentUnavailableView("Couldn't Load This Show", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .task {
            guard podcast == nil else { return }
            do {
                podcast = try await FeedService.podcast(for: feedURL, context: context)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
