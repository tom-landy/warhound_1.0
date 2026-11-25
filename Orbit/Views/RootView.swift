import CoreSpotlight
import SwiftData
import SwiftUI

enum AppTab: String, Hashable {
    case latest, library, search, downloads, settings
}

struct RootView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastRefreshAll") private var lastRefreshAll: Double = 0
    @State private var tab: AppTab = .latest
    @State private var importRequest: ImportRequest?
    @State private var libraryPath = NavigationPath()
    @State private var showsUpNext = false
    private var quickActions = QuickActions.shared
    @State private var demoSheet: String?
    @AppStorage(AppAppearance.chosenKey) private var appearanceChosen = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var ipadSheet: IPadSheet?
    @State private var ipadShow: Podcast?

    /// The iPad layout on a full-width iPad; the tab layout everywhere else
    /// (iPhone, iPad Split View and Slide Over, narrow windows).
    private var usesIPadLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
    }

    var body: some View {
        @Bindable var player = player
        Group {
            if usesIPadLayout {
                IPadRootView(sheet: $ipadSheet, openShow: $ipadShow)
                    .sheet(item: $ipadSheet) { sheet in
                        NavigationStack { ipadSheetContent(sheet) }
                    }
            } else {
                tabs
            }
        }
        .sheet(isPresented: Binding(get: { player.showsFullPlayer && !usesIPadLayout },
                                    set: { player.showsFullPlayer = $0 })) {
            NowPlayingView()
        }
        .sheet(item: $importRequest) { ImportView(file: $0.file) }
        .fullScreenCover(isPresented: Binding(get: { !appearanceChosen && !DemoData.isActive || DemoData.showsWelcome },
                                              set: { _ in })) {
            WelcomeView()
        }
        .sheet(isPresented: Binding(get: { demoSheet != nil }, set: { if !$0 { demoSheet = nil } })) {
            NavigationStack {
                if demoSheet == "stats" { StatsView() } else { WidgetGalleryView() }
            }
        }
        .sheet(isPresented: $showsUpNext) { UpNextView() }
        .onChange(of: quickActions.pending, initial: true) { _, action in
            guard let action else { return }
            quickActions.pending = nil
            switch action {
            case .resume:
                player.restoreLastEpisode()
                player.resume()
                player.showsFullPlayer = true
            case .upNext: showsUpNext = true
            case .search:
                if usesIPadLayout { ipadSheet = .search } else { tab = .search }
            }
        }
        .onChange(of: quickActions.open, initial: true) { _, id in
            guard let id else { return }
            quickActions.open = nil
            openSpotlightResult(id)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            openSpotlightResult(id)
        }
        .onOpenURL { url in
            if url.isFileURL { importRequest = ImportRequest(file: url) }
        }
        .task {
            if DemoData.isActive {
                if let t = DemoData.apply(player: player, context: context) { tab = t }
                if UserDefaults.standard.bool(forKey: "demoImport") { importRequest = ImportRequest() }
                if UserDefaults.standard.bool(forKey: "demoStats") { demoSheet = "stats" }
                if UserDefaults.standard.bool(forKey: "demoWidgets") { demoSheet = "widgets" }
                if UserDefaults.standard.bool(forKey: "demoLandscape"),
                   let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                }
            } else {
                await refreshIfStale(force: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Check feeds each time Orbit comes back, if it's been 15 minutes.
            if phase == .active && !DemoData.isActive { Task { await refreshIfStale() } }
        }
    }
}

extension RootView {
    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack { LatestView(tab: $tab) }
                .miniPlayerInset()
                .tabItem { Label("Latest", systemImage: "clock") }
                .tag(AppTab.latest)
            NavigationStack(path: $libraryPath) { LibraryView(tab: $tab) }
                .miniPlayerInset()
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
                .tag(AppTab.library)
            NavigationStack { SearchView() }
                .miniPlayerInset()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            NavigationStack { DownloadsView() }
                .miniPlayerInset()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .tag(AppTab.downloads)
            NavigationStack { SettingsView() }
                .miniPlayerInset()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }

    @ViewBuilder
    fileprivate func ipadSheetContent(_ sheet: IPadSheet) -> some View {
        switch sheet {
        case .latest: LatestView(tab: $tab)
        case .allEpisodes: AllEpisodesView()
        case .library: LibraryView(tab: $tab)
        case .search: SearchView()
        case .upNext: UpNextView()
        case .settings: SettingsView(showsDone: true)
        case .downloads: DownloadsView()
        case .stats: StatsView()
        }
    }

    fileprivate func refreshIfStale(force: Bool = false) async {
        guard force || Date.now.timeIntervalSince1970 - lastRefreshAll > 15 * 60 else { return }
        lastRefreshAll = Date.now.timeIntervalSince1970
        await FeedService.refreshAll(context: context)
    }

    /// Spotlight: a show opens its page; an episode opens in the player, paused.
    fileprivate func openSpotlightResult(_ id: String) {
        if id.hasPrefix(SpotlightIndex.showPrefix) {
            let feed = String(id.dropFirst(SpotlightIndex.showPrefix.count))
            guard let podcast = try? context.fetch(FetchDescriptor<Podcast>()).first(where: { $0.feedURL.absoluteString == feed }) else { return }
            if usesIPadLayout {
                ipadShow = podcast
            } else {
                tab = .library
                libraryPath = NavigationPath()
                libraryPath.append(podcast)
            }
        } else if id.hasPrefix(SpotlightIndex.episodePrefix) {
            let key = String(id.dropFirst(SpotlightIndex.episodePrefix.count))
            var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.key == key })
            descriptor.fetchLimit = 1
            guard let episode = try? context.fetch(descriptor).first else { return }
            if !player.isCurrent(episode) { player.load(episode, autoplay: false) }
            if usesIPadLayout { ipadShow = nil } else { player.showsFullPlayer = true }
        }
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Environment(AudioPlayer.self) private var player

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.episode != nil {
                MiniPlayerView()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: player.episode?.key)
    }
}

extension View {
    func miniPlayerInset() -> some View { modifier(MiniPlayerInset()) }
}
