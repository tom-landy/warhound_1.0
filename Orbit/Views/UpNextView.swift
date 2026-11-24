import SwiftData
import SwiftUI

struct UpNextView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Episode> { $0.queueOrder != nil }, sort: \Episode.queueOrder)
    private var queue: [Episode]

    var body: some View {
        NavigationStack {
            List {
                if let current = player.episode {
                    Section("Now Playing") {
                        Row(episode: current)
                    }
                }
                Section {
                    ForEach(queue) { episode in
                        Button {
                            player.play(episode)
                        } label: {
                            Row(episode: episode)
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { player.moveQueue(from: $0, to: $1) }
                    .onDelete { offsets in
                        withAnimation(.snappy) {
                            for i in offsets { player.removeFromQueue(queue[i]) }
                        }
                    }
                } header: {
                    Text("Up Next")
                } footer: {
                    if queue.isEmpty {
                        Text("Touch and hold an episode, then choose Play Next or Add to Up Next.")
                    }
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !queue.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !queue.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Clear Up Next", role: .destructive) { player.clearQueue() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct Row: View {
    let episode: Episode

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: episode.displayArtwork, seed: episode.podcast?.title ?? "", cornerRadius: 6)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text([episode.podcast?.title ?? "", (episode.isInProgress ? episode.remaining : episode.duration).spoken]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if episode.isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
