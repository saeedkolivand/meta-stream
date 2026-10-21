import SwiftUI

/// Who showed up: chatters split new / returning, the three most active, the top donor.
struct ReportAudienceCard: View {
    let insights: ReportInsights

    private var record: SessionRecord { insights.record }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ReportLabel("Audience")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(record.chatterCounts.count) chatters")
                    Spacer()
                    Text(split).font(.footnote).foregroundStyle(.secondary)
                }
                if !record.trackingStarted, record.newChatters + record.returningChatters > 0 { splitBar }
                active
                if let donor = record.topDonor { donorRow(donor) }
            }
            .font(.subheadline)
            .reportCard()
        }
    }

    private var split: String {
        record.trackingStarted ? "counting started this stream" : "\(record.newChatters) new · \(record.returningChatters) returning"
    }

    private var splitBar: some View {
        let total = Double(record.newChatters + record.returningChatters)
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                Color.blue.frame(width: proxy.size.width * Double(record.newChatters) / total)
                Color.indigo
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder private var active: some View {
        let top = insights.topChatters
        if let most = top.first?.count {
            Text("Most active").font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
            ForEach(top) { chatter in
                HStack(spacing: 10) {
                    Text(chatter.name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Capsule().fill(Color(.tertiarySystemFill)).frame(width: 120, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.blue).frame(width: 120 * Double(chatter.count) / Double(most), height: 6)
                        }
                    Text("\(chatter.count)").foregroundStyle(.secondary).monospacedDigit().frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func donorRow(_ donor: String) -> some View {
        VStack(spacing: 10) {
            Divider()
            HStack {
                Text("Top donor")
                Spacer()
                Text(donor + (record.topDonorDisplay.map { " · " + $0 } ?? "")).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }
}
