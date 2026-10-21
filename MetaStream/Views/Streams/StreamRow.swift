import Charts
import SwiftUI

/// One session in the Streams list: title, "Tue 21 Oct · 1 h 42 m · €45", viewers sparkline, peak.
struct StreamRow: View {
    let record: SessionRecord

    private var meta: String {
        var parts = [ReportInsights.day(record.start), ReportInsights.span(record.duration)]
        if record.donationTotal > 0 { parts.append(Money(record.donationTotal, record.currency).display) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title.isEmpty ? "Untitled stream" : record.title).font(.headline).lineLimit(1)
                Text(meta).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            // ponytail: every sample is drawn, no downsampling; a 10 h stream is ~600 points, still cheap at 64 pt wide.
            Chart(record.samples, id: \.minute) { sample in
                LineMark(x: .value("Minute", sample.minute), y: .value("Viewers", sample.viewers)).foregroundStyle(.green)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(width: 64, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(record.peakViewers)").font(.headline).monospacedDigit()
                Text("peak").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 34, alignment: .trailing)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}
