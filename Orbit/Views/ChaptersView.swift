import SwiftUI

struct ChaptersView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(player.chapters.enumerated()), id: \.offset) { index, chapter in
                        Button {
                            player.seek(to: chapter)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(chapter.start.clock)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 56, alignment: .leading)
                                Text(chapter.title.isEmpty ? "Chapter \(index + 1)" : chapter.title)
                                    .font(.body.weight(index == player.currentChapterIndex ? .semibold : .regular))
                                    .foregroundStyle(index == player.currentChapterIndex ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                Spacer(minLength: 0)
                                if let url = chapter.url {
                                    Button { openURL(url) } label: { Image(systemName: "link") }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Open Link")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if let current = player.currentChapterIndex { proxy.scrollTo(current, anchor: .center) }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
