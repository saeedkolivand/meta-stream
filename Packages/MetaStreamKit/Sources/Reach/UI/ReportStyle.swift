import SwiftUI

/// Shared look of the Session report and the Streams list: flat dark cards, small gray section labels.
extension View {
    public func reportCard(_ fill: Color = Color(.secondarySystemGroupedBackground)) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// "MOMENTS" style label above a card.
public struct ReportLabel: View {
    public let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            .padding(.leading, 16).padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

extension Moment.Kind {
    /// Chat spike blue, donation green, raid orange: the dot in the list and the marker on the chart.
    public var tint: Color {
        switch self {
        case .chatSpike: return .blue
        case .donation: return .green
        case .raid: return .orange
        }
    }
}

extension Moment {
    /// Today's wording for a moment.
    public var label: String {
        switch kind {
        case .chatSpike: return "Chat spike (\(detail))"
        case .donation: return "\(detail) from \(user)"
        case .raid: return "Raid from \(user) (\(detail) viewers)"
        }
    }
}

/// Moments list: coloured dot, text, clock time.
public struct ReportMomentsCard: View {
    public let moments: [Moment]

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ReportLabel("Moments")
            VStack(spacing: 0) {
                ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                    HStack(spacing: 12) {
                        Circle().fill(moment.kind.tint).frame(width: 10, height: 10)
                        Text(moment.label).font(.subheadline)
                        Spacer(minLength: 8)
                        Text(LivePostText.hhmm(moment.at)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 48)
                    .accessibilityElement(children: .combine)
                    if index < moments.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
