import Foundation

/// The Live post's templates (Settings › Telegram › Post texts): the built-in ones, the streamer's own, and the filling.
extension LivePostText {
    /// The posts whose words Settings › Telegram › Post texts can rewrite, and the placeholders each one fills.
    public enum Kind: String, CaseIterable, Identifiable {
        case announce, starting, live, recap, cancelled, pingDonation, pingRaid, pingWild

        public var id: String { rawValue }
        public var pref: String { "tgText." + rawValue }

        public var title: String {
            switch self {
            case .announce: "Announce"
            case .starting: "Starting countdown"
            case .live: "Live"
            case .recap: "Recap"
            case .cancelled: "Cancelled"
            case .pingDonation: "Ping: big donation"
            case .pingRaid: "Ping: raid"
            case .pingWild: "Ping: chat spike"
            }
        }

        public var keys: [String] {
            switch self {
            case .announce: ["title", "link"]
            case .starting: ["countdown", "title", "link", "updated"]
            case .live: ["title", "viewers", "duration", "reconnecting", "goal", "last", "city", "link", "updated"]
            case .recap: ["title", "duration", "peak", "avg", "donations", "goal", "moments", "chatters", "link"]
            case .cancelled: []
            case .pingDonation: ["user", "amount", "link"]
            case .pingRaid: ["user", "viewers", "link"]
            case .pingWild: ["link"]
            }
        }
    }

    public typealias Custom = (Kind) -> String?

    /// The streamer's own template for `kind`, or nil for the built-in one.
    public static func stored(_ kind: Kind) -> String? {
        let text = UserDefaults.standard.string(forKey: kind.pref) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// Today's wording as a template: the labels in `lang`, one line per piece of the post.
    public static func defaultTemplate(_ kind: Kind, _ lang: String) -> String {
        let word = { tr($0, lang) }
        switch kind {
        case .announce: return "📣 \(word("soon"))[ · {title}]\n▶️ {link}"
        case .starting: return "🟡 \(word("starting")) {countdown}[ · {title}]\n▶️ {link}\n\(word("updated")) {updated}"
        case .live:
            return "🔴 \(word("live"))[ · {title}]\n👁 {viewers} \(word("watching")) · ⏱ {duration}\n📡 {reconnecting}\n"
                + "🎯 \(word("goal")): {goal}\n💸 \(word("last")): {last}\n📍 {city}\n▶️ {link}\n\(word("updated")) {updated}"
        case .recap:
            return "✅ \(word("ended"))[ · {title}]\n⏱ {duration} · 👁 \(word("peak")) {peak} · \(word("avg")) {avg}\n💸 {donations}\n"
                + "🎯 \(word("goal")): {goal}\n✨ \(word("moments")): {moments}\n💬 {chatters} · \(word("thanks")) ❤️\n▶️ {link}"
        case .cancelled: return "❌ \(word("cancelled"))"
        case .pingDonation: return "💸 \(word("pingDonation")) {user} ({amount}) \u{2014} \(word("pingThanks"))\n▶️ {link}"
        case .pingRaid: return "🚀 \(word("pingRaid")) {user} \(word("pingWith")) {viewers} \(word("pingViewers"))\n▶️ {link}"
        case .pingWild: return "🔥 \(word("pingWild"))\n▶️ {link}"
        }
    }

    /// Fills a template line by line: an empty {key} hides its line, an empty one inside [ ] drops only that bracket, an
    /// unknown {key} stays as typed so a typo shows. Values go in as they are (a title with braces stays text).
    public static func render(_ template: String, _ values: [String: String]) -> String {
        let lines = template.components(separatedBy: "\n").compactMap { line -> String? in
            var missing = false
            let out = line.replacing(#/\[([^\[\]]*)\]|\{(\w+)\}/#) { match -> String in
                if let optional = match.output.1 { return fill(String(optional), values) ?? "" }
                return value(String(match.output.2 ?? ""), values) { missing = true }
            }
            let blank = out.trimmingCharacters(in: .whitespaces).isEmpty && !line.trimmingCharacters(in: .whitespaces).isEmpty
            return missing || blank ? nil : out
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fill(_ part: String, _ values: [String: String]) -> String? {
        var missing = false
        let out = part.replacing(#/\{(\w+)\}/#) { match in value(String(match.output.1), values) { missing = true } }
        return missing ? nil : out
    }

    private static func value(_ key: String, _ values: [String: String], onEmpty: () -> Void) -> String {
        guard let found = values[key] else { return "{\(key)}" }
        if found.isEmpty { onEmpty() }
        return found
    }

    /// `kind` filled with made-up values, for the editor's preview.
    public static func preview(_ kind: Kind, lang: String, template: String) -> String {
        let mine: Custom = { $0 == kind ? template : nil }
        let title = "Walking through Cologne"
        let goal = GoalLine(pct: 45, target: "€500", title: "a new camera")
        let spike = Moment(at: Date().addingTimeInterval(-3600), kind: .chatSpike, user: "", detail: "30/min")
        switch kind {
        case .announce: return announce(title: title, slug: "yourname", lang: lang, custom: mine)
        case .starting: return live(Live(title: title, slug: "yourname", countdown: "4:59"), lang: lang, custom: mine)
        case .live:
            let post = Live(title: title, slug: "yourname", viewers: 42, elapsed: 4320, goal: goal, last: "Sara €10")
            return live(post, lang: lang, custom: mine)
        case .recap:
            let rec = Recap(title: title, slug: "yourname", duration: 8040, peak: 87, avg: 51, donationCount: 6, total: "€140",
                            topName: "Sara", topAmount: "€50", goal: goal, moments: [spike], chatters: 23)
            return recap(rec, lang: lang, custom: mine)
        case .cancelled: return cancelled(lang: lang, custom: mine)
        case .pingDonation:
            return ping(Moment(at: Date(), kind: .donation, user: "Sara", detail: "€25"), slug: "yourname", lang: lang, custom: mine)
        case .pingRaid:
            return ping(Moment(at: Date(), kind: .raid, user: "Ali", detail: "40"), slug: "yourname", lang: lang, custom: mine)
        case .pingWild: return ping(spike, slug: "yourname", lang: lang, custom: mine)
        }
    }
}
