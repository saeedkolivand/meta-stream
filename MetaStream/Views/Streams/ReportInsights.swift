import Foundation

/// The numbers and sentences the Session report derives from one record and the older ones. Pure: no disk, no views.
struct ReportInsights {
    struct Delta: Identifiable {
        let label: String
        let value: String
        /// Change against the baseline in percent; nil when the baseline is 0.
        let percent: Int?
        var id: String { label }
    }

    let record: SessionRecord
    /// Every saved session; the record itself may or may not be among them.
    let history: [SessionRecord]

    private var others: [SessionRecord] { history.filter { $0.start != record.start } }

    /// Up to 10 sessions before this one, newest first.
    var baseline: [SessionRecord] {
        Array(others.filter { $0.start < record.start }.sorted { $0.start > $1.start }.prefix(10))
    }

    /// Deltas need a baseline worth comparing with.
    var showDeltas: Bool { baseline.count >= 3 }
    var title: String { record.title.isEmpty ? "Untitled stream" : record.title }
    var chatTotal: Int { Self.chat(record) }
    var donationAmount: Double { Self.amount(record) }
    var donationText: String { Money(record.donationTotal, record.currency).display }
    var end: Date { record.end ?? record.start.addingTimeInterval(record.duration) }

    private static func chat(_ rec: SessionRecord) -> Int { rec.samples.map(\.chat).reduce(0, +) }
    private static func amount(_ rec: SessionRecord) -> Double { Double(truncating: rec.donationTotal as NSDecimalNumber) }

    // MARK: verdict

    /// Ranks this stream by average viewers among the month's streams; with fewer than 3 there is nothing to rank.
    var verdict: String {
        let month = WrappedBuilder.monthKey(record.start)
        let peers = others.filter { WrappedBuilder.monthKey($0.start) == month }
        if peers.count + 1 < 3 {
            return peers.contains { $0.start < record.start } ? "Your second stream this month" : "Your first stream this month"
        }
        let rank = peers.filter { $0.avgViewers > record.avgViewers }.count + 1
        return rank == 1 ? "Your best stream this month" : "Your \(Self.ordinal(rank)) best stream this month"
    }

    var deltas: [Delta] {
        let past = baseline
        let viewers = Self.percent(Double(record.avgViewers), against: past.map { Double($0.avgViewers) })
        let chat = Self.percent(Double(chatTotal), against: past.map { Double(Self.chat($0)) })
        let money = Self.percent(donationAmount, against: past.map { Self.amount($0) })
        return [Delta(label: "Average viewers", value: "\(record.avgViewers)", percent: viewers),
                Delta(label: "Chat messages", value: "\(chatTotal)", percent: chat),
                Delta(label: "Donations", value: donationText, percent: money)]
    }

    private static func percent(_ now: Double, against past: [Double]) -> Int? {
        let mean = past.reduce(0, +) / Double(max(past.count, 1))
        return mean > 0 ? Int(((now - mean) / mean * 100).rounded()) : nil
    }

    static func ordinal(_ value: Int) -> String {
        let format = NumberFormatter()
        format.numberStyle = .ordinal
        format.locale = Locale(identifier: "en_US")
        return format.string(from: NSNumber(value: value)) ?? "\(value)th"
    }

    // MARK: words

    /// "1 h 42 m", "58 m".
    static func span(_ time: TimeInterval) -> String {
        let minutes = max(0, Int(time)) / 60
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) m" : "\(minutes) m"
    }

    /// "Tue 21 Oct".
    static func day(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "EEE d MMM"
        return format.string(from: date)
    }

    var dateLine: String {
        let range = LivePostText.hhmm(record.start) + "–" + LivePostText.hhmm(end)
        return [Self.day(record.start), range, Self.span(record.duration)].joined(separator: " · ")
    }

    /// Plain text for the Share button.
    var summary: String {
        var lines = [title, dateLine, verdict, "Peak viewers \(record.peakViewers), average \(record.avgViewers)"]
        lines.append("Chat messages \(chatTotal)")
        if record.donationCount > 0 { lines.append("Donations \(donationText) (\(record.donationCount))") }
        lines.append("Chatters \(record.chatterCounts.count)")
        return lines.joined(separator: "\n")
    }
}
