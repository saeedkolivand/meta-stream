import CoreLogging
import Foundation

/// The words of the Live post, as pure functions of plain values (so `demo()` can check them): templates (built-in, or the
/// streamer's own; LivePostTemplates.swift) filled in. Built-in labels follow the language setting; titles, goal titles
/// and names stay as typed. Latin digits throughout.
/// ponytail: Persian digits and RTL marks if the mixed lines ever look wrong in Telegram.
public enum LivePostText {
    public struct GoalLine { var pct: Int; var target: String; var title: String }

    /// What the live (and Starting) post shows. `countdown` is set while the Starting scene's countdown runs.
    public struct Live {
        public var title = "", slug = "", countdown: String?
        public var viewers = 0, elapsed: TimeInterval = 0, reconnecting = false
        public var goal: GoalLine?, last: String?, city: String?
        public var updated = Date()
    }

    public struct Recap {
        public var title = "", slug = ""
        public var duration: TimeInterval = 0, peak = 0, avg = 0
        public var donationCount = 0, total = "", showTotal = true, topName: String?, topAmount: String?
        public var goal: GoalLine?, moments: [Moment] = [], chatters = 0, trackingStarted = false
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

    public static func tr(_ key: String, _ lang: String) -> String { (lang == "en" ? en : fa)[key] ?? key }

    /// The streamer's template when it renders to something, else the built-in one (Telegram refuses an empty message).
    private static func post(_ kind: Kind, _ lang: String, _ values: [String: String], _ custom: Custom) -> String {
        if let mine = custom(kind).map({ render($0, values) }), !mine.isEmpty { return mine }
        return render(defaultTemplate(kind, lang), values)
    }

    // MARK: posts

    public static func announce(title: String, slug: String, lang: String, custom: Custom = { _ in nil }) -> String {
        post(.announce, lang, ["title": title, "link": link(slug)], custom)
    }

    public static func cancelled(lang: String, custom: Custom = { _ in nil }) -> String { post(.cancelled, lang, [:], custom) }

    /// A stream that ended without a record (the app was killed): no stats to show.
    public static func endedBare(lang: String) -> String { "⚪️ " + tr("ended", lang) }

    public static func live(_ post: Live, lang: String, custom: Custom = { _ in nil }) -> String {
        var values = ["title": post.title, "link": link(post.slug), "updated": hhmm(post.updated)]
        if let countdown = post.countdown {
            values["countdown"] = countdown
            return Self.post(.starting, lang, values, custom)
        }
        let up = !post.reconnecting
        values["viewers"] = up ? "\(post.viewers)" : ""
        values["duration"] = up ? duration(post.elapsed) : ""
        values["reconnecting"] = up ? "" : tr("reconnecting", lang)
        values["goal"] = goalText(post.goal, lang)
        values["last"] = post.last ?? ""
        values["city"] = post.city ?? ""
        return Self.post(.live, lang, values, custom)
    }

    public static func recap(_ rec: Recap, lang: String, custom: Custom = { _ in nil }) -> String {
        var donations: [String] = []
        if rec.showTotal, rec.donationCount > 0 {
            donations.append("\(rec.total) \(tr("from", lang)) \(rec.donationCount) \(tr("donations", lang))")
        }
        if let name = rec.topName, let amount = rec.topAmount { donations.append("\(tr("top", lang)): \(name) \(amount)") }
        let moments = rec.moments.prefix(5).map { "\(hhmm($0.at)) \(label($0, lang))" }.joined(separator: " · ")
        let values = ["title": rec.title, "duration": duration(rec.duration), "peak": "\(rec.peak)", "avg": "\(rec.avg)",
                      "donations": donations.joined(separator: " · "), "goal": goalText(rec.goal, lang), "moments": moments,
                      "chatters": chattersText(rec, lang), "link": link(rec.slug)]
        return post(.recap, lang, values, custom)
    }

    /// A Moment ping: one short line about the moment, then the stream link (omitted without a slug).
    public static func ping(_ moment: Moment, slug: String, lang: String, custom: Custom = { _ in nil }) -> String {
        switch moment.kind {
        case .chatSpike: post(.pingWild, lang, ["link": link(slug)], custom)
        case .donation: post(.pingDonation, lang, ["user": moment.user, "amount": moment.detail, "link": link(slug)], custom)
        case .raid: post(.pingRaid, lang, ["user": moment.user, "viewers": moment.detail, "link": link(slug)], custom)
        }
    }

    /// Telegram limits: 1024 characters for a caption, 4096 for a text message.
    public static func fit(_ text: String, photo: Bool) -> String { String(text.prefix(photo ? 1024 : 4096)) }

    // MARK: parts

    private static func link(_ slug: String) -> String { slug.isEmpty ? "" : "kick.com/\(slug)" }

    private static func goalText(_ goal: GoalLine?, _ lang: String) -> String {
        guard let goal else { return "" }
        let name = goal.title.isEmpty ? "" : " \(tr("for", lang)) \(goal.title)"
        return "\(goal.pct)% \(tr("of", lang)) \(goal.target)\(name)"
    }

    private static func label(_ moment: Moment, _ lang: String) -> String {
        switch moment.kind {
        case .chatSpike: return tr("wild", lang)
        case .donation: return "\(moment.detail) \(tr("from", lang)) \(moment.user)"
        case .raid: return "\(tr("raid", lang)) \(moment.user) (\(moment.detail))"
        }
    }

    private static func chattersText(_ rec: Recap, _ lang: String) -> String {
        guard rec.chatters > 0 else { return "" }
        // trackingStarted: everyone looks new because counting began today, so don't claim they are.
        return "\(rec.chatters) \(tr(rec.trackingStarted ? "chatters" : "newChatters", lang))"
    }

    /// "2h 14m", or "14m" under an hour.
    public static func duration(_ span: TimeInterval) -> String {
        let minutes = max(0, Int(span)) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// Local time, 24 h.
    public static func hhmm(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "HH:mm"
        return format.string(from: date)
    }

    #if DEBUG
    public static func demo() {
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
        let values = ["title": "IRL", "city": "", "n": "3"]
        assert(render("A[ · {title}]\n📍 {city}\nn={n}", values) == "A · IRL\nn=3")
        assert(render("A[ · {city}]\n{typo}", values) == "A\n{typo}" && render("[{city}]", values).isEmpty)
        assert(live(Live(title: "IRL", slug: "s", viewers: 42), lang: "en", custom: { _ in "Live now: {title} ({viewers})" })
            == "Live now: IRL (42)")
        assert(announce(title: "", slug: "s", lang: "en", custom: { _ in "[{title}]" }) == "📣 Going live soon\n▶️ kick.com/s")
        applog("reach", "LivePostText.demo() passed")
    }
    #endif
}
