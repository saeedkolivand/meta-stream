import Charts
import SwiftUI

/// The Session report (CONTEXT.md "Session report"): the streamer's private account of one stream, never posted anywhere.
/// Flat on purpose, like the network panel: plain gray/white/system colors on the dark app.
struct SessionReportView: View {
    let record: SessionRecord

    private struct Stat: Identifiable {
        let label: String
        let value: String
        var note: String?
        var id: String { label }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                    ForEach(stats) { stat in tile(stat) }
                }
                if let cities = record.cities, !cities.isEmpty {
                    Text("Cities: " + cities.joined(separator: ", ")).font(.footnote).foregroundStyle(.gray)
                }
                if !record.moments.isEmpty { momentsList }
                SessionCharts(record: record)
            }
            .padding()
        }
        .navigationTitle("Session report")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title.isEmpty ? "Untitled stream" : record.title).font(.title3.bold())
            Text(record.start.formatted(date: .abbreviated, time: .shortened) + " · " + LivePostText.duration(record.duration))
                .font(.footnote).foregroundStyle(.gray)
        }
    }

    private var stats: [Stat] {
        let last = record.samples.last
        var out = [Stat(label: "Peak viewers", value: "\(record.peakViewers)"),
                   Stat(label: "Average viewers", value: "\(record.avgViewers)")]
        let total = Money(record.donationTotal, record.currency).display
        var donations = Stat(label: "Donations", value: "\(record.donationCount) · " + total)
        donations.note = record.topDonor.map { "Top: \($0) " + (record.topDonorDisplay ?? "") }
        out.append(donations)
        if record.trackingStarted {
            out.append(Stat(label: "Chatters", value: "\(record.chatterCounts.count)", note: "counting started this stream"))
        } else {
            out.append(Stat(label: "New chatters", value: "\(record.newChatters)"))
            out.append(Stat(label: "Returning chatters", value: "\(record.returningChatters)"))
        }
        let down = last?.downSeconds ?? 0
        out.append(Stat(label: "Drops", value: "\(last?.drops ?? 0)"))
        out.append(Stat(label: "Downtime", value: "\(down / 60)m \(down % 60)s"))
        if let meters = record.distanceMeters { out.append(Stat(label: "Distance", value: String(format: "%.1f km", meters / 1000))) }
        return out
    }

    private func tile(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.label).font(.caption).foregroundStyle(.gray)
            Text(stat.value).font(.body.monospacedDigit())
            if let note = stat.note { Text(note).font(.caption2).foregroundStyle(.gray) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var momentsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MOMENTS").font(.caption.weight(.semibold)).foregroundStyle(.gray)
            ForEach(Array(record.moments.enumerated()), id: \.offset) { _, moment in
                HStack(spacing: 8) {
                    Text(LivePostText.hhmm(moment.at)).font(.footnote.monospacedDigit()).foregroundStyle(.gray)
                    Text(Self.icon(moment))
                    Text(Self.label(moment)).font(.footnote)
                }
            }
        }
    }

    static func icon(_ moment: Moment) -> String {
        switch moment.kind {
        case .chatSpike: return "🔥"
        case .donation: return "💸"
        case .raid: return "🚀"
        }
    }

    private static func label(_ moment: Moment) -> String {
        switch moment.kind {
        case .chatSpike: return "Chat spike (\(moment.detail))"
        case .donation: return "\(moment.detail) from \(moment.user)"
        case .raid: return "Raid from \(moment.user) (\(moment.detail) viewers)"
        }
    }
}

/// Small per-minute charts: viewers (with the Moments marked), chat, bitrate and, when the mix reported it, audio skew.
private struct SessionCharts: View {
    let record: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MinuteChart(title: "VIEWERS PER MINUTE", style: .line, color: .green, points: points { $0.viewers }, rules: rules)
            MinuteChart(title: "CHAT PER MINUTE", style: .bar, color: .blue, points: points { $0.chat })
            MinuteChart(title: "BITRATE (KBPS)", style: .line, color: .white, points: points { $0.kbps })
            if record.samples.contains(where: { $0.skewMs != nil }) {
                MinuteChart(title: "AUDIO SKEW (MS)", style: .line, color: .orange, points: points { $0.skewMs })
            }
        }
    }

    private func points(_ value: (SessionSample) -> Int?) -> [MinuteChart.Point] {
        record.samples.compactMap { sample in value(sample).map { MinuteChart.Point(id: sample.minute, value: $0) } }
    }

    private var rules: [MinuteChart.Rule] {
        record.moments.enumerated().map { index, moment in
            let minute = Int(moment.at.timeIntervalSince(record.start) / 60) + 1
            return MinuteChart.Rule(id: index, minute: minute, icon: SessionReportView.icon(moment))
        }
    }
}

private struct MinuteChart: View {
    enum Style { case line, bar }
    struct Point: Identifiable {
        let id: Int
        let value: Int
    }
    struct Rule: Identifiable {
        let id: Int
        let minute: Int
        let icon: String
    }

    let title: String
    let style: Style
    let color: Color
    let points: [Point]
    var rules: [Rule] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.gray)
            Chart {
                ForEach(style == .line ? points : []) { point in
                    LineMark(x: .value("Minute", point.id), y: .value("Value", point.value)).foregroundStyle(color)
                }
                ForEach(style == .bar ? points : []) { point in
                    BarMark(x: .value("Minute", point.id), y: .value("Value", point.value)).foregroundStyle(color)
                }
                ForEach(rules) { rule in
                    RuleMark(x: .value("Moment", rule.minute))
                        .foregroundStyle(Color.orange.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                        .annotation(position: .top, spacing: 0) { Text(rule.icon).font(.caption2) }
                }
            }
            .frame(height: 140)
        }
    }
}
