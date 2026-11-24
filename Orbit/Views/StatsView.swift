import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Query private var days: [ListeningDay]
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }) private var podcasts: [Podcast]
    @Environment(\.theme) private var theme
    @State private var range: ListeningStats.Range = .week
    @State private var selected: Date?

    var body: some View {
        let summary = ListeningStats.summary(range, days: days)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Range", selection: $range) {
                    ForEach(ListeningStats.Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    Tile(label: "Listening Time", value: summary.listened.hoursMinutes)
                    Tile(label: "Time Saved", value: summary.saved.hoursMinutes, note: "From playback speed")
                    Tile(label: "Episodes Finished", value: "\(summary.finished)")
                    Tile(label: "Day Streak", value: "\(summary.streak)")
                }

                chart(summary)

                if !summary.topShows.isEmpty {
                    topShows(summary)
                }
            }
            .padding()
        }
        .overlay {
            if days.isEmpty {
                ContentUnavailableView("No Listening Yet", systemImage: "chart.bar",
                                       description: Text("Stats appear here after you play episodes."))
            }
        }
        .navigationTitle("Stats")
        .onChange(of: range) { selected = nil }
    }

    // MARK: - Chart

    private func chart(_ summary: ListeningStats.Summary) -> some View {
        let unit = summary.bucketUnit
        // Whole hours on the axis once any bar passes an hour, minutes below that.
        let useHours = (summary.buckets.map(\.seconds).max() ?? 0) >= 3600
        let divisor: Double = useHours ? 3600 : 60
        let picked = selected.flatMap { date in
            summary.buckets.first { Calendar.current.isDate($0.date, equalTo: date, toGranularity: unit) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(range == .allTime ? "Monthly Listening" : "Daily Listening")
                    .font(.headline)
                Spacer()
                if let picked {
                    Text("\(picked.date.formatted(unit == .month ? .dateTime.month(.abbreviated).year() : .dateTime.day().month(.abbreviated))): \(picked.seconds.hoursMinutes)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Chart(summary.buckets) { bucket in
                BarMark(x: .value("Date", bucket.date, unit: unit),
                        y: .value(useHours ? "Hours" : "Minutes", bucket.seconds / divisor))
                    .foregroundStyle(theme.color.opacity(picked == nil || picked?.date == bucket.date ? 1 : 0.35))
                    .cornerRadius(4)
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4, roundLowerBound: true, roundUpperBound: true)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(useHours ? Self.hoursLabel(amount) : "\(Int(amount))m")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: range == .month ? 5 : 7)) { _ in
                    AxisValueLabel(format: unit == .month ? .dateTime.month(.narrow) : (range == .week ? .dateTime.weekday(.narrow) : .dateTime.day()))
                }
            }
            .frame(height: 180)
            .accessibilityLabel(range == .allTime ? "Monthly listening" : "Daily listening")
        }
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static func hoursLabel(_ hours: Double) -> String {
        hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }

    // MARK: - Top shows

    private func topShows(_ summary: ListeningStats.Summary) -> some View {
        let top = summary.topShows.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            Text("Top Shows").font(.headline)
            ForEach(summary.topShows) { show in
                let podcast = podcasts.first { $0.feedURL.absoluteString == show.feed }
                HStack(spacing: 12) {
                    ArtworkView(url: podcast?.artworkURL, seed: show.title, cornerRadius: 6)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(show.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(show.seconds.hoursMinutes)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            Capsule()
                                .fill(theme.color)
                                .frame(width: max(4, geo.size.width * show.seconds / top), height: 4)
                        }
                        .frame(height: 4)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct Tile: View {
    let label: String
    let value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(note ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
