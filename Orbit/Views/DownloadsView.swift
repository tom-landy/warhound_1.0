import SwiftData
import SwiftUI

struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Episode> { $0.localFileName != nil }, sort: \Episode.downloadedAt, order: .reverse)
    private var downloaded: [Episode]
    @State private var confirmDeleteAll = false

    private var inProgress: [Episode] {
        let keys = Array(downloads.active.keys)
        guard !keys.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { keys.contains($0.key) })
        return (try? context.fetch(descriptor)) ?? []
    }

    private var totalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(downloaded.reduce(0) { $0 + $1.fileSize }), countStyle: .file)
    }

    var body: some View {
        List {
            let pending = inProgress
            if !pending.isEmpty {
                Section("Downloading") {
                    ForEach(pending) { episode in
                        HStack(spacing: 12) {
                            ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 6)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if case .downloading(let f) = downloads.state(episode), let f {
                                    ProgressView(value: f)
                                } else if downloads.wifiOnly.contains(episode.key) {
                                    HStack {
                                        Text("Waiting for Wi-Fi").font(.caption).foregroundStyle(.secondary)
                                        Button("Use mobile data") { downloads.downloadNow(episode) }
                                            .font(.caption.weight(.semibold))
                                            .buttonStyle(.borderless)
                                    }
                                } else {
                                    Text("Waiting for connection").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            DownloadButton(episode: episode)
                        }
                    }
                }
            }
            Section {
                ForEach(downloaded) { EpisodeRow(episode: $0, showsPodcast: true) }
                    .onDelete { offsets in
                        for i in offsets { downloads.remove(downloaded[i]) }
                    }
            } header: {
                if !downloaded.isEmpty {
                    Text("\(downloaded.count) episodes · \(totalSize)")
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if downloaded.isEmpty && downloads.active.isEmpty {
                ContentUnavailableView {
                    Label("No downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Tap the download button on any episode. New episodes from shows you follow download by themselves on Wi-Fi.")
                }
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            if !downloaded.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete all", role: .destructive) { confirmDeleteAll = true }
                }
            }
        }
        .confirmationDialog("Delete all \(downloaded.count) downloads?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete \(totalSize)", role: .destructive) { downloads.removeAll() }
        }
    }
}
