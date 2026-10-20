import Foundation

/// The words of the Live post, as pure functions of plain values (so `demo()` can check them). Labels are the only
/// thing that follows the language setting; titles, goal titles and names stay as typed. Latin digits throughout.
/// ponytail: Persian digits and RTL marks if the mixed lines ever look wrong in Telegram.
enum LivePostText {
    struct GoalLine { var pct: Int; var target: String; var title: String }

    /// What the live (and Starting) post shows. `countdown` is set while the Starting scene's countdown runs.
    struct Live {
        var title = "", slug = "", countdown: String?
        var viewers = 0, elapsed: TimeInterval = 0, reconnecting = false
        var goal: GoalLine?, last: String?, city: String?
        var updated = Date()
    }

    struct Recap {
        var title = "", slug = ""
        var duration: TimeInterval = 0, peak = 0, avg = 0
        var donationCount = 0, total = "", showTotal = true, topName: String?, topAmount: String?
        var goal: GoalLine?, moments: [Moment] = [], chatters = 0, trackingStarted = false
    }

    private static let fa = [
        "soon": "به‌زودی لایو", "live": "لایو", "watching": "بیننده", "goal": "هدف", "of": "از", "for": "برای", "last": "آخرین",
        "updated": "به‌روزرسانی", "reconnecting": "در حال اتصال دوباره…", "starting": "شروع تا", "ended": "لایو تمام شد",
        "peak": "اوج", "avg": "میانگین", "donations": "دونیت", "top": "بیشترین", "moments": "لحظه‌ها",
        "wild": "چت ترکوند", "from": "از طرف", "raid": "رید از", "newChatters": "چتر جدید", "chatters": "چتر",
        "thanks": "ممنون از همه", "cancelled": "امروز لغو شد",
        "pingWild": "چت الان ترکونده", "pingDonation": "دونیت بزرگ از طرف", "pingThanks": "بیا تشکر کن",
        "pingRaid": "رید از", "pingWith": "با", "pingViewers": "بیننده",
        "wrappedWild": "چت ترکوند", "wrappedMsgs": "پیام در دقیقه", "wrappedStreams": "استریم", "wrappedHours": "ساعت",
        "wrappedKm": "کیلومتر", "wrappedPeak": "اوج بیننده", "wrappedTop": "چترهای برتر", "wrappedBest": "بهترین لحظه"
    ]
    private static let en = [
        "soon": "Going live soon", "live": "LIVE", "watching": "watching", "goal": "Goal", "of": "of", "for": "for", "last": "Last",
        "updated": "updated", "reconnecting": "reconnecting…", "starting": "Starting in", "ended": "Stream ended",
        "peak": "peak", "avg": "avg", "donations": "donations", "top": "top", "moments": "Moments",
        "wild": "chat went wild", "from": "from", "raid": "raid from", "newChatters": "new chatters", "chatters": "chatters",
        "thanks": "thanks everyone", "cancelled": "Cancelled for today",
        "pingWild": "Chat's going wild right now", "pingDonation": "Big donation from", "pingThanks": "come say thanks",
        "pingRaid": "Raid from", "pingWith": "with", "pingViewers": "viewers",
        "wrappedWild": "chat went wild", "wrappedMsgs": "messages/min", "wrappedStreams": "streams", "wrappedHours": "hours",
        "wrappedKm": "km", "wrappedPeak": "peak viewers", "wrappedTop": "top chatters", "wrappedBest": "best moment"
    ]

    static func tr(_ key: String, _ lang: String) -> String { (lang == "en" ? en : fa)[key] ?? key }

    // MARK: posts

    static func announce(title: String, slug: String, lang: String) -> String {
        join(["📣 " + head(tr("soon", lang), title), link(slug)])
    }

    static func cancelled(lang: String) -> String { "❌ " + tr("cancelled", lang) }

    /// A stream that ended without a record (the app was killed): no stats to show.
    static func endedBare(lang: String) -> String { "⚪️ " + tr("ended", lang) }

    static func live(_ post: Live, lang: String) -> String {
        let up: String? = "\(tr("updated", lang)) \(hhmm(post.updated))"
        if let countdown = post.countdown {
            let top: String? = "🟡 " + head("\(tr("starting", lang)) \(countdown)", post.title)
            return join([top, link(post.slug), up])
        }
        let top: String? = "🔴 " + head(tr("live", lang), post.title)
        var watching: String? = "👁 \(post.viewers) \(tr("watching", lang)) · ⏱ \(duration(post.elapsed))"
        if post.reconnecting { watching = "📡 " + tr("reconnecting", lang) }
        let last = post.last.map { "💸 \(tr("last", lang)): \($0)" }
        let city = post.city.map { "📍 \($0)" }
        return join([top, watching, goalLine(post.goal, lang), last, city, link(post.slug), up])
    }

    static func recap(_ rec: Recap, lang: String) -> String {
        let top: String? = "✅ " + head(tr("ended", lang), rec.title)
        let stats: String? = "⏱ \(duration(rec.duration)) · 👁 \(tr("peak", lang)) \(rec.peak) · \(tr("avg", lang)) \(rec.avg)"
        return join([top, stats, donationLine(rec, lang), goalLine(rec.goal, lang), momentsLine(rec.moments, lang),
                     chattersLine(rec, lang), link(rec.slug)])
    }

    /// A Moment ping: one short line about the moment, then the stream link (omitted without a slug).
    static func ping(_ moment: Moment, slug: String, lang: String) -> String {
        let line: String
        switch moment.kind {
        case .chatSpike: line = "🔥 " + tr("pingWild", lang)
        case .donation: line = "💸 \(tr("pingDonation", lang)) \(moment.user) (\(moment.detail)) \u{2014} \(tr("pingThanks", lang))"
        case .raid:
            line = "🚀 \(tr("pingRaid", lang)) \(moment.user) \(tr("pingWith", lang)) \(moment.detail) \(tr("pingViewers", lang))"
        }
        return join([line, link(slug)])
    }

    /// Telegram limits: 1024 characters for a caption, 4096 for a text message.
    static func fit(_ text: String, photo: Bool) -> String { String(text.prefix(photo ? 1024 : 4096)) }

    // MARK: parts

    private static func head(_ label: String, _ title: String) -> String { title.isEmpty ? label : "\(label) · \(title)" }

    private static func link(_ slug: String) -> String? { slug.isEmpty ? nil : "▶️ kick.com/\(slug)" }

    private static func join(_ lines: [String?]) -> String { lines.compactMap { $0 }.joined(separator: "\n") }

    private static func goalLine(_ goal: GoalLine?, _ lang: String) -> String? {
        guard let goal else { return nil }
        let name = goal.title.isEmpty ? "" : " \(tr("for", lang)) \(goal.title)"
        return "🎯 \(tr("goal", lang)): \(goal.pct)% \(tr("of", lang)) \(goal.target)\(name)"
    }

    private static func donationLine(_ rec: Recap, _ lang: String) -> String? {
        var parts: [String] = []
        if rec.showTotal, rec.donationCount > 0 {
            parts.append("\(rec.total) \(tr("from", lang)) \(rec.donationCount) \(tr("donations", lang))")
        }
        if let name = rec.topName, let amount = rec.topAmount { parts.append("\(tr("top", lang)): \(name) \(amount)") }
        return parts.isEmpty ? nil : "💸 " + parts.joined(separator: " · ")
    }

    private static func momentsLine(_ moments: [Moment], _ lang: String) -> String? {
        guard !moments.isEmpty else { return nil }
        return "✨ \(tr("moments", lang)): " + moments.prefix(5).map { "\(hhmm($0.at)) \(label($0, lang))" }.joined(separator: " · ")
    }

    private static func label(_ moment: Moment, _ lang: String) -> String {
        switch moment.kind {
        case .chatSpike: return tr("wild", lang)
        case .donation: return "\(moment.detail) \(tr("from", lang)) \(moment.user)"
        case .raid: return "\(tr("raid", lang)) \(moment.user) (\(moment.detail))"
        }
    }

    private static func chattersLine(_ rec: Recap, _ lang: String) -> String? {
        guard rec.chatters > 0 else { return nil }
        // trackingStarted: everyone looks new because counting began today, so don't claim they are.
        return "💬 \(rec.chatters) \(tr(rec.trackingStarted ? "chatters" : "newChatters", lang)) · \(tr("thanks", lang)) ❤️"
    }

    /// "2h 14m", or "14m" under an hour.
    static func duration(_ span: TimeInterval) -> String {
        let minutes = max(0, Int(span)) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// Local time, 24 h.
    static func hhmm(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "HH:mm"
        return format.string(from: date)
    }

    #if DEBUG
    static func demo() {
        var post = Live(title: "IRL Köln", slug: "saeed", viewers: 42, elapsed: 8040)
        assert(live(post, lang: "en").contains("42 watching") && live(post, lang: "en").contains("2h 14m"))
        assert(live(post, lang: "fa").contains("بیننده") && live(post, lang: "fa").contains("kick.com/saeed"))
        post.reconnecting = true
        assert(live(post, lang: "en").contains("reconnecting") && !live(post, lang: "en").contains("watching"))
        assert(!live(Live(), lang: "en").contains("kick.com") && live(Live(), lang: "en").hasPrefix("🔴 LIVE\n"))
        var rec = Recap(title: "t", slug: "s", duration: 3600, peak: 9, avg: 5,
                        donationCount: 2, total: "€30", topName: "Bob", topAmount: "€25")
        assert(recap(rec, lang: "en").contains("€30 from 2 donations") && recap(rec, lang: "en").contains("top: Bob €25"))
        rec.showTotal = false
        assert(!recap(rec, lang: "en").contains("€30") && recap(rec, lang: "en").contains("top: Bob €25"))
        rec.topName = nil
        assert(!recap(rec, lang: "en").contains("💸"))
        assert(fit(String(repeating: "x", count: 5000), photo: true).count == 1024)
        let donation = Moment(at: Date(), kind: .donation, user: "Bob", detail: "€25")
        assert(ping(donation, slug: "s", lang: "en") == "💸 Big donation from Bob (€25) \u{2014} come say thanks\n▶️ kick.com/s")
        assert(ping(donation, slug: "", lang: "fa") == "💸 دونیت بزرگ از طرف Bob (€25) \u{2014} بیا تشکر کن")
        let raid = Moment(at: Date(), kind: .raid, user: "Al", detail: "40")
        assert(ping(raid, slug: "", lang: "en") == "🚀 Raid from Al with 40 viewers")
        assert(ping(raid, slug: "s", lang: "fa") == "🚀 رید از Al با 40 بیننده\n▶️ kick.com/s")
        let spike = Moment(at: Date(), kind: .chatSpike, user: "", detail: "30/min")
        assert(ping(spike, slug: "s", lang: "en") == "🔥 Chat's going wild right now\n▶️ kick.com/s")
        assert(ping(spike, slug: "", lang: "fa") == "🔥 چت الان ترکونده")
        applog("reach", "LivePostText.demo() passed")
    }
    #endif
}
