import SwiftUI

extension Rates {
    /// Toman per euro: the user's own rate if set, else Nobitex toman x ECB euro.
    var tomanPerEuro: Decimal? {
        if manualTomanPerEUR > 0 { return manualTomanPerEUR }
        guard let toman = tomanRate(), let euro = usdPerEUR?.value else { return nil }
        return toman * euro
    }
}

/// Settings › Goal › Rates: the exchange rates behind the goal and what subs and Bits are worth in it.
struct GoalRatesView: View {
    @ObservedObject private var rates = Rates.shared
    @AppStorage("goalManualTomanPerEUR") private var manualRate = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Toman rate", value: rates.tomanSource)
                LabeledContent("₮ per €", value: rates.tomanPerEuro.map { Money($0, "IRT").display } ?? "No rate")
                TextField("Your rate (₮ per €)", text: $manualRate).keyboardType(.decimalPad)
                Button("Refresh rates") { Task { await rates.refresh() } }
            } header: { Text("Rates") } footer: {
                Text("Toman from Nobitex, euro from the ECB. Your rate replaces Nobitex; empty = Nobitex.")
            }
            Section {
                ForEach([("kickSub", "Kick sub"), ("twitchTier1", "Twitch Tier 1 / Prime"), ("twitchTier2", "Twitch Tier 2"),
                         ("twitchTier3", "Twitch Tier 3"), ("youtubeMember", "YouTube membership"), ("bit", "Bit"), ("kick", "KICK")],
                        id: \.0) { PriceField(key: $0.0, label: $0.1) }
            } header: { Text("Values (US dollars)") } footer: {
                Text("What each counts for in the goal.")
            }
        }
        .navigationTitle("Rates")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One editable dollar price (DonationPrices); saves as soon as the text is a number.
private struct PriceField: View {
    let key: String
    let label: String
    @State private var text = ""

    var body: some View {
        LabeledContent(label) {
            TextField("0", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
        .onAppear { text = "\(DonationPrices.price(key))" }
        .onChange(of: text) { _, new in
            if let price = Decimal(string: new.replacingOccurrences(of: ",", with: ".")) { DonationPrices.set(key, price) }
        }
    }
}

/// Settings › Goal › Recent donations: the last 50, newest first; swipe to remove one from the total.
struct GoalRecentView: View {
    @ObservedObject private var goal = GoalStore.shared

    private func money(_ amount: Decimal) -> String { Money(amount, goal.config.currency).display }

    var body: some View {
        Form {
            Section {
                if goal.entries.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                ForEach(goal.entries.prefix(50)) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(e.original.display).font(.body.weight(.semibold))
                            if let val = e.value, e.original.inToman.currency != goal.config.currency {
                                Text("= \(money(val))").foregroundStyle(.secondary)
                            }
                            Spacer()
                            badges(e)
                        }
                        // who, what (sub, KICKs, bits...) and their message
                        if !e.note.isEmpty { Text(e.note).font(.subheadline).lineLimit(2) }
                        Text("\(e.source.capitalized) · \(e.at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .swipeActions {   // a test that counted, a mistake: out of the total, kept in the list as refunded
                        if e.state == .counted || e.state == .pending {
                            Button("Remove", role: .destructive) { goal.refund(e.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent donations")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func badges(_ e: GoalStore.Entry) -> some View {
        HStack(spacing: 4) {
            if e.state == .pending { badge("pending", .orange) }
            if e.state == .refunded { badge("refunded", .red) }
            if e.state == .test { badge("test", .blue) }
            if e.missed { badge("missed", .gray) }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.15), in: Capsule())
    }
}
