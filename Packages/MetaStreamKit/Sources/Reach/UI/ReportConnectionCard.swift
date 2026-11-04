import Charts
import SwiftUI

/// Connection health: a verdict, the numbers, and per-minute bitrate and audio sync charts behind a disclosure.
struct ReportConnectionCard: View {
    let insights: ReportInsights
    @State private var showCharts = false

    private var rows: [(key: String, value: String)] {
        var out: [(key: String, value: String)] = [("Drops", "\(insights.drops)"), ("Downtime", insights.downText)]
        if let mbps = insights.avgMbps { out.append(("Average bitrate", String(format: "%.1f Mbps", mbps))) }
        if let sync = insights.audioSync { out.append(("Audio sync", sync)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ReportLabel("Connection")
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Circle().fill(insights.solid ? Color.green : Color.orange).frame(width: 10, height: 10)
                    Text(insights.connectionVerdict).font(.headline)
                    Spacer()
                }
                .padding(.vertical, 14)
                ForEach(rows, id: \.key) { row in
                    Divider()
                    HStack {
                        Text(row.key)
                        Spacer(minLength: 12)
                        Text(row.value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
                Divider()
                Button(showCharts ? "Hide charts" : "Show bitrate and audio charts") { withAnimation { showCharts.toggle() } }
                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                if showCharts { charts }
            }
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: 16) {
            MinuteChart(title: "Bitrate (kbps)", color: .white, points: points { $0.kbps })
            if insights.record.samples.contains(where: { $0.skewMs != nil }) {
                MinuteChart(title: "Audio sync (ms)", color: .orange, points: points { $0.skewMs })
            }
        }
        .padding(.bottom, 14)
    }

    private func points(_ value: (SessionSample) -> Int?) -> [MinuteChart.Point] {
        insights.record.samples.compactMap { sample in value(sample).map { MinuteChart.Point(id: sample.minute, value: $0) } }
    }
}

/// A small per-minute line chart.
private struct MinuteChart: View {
    struct Point: Identifiable {
        let id: Int
        let value: Int
    }

    let title: String
    let color: Color
    let points: [Point]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Chart(points) { point in
                LineMark(x: .value("Minute", point.id), y: .value("Value", point.value)).foregroundStyle(color)
            }
            .frame(height: 120)
            .accessibilityLabel(title + " per minute")
        }
    }
}
