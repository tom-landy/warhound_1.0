import SwiftData
import SwiftUI

enum AppTab: String, Hashable {
    case latest, library, search
}

struct RootView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .latest

    var body: some View {
        @Bindable var player = player
        TabView(selection: $tab) {
            NavigationStack { LatestView(tab: $tab) }
                .miniPlayerInset()
                .tabItem { Label("Latest", systemImage: "clock") }
                .tag(AppTab.latest)
            NavigationStack { LibraryView(tab: $tab) }
                .miniPlayerInset()
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
                .tag(AppTab.library)
            NavigationStack { SearchView() }
                .miniPlayerInset()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
        }
        .sheet(isPresented: $player.showsFullPlayer) {
            NowPlayingView()
        }
        .task {
            if DemoData.isActive {
                if let t = DemoData.apply(player: player, context: context) { tab = t }
            } else {
                await FeedService.refreshAll(context: context)
            }
        }
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Environment(AudioPlayer.self) private var player

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.episode != nil {
                MiniPlayerView()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: player.episode?.key)
    }
}

extension View {
    func miniPlayerInset() -> some View { modifier(MiniPlayerInset()) }
}
