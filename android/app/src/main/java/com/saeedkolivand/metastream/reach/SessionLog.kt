package com.saeedkolivand.metastream.reach

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.bot.AppBot
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.goal.DonationPrices
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.goal.Rates
import com.saeedkolivand.metastream.overlay.WidgetLocation
import com.saeedkolivand.metastream.speech.SpeechSettings
import com.saeedkolivand.metastream.speech.isBlocked
import com.saeedkolivand.metastream.speech.offensive
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import java.io.File
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONObject

/**
 * Records the running stream session (iOS SessionLog): a per-minute timeline, Moments, donation totals and Chatters, saved
 * as JSON in filesDir/sessions when it ends (and every 5 min, so a crash hours in loses little). Chat text is never stored.
 * Main thread only.
 */
object SessionLog {
    private class Known(var name: String, val firstSeen: Long, var lastSeen: Long)

    var current: SessionRecord? = null
        private set

    /** The session that just ended, for the Session report sheet. */
    var justEnded by mutableStateOf<SessionRecord?>(null)

    /** The latest donation this session (name, display), for the Live post's "Last:" line. */
    var lastDonation: Pair<String, String>? = null
        private set
    private val registry = HashMap<String, Known>()
    private var minuteChat = 0
    private var minuteDonations = 0.0
    private var minuteNewChatters = 0
    private var lastSpikeAt: Long? = null
    private var holdingGps = false
    private lateinit var dir: File
    private lateinit var chattersFile: File
    private val anonymous = setOf("someone", "anonymous", "an anonymous cheerer")

    fun init(context: Context) {
        dir = File(context.filesDir, "sessions").apply { mkdirs() }
        chattersFile = File(context.filesDir, "chatters.json")
    }

    /** At least 20 messages this minute and 3x the mean of up to the previous 10 minutes (needs 3 of them). */
    fun isSpike(count: Int, previous: List<Int>): Boolean {
        val prev = previous.takeLast(10)
        if (prev.size < 3) return false
        return count >= 20 && count >= 3 * maxOf(prev.average(), 1.0)
    }

    fun isAnonymous(name: String) = name.trim().lowercase().let { it.isEmpty() || it in anonymous }

    /** The name the Live post may publish: the gate that keeps slurs off TTS and the widgets. */
    fun publicName(e: ChatEvent) = if (e.offensive) "Someone" else e.user

    fun begin(title: String) {
        loadRegistry()
        current = SessionRecord(System.currentTimeMillis(), title, GoalStore.config.currency, trackingStarted = registry.isEmpty())
        lastDonation = null
        minuteChat = 0
        minuteDonations = 0.0
        minuteNewChatters = 0
        lastSpikeAt = null
        if (!holdingGps) WidgetLocation.retain().also { holdingGps = true }
    }

    /** Every second while live; a sample on each minute boundary, then a look for a chat spike. */
    fun tick(viewers: Int, kbps: Int, drops: Int, downSeconds: Int) {
        val rec = current ?: return
        val now = System.currentTimeMillis()
        if ((now - rec.start) / 60_000 <= rec.samples.size) return
        if (rec.camera == null) rec.camera = cameraName()
        val previous = rec.samples.takeLast(10).map { it.chat }
        rec.samples +=
            SessionSample(rec.samples.size + 1, viewers, minuteChat, kbps, drops, downSeconds, minuteDonations, minuteNewChatters)
        WidgetLocation.cityText.takeIf { it != "--" && it !in rec.cities }?.let { rec.cities += it }
        if (isSpike(minuteChat, previous) && (lastSpikeAt?.let { now - it >= 300_000 } != false)) {
            lastSpikeAt = now
            rec.moments += Moment(now, Moment.SPIKE, "", "$minuteChat/min", minuteChat.toDouble())
        }
        minuteChat = 0
        minuteDonations = 0.0
        minuteNewChatters = 0
        if (rec.samples.size % 5 == 0) save(rec)
    }

    fun record(e: ChatEvent) {
        val rec = current ?: return
        when (e.kind) {
            Kind.Message -> message(rec, e)
            Kind.Tip, Kind.Cheer -> donation(rec, e)
            Kind.Raid -> if (e.count >= 10) rec.moments += Moment(e.time, Moment.RAID, publicName(e), "${e.count}", e.count.toDouble())
            else -> Unit
        }
    }

    /** Finishes and saves the session and the Chatter registry. */
    fun end(): SessionRecord? {
        val rec = current ?: return null
        rec.end = System.currentTimeMillis()
        rec.distanceMeters = WidgetLocation.metersSince(Engine.liveSince)
        current = null
        if (holdingGps) WidgetLocation.release().also { holdingGps = false }
        save(rec)
        saveRegistry()
        justEnded = rec
        return rec
    }

    private fun cameraName() = when (Engine.source) {
        Source.Screen -> "Screen share"
        Source.Glasses -> "Glasses"
        Source.Usb -> "External camera"
        Source.Phone -> "Phone camera"
    }

    private fun message(rec: SessionRecord, e: ChatEvent) {
        if (e.userId.isEmpty() || AppBot.isOwn(e)) return
        minuteChat++
        val key = "${e.platform}|${e.userId}"
        val first = key !in rec.chatterCounts
        rec.chatterCounts[key] = (rec.chatterCounts[key] ?: 0) + 1
        rec.chatterNames[key] = if (isBlocked(e.user, SpeechSettings.blocked)) "" else e.user // Wrapped may publish it later
        if (!first) return
        val now = System.currentTimeMillis()
        val known = registry[key]
        if (known != null) {
            known.name = rec.chatterNames[key].orEmpty()
            known.lastSeen = now
            rec.returningChatters++
        } else {
            registry[key] = Known(rec.chatterNames[key].orEmpty(), now, now)
            rec.newChatters++
            minuteNewChatters++
        }
    }

    private fun donation(rec: SessionRecord, e: ChatEvent) {
        if (e.platform == "test-donation") return
        val money = (if (e.kind == Kind.Tip) e.money else null) ?: DonationPrices.money(e) ?: return
        val converted = Rates.convert(money, GoalStore.config.currency)
        val name = publicName(e)
        rec.donationCount++
        if (converted != null) {
            rec.donationTotal += converted
            minuteDonations += converted.toDouble()
            if (!isAnonymous(name)) {
                if (converted > rec.topDonorAmount) {
                    rec.topDonor = name
                    rec.topDonorDisplay = money.display
                    rec.topDonorAmount = converted
                }
                rec.donors[name] = (rec.donors[name] ?: BigDecimal.ZERO) + converted
            }
        }
        lastDonation = name to money.display
        val threshold = Prefs.string("momentDonationEUR", "20").toDoubleOrNull() ?: 20.0
        Rates.convert(money, "EUR")?.takeIf { it.toDouble() >= threshold }?.let {
            rec.moments += Moment(e.time, Moment.DONATION, name, money.display, it.toDouble())
        }
    }

    // files

    private fun stamp(t: Long) = SimpleDateFormat("yyyy-MM-dd'T'HHmmss", Locale.US).format(Date(t))

    private fun file(rec: SessionRecord) = File(dir, "${stamp(rec.start)}.json")

    /** Every saved session, newest first; files that no longer parse are skipped. */
    fun all(): List<SessionRecord> = (dir.listFiles { f -> f.extension == "json" } ?: emptyArray())
        .mapNotNull { runCatching { SessionRecord.from(JSONObject(it.readText())) }.getOrNull() }.sortedByDescending { it.start }

    fun delete(rec: SessionRecord) = file(rec).delete()

    private fun save(rec: SessionRecord) = write(file(rec), rec.toJson().toString())

    private fun write(f: File, text: String) = runCatching {
        val tmp = File(f.path + ".tmp")
        tmp.writeText(text)
        tmp.renameTo(f)
    }.onFailure { applog("reach", "save ${f.name} failed") }

    private fun loadRegistry() {
        registry.clear()
        val o = runCatching { JSONObject(chattersFile.readText()) }.getOrNull() ?: return
        for (k in o.keys()) {
            val v = o.getJSONObject(k)
            registry[k] = Known(v.optString("name"), v.optLong("firstSeen"), v.optLong("lastSeen"))
        }
    }

    private fun saveRegistry() {
        val o = JSONObject()
        for ((k, v) in registry) o.put(k, JSONObject().put("name", v.name).put("firstSeen", v.firstSeen).put("lastSeen", v.lastSeen))
        write(chattersFile, o.toString())
    }
}
