package com.saeedkolivand.metastream.goal

import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.time.OffsetDateTime
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject

/** One donation as a site reports it. */
internal data class Parsed(val id: String, val name: String, val message: String, val money: Money, val date: Long, val state: State) {
    enum class State { Paid, Pending, Refunded }
}

/** Which JSON keys carry which field, first non-empty wins (the sites' shapes are partly undocumented). */
internal class Shape(
    val id: List<String>,
    val amount: List<String>,
    val currency: List<String>,
    val name: List<String>,
    val message: List<String>,
    val date: List<String>
) {
    companion object {
        val donofa = Shape(listOf("id"), listOf("amount"), listOf("currency"), listOf("name"), listOf("message"), listOf("created_at"))
        val reymit = Shape(
            listOf("id", "_id", "donate_id"),
            listOf("amount", "price", "value"),
            listOf("currency", "type"),
            listOf("name", "donator", "donor_name", "user"),
            listOf("message", "text", "description"),
            listOf("created_at", "date", "time")
        )
    }
}

/** iOS DonationHub's parsing statics. */
internal object DonationParse {
    /** A string, number or {code/symbol/name/username} object as text; "" for anything else. */
    fun text(v: Any?): String = when (v) {
        is String -> v.trim()
        is Number -> if (v is Double || v is Float) BigDecimal(v.toString()).stripTrailingZeros().toPlainString() else v.toString()
        is JSONObject -> listOf("code", "symbol", "name", "username").map { text(v.opt(it)) }.firstOrNull { it.isNotEmpty() }.orEmpty()
        else -> ""
    }

    fun first(d: JSONObject, keys: List<String>): Any? = keys.mapNotNull { d.opt(it) }.firstOrNull { text(it).isNotEmpty() }

    /** An amount as exact money text: thousands commas dropped, never through Double arithmetic. */
    fun decimal(v: Any?): BigDecimal? = text(v).replace(",", "").toBigDecimalOrNull()

    /** The donation objects in a response: a top-level array, or under data/donates/result/docs (nesting allowed). */
    fun items(j: Any?): List<JSONObject> {
        if (j is JSONArray) return (0 until j.length()).mapNotNull { j.optJSONObject(it) }
        if (j !is JSONObject) return emptyList()
        for (k in listOf("data", "donates", "result", "docs")) items(j.opt(k)).takeIf { it.isNotEmpty() }?.let { return it }
        return emptyList()
    }

    /** "toman…" or nothing is toman, the sites' default. */
    fun currency(raw: String) = if (raw.isEmpty() || raw.lowercase().startsWith("toman")) "IRT" else raw

    fun parse(d: JSONObject, shape: Shape): Parsed? {
        val id = text(first(d, shape.id))
        val amount = decimal(first(d, shape.amount))?.takeIf { it.signum() > 0 } ?: return null
        if (id.isEmpty()) return null
        val name = text(first(d, shape.name))
        return Parsed(
            id,
            name.ifEmpty { "Someone" },
            text(first(d, shape.message)),
            Money.of(amount, currency(text(first(d, shape.currency)))),
            date(first(d, shape.date)) ?: System.currentTimeMillis(),
            state(d.opt("status"))
        )
    }

    /** {"_id", "donation": {"user": {"username"}, "message", "amount", "currency"}, "status", "createdAt"}. */
    fun parseStreamElements(d: JSONObject): Parsed? {
        val don = d.optJSONObject("donation") ?: return null
        val flat = JSONObject().put("id", d.opt("_id")).put("status", d.opt("status")).put("created_at", d.opt("createdAt"))
            .put("name", don.optJSONObject("user")?.opt("username")).put("message", don.opt("message"))
            .put("amount", don.opt("amount")).put("currency", don.opt("currency"))
        return parse(flat, Shape.donofa)
    }

    /** "paid"/1 counts, "refunded"/3 is refunded, anything else is pending; a missing status counts as paid. */
    fun state(v: Any?): Parsed.State = when (v) {
        is String -> when (v.lowercase()) {
            "", "paid", "success", "completed", "succeeded" -> Parsed.State.Paid
            "refunded", "refund" -> Parsed.State.Refunded
            else -> Parsed.State.Pending
        }
        is Number -> when (v.toInt()) {
            1 -> Parsed.State.Paid
            3 -> Parsed.State.Refunded
            else -> Parsed.State.Pending
        }
        else -> Parsed.State.Paid
    }

    /** ISO 8601, "yyyy-MM-dd HH:mm:ss" (taken as UTC: ponytail, the sites don't say) or unix seconds/milliseconds. */
    fun date(v: Any?): Long? {
        fun unix(t: Double) = (if (t > 1e12) t else t * 1000).toLong()
        if (v is Number) return unix(v.toDouble())
        val s = (v as? String)?.trim() ?: return null
        s.toDoubleOrNull()?.let { return unix(it) }
        runCatching { return OffsetDateTime.parse(s).toInstant().toEpochMilli() }
        return runCatching {
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.parse(s)?.time
        }.getOrNull()
    }
}
