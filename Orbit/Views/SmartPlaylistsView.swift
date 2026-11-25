import SwiftData
import SwiftUI

struct SmartPlaylistsView: View {
    @State private var store = SmartPlaylists.shared
    @State private var editing: SmartPlaylist?

    var body: some View {
        List {
            ForEach(store.items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { playlist in
                NavigationLink {
                    SmartPlaylistDetail(id: playlist.id)
                } label: {
                    Label(playlist.name, systemImage: "list.bullet.rectangle")
                }
            }
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView {
                    Label("No Smart Playlists", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Save filters to keep a playlist up to date as episodes arrive.")
                } actions: {
                    Button("New Playlist") { editing = SmartPlaylist() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Smart Playlists")
        .toolbar {
            Button("New Playlist", systemImage: "plus") { editing = SmartPlaylist() }
        }
        .sheet(item: $editing) { SmartPlaylistEditor(playlist: $0) }
    }
}

private struct SmartPlaylistDetail: View {
    let id: UUID
    @State private var store = SmartPlaylists.shared
    @State private var editing: SmartPlaylist?
    @State private var confirmDelete = false
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Query private var episodes: [Episode]

    var body: some View {
        if let playlist = store.items.first(where: { $0.id == id }) {
            let matches = matches(for: playlist)
            List {
                Button {
                    player.playInOrder(matches)
                } label: {
                    Label("Play in Order", systemImage: "play.fill")
                }
                .disabled(matches.isEmpty)
                ForEach(matches) { episode in
                    EpisodeRow(episode: episode, showsPodcast: true)
                }
                if matches.isEmpty {
                    ContentUnavailableView("No Matching Episodes", systemImage: "line.3.horizontal.decrease",
                                           description: Text("Edit the playlist to change its filters."))
                }
            }
            .navigationTitle(playlist.name)
            .toolbar {
                Menu("Playlist Options", systemImage: "ellipsis.circle") {
                    Button("Edit Playlist", systemImage: "pencil") { editing = playlist }
                    Button("Delete Playlist", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
            .sheet(item: $editing) { SmartPlaylistEditor(playlist: $0) }
            .confirmationDialog("Delete this playlist?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Playlist", role: .destructive) {
                    store.delete(id)
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("Playlist Unavailable", systemImage: "list.bullet.rectangle")
        }
    }

    private func matches(for playlist: SmartPlaylist) -> [Episode] {
        episodes.filter { episode in
            guard let podcast = episode.podcast, podcast.isSubscribed else { return false }
            let available = playlist.downloadedOnly
                && (episode.localFileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
            return playlist.includes(feed: podcast.feedURL, played: episode.isPlayed, downloaded: available,
                                     duration: episode.duration)
        }.sorted { first, second in
            if first.pubDate == second.pubDate { return first.key < second.key }
            return playlist.order == .newest ? first.pubDate > second.pubDate : first.pubDate < second.pubDate
        }
    }
}

private struct SmartPlaylistEditor: View {
    @State var playlist: SmartPlaylist
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }, sort: \Podcast.title) private var podcasts: [Podcast]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Playlist Name", text: $playlist.name)
                Section("Episodes") {
                    Toggle("Unplayed Only", isOn: $playlist.unplayedOnly)
                    Toggle("Downloaded on This Device", isOn: $playlist.downloadedOnly)
                    Picker("Maximum Length", selection: $playlist.maxMinutes) {
                        Text("Any Length").tag(0)
                        ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    Picker("Order", selection: $playlist.order) {
                        ForEach(SmartPlaylist.EpisodeOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                }
                Section {
                    ForEach(podcasts) { podcast in
                        Toggle(podcast.title, isOn: Binding {
                            playlist.feeds.contains(podcast.feedURL)
                        } set: { selected in
                            if selected { playlist.feeds.insert(podcast.feedURL) }
                            else { playlist.feeds.remove(podcast.feedURL) }
                        })
                    }
                    if !playlist.feeds.isEmpty {
                        Button("Use All Followed Shows") { playlist.feeds.removeAll() }
                    }
                } header: {
                    Text("Shows")
                } footer: {
                    Text("Leave all shows unselected to include every show you follow.")
                }
            }
            .navigationTitle("Smart Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        playlist.name = playlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        SmartPlaylists.shared.save(playlist)
                        dismiss()
                    }
                    .disabled(playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
