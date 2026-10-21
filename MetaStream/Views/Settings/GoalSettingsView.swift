import SwiftUI

/// Settings › Goal: the donation goal, manual and test donations; rates and the donation list are one level down.
/// The donation-site keys and the donate page have their own screens. Money is Decimal throughout (parsed from text, never Double).
struct GoalSettingsView: View {
    @EnvironmentObject var chat: ChatFeed
    @ObservedObject private var goal = GoalStore.shared
    @ObservedObject private var rates = Rates.shared

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
            addSection
            testSection
            subScreensSection
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

    private var subScreensSection: some View {
        Section {
            NavigationLink { GoalRatesView() } label: {
                LabeledContent("Rates", value: rates.tomanPerEuro.map { Money($0, "IRT").display } ?? "")
            }
            NavigationLink { GoalRecentView() } label: {
                LabeledContent("Recent donations", value: "\(goal.entries.count)")
            }
        } footer: {
            Text("Exchange rates, what subs and Bits are worth, and the donation list.")
        }
    }

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
                goal.reset(title: title, target: parse(target) ?? goal.config.target,
                           currency: goal.config.currency, start: parse(start) ?? 0)
                currency = goal.config.currency
            }
        } header: { Text("Goal") } footer: {
            Text("Donations are counted in the goal's currency when they arrive and keep that value. "
                     + "Another currency starts a new goal; reset clears the list.")
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
}
