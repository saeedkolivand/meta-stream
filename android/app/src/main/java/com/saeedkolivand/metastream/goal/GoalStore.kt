package com.saeedkolivand.metastream.goal

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Money
import java.io.File
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** [currency]: "IRT" (toman), "USD" or "EUR". [start]: raised before the app counted; [startedAt]: older site history doesn't count. */
data class GoalConfig(
    val title: String = "Goal",
    val target: BigDecimal = BigDecimal(500),
    val currency: String = "EUR",
    val start: BigDecimal = BigDecimal.ZERO,
    val startedAt: Long = System.currentTimeMillis()
)

enum class EntryState { Counted, Pending, Refunded, Test }

/** One donation; [id] is "<source>:<id>", the dedupe key; [value] in the goal currency, null while pending. */
data class GoalEntry(
    val id: String,
    val source: String,
    val original: Money,
    val value: BigDecimal?,
    val at: Long,
    val state: EntryState,
    val missed: Boolean = false,
    val note: String = ""
)

/**
 * The goal and its ledger (iOS GoalStore, adr/0006). Every donation is recorded once under its key, converted into the
 * goal currency when it arrives and kept at that value. Persisted as JSON in filesDir until the streamer resets it.
 * Main thread only.
 */
object GoalStore {
    var config by mutableStateOf(GoalConfig())
        private set
    var entries by mutableStateOf<List<GoalEntry>>(emptyList()) // newest first
        private set
    var reached by mutableStateOf(false)
        private set
    var onReached: () -> Unit = {}

    private const val MAX_ENTRIES = 1000
    private lateinit var file: File
    private lateinit var scope: CoroutineScope

    fun init(context: Context, scope: CoroutineScope) {
        this.scope = scope
        file = File(context.filesDir, "goal.json")
        runCatching { load(JSONObject(file.readText())) }
        Rates.onUpdate = ::resolvePending
        Rates.start(scope)
    }

    val total: BigDecimal
        get() = entries.filter { it.state == EntryState.Counted || it.state == EntryState.Test }
            .fold(config.start) { sum, e -> sum + (e.value ?: BigDecimal.ZERO) }

    val progress: Double get() = if (config.target.signum() > 0) total.divide(config.target, MathContext.DECIMAL64).toDouble() else 0.0

    val pendingCount get() = entries.count { it.state == EntryState.Pending }

    fun knows(key: String) = entries.any { it.id == key }

    fun money(d: BigDecimal) = Money(d, config.currency).display

    private fun convert(m: Money) = Rates.convert(m, config.currency)?.setScale(4, RoundingMode.HALF_UP)

    /** Records a donation once per key; false when already known or older than the goal. No rate = pending. */
    fun record(
        key: String,
        source: String,
        money: Money,
        at: Long = System.currentTimeMillis(),
        missed: Boolean = false,
        note: String = ""
    ): Boolean {
        if (money.amount.signum() <= 0 || knows(key) || at < config.startedAt) return false
        val value = convert(money)
        entries =
            (
                listOf(
                    GoalEntry(key, source, money, value, at, if (value == null) EntryState.Pending else EntryState.Counted, missed, note)
                ) +
                    entries
                )
                .take(MAX_ENTRIES)
        applog("goal", "$source ${money.display} -> ${value?.let(::money) ?: "pending"}${if (missed) " (missed)" else ""}")
        changed()
        return true
    }

    /** The site reports it refunded: out of the goal, kept in the list. */
    fun refund(key: String) {
        val e = entries.firstOrNull { it.id == key }?.takeIf { it.state == EntryState.Counted || it.state == EntryState.Pending } ?: return
        entries = entries.map { if (it === e) it.copy(state = EntryState.Refunded) else it }
        applog("goal", "$key refunded")
        changed()
    }

    /** Cash, a bank transfer: anything no source reports. A negative amount corrects a mistake. */
    fun addManual(money: Money, note: String) {
        val v = convert(money)
        entries =
            listOf(
                GoalEntry(
                    "manual:${UUID.randomUUID()}",
                    "manual",
                    money,
                    v,
                    System.currentTimeMillis(),
                    if (v ==
                        null
                    ) {
                        EntryState.Pending
                    } else {
                        EntryState.Counted
                    },
                    note = note
                )
            ) +
            entries
        changed()
    }

    /** A test donation: moves the bar for 10 s, then leaves no trace. */
    fun test(money: Money) {
        val key = "test:${UUID.randomUUID()}"
        entries =
            listOf(GoalEntry(key, "test", money, convert(money), System.currentTimeMillis(), EntryState.Test, note = "Test")) + entries
        scope.launch {
            delay(10_000)
            entries = entries.filter { it.id != key }
        }
    }

    /** Converts donations that waited for a rate (after every rate refresh). */
    fun resolvePending() {
        var any = false
        entries = entries.map { e ->
            if (e.state != EntryState.Pending) return@map e
            convert(e.original)?.let {
                any = true
                e.copy(value = it, state = EntryState.Counted)
            } ?: e
        }
        if (any) changed()
    }

    /** Title, target and start change any time; another currency starts a new goal ([reset]). */
    fun update(title: String, target: BigDecimal, start: BigDecimal) {
        config = config.copy(title = title, target = target, start = start)
        reached = total >= target
        changed()
    }

    fun reset(title: String, target: BigDecimal, currency: String, start: BigDecimal) {
        config = GoalConfig(title, target, currency, start)
        entries = emptyList()
        reached = false
        applog("goal", "goal reset: $title, target ${money(target)}")
        changed()
    }

    private fun changed() {
        if (!reached && config.target.signum() > 0 && total >= config.target) {
            reached = true
            applog("goal", "goal reached: ${money(total)} of ${money(config.target)}")
            onReached()
        }
        save()
    }

    private fun save() = runCatching {
        val c = config
        val list = JSONArray(
            entries.filter { it.state != EntryState.Test }.map { e ->
                JSONObject().put("id", e.id).put("source", e.source).put("amount", e.original.amount.toPlainString())
                    .put("currency", e.original.currency).put("value", e.value?.toPlainString() ?: "").put("at", e.at)
                    .put("state", e.state.name).put("missed", e.missed).put("note", e.note)
            }
        )
        val o = JSONObject().put("title", c.title).put("target", c.target.toPlainString()).put("currency", c.currency)
            .put("start", c.start.toPlainString()).put("startedAt", c.startedAt).put("reached", reached).put("entries", list)
        val tmp = File(file.path + ".tmp")
        tmp.writeText(o.toString())
        tmp.renameTo(file)
    }.onFailure { applog("goal", "goal save failed: ${it.message}") }

    private fun load(o: JSONObject) {
        config = GoalConfig(
            o.optString("title", "Goal"),
            o.optString("target").toBigDecimalOrNull() ?: BigDecimal(500),
            o.optString("currency", "EUR"),
            o.optString("start").toBigDecimalOrNull() ?: BigDecimal.ZERO,
            o.optLong("startedAt", System.currentTimeMillis())
        )
        reached = o.optBoolean("reached")
        val a = o.optJSONArray("entries") ?: JSONArray()
        entries = (0 until a.length()).mapNotNull { i ->
            val e = a.getJSONObject(i)
            val amount = e.optString("amount").toBigDecimalOrNull() ?: return@mapNotNull null
            GoalEntry(
                e.getString("id"),
                e.optString("source"),
                Money(amount, e.optString("currency")),
                e.optString("value").toBigDecimalOrNull(),
                e.optLong("at"),
                runCatching { EntryState.valueOf(e.optString("state")) }.getOrDefault(EntryState.Counted),
                e.optBoolean("missed"),
                e.optString("note")
            )
        }.filter { it.state != EntryState.Test }
    }
}

/** Donation sources record their own tips under their own ids, and test alerts never count. */
private val SELF_RECORDING = setOf("test-donation", "test", "donofa", "reymit", "streamelements", "donito")

/** Every money event from chat (tips, Bits, KICKs, subs) counts toward the goal once. */
fun countDonation(e: ChatEvent) {
    if (e.platform in SELF_RECORDING) return
    val m = DonationPrices.money(e) ?: return
    GoalStore.record(e.platform + ":" + e.msgId.ifEmpty { UUID.randomUUID().toString() }, e.platform, m, e.time, note = e.user)
}
