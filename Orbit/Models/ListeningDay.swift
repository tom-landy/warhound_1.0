import Foundation
import SwiftData

/// Listening totals for one show on one day.
@Model
final class ListeningDay {
    var day: Date
    var feedURL: String
    var showTitle: String
    /// Real time spent listening, in seconds.
    var listened: Double = 0
    /// Audio covered, in seconds. More than `listened` when playing faster than 1×.
    var content: Double = 0
    var finished: Int = 0

    init(day: Date, feedURL: String, showTitle: String) {
        self.day = day
        self.feedURL = feedURL
        self.showTitle = showTitle
    }
}
