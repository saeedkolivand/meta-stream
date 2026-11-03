package com.saeedkolivand.metastream.goal

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.platforms.http
import java.math.BigDecimal
import java.math.MathContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

data class Quote(val value: BigDecimal, val at: Long)

/**
 * Market rates for the goal (adr/0006): toman per US dollar from Nobitex's USDT price, dollars per euro from the ECB
 * (frankfurter.app), crypto in dollars from CoinGecko. Refreshed every 10 minutes and kept across launches. The
 * streamer's own toman rate, when set, replaces Nobitex. A rate older than a day (the ECB: 4 days) is never used.
 */
object Rates {
    var tomanPerUsd by mutableStateOf<Quote?>(null)
        private set
    var usdPerEur by mutableStateOf<Quote?>(null)
        private set
    private var crypto = mapOf<String, Quote>()
    var onUpdate: () -> Unit = {}

    private const val MAX_AGE = 24 * 3600_000L
    private const val ECB_MAX_AGE = 4 * 24 * 3600_000L
    private val MC = MathContext.DECIMAL64

    /** CoinGecko ids for the coins donation sites take. */
    val coins = mapOf(
        "BTC" to "bitcoin", "ETH" to "ethereum", "TON" to "the-open-network", "TRX" to "tron", "BNB" to "binancecoin",
        "SOL" to "solana", "LTC" to "litecoin", "DOGE" to "dogecoin", "XRP" to "ripple", "ADA" to "cardano", "NOT" to "notcoin",
        "USDT" to "tether", "USDC" to "usd-coin", "DAI" to "dai"
    )

    /** The streamer's rate in toman per euro, 0 = none (Settings › Goal). */
    val manualTomanPerEur get() = Prefs.string("goalManualTomanPerEUR").toBigDecimalOrNull() ?: BigDecimal.ZERO

    fun start(scope: CoroutineScope) {
        load()
        scope.launch {
            while (true) {
                refresh()
                delay(600_000)
            }
        }
    }

    suspend fun refresh() {
        val (t, e, c) = withContext(Dispatchers.IO) {
            val t = async { fetchNobitex() }
            val e = async { fetchEcb() }
            val c = async { fetchCoinGecko() }
            Triple(t.await(), e.await(), c.await())
        }
        val now = System.currentTimeMillis()
        t?.let { tomanPerUsd = Quote(it, now) }
        e?.let { usdPerEur = Quote(it, now) }
        crypto = crypto + c.mapValues { Quote(it.value, now) }
        save()
        applog("goal", "rates: toman/USD ${t ?: "failed"}, USD/EUR ${e ?: "failed"}, ${c.size} coins")
        onUpdate()
    }

    /** [m] in [target] ("IRT", "USD" or "EUR"), or null when a rate it needs is missing or too old. */
    fun convert(m0: Money, target: String, now: Long = System.currentTimeMillis()): BigDecimal? {
        val m = m0.inToman
        if (m.currency == target) return m.amount
        val usd = usdValue(m, now) ?: return null
        return when (target) {
            "USD" -> usd
            "EUR" -> eurRate(now)?.let { usd.divide(it, MC) }
            "IRT" -> tomanRate(now)?.let { usd * it }
            else -> null
        }
    }

    private fun usdValue(m: Money, now: Long): BigDecimal? = when (m.currency) {
        "USD", "USDT", "USDC", "DAI" -> m.amount // ponytail: stablecoins at par
        "EUR" -> eurRate(now)?.let { m.amount * it }
        "IRT" -> tomanRate(now)?.let { m.amount.divide(it, MC) }
        else -> fresh(crypto[m.currency], now, MAX_AGE)?.let { m.amount * it }
    }

    private fun eurRate(now: Long) = fresh(usdPerEur, now, ECB_MAX_AGE)

    /** Toman per dollar: the streamer's rate when set (it overrides), else Nobitex if under a day old. */
    fun tomanRate(now: Long = System.currentTimeMillis()): BigDecimal? {
        val manual = manualTomanPerEur
        // ponytail: the euro-dollar rate barely moves; 1.08 only if it was never fetched.
        if (manual.signum() > 0) return manual.divide(usdPerEur?.value ?: BigDecimal("1.08"), MC)
        return fresh(tomanPerUsd, now, MAX_AGE)
    }

    val tomanPerEuro get() = tomanRate()?.let { r -> eurRate(System.currentTimeMillis())?.let { r * it } }

    private fun fresh(q: Quote?, now: Long, maxAge: Long) = q?.takeIf { it.value.signum() > 0 && now - it.at <= maxAge }?.value

    /** For Settings: where the toman rate comes from right now. */
    val tomanSource: String
        get() {
            if (manualTomanPerEur.signum() > 0) return "Your rate"
            val q = tomanPerUsd ?: return "No rate yet"
            val mins = (System.currentTimeMillis() - q.at) / 60_000
            val age = if (mins < 60) "$mins min ago" else "${mins / 60} h ago"
            return if (System.currentTimeMillis() - q.at > MAX_AGE) "Nobitex, too old ($age)" else "Nobitex, $age"
        }

    private fun get(req: Request): JSONObject? = runCatching {
        http.newCall(req).execute().use { r -> if (r.isSuccessful) JSONObject(r.body?.string().orEmpty()) else null }
    }.getOrNull()

    /** {"stats":{"usdt-rls":{"latest":"<rials>"}}}. apiv2 answers from abroad; api is for networks inside Iran. */
    private fun fetchNobitex(): BigDecimal? {
        for (host in listOf("apiv2.nobitex.ir", "api.nobitex.ir")) {
            val body = """{"srcCurrency":"usdt","dstCurrency":"rls"}""".toRequestBody("application/json".toMediaType())
            val rials = get(Request.Builder().url("https://$host/market/stats").post(body).build())
                ?.optJSONObject("stats")?.optJSONObject("usdt-rls")?.optString("latest")?.toBigDecimalOrNull()
            if (rials != null && rials.signum() > 0) return rials.divide(BigDecimal.TEN)
        }
        applog("goal", "Nobitex rate unavailable")
        return null
    }

    /** {"rates":{"USD":1.08}}: dollars per euro. */
    private fun fetchEcb() = get(Request.Builder().url("https://api.frankfurter.app/latest?from=EUR&to=USD").build())
        ?.optJSONObject("rates")?.opt("USD")?.toString()?.toBigDecimalOrNull()?.takeIf { it.signum() > 0 }

    private fun fetchCoinGecko(): Map<String, BigDecimal> {
        val ids = coins.values.toSortedSet().joinToString(",")
        val j =
            get(Request.Builder().url("https://api.coingecko.com/api/v3/simple/price?ids=$ids&vs_currencies=usd").build())
                ?: return emptyMap()
        return coins.mapNotNull { (sym, id) ->
            j.optJSONObject(id)?.opt("usd")?.toString()?.toBigDecimalOrNull()?.takeIf { it.signum() > 0 }?.let { sym to it }
        }.toMap()
    }

    private fun Quote.json() = JSONObject().put("v", value.toPlainString()).put("at", at)

    private fun JSONObject.quote() = optString("v").toBigDecimalOrNull()?.let { Quote(it, optLong("at")) }

    private fun save() = Prefs.put(
        "goalRates",
        JSONObject().apply {
            tomanPerUsd?.let { put("toman", it.json()) }
            usdPerEur?.let { put("eur", it.json()) }
            put("crypto", JSONObject(crypto.mapValues { it.value.json() }))
        }.toString()
    )

    private fun load() {
        val raw = Prefs.string("goalRates").ifEmpty { return }
        val o = runCatching { JSONObject(raw) }.getOrNull() ?: return
        tomanPerUsd = o.optJSONObject("toman")?.quote()
        usdPerEur = o.optJSONObject("eur")?.quote()
        val c = o.optJSONObject("crypto") ?: JSONObject()
        crypto = c.keys().asSequence().mapNotNull { k -> c.optJSONObject(k)?.quote()?.let { k to it } }.toMap()
    }
}
