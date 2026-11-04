package com.saeedkolivand.metastream.reach

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The words of the Live post (iOS LivePostText), pure functions of plain values. Labels follow the language setting; titles
 * and names stay as typed. Latin digits throughout. (Telegram text, not on-stream: emoji are fine here.)
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

    fun announce(title: String, slug: String, lang: String) = join("📣 " + head(tr("soon", lang), title), link(slug))

    fun cancelled(lang: String) = "❌ " + tr("cancelled", lang)

    /** A stream that ended without a record (the app was killed): no stats. */
    fun endedBare(lang: String) = "⚪️ " + tr("ended", lang)

    fun live(p: Live, lang: String): String {
        val up = "${tr("updated", lang)} ${hhmm(p.updated)}"
        if (p.countdown != null) return join("🟡 " + head("${tr("starting", lang)} ${p.countdown}", p.title), link(p.slug), up)
        val watching = if (p.reconnecting) {
            "📡 " + tr(
                "reconnecting",
                lang
            )
        } else {
            "👁 ${p.viewers} ${tr("watching", lang)} · ⏱ ${duration(p.elapsedMs)}"
        }
        return join(
            "🔴 " + head(tr("live", lang), p.title),
            watching,
            goalLine(p.goal, lang),
            p.last?.let { "💸 ${tr("last", lang)}: $it" },
            p.city?.let { "📍 $it" },
            link(p.slug),
            up
        )
    }

    fun recap(r: Recap, lang: String): String {
        val donation = listOfNotNull(
            if (r.showTotal && r.donationCount > 0) "${r.total} ${tr("from", lang)} ${r.donationCount} ${tr("donations", lang)}" else null,
            if (r.topName != null && r.topAmount != null) "${tr("top", lang)}: ${r.topName} ${r.topAmount}" else null
        ).takeIf { it.isNotEmpty() }?.let { "💸 " + it.joinToString(" · ") }
        val moments = r.moments.takeIf { it.isNotEmpty() }?.let { m ->
            "✨ ${tr("moments", lang)}: " + m.take(5).joinToString(" · ") { "${hhmm(it.at)} ${label(it, lang)}" }
        }
        // trackingStarted: everyone looks new because counting began today, so don't claim they are.
        val chatters = if (r.chatters >
            0
        ) {
            "💬 ${r.chatters} ${tr(if (r.trackingStarted) "chatters" else "newChatters", lang)} · ${tr("thanks", lang)} ❤️"
        } else {
            null
        }
        return join(
            "✅ " + head(tr("ended", lang), r.title),
            "⏱ ${duration(r.durationMs)} · 👁 ${tr("peak", lang)} ${r.peak} · ${tr("avg", lang)} ${r.avg}",
            donation,
            goalLine(r.goal, lang),
            moments,
            chatters,
            link(r.slug)
        )
    }

    fun ping(m: Moment, slug: String, lang: String): String {
        val line = when (m.kind) {
            Moment.DONATION -> "💸 ${tr("pingDonation", lang)} ${m.user} (${m.detail}) — ${tr("pingThanks", lang)}"
            Moment.RAID -> "🚀 ${tr("pingRaid", lang)} ${m.user} ${tr("pingWith", lang)} ${m.detail} ${tr("pingViewers", lang)}"
            else -> "🔥 " + tr("pingWild", lang)
        }
        return join(line, link(slug))
    }

    /** Telegram limits: 1024 characters for a caption, 4096 for a text message. */
    fun fit(text: String, photo: Boolean) = text.take(if (photo) 1024 else 4096)

    private fun head(label: String, title: String) = if (title.isEmpty()) label else "$label · $title"

    private fun link(slug: String) = if (slug.isEmpty()) null else "▶️ kick.com/$slug"

    private fun join(vararg lines: String?) = lines.filterNotNull().joinToString("\n")

    private fun goalLine(g: GoalLine?, lang: String) = g?.let {
        "🎯 ${tr("goal", lang)}: ${it.pct}% ${tr("of", lang)} ${it.target}" +
            if (it.title.isEmpty()) "" else " ${tr("for", lang)} ${it.title}"
    }

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
