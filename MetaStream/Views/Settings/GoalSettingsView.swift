import SwiftUI

/// Settings › Goal: the donation goal, the rates behind it, what subs/Bits are worth, manual and test donations,
/// and the donation-site keys. Money is Decimal throughout (parsed from text, never Double).
struct GoalSettingsView: View {
    @EnvironmentObject var chat: ChatFeed
    @ObservedObject private var goal = GoalStore.shared
    @ObservedObject private var rates = Rates.shared
    @ObservedObject private var hub = DonationHub.shared
    @AppStorage("goalManualTomanPerEUR") private var manualRate = ""

    @State private var title = ""
    @State private var target = ""
    @State private var start = ""
    @State private var currency = "EUR"
    @State private var loaded = false

    @State private var addAmount = ""
    @State private var addCurrency = "EUR"
    @State private var addNote = ""
    @State private var testAmount = "10"
    @State private var testCurrency = "EUR"

    private static let currencies = [("IRT", "Toman"), ("EUR", "Euro"), ("USD", "US dollar")]

    private func parse(_ s: String) -> Decimal? {
        Decimal(string: s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func money(_ d: Decimal) -> String { Money(d, goal.config.currency).display }

    var body: some View {
        Form {
            goalSection
            statusSection
            ratesSection
            valuesSection
            addSection
            testSection
            sourcesSection
            recentSection
        }
        .navigationTitle("Goal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let c = goal.config
            title = c.title; target = "\(c.target)"; start = "\(c.start)"; currency = c.currency
        }
    }

    // MARK: sections

    private var goalSection: some View {
        Section {
            TextField("Title", text: $title)
            TextField("Target", text: $target).keyboardType(.decimalPad)
            TextField("Already raised", text: $start).keyboardType(.decimalPad)
            Picker("Currency", selection: $currency) {
                ForEach(Self.currencies, id: \.0) { Text($0.1).tag($0.0) }
            }
            if currency == goal.config.currency {
                Button("Save") {
                    if let t = parse(target), let s = parse(start) { goal.update(title: title, target: t, start: s) }
                }
                .disabled(parse(target) == nil || parse(start) == nil)
            } else {
                Button("Start a new goal in \(Money(0, currency).display.dropLast())", role: .destructive) {
                    if let t = parse(target), let s = parse(start) { goal.reset(title: title, target: t, currency: currency, start: s) }
                }
                .disabled(parse(target) == nil || parse(start) == nil)
            }
            Button("Reset goal", role: .destructive) {
                goal.reset(title: title, target: parse(target) ?? goal.config.target, currency: goal.config.currency, start: parse(start) ?? 0)
                currency = goal.config.currency
            }
        } header: { Text("Goal") } footer: {
            Text("Donations are counted in the goal's currency when they arrive and keep that value. Another currency starts a new goal; reset clears the list.")
        }
    }

    private var statusSection: some View {
        Section("Status") {
            let pct = Int(goal.progress * 100)
            LabeledContent("Raised", value: "\(money(goal.total)) / \(money(goal.config.target)) (\(pct)%)")
            if goal.pendingCount > 0 {
                LabeledContent("Waiting for a rate", value: "\(goal.pendingCount)")
            }
        }
    }

    private var ratesSection: some View {
        Section {
            LabeledContent("Toman rate", value: rates.tomanSource)
            LabeledContent("₮ per €", value: tomanPerEuro.map { Money($0, "IRT").display } ?? "No rate")
            TextField("Your rate (₮ per €)", text: $manualRate).keyboardType(.decimalPad)
            Button("Refresh rates") { Task { await rates.refresh() } }
        } header: { Text("Rates") } footer: {
            Text("Toman from Nobitex, euro from the ECB. Your rate replaces Nobitex; empty = Nobitex.")
        }
    }

    private var tomanPerEuro: Decimal? {
        if rates.manualTomanPerEUR > 0 { return rates.manualTomanPerEUR }
        guard let t = rates.tomanRate(), let e = rates.usdPerEUR?.value else { return nil }
        return t * e
    }

    private var valuesSection: some View {
        Section {
            ForEach([("kickSub", "Kick sub"), ("twitchTier1", "Twitch Tier 1 / Prime"), ("twitchTier2", "Twitch Tier 2"),
                     ("twitchTier3", "Twitch Tier 3"), ("youtubeMember", "YouTube membership"), ("bit", "Bit"), ("kick", "KICK")],
                    id: \.0) { PriceField(key: $0.0, label: $0.1) }
        } header: { Text("Values (US dollars)") } footer: {
            Text("What each counts for in the goal.")
        }
    }

    private var addSection: some View {
        Section {
            TextField("Amount", text: $addAmount).keyboardType(.numbersAndPunctuation)
            Picker("Currency", selection: $addCurrency) { ForEach(Self.currencies, id: \.0) { Text($0.1).tag($0.0) } }
            TextField("Note", text: $addNote)
            Button("Add") {
                if let d = parse(addAmount), d != 0 {
                    goal.addManual(Money(d, addCurrency), note: addNote)
                    addAmount = ""; addNote = ""
                }
            }
            .disabled((parse(addAmount) ?? 0) == 0)
        } header: { Text("Add amount") } footer: {
            Text("Cash or a bank transfer. A negative amount corrects a mistake.")
        }
    }

    private var testSection: some View {
        Section {
            TextField("Amount", text: $testAmount).keyboardType(.decimalPad)
            Picker("Currency", selection: $testCurrency) {
                ForEach(Self.currencies, id: \.0) { Text($0.1).tag($0.0) }
                Text("Bits").tag("BITS")
            }
            Button("Send test donation") {
                if testCurrency == "BITS" {
                    chat.yield(ChatEvent(kind: .cheer, user: "Test", text: "Test donation", count: 100, origin: "test-donation"))
                    goal.test(Money(100 * DonationPrices.price("bit"), "USD"))
                } else if let d = parse(testAmount), d > 0 {
                    let m = Money(d, testCurrency)
                    goal.test(m)
                    chat.yield(ChatEvent(kind: .tip, user: "Test", text: "Test donation", money: m, origin: "test-donation"))
                }
            }
        } header: { Text("Test donation") } footer: {
            Text("Moves the bar for 10 seconds and shows the alert. Bits sends 100 Bits. Not counted.")
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(DonationHub.Site.allCases, id: \.self) { site in
                SiteKeyRow(site: site, status: hub.status[site] ?? "")
            }
        } header: { Text("Donation sources") }
    }

    private var recentSection: some View {
        Section("Recent donations") {
            if goal.entries.isEmpty { Text("None yet").foregroundStyle(.secondary) }
            ForEach(goal.entries.prefix(50)) { e in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(e.original.display).font(.body.weight(.semibold))
                        if let v = e.value, e.original.inToman.currency != goal.config.currency {
                            Text("= \(money(v))").foregroundStyle(.secondary)
                        }
                        Spacer()
                        badges(e)
                    }
                    if !e.note.isEmpty { Text(e.note).font(.subheadline).lineLimit(2) }   // who, what (sub, KICKs, bits...) and their message
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
        .onChange(of: text) { _, v in
            if let d = Decimal(string: v.replacingOccurrences(of: ",", with: ".")) { DonationPrices.set(key, d) }
        }
    }
}

/// A donation site: status, its key (secure) and Save.
private struct SiteKeyRow: View {
    let site: DonationHub.Site
    let status: String
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(site.title).font(.headline)
            if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
            SecureField(site.keyLabel, text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text(site.help).font(.footnote).foregroundStyle(.secondary)
            Button("Save") { DonationHub.shared.setKey(site, key) }.buttonStyle(.borderless)
        }
        .onAppear { key = DonationHub.shared.key(site) }
    }
}
