// The goal and its ledger (CONTEXT.md: Goal, Donation, Pending/Missed donation; adr/0006). Every donation is recorded
// once under "<source>:<id>", converted into the goal currency when it arrives and kept at that value. Persisted as
// JSON in Application Support, so a goal lasts across streams until the streamer resets it.
import CoreLogging
import CoreModel
import Foundation
import Observation

@MainActor @Observable
public final class GoalStore {
    public static let shared = GoalStore()

    public struct Config: Codable, Equatable {
        public var title = "Goal"
        public var target: Decimal = 500
        public var currency = "EUR"          // "IRT" (toman), "USD" or "EUR"
        public var start: Decimal = 0        // money raised before the app was counting
        public var startedAt = Date()        // donations found in a site's history from before this don't count

        public init(title: String = "Goal", target: Decimal = 500, currency: String = "EUR", start: Decimal = 0,
                    startedAt: Date = Date()) {
            self.title = title
            self.target = target
            self.currency = currency
            self.start = start
            self.startedAt = startedAt
        }
    }

    public enum State: String, Codable { case counted, pending, refunded, test }

    public struct Entry: Codable, Identifiable, Equatable {
        public let id: String                // "<source>:<id>", the dedupe key
        public var source: String            // "kick", "twitch", "youtube", "donofa", "reymit", "streamelements", "manual", "test"
        public var original: Money
        public var value: Decimal?           // in the goal currency; nil while pending
        public var at: Date
        public var state: State
        public var missed = false            // found afterwards in a site's history: counted, never announced
        public var note = ""

        public init(id: String, source: String, original: Money, value: Decimal? = nil, at: Date, state: State,
                    missed: Bool = false, note: String = "") {
            self.id = id
            self.source = source
            self.original = original
            self.value = value
            self.at = at
            self.state = state
            self.missed = missed
            self.note = note
        }
    }

    public private(set) var config = Config() { didSet { onChange?() } }
    public private(set) var entries: [Entry] = [] { didSet { onChange?() } }   // newest first
    public private(set) var reached = false { didSet { onChange?() } }
    /// Fires once when the total first reaches the target (the widget celebrates, read-aloud says it).
    @ObservationIgnored public var onReached: (() -> Void)?
    /// Any goal state changed (DonatePagePublisher republishes); was a sink on objectWillChange.
    @ObservationIgnored public var onChange: (() -> Void)?

    private static let maxEntries = 1000
    private var file: URL {
        URL.applicationSupportDirectory.appending(path: "goal.json")
    }

    private struct Saved: Codable { var config: GoalStore.Config; var entries: [GoalStore.Entry]; var reached: Bool }

    public init() {
        if let d = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            config = s.config; entries = s.entries.filter { $0.state != .test }; reached = s.reached
        }
        Rates.shared.onUpdate = { [weak self] in self?.resolvePending() }
    }

    // MARK: totals

    public var total: Decimal {
        entries.reduce(config.start) { sum, e in
            (e.state == .counted || e.state == .test) ? sum + (e.value ?? 0) : sum
        }
    }

    public var progress: Double {
        guard config.target > 0 else { return 0 }
        return NSDecimalNumber(decimal: total / config.target).doubleValue
    }

    public var pendingCount: Int { entries.filter { $0.state == .pending }.count }

    public func knows(_ key: String) -> Bool { entries.contains { $0.id == key } }

    // MARK: recording

    /// Records a donation once per key; false when it's already known (a site's live feed and its history report the
    /// same donation) or it predates the goal. Converted now at the market rate, or left pending without one.
    @discardableResult
    public func record(key: String, source: String, money: Money, at: Date = Date(), missed: Bool = false, note: String = "") -> Bool {
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
    public func refund(_ key: String) {
        guard let i = entries.firstIndex(where: { $0.id == key }), entries[i].state == .counted || entries[i].state == .pending else { return }
        entries[i].state = .refunded
        applog("goal", "\(key) refunded")
        changed()
    }

    /// Cash in hand, a bank transfer: anything no source reports. A negative amount corrects a mistake.
    public func addManual(_ money: Money, note: String) {
        let value = Rates.shared.convert(money, to: config.currency)
        entries.insert(Entry(id: "manual:\(UUID().uuidString)", source: "manual", original: money, value: value?.rounded(4), at: Date(),
                             state: value == nil ? .pending : .counted, note: note), at: 0)
        changed()
    }

    /// A test donation: moves the bar for 10 s, then leaves no trace in the total.
    public func test(_ money: Money) {
        let key = "test:\(UUID().uuidString)"
        entries.insert(Entry(id: key, source: "test", original: money, value: Rates.shared.convert(money, to: config.currency)?.rounded(4),
                             at: Date(), state: .test, note: "Test"), at: 0)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.entries.removeAll { $0.id == key }
        }
    }

    /// Converts donations that waited for a rate (called after every rate refresh).
    public func resolvePending() {
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
    public func update(title: String, target: Decimal, start: Decimal) {
        config.title = title
        config.target = target
        config.start = start
        reached = total >= target
        changed()
    }

    public func reset(title: String, target: Decimal, currency: String, start: Decimal) {
        config = Config(title: title, target: target, currency: currency, start: start, startedAt: Date())
        entries = []
        reached = false
        applog("goal", "goal reset: \(title), target \(Money(target, currency).display)")
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
