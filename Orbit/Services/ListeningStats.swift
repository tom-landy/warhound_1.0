import Foundation
import SwiftData

@MainActor
enum ListeningStats {
    static func record(_ episode: Episode, listened: Double, content: Double, finished: Int, context: ModelContext) {
        guard listened > 0 || finished > 0, let podcast = episode.podcast else { return }
        let day = Calendar.current.startOfDay(for: .now)
        let feed = podcast.feedURL.absoluteString
        var descriptor = FetchDescriptor<ListeningDay>(predicate: #Predicate { $0.day == day && $0.feedURL == feed })
        descriptor.fetchLimit = 1
        let entry: ListeningDay
        if let existing = try? context.fetch(descriptor).first {
            entry = existing
        } else {
            entry = ListeningDay(day: day, feedURL: feed, showTitle: podcast.title)
            context.insert(entry)
        }
        entry.showTitle = podcast.title
        entry.listened += listened
        entry.content += content
        entry.finished += finished
        try? context.save()
    }

    enum Range: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", allTime = "All Time"
        var id: String { rawValue }

        var start: Date? {
            let today = Calendar.current.startOfDay(for: .now)
            switch self {
            case .week: return Calendar.current.date(byAdding: .day, value: -6, to: today)
            case .month: return Calendar.current.date(byAdding: .day, value: -29, to: today)
            case .allTime: return nil
            }
        }
    }

    struct Bucket: Identifiable {
        let date: Date
        let seconds: Double
        var id: Date { date }
    }

    struct ShowTotal: Identifiable {
        let title: String
        let feed: String
        let seconds: Double
        var id: String { feed }
    }

    struct Summary {
        var listened: Double = 0
        var saved: Double = 0
        var finished = 0
        var streak = 0
        var buckets: [Bucket] = []
        var bucketUnit: Calendar.Component = .day
        var topShows: [ShowTotal] = []
    }

    static func summary(_ range: Range, days: [ListeningDay]) -> Summary {
        let calendar = Calendar.current
        let inRange = days.filter { day in range.start.map { day.day >= $0 } ?? true }
        var s = Summary()
        s.listened = inRange.reduce(0) { $0 + $1.listened }
        s.saved = max(0, inRange.reduce(0) { $0 + $1.content } - s.listened)
        s.finished = inRange.reduce(0) { $0 + $1.finished }
        s.streak = streak(days: days)

        // Bars: days for week and month, months for all time.
        switch range {
        case .week, .month:
            let count = range == .week ? 7 : 30
            let today = calendar.startOfDay(for: .now)
            let byDay = Dictionary(grouping: inRange, by: \.day).mapValues { $0.reduce(0) { $0 + $1.listened } }
            s.buckets = (0..<count).reversed().compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today).map { Bucket(date: $0, seconds: byDay[$0] ?? 0) }
            }
            s.bucketUnit = .day
        case .allTime:
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
            let byMonth = Dictionary(grouping: inRange) {
                calendar.date(from: calendar.dateComponents([.year, .month], from: $0.day)) ?? $0.day
            }.mapValues { $0.reduce(0) { $0 + $1.listened } }
            s.buckets = (0..<12).reversed().compactMap { offset in
                calendar.date(byAdding: .month, value: -offset, to: thisMonth).map { Bucket(date: $0, seconds: byMonth[$0] ?? 0) }
            }
            s.bucketUnit = .month
        }

        let byShow = Dictionary(grouping: inRange, by: \.feedURL)
        s.topShows = byShow.map { feed, entries in
            ShowTotal(title: entries.last?.showTitle ?? "", feed: feed, seconds: entries.reduce(0) { $0 + $1.listened })
        }
        .filter { $0.seconds >= 60 }
        .sorted { $0.seconds > $1.seconds }
        .prefix(8)
        .map { $0 }
        return s
    }

    /// Consecutive days with at least a minute of listening, ending today or yesterday.
    static func streak(days: [ListeningDay]) -> Int {
        let calendar = Calendar.current
        let active = Set(Dictionary(grouping: days, by: \.day)
            .filter { $0.value.reduce(0) { $0 + $1.listened } >= 60 }
            .keys)
        var day = calendar.startOfDay(for: .now)
        if !active.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while active.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }
}

extension TimeInterval {
    /// "12h 30m", "45m", "0m"
    var hoursMinutes: String {
        let mins = Int(self / 60)
        return mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
    }
}
