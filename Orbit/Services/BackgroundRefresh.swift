import BackgroundTasks
import SwiftData

/// Checks feeds while the app is closed, so new episodes download on Wi-Fi without you opening Orbit.
/// iOS decides when this actually runs, typically a few times a day, often overnight on charge.
enum BackgroundRefresh {
    static let identifier = "com.tomlandy.Orbit.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run(_ container: ModelContainer) async {
        schedule()
        await FeedService.refreshAll(context: container.mainContext)
    }
}
