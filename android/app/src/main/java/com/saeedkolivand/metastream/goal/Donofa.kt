package com.saeedkolivand.metastream.goal

import android.net.Uri
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import com.saeedkolivand.metastream.core.model.Money
import com.saeedkolivand.metastream.core.network.http
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

private const val TEST_MESSAGE = "پیام نمایشی و فرضی دونیت"
internal const val BROWSER_UA =
    "Mozilla/5.0 (Linux; Android 16; Pixel) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Mobile Safari/537.36"

private val widgetIds = HashMap<Int, String>() // widget child id -> identifier (a single widget maps itself)
private val widgetSeen = HashSet<Int>() // action ids already handled

internal fun jsonOf(text: String): JSONObject? = runCatching { JSONObject(text) }.getOrNull()

/** Pusher's data is an object or a JSON string holding one. */
private fun data(o: JSONObject): JSONObject? = o.optJSONObject("data") ?: jsonOf(o.optString("data"))

/** Donofa (iOS DonationHub Donofa): history catch-up, then the Pusher socket; reconnects with backoff. */
internal suspend fun runDonofa(key: String) {
    DonationHub.reconnecting(Site.Donofa) {
        if (donofaCatchUp(key) == Outcome.Rejected) true to false else donofaSocket(key)
    }
}

/** The latest 20 donations: anything not already known is recorded as missed. Iran's host first, then the global one. */
private suspend fun donofaCatchUp(key: String): Outcome {
    var out = Outcome.Unreachable
    for (base in listOf("https://api.donofa.ir", "https://api.donofa.com")) {
        val (o, j) = DonationHub.get("$base/api/v2/donates/last", "Api $key", setOf(401, 403))
        out = o
        if (o != Outcome.Ok) continue
        val parsed = DonationParse.items(j).mapNotNull { DonationParse.parse(it, Shape.donofa) }
        val n = DonationHub.ingest(Site.Donofa, parsed, live = false)
        applog("goal", "donofa history ok: ${parsed.size} donations, $n new")
        DonationHub.setStatus(Site.Donofa, DonationHub.connectedText(Site.Donofa))
        return Outcome.Ok
    }
    DonationHub.setStatus(Site.Donofa, if (out == Outcome.Rejected) DonationHub.REJECTED else "Can't reach Donofa")
    return out
}

/** (rejected, connected) when the socket ends. */
private suspend fun donofaSocket(key: String): Pair<Boolean, Boolean> {
    val ws = Ws(Request.Builder().url("wss://ws.donofa.com/app/AF5Ed2JK?protocol=7&client=js&version=8.4.0&flash=false").build())
    var connected = false
    try {
        fun subscribe(channel: String) =
            ws.send(JSONObject().put("event", "pusher:subscribe").put("data", JSONObject().put("channel", channel)).toString())
        subscribe("user.$key")
        fetchWidget()?.let { subscribe("widget.$it") }
        for (text in ws.frames) {
            val o = jsonOf(text) ?: continue
            when (val ev = o.optString("event")) {
                "pusher:ping" -> ws.send("""{"event":"pusher:pong"}""")
                "pusher_internal:subscription_succeeded" -> {
                    connected = true
                    DonationHub.setStatus(Site.Donofa, DonationHub.connectedText(Site.Donofa))
                }
                "pusher_internal:subscription_error" -> {
                    DonationHub.setStatus(Site.Donofa, DonationHub.REJECTED)
                    return true to connected
                }
                "pusher:error" -> {
                    val code = data(o)?.optInt("code") ?: 0
                    applog("goal", "donofa: pusher:error code $code")
                    if (code >= 4100) return false to connected // 41xx-43xx: reconnect as the protocol says
                    DonationHub.setStatus(Site.Donofa, DonationHub.REJECTED)
                    return true to connected
                }
                "widget.action" -> data(o)?.let(::widgetAction)
                else -> {
                    applog("goal", "donofa event: $ev") // names only
                    val isTest = "test" in ev.lowercase()
                    if (!isTest && !ev.endsWith("donate.created")) continue // goal.updated, timer.updated, ...
                    val inner = data(o)
                    // ponytail: the payload may be the donation itself or wrap it; unwrap both guesses.
                    val d = inner?.optJSONObject("donate") ?: inner?.optJSONObject("data") ?: inner ?: continue
                    val s = Shape.donofa
                    if (isTest) {
                        DonationHub.announceTest(
                            Site.Donofa,
                            DonationParse.text(DonationParse.first(d, s.name)),
                            DonationParse.text(DonationParse.first(d, s.message)),
                            DonationParse.first(d, s.amount),
                            DonationParse.currency(DonationParse.text(DonationParse.first(d, s.currency)))
                        )
                        continue
                    }
                    // With a widget link the widget's alert is the one announcement: record silently.
                    DonationParse.parse(d, s)?.let {
                        DonationHub.ingest(Site.Donofa, listOf(it), live = true, announce = DonationHub.donofaWidget().isEmpty())
                    }
                }
            }
        }
    } finally {
        ws.close()
    }
    return false to connected
}

/** Cloudflare answers 403 (1010) without these browser headers. */
private fun widgetRequest(url: String, post: Boolean) = Request.Builder().url(url)
    .header("User-Agent", BROWSER_UA).header("Origin", "https://w.donofa.com").header("Referer", "https://w.donofa.com/")
    .header("Accept", "application/json")
    .apply { if (post) post(ByteArray(0).toRequestBody("application/json".toMediaType())) }
    .build()

/** Widget info into [widgetIds]; the channel identifier to subscribe, null when there's none or it's rejected. Never logs the link. */
private suspend fun fetchWidget(): String? {
    val link = Uri.parse(DonationHub.donofaWidget().ifEmpty { return null })
    val ident = link.lastPathSegment?.takeIf { it.isNotEmpty() } ?: return null
    val url = "https://api.donofa.com/api/v2/widgets/legacy/${Uri.encode(
        ident
    )}?salt=${Uri.encode(link.getQueryParameter("salt").orEmpty())}"
    val (code, body) = withContext(Dispatchers.IO) {
        runCatching { http.newCall(widgetRequest(url, false)).execute().use { it.code to it.body?.string().orEmpty() } }.getOrDefault(
            0 to ""
        )
    }
    if (code == 0) return ident.also { applog("goal", "donofa widget: can't reach Donofa") }
    if (code !in 200..299) return if (code == 403 || code == 404) null.also { applog("goal", "donofa widget: link rejected") } else ident
    val w = jsonOf(body)?.optJSONObject("widget")
    val kids = w?.optJSONArray("children")
    widgetIds.clear()
    val list = if (kids == null || kids.length() == 0) listOfNotNull(w) else (0 until kids.length()).mapNotNull { kids.optJSONObject(it) }
    for (k in list) {
        DonationParse.text(k.opt("identifier")).takeIf {
            it.isNotEmpty() && k.has("id")
        }?.let { widgetIds[k.optInt("id")] = it }
    }
    applog("goal", "donofa widget: ${if (kids == null || kids.length() == 0) "single widget" else "group of ${kids.length()}"}")
    return ident
}

/** One alert from the widget channel: acknowledged always (Donofa's queue stalls otherwise), played if a donation or a test. */
private fun widgetAction(a: JSONObject) {
    val id = a.optInt("id", -1).takeIf { it >= 0 && widgetSeen.add(it) } ?: return // the group channel repeats children's alerts
    val type = DonationParse.text(a.opt("type"))
    val d = a.optJSONObject("data") ?: JSONObject()
    widgetIds[a.optInt("widget_id", -1)]?.let { ack(id, it, a.optBoolean("is_legacy")) }
        ?: applog("goal", "donofa ack $id skipped: unknown widget")
    val name = DonationParse.text(d.opt("name"))
    val message = DonationParse.text(d.opt("message"))
    val test = name == "John Doe" && message == TEST_MESSAGE // the panel's test button carries no flag
    val cur = DonationParse.currency(DonationParse.text(d.opt("currency")))
    val result = when {
        type == "donate" && test -> "test".also { DonationHub.announceTest(Site.Donofa, name, message, d.opt("amount"), cur) }
        type == "donate" -> DonationParse.decimal(d.opt("amount"))?.takeIf { it.signum() > 0 }?.let {
            // Alert only: the goal counts it from user.<key> donate.created.
            ChatFeed.onChat(ChatEvent("donofa", name.ifEmpty { "Someone" }, message, kind = Kind.Tip, money = Money.of(it, cur)))
            "alert"
        } ?: "ignored"
        test -> {
            val n = DonationParse.text(d.opt("amount")).toIntOrNull() ?: 0
            val (kind, count) = when (type) {
                "follow" -> Kind.Follow to 0
                "subscribe" -> Kind.Subscribe to 0
                "raid" -> Kind.Raid to n.coerceIn(1, 10_000)
                "points" -> Kind.Cheer to n.coerceIn(1, 100_000)
                else -> null to 0
            }
            kind?.let { ChatFeed.onChat(ChatEvent("test-donation", name.ifEmpty { "Someone" }, message, kind = it, count = count)) }
            if (kind != null) "test" else "ignored"
        }
        else -> "ignored (platform event)"
    }
    applog("goal", "donofa widget action $id $type -> $result")
}

/** Handshake now, complete 3 s later (the alert has played). */
private fun ack(id: Int, child: String, legacy: Boolean) {
    val base = "https://api.donofa.com/api/v2/widgets/${if (legacy) "legacy/" else ""}${Uri.encode(child)}/actions/$id/"
    DonationHub.scope.launch {
        val codes = mutableListOf<String>()
        for (step in listOf("handshake", "complete")) {
            if (step == "complete") delay(3000)
            val code =
                withContext(Dispatchers.IO) {
                    runCatching {
                        http.newCall(widgetRequest(base + step, true)).execute().use { it.code.toString() }
                    }.getOrDefault("failed")
                }
            codes += "$step $code"
        }
        applog("goal", "donofa ack $id ${codes.joinToString(", ")}")
    }
}
