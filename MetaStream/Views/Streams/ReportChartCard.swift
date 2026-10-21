import Charts
import SwiftUI

/// One chart for the stream: Viewers | Chat | Bitrate, the Moments marked, with a one-line takeaway under it.
struct ReportChartCard: View {
    let insights: ReportInsights
    @State private var tab = ReportInsights.Tab.viewers

    private var tint: Color {
        switch tab {
        case .viewers: return .green
        case .chat: return .blue
        case .bitrate: return .white
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Chart", selection: $tab) {
                ForEach(ReportInsights.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            chart
            Text(insights.takeaway(tab)).font(.footnote).foregroundStyle(.secondary)
        }
        .reportCard()
    }

    private var chart: some View {
        let points = insights.series(tab)
        let dates = insights.axisDates
        return Chart {
            ForEach(points) { point in
                if tab == .chat {
                    BarMark(x: .value("Time", point.date, unit: .minute), y: .value("Messages", point.value)).foregroundStyle(tint)
                } else {
                    AreaMark(x: .value("Time", point.date), y: .value("Value", point.value)).foregroundStyle(tint.opacity(0.18))
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value)).foregroundStyle(tint)
                }
            }
            ForEach(Array(insights.record.moments.enumerated()), id: \.offset) { _, moment in
                RuleMark(x: .value("Moment", moment.at))
                    .foregroundStyle(moment.kind.tint.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    .annotation(position: .top, spacing: 0) { Circle().fill(moment.kind.tint).frame(width: 8, height: 8) }
            }
        }
        .chartXScale(domain: dates[0]...dates[2])
        .chartXAxis {
            AxisMarks(values: dates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(LivePostText.hhmm(date)) }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) }
        .frame(height: 170)
        .padding(.top, 10)
        .accessibilityLabel("\(tab.rawValue) per minute")
        .accessibilityValue(insights.takeaway(tab))
    }
}
