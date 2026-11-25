import SwiftData
import SwiftUI

struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Episode> { $0.localFileName != nil }, sort: \Episode.downloadedAt, order: .reverse)
    private var downloaded: [Episode]
    @State private var confirmDeleteAll = false

    private var inProgress: [Episode] {
        let keys = Array(downloads.active)
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
                    ForEach(pending) { DownloadingRow(episode: $0) }
                }
            }
            Section {
                ForEach(downloaded) { EpisodeRow(episode: $0, showsPodcast: true) }
                    .onDelete { offsets in
                        withAnimation(.snappy(duration: 0.25)) {
                            for i in offsets { downloads.remove(downloaded[i]) }
                        }
                    }
            } header: {
                if !downloaded.isEmpty {
                    Text("\(downloaded.count) episodes · \(totalSize)")
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .overlay {
            if downloaded.isEmpty && downloads.active.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Tap to download on any episode. New episodes download automatically on Wi-Fi.")
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !downloaded.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete All", role: .destructive) { confirmDeleteAll = true }
                }
            }
        }
        .confirmationDialog("Delete all \(downloaded.count) downloads?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete \(totalSize)", role: .destructive) { downloads.removeAll() }
        }
    }
}

/// One in-progress download. Kept separate so its progress doesn't redraw the whole screen.
private struct DownloadingRow: View {
    let episode: Episode
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 6)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                DownloadStatusLine(episode: episode, progress: downloads.progress(for: episode.key))
            }
            DownloadButton(episode: episode)
        }
    }
}

private struct DownloadStatusLine: View {
    let episode: Episode
    let progress: DownloadProgress?
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        if let fraction = progress?.fraction {
            ProgressView(value: fraction)
        } else if downloads.wifiOnly.contains(episode.key) {
            HStack {
                Text("Waiting for Wi-Fi").font(.caption).foregroundStyle(.secondary)
                Button("Use Mobile Data") { downloads.downloadNow(episode) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        } else {
            Text("Waiting for Connection").font(.caption).foregroundStyle(.secondary)
        }
    }
}
