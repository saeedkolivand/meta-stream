import SwiftUI

/// Review a month's Wrapped before it goes public: toggles and per-row exclusions edit what is sent, nothing is
/// published until Publish. Flat, plain system rows like the Session report.
struct WrappedReviewView: View {
    let month: String
    private let base: WrappedDraft?
    private let lang = WrappedStore.lang
    @Environment(\.dismiss) private var dismiss
    @State private var includeDistance = true
    @State private var includeCities = true
    @State private var includeTotal: Bool
    @State private var excluded: Set<String> = []
    @State private var published: Bool
    @State private var busy = false
    @State private var error: String?
    @State private var image: UIImage?

    init(month: String, records: [SessionRecord]) {
        self.month = month
        base = WrappedBuilder.build(month: month, records: records, lang: WrappedStore.lang, showTotal: true)
        _includeTotal = State(initialValue: UserDefaults.standard.object(forKey: "telegramShowTotal") as? Bool ?? true)
        _published = State(initialValue: WrappedStore.months(WrappedStore.published).contains(month))
    }

    /// The base draft with the toggles and exclusions applied: exactly what Publish sends.
    private var draft: WrappedDraft? {
        guard var out = base else { return nil }
        if !includeDistance { out.km = nil }
        if !includeCities { out.cities = [] }
        if !includeTotal { out.donations = nil }
        out.topChatters.removeAll { excluded.contains("c:" + $0.name) }
        out.topDonors.removeAll { excluded.contains("d:" + $0.name) }
        return out
    }

    var body: some View {
        List {
            if let draft {
                Section("Include") {
                    Toggle("Include distance", isOn: $includeDistance)
                    Toggle("Include cities", isOn: $includeCities)
                    Toggle("Include donation total", isOn: $includeTotal)
                }
                summary(draft)
                rows("Top chatters", prefix: "c:", items: base?.topChatters.map { ($0.name, "\($0.messages)") } ?? [])
                rows("Top donors", prefix: "d:", items: base?.topDonors.map { ($0.name, $0.amount) } ?? [])
                actions(draft)
            } else {
                Text("No streams this month").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(WrappedStore.monthName(month) + " Wrapped")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if published, let draft { image = render(draft) } }
    }

    // MARK: parts

    private func summary(_ draft: WrappedDraft) -> some View {
        Section("Will be published") {
            LabeledContent("Streams", value: "\(draft.streams)")
            LabeledContent("Hours", value: String(format: "%.1f", draft.hours))
            if let km = draft.km { LabeledContent("Distance", value: String(format: "%.1f km", km)) }
            if !draft.cities.isEmpty { LabeledContent("Cities", value: draft.cities.joined(separator: ", ")) }
            LabeledContent("Peak viewers", value: "\(draft.peakViewers)")
            LabeledContent("Average viewers", value: "\(draft.avgViewers)")
            LabeledContent("New chatters", value: "\(draft.newChatters)")
            if let money = draft.donations { LabeledContent("Donations", value: "\(money.count) · \(money.total)") }
            if let moment = draft.bestMoment { LabeledContent("Best moment", value: moment.label) }
        }
    }

    @ViewBuilder
    private func rows(_ title: String, prefix: String, items: [(String, String)]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Toggle(isOn: included(prefix + item.0)) {
                        HStack { Text(item.0); Spacer(); Text(item.1).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    private func included(_ key: String) -> Binding<Bool> {
        Binding(get: { !excluded.contains(key) },
                set: { if $0 { excluded.remove(key) } else { excluded.insert(key) } })
    }

    private func actions(_ draft: WrappedDraft) -> some View {
        Section {
            if !DonatePagePublisher.shared.hasToken { Text("Set the donate page key in Settings › Goal first").foregroundStyle(.orange) }
            if let error { Text(error).foregroundStyle(.red) }
            Button(published ? "Publish again" : "Publish") { publish(draft) }
                .disabled(busy || !DonatePagePublisher.shared.hasToken)
            if published {
                if let url = URL(string: WrappedPublisher.pageLink(month: month)) { Link("Open the page", destination: url) }
                if let image {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Wrapped", image: Image(uiImage: image)))
                }
                Button("Withdraw", role: .destructive) { withdraw() }.disabled(busy)
            }
            Button("Not this month") {
                WrappedStore.add(month, to: WrappedStore.dismissed)
                dismiss()
            }
        }
    }

    // MARK: actions

    /// ponytail: the image is rendered on appear (when already published) and after a publish, not when a toggle changes.
    private func render(_ draft: WrappedDraft) -> UIImage? {
        let host = DonatePagePublisher.shared.chatURL.replacingOccurrences(of: "https://", with: "")
        let renderer = ImageRenderer(content: WrappedShareCard(draft: draft, lang: lang, host: host))
        renderer.scale = 3
        return renderer.uiImage
    }

    private func publish(_ draft: WrappedDraft) {
        busy = true
        error = nil
        Task {
            let failure = await WrappedPublisher.publish(draft)
            busy = false
            error = failure
            guard failure == nil else { return }
            WrappedStore.add(month, to: WrappedStore.published)
            published = true
            image = render(draft)
        }
    }

    private func withdraw() {
        busy = true
        error = nil
        Task {
            let failure = await WrappedPublisher.withdraw(month: month)
            busy = false
            error = failure
            guard failure == nil else { return }
            WrappedStore.remove(month, from: WrappedStore.published)
            published = false
            image = nil
        }
    }
}
