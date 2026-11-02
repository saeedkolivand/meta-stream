package com.saeedkolivand.metastream.reach

import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.goal.DonatePage
import com.saeedkolivand.metastream.goal.Money
import com.saeedkolivand.metastream.platforms.TokenStore
import com.saeedkolivand.metastream.platforms.http
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

/**
 * The body of the monthly Wrapped page (iOS WrappedDraft): exactly the keys the donate page accepts. Never a date or a place,
 * only city names. km, donations and bestMoment are sent as JSON null when absent (the server rejects a missing key).
 */
data class WrappedDraft(
    val month: String,
    val streams: Int,
    val hours: Double,
    val km: Double?,
    val cities: List<String>,
    val peakViewers: Int,
    val avgViewers: Int,
    val newChatters: Int,
    val topChatters: List<Pair<String, Int>>,
    val topDonors: List<Pair<String, String>>,
    val donations: Pair<Int, String>?,
    val bestMoment: Pair<String, String>?,
    val publishedAt: String
) {
    fun toJson(): JSONObject = JSONObject().put("month", month).put("streams", streams).put("hours", hours)
        .put("km", km ?: JSONObject.NULL).put("cities", JSONArray(cities)).put("peakViewers", peakViewers)
        .put("avgViewers", avgViewers).put("newChatters", newChatters)
        .put("topChatters", JSONArray(topChatters.map { JSONObject().put("name", it.first).put("messages", it.second) }))
        .put("topDonors", JSONArray(topDonors.map { JSONObject().put("name", it.first).put("amount", it.second) }))
        .put("donations", donations?.let { JSONObject().put("count", it.first).put("total", it.second) } ?: JSONObject.NULL)
        .put("bestMoment", bestMoment?.let { JSONObject().put("kind", it.first).put("label", it.second) } ?: JSONObject.NULL)
        .put("publishedAt", publishedAt)
}

/** Sums a month of session records into a draft. Pure. */
object WrappedBuilder {
    fun monthKey(t: Long, tz: TimeZone = TimeZone.getDefault()): String =
        SimpleDateFormat("yyyy-MM", Locale.US).apply { timeZone = tz }.format(Date(t))

    private fun String.cut(n: Int) = take(n)

    fun build(month: String, records: List<SessionRecord>, lang: String, tz: TimeZone = TimeZone.getDefault()): WrappedDraft? {
        val sessions = records.filter { monthKey(it.start, tz) == month }.sortedBy { it.start }
        if (sessions.isEmpty()) return null
        val live = sessions.flatMap { it.samples }.map { it.viewers }.filter { it > 0 }
        val meters = sessions.sumOf { it.distanceMeters }
        val hours = sessions.sumOf { it.durationMs } / 3_600_000.0
        val (donors, total) = donations(sessions)
        return WrappedDraft(
            month, sessions.size, (hours * 10).roundToLong() / 10.0, if (meters > 0) (meters / 100).roundToLong() / 10.0 else null,
            sessions.flatMap { it.cities }.distinct().take(30).map { it.cut(40) }, sessions.maxOf { it.peakViewers },
            if (live.isEmpty()) 0 else live.sum() / live.size, sessions.sumOf { it.newChatters }, chatters(sessions), donors, total,
            bestMoment(sessions.flatMap { it.moments }, lang), Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()
        )
    }

    private fun chatters(sessions: List<SessionRecord>): List<Pair<String, Int>> {
        val counts = HashMap<String, Int>()
        val names = HashMap<String, String>()
        for (s in sessions) { // sorted by start, so the latest non-empty name wins
            s.chatterCounts.forEach { (k, n) -> counts[k] = (counts[k] ?: 0) + n }
            s.chatterNames.forEach { (k, n) -> if (n.isNotEmpty()) names[k] = n }
        }
        return counts.mapNotNull { (k, n) -> names[k]?.let { it.cut(40) to n } }
            .sortedWith(compareByDescending<Pair<String, Int>> { it.second }.thenBy { it.first }).take(10)
    }

    // ponytail: a month that switched goal currency drops the minority currency from donors and the total.
    private fun donations(sessions: List<SessionRecord>): Pair<List<Pair<String, String>>, Pair<Int, String>?> {
        val (cur, group) = sessions.groupBy { it.currency }.entries
            .maxWithOrNull(compareBy<Map.Entry<String, List<SessionRecord>>> { it.value.size }.thenBy { it.key })
            ?: return emptyList<Pair<String, String>>() to null
        val sums = HashMap<String, BigDecimal>()
        group.forEach { s -> s.donors.forEach { (n, a) -> sums[n] = (sums[n] ?: BigDecimal.ZERO) + a } }
        val donors = sums.filterKeys {
            it.isNotEmpty()
        }.entries.sortedWith(compareByDescending<Map.Entry<String, BigDecimal>> { it.value }.thenBy { it.key })
            .take(10).map { it.key.cut(40) to Money(it.value, cur).display.cut(24) }
        val count = group.sumOf { it.donationCount }
        val total = group.fold(BigDecimal.ZERO) { a, s -> a + s.donationTotal }
        return donors to if (count > 0) count to Money(total, cur).display.cut(24) else null
    }

    private fun bestMoment(moments: List<Moment>, lang: String): Pair<String, String>? {
        fun best(kind: String) = moments.filter { it.kind == kind }.maxByOrNull { it.value }
        fun tr(k: String) = LivePostText.tr(k, lang)
        best(Moment.SPIKE)?.let { return Moment.SPIKE to "${tr("wrappedWild")} — ${it.value.toInt()} ${tr("wrappedMsgs")}".cut(80) }
        best(Moment.RAID)?.let {
            return Moment.RAID to
                "${tr("raid")} ${it.user} ${tr("pingWith")} ${it.detail} ${tr("pingViewers")}".cut(80)
        }
        return best(Moment.DONATION)?.let { Moment.DONATION to "${it.detail} ${tr("from")} ${it.user}".cut(80) }
    }
}

/** Which months were published or turned down, which one waits for review, and sending to the donate page. */
object WrappedStore {
    const val PUBLISHED = "wrappedPublished"
    const val DISMISSED = "wrappedDismissed"

    val lang get() = if (Prefs.string("telegramLang", "fa") == "en") "en" else "fa"

    fun months(key: String) = Prefs.string(key, "").split(',').filter { it.isNotEmpty() }.toSet()

    fun add(month: String, key: String) = Prefs.put(key, (months(key) + month).joinToString(","))

    fun remove(month: String, key: String) = Prefs.put(key, (months(key) - month).joinToString(","))

    fun allMonths(records: List<SessionRecord>) = records.map { WrappedBuilder.monthKey(it.start) }.distinct().sortedDescending()

    /** The previous calendar month, when it has a session and was neither published nor dismissed. */
    fun pendingMonth(records: List<SessionRecord>): String? {
        val month = WrappedBuilder.monthKey(Calendar.getInstance().apply { add(Calendar.MONTH, -1) }.timeInMillis)
        return month.takeIf {
            it !in months(PUBLISHED) + months(DISMISSED) && records.any { r -> WrappedBuilder.monthKey(r.start) == month }
        }
    }

    fun monthName(month: String): String = runCatching {
        SimpleDateFormat("LLLL yyyy", Locale.getDefault()).format(SimpleDateFormat("yyyy-MM", Locale.US).parse(month)!!)
    }.getOrDefault(month)

    /** "https://donate.iamsaeed.dev/wrapped/2026-09", or ".../fa/wrapped/..." in Persian. */
    fun pageLink(month: String) = DonatePage.chatURL + (if (lang == "fa") "/fa/wrapped/" else "/wrapped/") + month

    /** null on success, else a short error. Same key and guard as the goal publisher; never logs the key. */
    suspend fun publish(d: WrappedDraft): String? {
        val body = d.toJson().toString()
        if (body.toByteArray().size > 8192) return "Too big"
        return send("POST", "", body)
    }

    suspend fun withdraw(month: String) = send("DELETE", "?month=$month", null)

    private suspend fun send(method: String, query: String, body: String?): String? {
        val key = TokenStore.get("donatePageToken").orEmpty().ifEmpty { return "No key" }
        val url = DonatePage.endpoint("/api/wrapped$query") ?: return "Needs an https:// URL"
        val code = withContext(Dispatchers.IO) {
            runCatching {
                val req = Request.Builder().url(url).header("Authorization", "Bearer $key")
                    .method(method, body?.toRequestBody("application/json".toMediaType())).build()
                http.newCall(req).execute().use { it.code }
            }.getOrDefault(0)
        }
        return when {
            code in 200..299 || (method == "DELETE" && code == 404) -> null
            code == 401 || code == 403 -> "Key rejected"
            code == 0 -> "Can't reach the page"
            else -> "HTTP $code"
        }
    }
}
