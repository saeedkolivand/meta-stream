import SwiftUI

/// "How it went": the verdict against the month, then three numbers with their change against the last streams.
struct ReportOverviewCard: View {
    let insights: ReportInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How it went").font(.footnote.weight(.semibold)).textCase(.uppercase).foregroundStyle(.green)
            Text(insights.verdict).font(.title3.bold())
            if insights.showDeltas {
                Text("Compared with your last \(insights.baseline.count) streams").font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 9) {
                    ForEach(insights.deltas) { row($0) }
                }
                .padding(.top, 10)
            }
        }
        .reportCard(Color(red: 0.075, green: 0.141, blue: 0.102))
    }

    private func row(_ delta: ReportInsights.Delta) -> some View {
        HStack(spacing: 10) {
            Text(delta.label).frame(maxWidth: .infinity, alignment: .leading)
            Text(delta.value).fontWeight(.bold).monospacedDigit()
            if let percent = delta.percent { chip(percent) }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ percent: Int) -> some View {
        let up = percent >= 0
        return Text(up ? "+\(percent)%" : "\u{2212}\(-percent)%")
            .font(.footnote.weight(.bold)).monospacedDigit()
            .frame(minWidth: 58)
            .padding(.vertical, 2)
            .background(up ? Color.green.opacity(0.25) : Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(up ? Color.green : Color.orange)
    }
}

/// The 2x2 grid of big numbers.
struct ReportTiles: View {
    let insights: ReportInsights

    private struct Tile: Identifiable {
        let label: String
        let value: String
        let note: String
        var id: String { label }
    }

    private var tiles: [Tile] {
        let record = insights.record
        let peak = insights.peakSample.map { "at " + insights.clock($0) } ?? ""
        let count = record.donationCount
        let chatters = record.trackingStarted ? "counting started this stream" : "\(record.newChatters) new"
        return [Tile(label: "Peak viewers", value: "\(record.peakViewers)", note: peak),
                Tile(label: "Average viewers", value: "\(record.avgViewers)", note: ""),
                Tile(label: "Donations", value: insights.donationText, note: count == 1 ? "1 donation" : "\(count) donations"),
                Tile(label: "Chatters", value: "\(record.chatterCounts.count)", note: chatters)]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(tiles) { tile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.label).font(.footnote).foregroundStyle(.secondary)
                    Text(tile.value).font(.title.weight(.heavy)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    Text(tile.note).font(.footnote).foregroundStyle(.secondary)
                }
                .reportCard()
                .accessibilityElement(children: .combine)
            }
        }
    }
}
