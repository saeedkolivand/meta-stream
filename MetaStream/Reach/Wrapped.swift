import Foundation

/// The body of the monthly Wrapped page (CONTEXT.md "Wrapped"): exactly the keys the donate page accepts. Never a date
/// or a place, only city names. `km`, `donations` and `bestMoment` encode as JSON null when absent (the server rejects
/// a missing key, and JSONEncoder omits nil optionals), hence the hand-written `encode(to:)`.
struct WrappedDraft: Encodable {
    struct Chatter: Encodable { var name: String; var messages: Int }
    struct Donor: Encodable { var name: String; var amount: String }
    struct Donations: Encodable { var count: Int; var total: String }
    struct BestMoment: Encodable { var kind: String; var label: String }

    var month: String
    var streams: Int
    var hours: Double
    var km: Double?
    var cities: [String]
    var peakViewers: Int
    var avgViewers: Int
    var newChatters: Int
    var topChatters: [Chatter]
    var topDonors: [Donor]
    var donations: Donations?
    var bestMoment: BestMoment?
    var publishedAt: String

    enum CodingKeys: String, CodingKey {
        case month, streams, hours, km, cities, peakViewers, avgViewers, newChatters, topChatters, topDonors
        case donations, bestMoment, publishedAt
    }

    func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(month, forKey: .month)
        try box.encode(streams, forKey: .streams)
        try box.encode(hours, forKey: .hours)
        if let km { try box.encode(km, forKey: .km) } else { try box.encodeNil(forKey: .km) }
        try box.encode(cities, forKey: .cities)
        try box.encode(peakViewers, forKey: .peakViewers)
        try box.encode(avgViewers, forKey: .avgViewers)
        try box.encode(newChatters, forKey: .newChatters)
        try box.encode(topChatters, forKey: .topChatters)
        try box.encode(topDonors, forKey: .topDonors)
        if let donations { try box.encode(donations, forKey: .donations) } else { try box.encodeNil(forKey: .donations) }
        if let bestMoment { try box.encode(bestMoment, forKey: .bestMoment) } else { try box.encodeNil(forKey: .bestMoment) }
        try box.encode(publishedAt, forKey: .publishedAt)
    }
}

/// Sums a month of session records into a draft. Pure, so `demo()` can check it.
enum WrappedBuilder {
    static func monthKey(_ date: Date, _ calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    private static func cut(_ text: String, _ limit: Int) -> String { String(text.prefix(limit)) }

    static func build(month: String, records: [SessionRecord], lang: String, showTotal: Bool,
                      calendar: Calendar = .current) -> WrappedDraft? {
        let sessions = records.filter { monthKey($0.start, calendar) == month }.sorted { $0.start < $1.start }
        guard !sessions.isEmpty else { return nil }
        let live = sessions.flatMap(\.samples).map(\.viewers).filter { $0 > 0 }
        let meters = sessions.compactMap(\.distanceMeters)
        var cities: [String] = []
        for city in sessions.flatMap({ $0.cities ?? [] }) where !cities.contains(city) { cities.append(city) }
        let hours = sessions.reduce(0.0) { $0 + $1.duration } / 3600
        let newChatters = sessions.reduce(0) { $0 + $1.newChatters + ($1.trackingStarted ? $1.chatterCounts.count : 0) }
        let money = donations(sessions, showTotal: showTotal)
        return WrappedDraft(
            month: month, streams: sessions.count, hours: (hours * 10).rounded() / 10,
            km: meters.isEmpty ? nil : (meters.reduce(0, +) / 100).rounded() / 10,
            cities: cities.prefix(30).map { cut($0, 40) }, peakViewers: sessions.map(\.peakViewers).max() ?? 0,
            avgViewers: live.isEmpty ? 0 : live.reduce(0, +) / live.count, newChatters: newChatters,
            topChatters: chatters(sessions), topDonors: money.donors, donations: money.total,
            bestMoment: bestMoment(sessions.flatMap(\.moments), lang), publishedAt: ISO8601DateFormatter().string(from: Date()))
    }

    private static func chatters(_ sessions: [SessionRecord]) -> [WrappedDraft.Chatter] {
        var counts: [String: Int] = [:], names: [String: String] = [:]
        for session in sessions {   // sorted by start, so the latest non-empty name wins
            for (key, count) in session.chatterCounts { counts[key, default: 0] += count }
            for (key, name) in session.chatterNames where !name.isEmpty { names[key] = name }
        }
        let rows = counts.compactMap { key, count in names[key].map { WrappedDraft.Chatter(name: cut($0, 40), messages: count) } }
        return rows.sorted { ($0.messages, $1.name) > ($1.messages, $0.name) }.prefix(10).map { $0 }
    }

    /// ponytail: a month that switched goal currency drops the minority currency from donors and the total.
    private static func donations(_ sessions: [SessionRecord], showTotal: Bool)
        -> (donors: [WrappedDraft.Donor], total: WrappedDraft.Donations?) {
        let groups = Dictionary(grouping: sessions, by: \.currency)
        guard let top = groups.max(by: { ($0.value.count, $0.key) < ($1.value.count, $1.key) }) else { return ([], nil) }
        var sums: [String: Decimal] = [:]
        for session in top.value { for (name, amount) in session.donors ?? [:] { sums[name, default: 0] += amount } }
        let donors = sums.filter { !$0.key.isEmpty }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(10)
            .map { WrappedDraft.Donor(name: cut($0.key, 40), amount: cut(Money($0.value, top.key).display, 24)) }
        let count = top.value.reduce(0) { $0 + $1.donationCount }
        let total = top.value.reduce(Decimal(0)) { $0 + $1.donationTotal }
        let line = WrappedDraft.Donations(count: count, total: cut(Money(total, top.key).display, 24))
        return (donors, showTotal && count > 0 ? line : nil)
    }

    private static func bestMoment(_ moments: [Moment], _ lang: String) -> WrappedDraft.BestMoment? {
        func best(_ kind: Moment.Kind) -> Moment? {
            moments.filter { $0.kind == kind }.max { ($0.value ?? 0) < ($1.value ?? 0) }
        }
        let tr = { LivePostText.tr($0, lang) }
        if let spike = best(.chatSpike) {
            let line = "\(tr("wrappedWild")) \u{2014} \(Int(spike.value ?? 0)) \(tr("wrappedMsgs"))"
            return WrappedDraft.BestMoment(kind: "chatSpike", label: cut(line, 80))
        }
        if let raid = best(.raid) {
            let line = "\(tr("raid")) \(raid.user) \(tr("pingWith")) \(raid.detail) \(tr("pingViewers"))"
            return WrappedDraft.BestMoment(kind: "raid", label: cut(line, 80))
        }
        guard let gift = best(.donation) else { return nil }
        return WrappedDraft.BestMoment(kind: "donation", label: cut("\(gift.detail) \(tr("from")) \(gift.user)", 80))
    }
}

/// Which months were published or turned down, and which one is waiting for review.
enum WrappedStore {
    static let published = "wrappedPublished"
    static let dismissed = "wrappedDismissed"

    static var lang: String { UserDefaults.standard.string(forKey: "telegramLang") == "en" ? "en" : "fa" }

    static func months(_ key: String) -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    static func add(_ month: String, to key: String) { UserDefaults.standard.set(Array(months(key).union([month])), forKey: key) }

    static func remove(_ month: String, from key: String) {
        UserDefaults.standard.set(Array(months(key).subtracting([month])), forKey: key)
    }

    /// Every month with at least one session, newest first.
    static func allMonths(_ records: [SessionRecord]) -> [String] {
        Set(records.map { WrappedBuilder.monthKey($0.start) }).sorted(by: >)
    }

    /// The previous calendar month, when it has a session and was neither published nor dismissed.
    static func pendingMonth(records: [SessionRecord], now: Date = Date()) -> String? {
        guard let before = Calendar.current.date(byAdding: .month, value: -1, to: now) else { return nil }
        let month = WrappedBuilder.monthKey(before)
        let seen = months(published).union(months(dismissed))
        return !seen.contains(month) && records.contains { WrappedBuilder.monthKey($0.start) == month } ? month : nil
    }

    /// "October 2026" in the app's language setting, Latin digits not guaranteed for Persian.
    static func monthName(_ month: String, lang: String? = nil) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
        else { return month }
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        if let lang { format.locale = Locale(identifier: lang) }
        format.dateFormat = "LLLL yyyy"
        return format.string(from: date)
    }
}

/// Sends the draft to the donate page with the same key and the same guard as `DonatePagePublisher.send()`.
@MainActor
enum WrappedPublisher {
    /// nil on success, else a short error text. Never logs the key.
    static func publish(_ draft: WrappedDraft) async -> String? {
        guard let data = try? JSONEncoder().encode(draft) else { return "Can't encode" }
        guard data.count <= 8192 else { return "Too big" }
        return await send(method: "POST", query: "", body: data)
    }

    static func withdraw(month: String) async -> String? {
        await send(method: "DELETE", query: "?month=" + month, body: nil)
    }

    /// "https://donate.iamsaeed.dev/wrapped/2026-09", or ".../fa/wrapped/..." in Persian.
    static func pageLink(month: String) -> String {
        DonatePagePublisher.shared.chatURL + (WrappedStore.lang == "fa" ? "/fa/wrapped/" : "/wrapped/") + month
    }

    private static func send(method: String, query: String, body: Data?) async -> String? {
        let page = DonatePagePublisher.shared
        let key = page.token
        guard !key.isEmpty else { return "No key" }
        // HTTPS only (the key is a bearer secret), and only to the host the key was saved for.
        let base = page.pageURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/wrapped" + query), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == UserDefaults.standard.string(forKey: "donatePageTokenHost") else { return "Needs an https:// URL" }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) || (method == "DELETE" && code == 404) { return nil }
            return code == 401 || code == 403 ? "Key rejected" : "HTTP \(code)"
        } catch {
            return "Can't reach the page"
        }
    }
}

#if DEBUG
extension WrappedBuilder {
    static func demo() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let base = Date(timeIntervalSince1970: 1_704_067_200)   // 2024-01-01 00:00 UTC
        let first = SessionRecord(start: base, end: base.addingTimeInterval(3600), title: "a", currency: "EUR",
                                  chatterCounts: ["k|1": 5, "k|2": 3, "k|3": 9], chatterNames: ["k|1": "Ann", "k|2": "Bob", "k|3": ""])
        var second = SessionRecord(start: base.addingTimeInterval(86400), end: base.addingTimeInterval(86400 + 7200), title: "b",
                                   currency: "EUR", chatterCounts: ["k|1": 4], chatterNames: ["k|1": "Annie"])
        let other = SessionRecord(start: base.addingTimeInterval(40 * 86400), title: "c", currency: "EUR")
        assert(build(month: "2023-12", records: [first], lang: "en", showTotal: true, calendar: cal) == nil)
        let draft = build(month: "2024-01", records: [second, first, other], lang: "en", showTotal: true, calendar: cal)
        assert(draft?.streams == 2 && draft?.hours == 3.0 && draft?.km == nil)
        assert(draft?.topChatters.count == 2 && draft?.topChatters.first?.name == "Annie" && draft?.topChatters.first?.messages == 9)
        assert(draft?.donations == nil && draft?.bestMoment == nil)
        guard let draft, let data = try? JSONEncoder().encode(draft) else { assertionFailure(); return }
        let text = String(decoding: data, as: UTF8.self)
        assert(text.contains("\"km\":null") && text.contains("\"donations\":null") && text.contains("\"bestMoment\":null"))
        assert(((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?.count == 13)
        second.distanceMeters = 1234
        let withKm = build(month: "2024-01", records: [second, first], lang: "en", showTotal: true, calendar: cal)
        assert(withKm?.km == 1.2)
        applog("reach", "WrappedBuilder.demo() passed")
    }
}
#endif
