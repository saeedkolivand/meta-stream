import SwiftUI

/// The shareable Wrapped image, designed at 360x640 points (9:16) and rendered at scale 3 (1080x1920). Flat and
/// minimal: black, big numbers, no blur. Persian text is RTL by script but the layout stays LTR.
struct WrappedShareCard: View {
    let draft: WrappedDraft
    let lang: String
    let host: String

    private struct Stat: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private func tr(_ key: String) -> String { LivePostText.tr(key, lang) }

    private var stats: [Stat] {
        var out = [Stat(label: tr("wrappedStreams"), value: "\(draft.streams)"),
                   Stat(label: tr("wrappedHours"), value: String(format: "%.1f", draft.hours))]
        if let km = draft.km { out.append(Stat(label: tr("wrappedKm"), value: String(format: "%.1f", km))) }
        out.append(Stat(label: tr("wrappedPeak"), value: "\(draft.peakViewers)"))
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wrapped").font(.system(size: 34, weight: .bold))
                Text(WrappedStore.monthName(draft.month, lang: lang)).font(.system(size: 18)).foregroundStyle(.gray)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                ForEach(stats) { stat in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stat.value).font(.system(size: 44, weight: .bold).monospacedDigit())
                        Text(stat.label).font(.system(size: 14)).foregroundStyle(.gray)
                    }
                }
            }
            if !draft.topChatters.isEmpty { chatters }
            if let moment = draft.bestMoment {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("wrappedBest")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.gray)
                    Text(moment.label).font(.system(size: 16))
                }
            }
            Spacer(minLength: 0)
            Text(host).font(.system(size: 14)).foregroundStyle(.gray)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(width: 360, height: 640, alignment: .topLeading)
        .background(Color.black)
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.colorScheme, .dark)
    }

    private var chatters: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("wrappedTop")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.gray)
            ForEach(Array(draft.topChatters.prefix(3).enumerated()), id: \.offset) { _, chatter in
                HStack {
                    Text(chatter.name).lineLimit(1)
                    Spacer()
                    Text("\(chatter.messages)").monospacedDigit().foregroundStyle(.gray)
                }
                .font(.system(size: 16))
            }
        }
    }
}
