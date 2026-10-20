import Charts
import SwiftUI

/// The best-time heatmap (Settings > Streams): weekday x hour of day over every recorded sample, in the current time zone.
/// Needs 10 streams; a slot seen in fewer than 2 distinct streams is drawn gray because one stream proves nothing.
struct HeatmapView: View {
    enum Metric: String, CaseIterable, Identifiable {
        case viewers = "Avg viewers", donations = "Donations / h", chatters = "New chatters / h"
        var id: String { rawValue }

        /// One sample's value for this metric; nil when it doesn't count (older files, or nobody watching).
        func value(of sample: SessionSample) -> Double? {
            switch self {
            case .viewers: return sample.viewers > 0 ? Double(sample.viewers) : nil
            case .donations: return sample.donations
            case .chatters: return sample.newChatters.map(Double.init)
            }
        }
    }

    struct Cell: Identifiable {
        let weekday: Int   // 0 = Monday
        let hour: Int
        let value: Double
        let sessions: Int
        var id: Int { weekday * 24 + hour }
        var enough: Bool { sessions >= 2 }
    }

    private struct Bucket {
        var sum = 0.0
        var count = 0
        var sessions: Set<Date> = []
    }

    static let minStreams = 10
    let records: [SessionRecord]
    @State private var metric = Metric.viewers

    var body: some View {
        if records.count < Self.minStreams {
            Text("The best-time heatmap appears after 10 streams (\(records.count) so far)")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Metric", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                chart(Self.cells(records, metric))
                Text("Gray cells: fewer than 2 streams in that slot, not enough data to compare.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: chart

    private func chart(_ cells: [Cell]) -> some View {
        let top = max(cells.filter(\.enough).map(\.value).max() ?? 0, 0.0001)
        let names = Self.dayNames
        return Chart(cells) { cell in
            RectangleMark(xStart: .value("From", Double(cell.hour) - 0.5), xEnd: .value("To", Double(cell.hour) + 0.5),
                          yStart: .value("Day from", Double(6 - cell.weekday) - 0.5),
                          yEnd: .value("Day to", Double(6 - cell.weekday) + 0.5))
                .foregroundStyle(Self.color(cell, top: top))
        }
        .chartXScale(domain: -0.5...23.5)
        .chartYScale(domain: -0.5...6.5)
        .chartXAxis { AxisMarks(values: [0.0, 6.0, 12.0, 18.0, 23.0]) }
        .chartYAxis {
            AxisMarks(values: [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]) { value in
                AxisValueLabel {
                    if let row = value.as(Double.self) { Text(names[max(0, min(names.count - 1, 6 - Int(row)))]) }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 200)
    }

    private static func color(_ cell: Cell, top: Double) -> Color {
        cell.enough ? Color.accentColor.opacity(0.15 + 0.85 * cell.value / top) : Color.gray.opacity(0.15)
    }

    /// Localized short weekday names, Monday first.
    static var dayNames: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        return Array(symbols.dropFirst()) + symbols.prefix(1)
    }

    // MARK: aggregation

    /// Every sample belongs to the (weekday, hour) of `start + (minute - 1) minutes`. Viewers: mean over samples with
    /// viewers; donations and new chatters: the sum scaled to one hour of samples.
    static func cells(_ records: [SessionRecord], _ metric: Metric, calendar: Calendar = .current) -> [Cell] {
        var buckets: [Int: Bucket] = [:]
        for record in records {
            for sample in record.samples {
                guard let value = metric.value(of: sample) else { continue }
                let when = record.start.addingTimeInterval(Double(sample.minute - 1) * 60)
                let parts = calendar.dateComponents([.weekday, .hour], from: when)
                let key = ((parts.weekday ?? 2) + 5) % 7 * 24 + (parts.hour ?? 0)   // Gregorian: 1 = Sunday
                buckets[key, default: Bucket()].sum += value
                buckets[key, default: Bucket()].count += 1
                buckets[key, default: Bucket()].sessions.insert(record.start)
            }
        }
        return buckets.map { key, bucket in
            let value = metric == .viewers ? bucket.sum / Double(bucket.count) : bucket.sum * 60 / Double(bucket.count)
            return Cell(weekday: key / 24, hour: key % 24, value: value, sessions: bucket.sessions.count)
        }
        .sorted { $0.id < $1.id }
    }

    #if DEBUG
    static func demo() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let monday = Date(timeIntervalSince1970: 1_704_067_200 + 10 * 3600)   // Monday 2024-01-01 10:00 UTC
        func record(_ start: Date, viewers: [Int]) -> SessionRecord {
            let samples = viewers.enumerated().map {
                SessionSample(minute: $0.offset + 1, viewers: $0.element, chat: 0, kbps: 0, drops: 0, downSeconds: 0,
                              donations: Double($0.element), newChatters: nil)
            }
            return SessionRecord(start: start, title: "", samples: samples, currency: "EUR")
        }
        let oldSample = SessionSample(minute: 1, viewers: 5, chat: 0, kbps: 0, drops: 0, downSeconds: 0)
        let old = SessionRecord(start: monday.addingTimeInterval(60), title: "", samples: [oldSample], currency: "EUR")
        let recs = [record(monday, viewers: [10, 20]), record(monday.addingTimeInterval(7 * 86400), viewers: [30, 0]), old]
        let avg = cells(recs, .viewers, calendar: cal)
        assert(avg.count == 1 && avg[0].weekday == 0 && avg[0].hour == 10 && avg[0].sessions == 3 && avg[0].value == 16.25)
        let money = cells(recs, .donations, calendar: cal)   // old file skipped; 4 samples sum 60 -> 60 / (4 / 60) per hour
        assert(money.count == 1 && money[0].sessions == 2 && money[0].value == 900)
        assert(cells(recs, .chatters, calendar: cal).isEmpty)
        let late = record(monday.addingTimeInterval(55 * 60), viewers: Array(repeating: 1, count: 10))   // crosses 11:00
        assert(Set(cells([late], .viewers, calendar: cal).map(\.hour)) == [10, 11])
        applog("reach", "HeatmapView.demo() passed")
    }
    #endif
}
