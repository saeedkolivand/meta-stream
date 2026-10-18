// The goal and its ledger (CONTEXT.md: Goal, Donation, Pending/Missed donation; adr/0006). Every donation is recorded
// once under "<source>:<id>", converted into the goal currency when it arrives and kept at that value. Persisted as
// JSON in Application Support, so a goal lasts across streams until the streamer resets it.
import Foundation

@MainActor
final class GoalStore: ObservableObject {
    static let shared = GoalStore()

    struct Config: Codable, Equatable {
        var title = "Goal"
        var target: Decimal = 500
        var currency = "EUR"          // "IRT" (toman), "USD" or "EUR"
        var start: Decimal = 0        // money raised before the app was counting
        var startedAt = Date()        // donations found in a site's history from before this don't count
    }

    enum State: String, Codable { case counted, pending, refunded, test }

    struct Entry: Codable, Identifiable, Equatable {
        let id: String                // "<source>:<id>", the dedupe key
        var source: String            // "kick", "twitch", "youtube", "donofa", "reymit", "streamelements", "manual", "test"
        var original: Money
        var value: Decimal?           // in the goal currency; nil while pending
        var at: Date
        var state: State
        var missed = false            // found afterwards in a site's history: counted, never announced
        var note = ""
    }

    @Published private(set) var config = Config()
    @Published private(set) var entries: [Entry] = []   // newest first
    @Published private(set) var reached = false
    /// Fires once when the total first reaches the target (the widget celebrates, read-aloud says it).
    var onReached: (() -> Void)?

    private static let maxEntries = 1000
    private var file: URL {
        URL.applicationSupportDirectory.appending(path: "goal.json")
    }

    private struct Saved: Codable { var config: GoalStore.Config; var entries: [GoalStore.Entry]; var reached: Bool }

    init() {
        if let d = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            config = s.config; entries = s.entries.filter { $0.state != .test }; reached = s.reached
        }
        Rates.shared.onUpdate = { [weak self] in self?.resolvePending() }
    }

    // MARK: totals

    var total: Decimal {
        entries.reduce(config.start) { sum, e in
            (e.state == .counted || e.state == .test) ? sum + (e.value ?? 0) : sum
        }
    }

    var progress: Double {
        guard config.target > 0 else { return 0 }
        return NSDecimalNumber(decimal: total / config.target).doubleValue
    }

    var pendingCount: Int { entries.filter { $0.state == .pending }.count }

    func knows(_ key: String) -> Bool { entries.contains { $0.id == key } }

    // MARK: recording

    /// Records a donation once per key; false when it's already known (a site's live feed and its history report the
    /// same donation) or it predates the goal. Converted now at the market rate, or left pending without one.
    @discardableResult
    func record(key: String, source: String, money: Money, at: Date = Date(), missed: Bool = false, note: String = "") -> Bool {
        guard money.amount > 0, !knows(key), at >= config.startedAt else { return false }
        let value = Rates.shared.convert(money, to: config.currency)
        entries.insert(Entry(id: key, source: source, original: money, value: value?.rounded(4), at: at,
                             state: value == nil ? .pending : .counted, missed: missed, note: note), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        applog("goal", "\(source) \(money.display) -> \(value.map { Money($0, config.currency).display } ?? "pending")\(missed ? " (missed)" : "")")
        changed()
        return true
    }

    /// A donation the site now reports refunded: out of the goal at the value it added, kept in the list as refunded.
    func refund(_ key: String) {
        guard let i = entries.firstIndex(where: { $0.id == key }), entries[i].state == .counted || entries[i].state == .pending else { return }
        entries[i].state = .refunded
        applog("goal", "\(key) refunded")
        changed()
    }

    /// Cash in hand, a bank transfer: anything no source reports. A negative amount corrects a mistake.
    func addManual(_ money: Money, note: String) {
        let value = Rates.shared.convert(money, to: config.currency)
        entries.insert(Entry(id: "manual:\(UUID().uuidString)", source: "manual", original: money, value: value?.rounded(4), at: Date(),
                             state: value == nil ? .pending : .counted, note: note), at: 0)
        changed()
    }

    /// A test donation: moves the bar for 10 s, then leaves no trace in the total.
    func test(_ money: Money) {
        let key = "test:\(UUID().uuidString)"
        entries.insert(Entry(id: key, source: "test", original: money, value: Rates.shared.convert(money, to: config.currency)?.rounded(4),
                             at: Date(), state: .test, note: "Test"), at: 0)
        objectWillChange.send()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.entries.removeAll { $0.id == key }
        }
    }

    /// Converts donations that waited for a rate (called after every rate refresh).
    func resolvePending() {
        var any = false
        for i in entries.indices where entries[i].state == .pending {
            if let v = Rates.shared.convert(entries[i].original, to: config.currency) {
                entries[i].value = v.rounded(4)
                entries[i].state = .counted
                any = true
            }
        }
        if any { changed() }
    }

    // MARK: setting up

    /// Title, target and starting amount can change at any time. A different currency starts a new goal: values
    /// already counted are locked in the old one (adr/0006).
    func update(title: String, target: Decimal, start: Decimal) {
        config.title = title
        config.target = target
        config.start = start
        reached = total >= target
        changed()
    }

    func reset(title: String, target: Decimal, currency: String, start: Decimal) {
        config = Config(title: title, target: target, currency: currency, start: start, startedAt: Date())
        entries = []
        reached = false
        changed()
    }

    private func changed() {
        if !reached, config.target > 0, total >= config.target {
            reached = true
            applog("goal", "goal reached: \(Money(total, config.currency).display) of \(Money(config.target, config.currency).display)")
            onReached?()
        }
        save()
    }

    private func save() {
        let s = Saved(config: config, entries: entries.filter { $0.state != .test }, reached: reached)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(s).write(to: file, options: .atomic)
        } catch {
            applog("goal", "goal save failed: \(error.localizedDescription)", error: true)
        }
    }
}
