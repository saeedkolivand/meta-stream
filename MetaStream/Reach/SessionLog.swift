import Foundation

/// Records the running stream session (CONTEXT.md "Reach"): a per-minute timeline, Moments, donation totals and
/// Chatters. Saved as JSON when the session ends. Chat text is never stored, only counts per Chatter key.
@MainActor
final class SessionLog {
    static let shared = SessionLog()

    /// A Chatter the app has seen before, kept across sessions.
    struct Known: Codable { var name: String; var firstSeen: Date; var lastSeen: Date }

    private(set) var current: SessionRecord?
    /// The latest donation this session, for the Live post's "Last:" line.
    private(set) var lastDonation: (user: String, display: String)?
    private var registry: [String: Known] = [:]
    private var minuteChat = 0
    private var lastSpikeAt: Date?

    private static let anonymous = ["someone", "anonymous", "an anonymous cheerer"]
    private static var sessionsDir: URL { URL.applicationSupportDirectory.appending(path: "sessions") }
    private static var chattersFile: URL { URL.applicationSupportDirectory.appending(path: "chatters.json") }

    // MARK: pure decisions

    /// A chat spike: at least 20 messages this minute and 3x the mean of up to the previous 10 minutes (needs 3 of them).
    static func isSpike(_ count: Int, previous: [Int]) -> Bool {
        let prev = Array(previous.suffix(10))
        guard prev.count >= 3 else { return false }
        let mean = Double(prev.reduce(0, +)) / Double(prev.count)
        return count >= 20 && Double(count) >= 3 * max(mean, 1)
    }

    /// Donation sites and platforms use these placeholders for a donor who gave no name; they never become top donor.
    static func isAnonymous(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty || anonymous.contains(trimmed)
    }

    // MARK: lifecycle

    func begin(title: String) {
        registry = Self.load([String: Known].self, from: Self.chattersFile) ?? [:]
        current = SessionRecord(start: Date(), title: title, currency: GoalStore.shared.config.currency, trackingStarted: registry.isEmpty)
        lastDonation = nil
        minuteChat = 0
        lastSpikeAt = nil
    }

    /// Called every second while live; appends a sample on each minute boundary, then looks for a chat spike.
    func tick(_ streamer: Streamer, viewers: Int) {
        guard var rec = current else { return }
        let now = Date()
        guard Int(now.timeIntervalSince(rec.start)) / 60 > rec.samples.count else { return }
        let previous = rec.samples.suffix(10).map(\.chat)
        rec.samples.append(SessionSample(
            minute: rec.samples.count + 1, viewers: viewers, chat: minuteChat, kbps: streamer.kbps,
            drops: streamer.drops, downSeconds: Int(streamer.downtime)))
        if Self.isSpike(minuteChat, previous: previous), lastSpikeAt.map({ now.timeIntervalSince($0) >= 300 }) ?? true {
            lastSpikeAt = now
            rec.moments.append(Moment(at: now, kind: .chatSpike, user: "", detail: "\(minuteChat)/min"))
        }
        minuteChat = 0
        current = rec
        // Every 5 minutes the session so far goes to disk too, so a crash 6 hours in doesn't lose the whole record.
        if rec.samples.count % 5 == 0 { Self.save(rec, to: Self.file(rec)) }
    }

    func record(_ e: ChatEvent) {
        guard current != nil else { return }
        switch e.kind {
        case .message: message(e)
        case .tip, .cheer: donation(e)
        case .raid where e.count >= 10: current?.moments.append(Moment(at: e.at, kind: .raid, user: e.user, detail: "\(e.count)"))
        default: break
        }
    }

    /// Finishes and saves the session and the Chatter registry.
    func end() -> SessionRecord? {
        guard var rec = current else { return nil }
        rec.end = Date()
        current = nil
        Self.save(rec, to: Self.file(rec))
        Self.save(registry, to: Self.chattersFile)
        return rec
    }

    // MARK: events

    private func message(_ e: ChatEvent) {
        guard !e.userId.isEmpty, !AppBot.shared.isOwn(e) else { return }
        minuteChat += 1
        let key = "\(e.origin)|\(e.userId)"
        let first = current?.chatterCounts[key] == nil
        current?.chatterCounts[key, default: 0] += 1
        current?.chatterNames[key] = e.user
        guard first else { return }
        let now = Date()
        if var known = registry[key] {
            known.name = e.user
            known.lastSeen = now
            registry[key] = known
            current?.returningChatters += 1
        } else {
            registry[key] = Known(name: e.user, firstSeen: now, lastSeen: now)
            current?.newChatters += 1
        }
    }

    private func donation(_ e: ChatEvent) {
        guard e.origin != "test-donation", let money = DonationPrices.money(e) else { return }
        let converted = Rates.shared.convert(money, to: GoalStore.shared.config.currency)
        current?.donationCount += 1
        if let converted {
            current?.donationTotal += converted
            if !Self.isAnonymous(e.user), converted > (current?.topDonorAmount ?? 0) {
                current?.topDonor = e.user
                current?.topDonorDisplay = money.display
                current?.topDonorAmount = converted
            }
        }
        lastDonation = (e.user, money.display)
        let threshold = UserDefaults.standard.object(forKey: "momentDonationEUR") as? Double ?? 20
        if let eur = Rates.shared.convert(money, to: "EUR"), eur >= Decimal(threshold) {
            current?.moments.append(Moment(at: e.at, kind: .donation, user: e.user, detail: money.display))
        }
    }

    // MARK: files

    private static func file(_ rec: SessionRecord) -> URL { sessionsDir.appending(path: "\(stamp(rec.start)).json") }

    private static func stamp(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return format.string(from: date)
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save(_ value: some Encodable, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            applog("reach", "save \(url.lastPathComponent) failed: \(error.localizedDescription)", error: true)
        }
    }

    #if DEBUG
    static func demo() {
        assert(!isSpike(40, previous: [5, 5]))                      // too little history
        assert(!isSpike(19, previous: [1, 1, 1]) && isSpike(20, previous: [1, 1, 1]))
        assert(!isSpike(29, previous: [10, 10, 10]) && isSpike(30, previous: [10, 10, 10]))
        assert(isSpike(60, previous: Array(repeating: 5, count: 15)))
        assert(isAnonymous("Someone") && isAnonymous(" anonymous ") && isAnonymous("An anonymous cheerer") && isAnonymous(""))
        assert(!isAnonymous("Bob"))
        applog("reach", "SessionLog.demo() passed")
    }
    #endif
}
