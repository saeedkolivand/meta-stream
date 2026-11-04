import Foundation

/// Chart data, takeaways and the connection facts of a Session report.
extension ReportInsights {
    public enum Tab: String, CaseIterable, Identifiable {
        case viewers = "Viewers", chat = "Chat", bitrate = "Bitrate"
        public var id: String { rawValue }
    }

    public struct Point: Identifiable {
        public let date: Date
        public let value: Double
        public var id: Date { date }
    }

    public struct Chatter: Identifiable {
        public let id: String
        public let name: String
        public let count: Int
    }

    /// A sample's minute counts from 1, as the heatmap reads it.
    public func date(_ sample: SessionSample) -> Date { record.start.addingTimeInterval(Double(sample.minute - 1) * 60) }
    public func clock(_ sample: SessionSample) -> String { LivePostText.hhmm(date(sample)) }

    public func series(_ tab: Tab) -> [Point] {
        record.samples.map { sample in
            switch tab {
            case .viewers: return Point(date: date(sample), value: Double(sample.viewers))
            case .chat: return Point(date: date(sample), value: Double(sample.chat))
            case .bitrate: return Point(date: date(sample), value: Double(sample.kbps) / 1000)
            }
        }
    }

    /// Start, middle and end of the stream for the x axis.
    public var axisDates: [Date] {
        let last = record.samples.last.map(date) ?? record.start
        let stop = max(last, record.start.addingTimeInterval(60))
        return [record.start, record.start.addingTimeInterval(stop.timeIntervalSince(record.start) / 2), stop]
    }

    // MARK: takeaways

    public var peakSample: SessionSample? { record.samples.max { $0.viewers < $1.viewers } }

    public func takeaway(_ tab: Tab) -> String {
        switch tab {
        case .viewers: return viewersTakeaway
        case .chat: return chatTakeaway
        case .bitrate: return bitrateTakeaway
        }
    }

    private var viewersTakeaway: String {
        guard let peak = peakSample, peak.viewers > 0 else { return "No viewers counted" }
        return "Peak \(peak.viewers) at \(clock(peak))"
    }

    private var chatTakeaway: String {
        guard let busiest = record.samples.max(by: { $0.chat < $1.chat }), busiest.chat > 0 else { return "No chat this stream" }
        return "Busiest minute \(clock(busiest)) · \(busiest.chat) messages"
    }

    public var avgMbps: Double? {
        let live = record.samples.map(\.kbps).filter { $0 > 0 }
        return live.isEmpty ? nil : Double(live.reduce(0, +)) / Double(live.count) / 1000
    }

    private var bitrateTakeaway: String {
        guard let avg = avgMbps else { return "No bitrate recorded" }
        var text = "Average " + String(format: "%.1f", avg) + " Mbps"
        if let dip = record.samples.first(where: { Double($0.kbps) / 1000 < avg / 2 }) { text += "; it dipped around \(clock(dip))" }
        return text
    }

    // MARK: audience and connection

    public var topChatters: [Chatter] {
        let sorted = record.chatterCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        return sorted.prefix(3).map { Chatter(id: $0.key, name: record.chatterNames[$0.key] ?? $0.key, count: $0.value) }
    }

    public var drops: Int { record.samples.last?.drops ?? 0 }
    public var downSeconds: Int { record.samples.last?.downSeconds ?? 0 }
    public var downText: String { downSeconds >= 60 ? "\(downSeconds / 60) m \(downSeconds % 60) s" : "\(downSeconds) s" }
    public var solid: Bool { drops == 0 && downSeconds == 0 }
    public var connectionVerdict: String { solid ? "Solid the whole way" : "\(drops) drops · \(downSeconds) s down" }

    /// Audio sync range; "In sync" when every minute stayed within 60 ms.
    public var audioSync: String? {
        let skews = record.samples.compactMap(\.skewMs)
        guard let low = skews.min(), let high = skews.max() else { return nil }
        let range = "\(low) to \(high) ms"
        return skews.allSatisfy { abs($0) <= 60 } ? "In sync (\(range))" : "Off by up to \(max(abs(low), abs(high))) ms (\(range))"
    }
}
