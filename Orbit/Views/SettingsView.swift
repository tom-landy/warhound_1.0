import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(AccentTheme.storageKey) private var theme: AccentTheme = .orange
    @AppStorage(AccentTheme.matchIconKey) private var matchIcon = false
    @AppStorage(DownloadManager.wifiOnlyKey) private var wifiOnly = true
    @AppStorage(DownloadManager.removePlayedKey) private var removePlayed = true
    @AppStorage(DownloadManager.keepPerShowKey) private var keepPerShow = 1
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var downloads
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }, sort: \Podcast.title) private var subscriptions: [Podcast]
    @State private var showsImport = false
    @State private var exportURL: URL?

    private let columns = [GridItem(.adaptive(minimum: 58), spacing: 14)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LogoView(theme: theme)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                        .shadow(color: theme.color.opacity(0.35), radius: 20, y: 6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                        .animation(.easeInOut(duration: 0.25), value: theme)
                }

                Section {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AccentTheme.allCases) { option in
                            Swatch(theme: option, selected: option == theme) {
                                withAnimation(.snappy) { theme = option }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    Toggle("Match App Icon", isOn: $matchIcon)
                } header: {
                    Text("Colour")
                } footer: {
                    Text("Also changes the app icon on the Home Screen.")
                }

                Section {
                    Picker("Keep Downloaded per Show", selection: $keepPerShow) {
                        ForEach([1, 2, 3, 5], id: \.self) { Text("\($0) latest").tag($0) }
                    }
                    Toggle("Automatic Downloads on Wi-Fi Only", isOn: $wifiOnly)
                    Toggle("Remove After Playing", isOn: $removePlayed)
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        LabeledContent("Manage Downloads", value: storageUsed)
                    }
                } header: {
                    Text("Downloads")
                } footer: {
                    Text("Wi-Fi Only applies to automatic downloads. Episodes you download yourself use any connection. Turn off automatic downloads for a show in its ⋯ menu.")
                }

                Section("Your Shows") {
                    Button {
                        showsImport = true
                    } label: {
                        Label("Import from Another App", systemImage: "square.and.arrow.down")
                    }
                    if let exportURL, !subscriptions.isEmpty {
                        ShareLink(item: exportURL) {
                            Label("Export \(subscriptions.count) Shows (OPML)", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent("Built", value: Self.buildDate)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsImport) { ImportView() }
            .onChange(of: keepPerShow) { FeedService.keepLatestDownloaded(context: context) }
            .task(id: subscriptions.count) { exportURL = OPML.exportFile(subscriptions) }
            .onChange(of: theme) { _, new in new.applyIcon(matchIcon) }
            .onChange(of: matchIcon) { _, new in theme.applyIcon(new) }
        }
    }

    private var storageUsed: String {
        let bytes = downloads.downloadedEpisodes().reduce(0) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// When this copy was built in Xcode, read from the app binary's date.
    private static var buildDate: String {
        guard let url = Bundle.main.executableURL,
              let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

private struct Swatch: View {
    let theme: AccentTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(theme.gradient)
                        .frame(width: 44, height: 44)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.black)
                    }
                }
                .padding(4)
                .overlay {
                    Circle().strokeBorder(selected ? theme.color : .clear, lineWidth: 2.5)
                }
                Text(theme.name)
                    .font(.caption2.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Gear button that opens Settings. Apply inside a NavigationStack.
private struct SettingsButton: ViewModifier {
    @State private var shows: Bool

    init(demo: Bool) {
        _shows = State(initialValue: demo && DemoData.isActive && UserDefaults.standard.bool(forKey: "demoSettings"))
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { shows = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $shows) { SettingsView() }
    }
}

extension View {
    /// `demo`: this instance may auto-open for screenshots (`-demo -demoSettings YES`).
    func settingsButton(demo: Bool = false) -> some View { modifier(SettingsButton(demo: demo)) }
}
