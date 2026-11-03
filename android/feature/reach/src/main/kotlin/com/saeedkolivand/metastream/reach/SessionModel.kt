package com.saeedkolivand.metastream.reach

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject

/** One minute of a stream session: what the Session report's timeline and the recap's peak/average read from. */
data class SessionSample(
    val minute: Int,
    val viewers: Int,
    val chat: Int,
    val kbps: Int,
    val drops: Int,
    val downSeconds: Int,
    val donations: Double = 0.0,
    val newChatters: Int = 0
)

/** A point worth coming back for. [detail]: money display, raid viewers, or messages per minute; [value]: EUR / viewers / msgs. */
data class Moment(val at: Long, val kind: String, val user: String, val detail: String, val value: Double = 0.0) {
    companion object {
        const val SPIKE = "chatSpike"
        const val DONATION = "donation"
        const val RAID = "raid"
    }
}

/** Everything kept about one stream session (iOS SessionRecord). Chat text is never stored, only counts per Chatter key. */
class SessionRecord(val start: Long, var title: String, var currency: String, var trackingStarted: Boolean = false) {
    var end: Long? = null
    val samples = ArrayList<SessionSample>()
    val moments = ArrayList<Moment>()
    var donationCount = 0
    var donationTotal: BigDecimal = BigDecimal.ZERO
    var topDonor: String? = null
    var topDonorDisplay: String? = null
    var topDonorAmount: BigDecimal = BigDecimal.ZERO
    val chatterCounts = HashMap<String, Int>()
    val chatterNames = HashMap<String, String>()
    var newChatters = 0
    var returningChatters = 0
    var distanceMeters = 0.0
    val cities = ArrayList<String>()
    val donors = HashMap<String, BigDecimal>() // public name -> total in [currency]; anonymous excluded
    var camera: String? = null

    val peakViewers get() = samples.maxOfOrNull { it.viewers } ?: 0
    val avgViewers get() = samples.map { it.viewers }.filter { it > 0 }.let { if (it.isEmpty()) 0 else it.sum() / it.size }
    val durationMs get() = (end ?: System.currentTimeMillis()) - start

    fun toJson(): JSONObject = JSONObject().put("start", start).put("end", end).put("title", title).put("currency", currency)
        .put("trackingStarted", trackingStarted)
        .put(
            "samples",
            JSONArray(
                samples.map {
                    JSONObject().put("minute", it.minute).put("viewers", it.viewers).put("chat", it.chat).put("kbps", it.kbps)
                        .put(
                            "drops",
                            it.drops
                        ).put("downSeconds", it.downSeconds).put("donations", it.donations).put("newChatters", it.newChatters)
                }
            )
        )
        .put(
            "moments",
            JSONArray(
                moments.map {
                    JSONObject().put("at", it.at).put("kind", it.kind).put("user", it.user).put("detail", it.detail).put("value", it.value)
                }
            )
        )
        .put("donationCount", donationCount).put("donationTotal", donationTotal.toPlainString()).put("topDonor", topDonor)
        .put("topDonorDisplay", topDonorDisplay).put("topDonorAmount", topDonorAmount.toPlainString())
        .put("chatterCounts", JSONObject(chatterCounts as Map<*, *>)).put("chatterNames", JSONObject(chatterNames as Map<*, *>))
        .put("newChatters", newChatters).put("returningChatters", returningChatters).put("distanceMeters", distanceMeters)
        .put("cities", JSONArray(cities)).put("donors", JSONObject(donors.mapValues { it.value.toPlainString() })).put("camera", camera)

    companion object {
        fun from(o: JSONObject): SessionRecord {
            val r = SessionRecord(o.getLong("start"), o.optString("title"), o.optString("currency", "EUR"), o.optBoolean("trackingStarted"))
            r.end = if (o.isNull("end")) null else o.optLong("end")
            o.optJSONArray("samples")?.let { a ->
                for (i in 0 until a.length()) {
                    val s = a.getJSONObject(i)
                    r.samples += SessionSample(
                        s.optInt("minute"),
                        s.optInt("viewers"),
                        s.optInt("chat"),
                        s.optInt("kbps"),
                        s.optInt("drops"),
                        s.optInt("downSeconds"),
                        s.optDouble("donations", 0.0),
                        s.optInt("newChatters")
                    )
                }
            }
            o.optJSONArray("moments")?.let { a ->
                for (i in 0 until a.length()) {
                    val m = a.getJSONObject(i)
                    r.moments +=
                        Moment(m.optLong("at"), m.optString("kind"), m.optString("user"), m.optString("detail"), m.optDouble("value", 0.0))
                }
            }
            r.donationCount = o.optInt("donationCount")
            r.donationTotal = o.optString("donationTotal").toBigDecimalOrNull() ?: BigDecimal.ZERO
            r.topDonor = o.optString("topDonor").takeIf { !o.isNull("topDonor") && it.isNotEmpty() }
            r.topDonorDisplay = o.optString("topDonorDisplay").takeIf { !o.isNull("topDonorDisplay") && it.isNotEmpty() }
            r.topDonorAmount = o.optString("topDonorAmount").toBigDecimalOrNull() ?: BigDecimal.ZERO
            o.optJSONObject("chatterCounts")?.let { c -> c.keys().forEach { r.chatterCounts[it] = c.optInt(it) } }
            o.optJSONObject("chatterNames")?.let { c -> c.keys().forEach { r.chatterNames[it] = c.optString(it) } }
            r.newChatters = o.optInt("newChatters")
            r.returningChatters = o.optInt("returningChatters")
            r.distanceMeters = o.optDouble("distanceMeters", 0.0)
            o.optJSONArray("cities")?.let { a -> for (i in 0 until a.length()) r.cities += a.getString(i) }
            o.optJSONObject("donors")?.let { d -> d.keys().forEach { k -> d.optString(k).toBigDecimalOrNull()?.let { r.donors[k] = it } } }
            r.camera = o.optString("camera").takeIf { !o.isNull("camera") && it.isNotEmpty() }
            return r
        }
    }
}
