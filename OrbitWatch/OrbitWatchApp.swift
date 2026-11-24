import SwiftUI

@main
struct OrbitWatchApp: App {
    @State private var link = PhoneLink()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(link)
                .tint(Color(red: 0xF2 / 255, green: 0x6A / 255, blue: 0x2A / 255))
        }
    }
}
