import Foundation

extension HeatmapView {
    /// "Sunday 18:00-19:00, 26 viewers on average": the strongest slot seen in at least 2 streams. Nil below the
    /// heatmap's own minimum of streams, and when no slot has enough data.
    static func bestSlot(_ records: [SessionRecord]) -> String? {
        guard records.count >= minStreams else { return nil }
        guard let best = cells(records, .viewers).filter(\.enough).max(by: { $0.value < $1.value }) else { return nil }
        let day = Calendar.current.weekdaySymbols[(best.weekday + 1) % 7]   // weekday 0 = Monday, symbols start Sunday
        let hour = { (value: Int) in String(format: "%02d:00", value % 24) }
        return "\(day) \(hour(best.hour))\u{2013}\(hour(best.hour + 1)), \(Int(best.value.rounded())) viewers on average"
    }
}
