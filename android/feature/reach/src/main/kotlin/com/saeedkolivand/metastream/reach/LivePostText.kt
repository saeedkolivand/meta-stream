package com.saeedkolivand.metastream.reach

import com.saeedkolivand.metastream.core.storage.Prefs
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The words of the Live post (iOS LivePostText): templates (built-in, or the streamer's own from Settings) filled with plain
 * values. Built-in labels follow the language setting; titles and names stay as typed. Latin digits throughout. (Telegram
 * text, not on-stream: emoji are fine here.)
 */
object LivePostText {
    class GoalLine(val pct: Int, val target: String, val title: String)

    class Live(
        val title: String = "",
        val slug: String = "",
        val countdown: String? = null,
        val viewers: Int = 0,
        val elapsedMs: Long = 0,
        val reconnecting: Boolean = false,
        val goal: GoalLine? = null,
        val last: String? = null,
        val city: String? = null,
        val updated: Long = System.currentTimeMillis()
    )

    class Recap(
        val title: String = "",
        val slug: String = "",
        val durationMs: Long = 0,
        val peak: Int = 0,
        val avg: Int = 0,
        val donationCount: Int = 0,
        val total: String = "",
        val showTotal: Boolean = true,
        val topName: String? = null,
        val topAmount: String? = null,
        val goal: GoalLine? = null,
        val moments: List<Moment> = emptyList(),
        val chatters: Int = 0,
        val trackingStarted: Boolean = false
    )

    private val fa = mapOf(
        "soon" to "به‌زودی لایو", "live" to "لایو", "watching" to "بیننده", "goal" to "هدف", "of" to "از", "for" to "برای",
        "last" to "آخرین",
        "updated" to "به‌روزرسانی", "reconnecting" to "در حال اتصال دوباره…", "starting" to "شروع تا", "ended" to "لایو تمام شد",
        "peak" to "اوج", "avg" to "میانگین", "donations" to "دونیت", "top" to "بیشترین", "moments" to "لحظه‌ها",
        "wild" to "چت ترکوند", "from" to "از طرف", "raid" to "رید از", "newChatters" to "چتر جدید", "chatters" to "چتر",
        "thanks" to "ممنون از همه", "cancelled" to "امروز لغو شد",
        "pingWild" to "چت الان ترکونده", "pingDonation" to "دونیت بزرگ از طرف", "pingThanks" to "بیا تشکر کن",
        "pingRaid" to "رید از", "pingWith" to "با", "pingViewers" to "بیننده",
        "wrappedWild" to "چت ترکوند", "wrappedMsgs" to "پیام در دقیقه"
    )
    private val en = mapOf(
        "soon" to "Going live soon", "live" to "LIVE", "watching" to "watching", "goal" to "Goal", "of" to "of", "for" to "for",
        "last" to "Last",
        "updated" to "updated", "reconnecting" to "reconnecting…", "starting" to "Starting in", "ended" to "Stream ended",
        "peak" to "peak", "avg" to "avg", "donations" to "donations", "top" to "top", "moments" to "Moments",
        "wild" to "chat went wild", "from" to "from", "raid" to "raid from", "newChatters" to "new chatters", "chatters" to "chatters",
        "thanks" to "thanks everyone", "cancelled" to "Cancelled for today",
        "pingWild" to "Chat's going wild right now", "pingDonation" to "Big donation from", "pingThanks" to "come say thanks",
        "pingRaid" to "Raid from", "pingWith" to "with", "pingViewers" to "viewers",
        "wrappedWild" to "chat went wild", "wrappedMsgs" to "messages/min"
    )

    fun tr(key: String, lang: String) = (if (lang == "en") en else fa)[key] ?: key

    /** The posts whose words Settings › Telegram › Post texts can rewrite (iOS LivePostText.Kind), and their placeholders. */
    enum class Kind(val title: String, val keys: List<String>) {
        Announce("Announce", listOf("title", "link")),
        Starting("Starting countdown", listOf("countdown", "title", "link", "updated")),
        Live("Live", listOf("title", "viewers", "duration", "reconnecting", "goal", "last", "city", "link", "updated")),
        Recap("Recap", listOf("title", "duration", "peak", "avg", "donations", "goal", "moments", "chatters", "link")),
        Cancelled("Cancelled", emptyList()),
        PingDonation("Ping: big donation", listOf("user", "amount", "link")),
        PingRaid("Ping: raid", listOf("user", "viewers", "link")),
        PingWild("Ping: chat spike", listOf("link"));

        val pref get() = "tgText." + name.replaceFirstChar { it.lowercase() }
    }

    /** The streamer's own template for [k], or null for the built-in one. */
    fun stored(k: Kind): String? = Prefs.string(k.pref, "").ifBlank { null }

    /** Today's wording as a template: the labels in [lang], one line per piece of the post. */
    fun default(k: Kind, lang: String): String {
        fun t(key: String) = tr(key, lang)
        return when (k) {
            Kind.Announce -> "📣 ${t("soon")}[ · {title}]\n▶️ {link}"
            Kind.Starting -> "🟡 ${t("starting")} {countdown}[ · {title}]\n▶️ {link}\n${t("updated")} {updated}"
            Kind.Live ->
                "🔴 ${t("live")}[ · {title}]\n👁 {viewers} ${t("watching")} · ⏱ {duration}\n📡 {reconnecting}\n" +
                    "🎯 ${t("goal")}: {goal}\n💸 ${t("last")}: {last}\n📍 {city}\n▶️ {link}\n${t("updated")} {updated}"
            Kind.Recap ->
                "✅ ${t("ended")}[ · {title}]\n⏱ {duration} · 👁 ${t("peak")} {peak} · ${t("avg")} {avg}\n💸 {donations}\n" +
                    "🎯 ${t("goal")}: {goal}\n✨ ${t("moments")}: {moments}\n💬 {chatters} · ${t("thanks")} ❤️\n▶️ {link}"
            Kind.Cancelled -> "❌ ${t("cancelled")}"
            Kind.PingDonation -> "💸 ${t("pingDonation")} {user} ({amount}) — ${t("pingThanks")}\n▶️ {link}"
            Kind.PingRaid -> "🚀 ${t("pingRaid")} {user} ${t("pingWith")} {viewers} ${t("pingViewers")}\n▶️ {link}"
            Kind.PingWild -> "🔥 ${t("pingWild")}\n▶️ {link}"
        }
    }

    private val token = Regex("""\[([^\[\]]*)]|\{(\w+)\}""")
    private val key = Regex("""\{(\w+)\}""")

    /**
     * Fills a template line by line: an empty {key} hides its line, an empty one inside [ ] drops only that bracket, an
     * unknown {key} stays as typed so a typo shows. Values are inserted as they are (a title with braces stays text).
     */
    fun render(template: String, values: Map<String, String>): String = template.lines().mapNotNull { line ->
        var missing = false
        val out = token.replace(line) { m ->
            val optional = m.groups[1]
            if (optional != null) fill(optional.value, values) ?: "" else value(m.groupValues[2], values) { missing = true }
        }
        out.takeUnless { missing || (out.isBlank() && line.isNotBlank()) }
    }.joinToString("\n").trim()

    private fun fill(s: String, values: Map<String, String>): String? {
        var missing = false
        val out = key.replace(s) { value(it.groupValues[1], values) { missing = true } }
        return if (missing) null else out
    }

    private fun value(k: String, values: Map<String, String>, onEmpty: () -> Unit): String {
        val v = values[k] ?: return "{$k}"
        if (v.isEmpty()) onEmpty()
        return v
    }

    /** The streamer's template when it renders to something, else the built-in one (Telegram refuses an empty message). */
    private fun post(k: Kind, lang: String, values: Map<String, String>, custom: (Kind) -> String?) =
        custom(k)?.let { render(it, values) }?.ifBlank { null } ?: render(default(k, lang), values)

    fun announce(title: String, slug: String, lang: String, custom: (Kind) -> String? = { null }) =
        post(Kind.Announce, lang, mapOf("title" to title, "link" to link(slug)), custom)

    fun cancelled(lang: String, custom: (Kind) -> String? = { null }) = post(Kind.Cancelled, lang, emptyMap(), custom)

    /** A stream that ended without a record (the app was killed): no stats. */
    fun endedBare(lang: String) = "⚪️ " + tr("ended", lang)

    fun live(p: Live, lang: String, custom: (Kind) -> String? = { null }): String {
        val common = mapOf("title" to p.title, "link" to link(p.slug), "updated" to hhmm(p.updated))
        if (p.countdown != null) return post(Kind.Starting, lang, common + ("countdown" to p.countdown), custom)
        val up = !p.reconnecting
        return post(
            Kind.Live,
            lang,
            common + mapOf(
                "viewers" to if (up) "${p.viewers}" else "",
                "duration" to if (up) duration(p.elapsedMs) else "",
                "reconnecting" to if (up) "" else tr("reconnecting", lang),
                "goal" to goalText(p.goal, lang),
                "last" to p.last.orEmpty(),
                "city" to p.city.orEmpty()
            ),
            custom
        )
    }

    fun recap(r: Recap, lang: String, custom: (Kind) -> String? = { null }): String {
        val donations = listOfNotNull(
            if (r.showTotal && r.donationCount > 0) "${r.total} ${tr("from", lang)} ${r.donationCount} ${tr("donations", lang)}" else null,
            if (r.topName != null && r.topAmount != null) "${tr("top", lang)}: ${r.topName} ${r.topAmount}" else null
        ).joinToString(" · ")
        val moments = r.moments.take(5).joinToString(" · ") { "${hhmm(it.at)} ${label(it, lang)}" }
        // trackingStarted: everyone looks new because counting began today, so don't claim they are.
        val chatters = if (r.chatters > 0) "${r.chatters} ${tr(if (r.trackingStarted) "chatters" else "newChatters", lang)}" else ""
        val values = mapOf(
            "title" to r.title, "duration" to duration(r.durationMs), "peak" to "${r.peak}", "avg" to "${r.avg}",
            "donations" to donations, "goal" to goalText(r.goal, lang), "moments" to moments, "chatters" to chatters,
            "link" to link(r.slug)
        )
        return post(Kind.Recap, lang, values, custom)
    }

    fun ping(m: Moment, slug: String, lang: String, custom: (Kind) -> String? = { null }): String = when (m.kind) {
        Moment.DONATION -> post(Kind.PingDonation, lang, mapOf("user" to m.user, "amount" to m.detail, "link" to link(slug)), custom)
        Moment.RAID -> post(Kind.PingRaid, lang, mapOf("user" to m.user, "viewers" to m.detail, "link" to link(slug)), custom)
        else -> post(Kind.PingWild, lang, mapOf("link" to link(slug)), custom)
    }

    /** [k] filled with made-up values, for the editor's preview. */
    fun preview(k: Kind, lang: String, template: String): String {
        val c: (Kind) -> String? = { if (it == k) template else null }
        val title = "Walking through Cologne"
        val goal = GoalLine(45, "€500", "a new camera")
        val now = System.currentTimeMillis()
        return when (k) {
            Kind.Announce -> announce(title, "yourname", lang, c)
            Kind.Starting -> live(Live(title, "yourname", countdown = "4:59"), lang, c)
            Kind.Live -> live(Live(title, "yourname", viewers = 42, elapsedMs = 4_320_000, goal = goal, last = "Sara €10"), lang, c)
            Kind.Recap -> recap(
                Recap(
                    title, "yourname", 8_040_000, 87, 51, 6, "€140", true, "Sara", "€50", goal,
                    listOf(Moment(now - 3_600_000, Moment.SPIKE, "", "30/min")), 23
                ),
                lang,
                c
            )
            Kind.Cancelled -> cancelled(lang, c)
            Kind.PingDonation -> ping(Moment(now, Moment.DONATION, "Sara", "€25"), "yourname", lang, c)
            Kind.PingRaid -> ping(Moment(now, Moment.RAID, "Ali", "40"), "yourname", lang, c)
            Kind.PingWild -> ping(Moment(now, Moment.SPIKE, "", "30/min"), "yourname", lang, c)
        }
    }

    /** Telegram limits: 1024 characters for a caption, 4096 for a text message. */
    fun fit(text: String, photo: Boolean) = text.take(if (photo) 1024 else 4096)

    private fun link(slug: String) = if (slug.isEmpty()) "" else "kick.com/$slug"

    private fun goalText(g: GoalLine?, lang: String) = g?.let {
        "${it.pct}% ${tr("of", lang)} ${it.target}" + if (it.title.isEmpty()) "" else " ${tr("for", lang)} ${it.title}"
    }.orEmpty()

    private fun label(m: Moment, lang: String) = when (m.kind) {
        Moment.DONATION -> "${m.detail} ${tr("from", lang)} ${m.user}"
        Moment.RAID -> "${tr("raid", lang)} ${m.user} (${m.detail})"
        else -> tr("wild", lang)
    }

    /** "2h 14m", or "14m" under an hour. */
    fun duration(ms: Long): String {
        val m = maxOf(0L, ms) / 60_000
        return if (m >= 60) "${m / 60}h ${m % 60}m" else "${m}m"
    }

    fun hhmm(t: Long): String = SimpleDateFormat("HH:mm", Locale.US).format(Date(t))
}
