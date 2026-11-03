package com.saeedkolivand.metastream.goal

import android.net.Uri
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import com.saeedkolivand.metastream.core.model.Money
import com.saeedkolivand.metastream.core.network.http
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject

private const val DONITO_DEMO_NAME = "کاربر آزمایشی"
private const val DONITO_DEMO_MESSAGE = "این یک پیام حامی آزمایشی است."

/** Donito's overlay Centrifugo socket (JSON protocol): live events only, no history, no ack. */
internal suspend fun runDonito(token: String) = DonationHub.reconnecting(Site.Donito) {
    val ws = Ws(Request.Builder().url("wss://donito.me/ws/connection/event/websocket?token=${Uri.encode(token)}").build())
    var connected = false
    try {
        ws.send("""{"id":1,"connect":{"name":"overlays"}}""")
        for (text in ws.frames) {
            for (line in text.split('\n')) { // a frame may hold several objects
                val o = jsonOf(line) ?: continue
                when {
                    o.length() == 0 -> ws.send("{}") // server ping
                    o.has("error") -> {
                        DonationHub.setStatus(Site.Donito, DonationHub.REJECTED)
                        return@reconnecting true to connected
                    }
                    o.has("connect") -> {
                        connected = true
                        DonationHub.setStatus(Site.Donito, DonationHub.connectedText(Site.Donito))
                    }
                    else -> o.optJSONObject("push")?.optJSONObject("pub")?.optJSONObject("data")?.let {
                        donitoEvent(DonationParse.text(it.opt("action")), it.optJSONObject("data") ?: JSONObject())
                    }
                }
            }
        }
    } finally {
        ws.close()
    }
    false to connected
}

private fun donitoEvent(action: String, d: JSONObject) {
    if (action.isEmpty()) return
    val name = DonationParse.text(d.opt("user_name"))
    val message = DonationParse.text(d.opt("message"))
    if (action == "donate") {
        val dn = DonationParse.text(d.opt("name"))
        val cur = DonationParse.text(d.opt("currency_type")).ifEmpty { "IRT" }
        if (dn == DONITO_DEMO_NAME && message == DONITO_DEMO_MESSAGE) { // the panel's test button carries no flag
            return DonationHub.announceTest(Site.Donito, dn, message, d.opt("amount"), cur)
        }
        val amount = DonationParse.decimal(d.opt("amount"))?.takeIf { it.signum() > 0 } ?: return
        // No donation id, but the socket delivers each donation once (no replay): every arrival gets its own id, so two
        // identical donations both count and both play.
        val p =
            Parsed(
                UUID.randomUUID().toString(),
                dn.ifEmpty {
                    "Someone"
                },
                message,
                Money.of(amount, cur),
                System.currentTimeMillis(),
                Parsed.State.Paid
            )
        DonationHub.ingest(Site.Donito, listOf(p), live = true)
        return
    }
    if ("آزمایشی" !in name) return // real follows/subs/KICKs arrive from Kick/Twitch directly
    val gift = d.optBoolean("is_gift") || d.optInt("is_gift") == 1
    val (kind, count) = when (action) {
        "kick_kicks_gifted" -> Kind.Cheer to (DonationParse.text(d.opt("kicks")).toIntOrNull() ?: 0)
        "kick_channel_follow", "twitch_channel_follow" -> Kind.Follow to 0
        "twitch_channel_subscribe", "kick_channel_subscribe", "kick_channel_subscribe_gift" ->
            Kind.Subscribe to if (gift) DonationParse.text(d.opt("gift_count")).toIntOrNull() ?: 1 else 0
        else -> return
    }
    val t = DonationParse.text(d.opt("tier")).toIntOrNull() ?: 1
    val tier = if (t >= 1000) minOf(t / 1000, 3) else t.coerceIn(1, 3)
    ChatFeed.onChat(ChatEvent("test-donation", name, message, kind = kind, count = count, tier = tier))
}

/** Any of isMock/isTest/mock/test true (Boolean or "true") marks an emulated event. */
private fun isMock(o: JSONObject) = listOf("isMock", "isTest", "mock", "test").any {
    o.opt(it) == true ||
        o.optString(it).lowercase() == "true"
}

/** StreamElements' socket.io v2 socket: live tips and test events; the tips poll stays for catch-up. */
internal suspend fun runStreamElements(key: String) = DonationHub.reconnecting(Site.StreamElements, report = false) {
    val ws = Ws(Request.Builder().url("wss://realtime.streamelements.com/socket.io/?cluster=main&EIO=3&transport=websocket").build())
    var connected = false
    var pinger: kotlinx.coroutines.Job? = null
    try {
        for (t in ws.frames) {
            when {
                t.startsWith("0{") -> { // Engine.IO open: keepalive "2" -> "3"
                    val ms = jsonOf(t.drop(1))?.optLong("pingInterval", 25_000) ?: 25_000
                    pinger?.cancel()
                    pinger = DonationHub.scope.launch {
                        while (true) {
                            delay(ms)
                            ws.send("2")
                        }
                    }
                }
                t == "40" -> ws.send("42" + JSONArray().put("authenticate").put(JSONObject().put("method", "jwt").put("token", key)))
                t.startsWith("41") -> return@reconnecting false to connected
                t.startsWith("42") -> {
                    val arr = runCatching { JSONArray(t.dropWhile { it.isDigit() }) }.getOrNull() ?: continue
                    val p = arr.optJSONObject(1) ?: JSONObject()
                    when (arr.optString(0)) {
                        "authenticated" -> connected = true
                        "unauthorized" -> {
                            DonationHub.setStatus(Site.StreamElements, DonationHub.REJECTED)
                            return@reconnecting true to connected
                        }
                        "event" -> seEvent(key, p)
                        "event:test" -> {
                            val e = p.optJSONObject("event")
                            if (DonationParse.text(p.opt("listener")).lowercase().startsWith("tip") && e != null) {
                                DonationHub.announceTest(
                                    Site.StreamElements,
                                    DonationParse.text(DonationParse.first(e, listOf("name", "displayName", "username"))),
                                    DonationParse.text(e.opt("message")),
                                    e.opt("amount"),
                                    DonationParse.text(e.opt("currency")).ifEmpty {
                                        "USD"
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    } finally {
        pinger?.cancel()
        ws.close()
    }
    false to connected
}

private suspend fun seEvent(key: String, p: JSONObject) {
    val type = DonationParse.text(p.opt("type"))
    val d = p.optJSONObject("data") ?: JSONObject()
    applog("goal", "streamelements event: $type")
    // The dashboard's Emulate buttons arrive as ordinary events: tell them apart before counting or announcing.
    val flagged = isMock(p) || isMock(d)
    val name = DonationParse.text(DonationParse.first(d, listOf("displayName", "username", "name")))
    if (type != "tip") {
        if (!flagged) return // real follows/subs: the platform delivers them
        val n = DonationParse.text(d.opt("amount")).toIntOrNull() ?: 0
        val (kind, count) = when (type) {
            "follower", "follow" -> Kind.Follow to 0
            "subscriber" -> Kind.Subscribe to 0 // amount is months; count > 0 would read as a gift
            "cheer" -> Kind.Cheer to n
            "raid", "host" -> Kind.Raid to n
            else -> return
        }
        ChatFeed.onChat(
            ChatEvent(
                "test-donation",
                name.ifEmpty {
                    "Someone"
                },
                DonationParse.text(d.opt("message")),
                kind = kind,
                count = count
            )
        )
        return
    }
    val currency = DonationParse.text(d.opt("currency")).ifEmpty { "USD" }
    val tipId = DonationParse.text(DonationParse.first(d, listOf("tipId")) ?: p.opt("_id"))
    // Real tips are saved by StreamElements (GET 200), emulated ones are not (404/400); lookup failures count as real.
    var test = flagged
    if (!flagged && tipId.isNotEmpty() && DonationHub.seChannel.isNotEmpty()) {
        val code = withContext(Dispatchers.IO) {
            runCatching {
                http.newCall(
                    Request.Builder().url(
                        "https://api.streamelements.com/kappa/v2/tips/${DonationHub.seChannel}/${Uri.encode(tipId)}"
                    ).header("Authorization", "Bearer $key").build()
                )
                    .execute().use { it.code }
            }.getOrNull()
        }
        test = code == 404 || code == 400
    }
    if (test) return DonationHub.announceTest(Site.StreamElements, name, DonationParse.text(d.opt("message")), d.opt("amount"), currency)
    val flat = JSONObject().put("id", tipId).put("amount", d.opt("amount")).put("currency", currency)
        .put("name", DonationParse.first(d, listOf("displayName", "username"))).put("message", d.opt("message"))
    DonationParse.parse(flat, Shape.donofa)?.let { DonationHub.ingest(Site.StreamElements, listOf(it), live = true) }
}

/**
 * Reymit's overlay long poll: the server holds each request until something changes. Only its test donation is used;
 * real ones arrive through the API-token poll. Never logs the link or key.
 */
internal suspend fun runReymitOverlay(link: String) {
    val key = Uri.parse(link).getQueryParameter("key")?.takeIf { it.isNotEmpty() } ?: return applog("goal", "reymit overlay: link rejected")
    var md5 = ""
    var md5o = ""
    var started = "0"
    var last = "0"
    var lastTest = ""
    var first = true
    var attempt = 0
    while (true) {
        val k = Uri.encode(key)
        val url = "https://reymit.ir/overlay/data.php?NWSL=1&key=$k&md5sum=$md5&md5overlaydata=$md5o&startedat=$started&lastupdate=$last"
        val (code, body) = withContext(Dispatchers.IO) {
            runCatching {
                http.newBuilder().readTimeout(40, java.util.concurrent.TimeUnit.SECONDS).build()
                    .newCall(
                        Request.Builder().url(
                            url
                        ).header("User-Agent", BROWSER_UA).header("Referer", "https://reymit.ir/overlay/?key=$k").build()
                    )
                    .execute().use { it.code to it.body?.string().orEmpty() }
            }.getOrDefault(0 to "")
        }
        if (code in 400..499) return applog("goal", "reymit overlay: link rejected")
        if (code !in 200..299) {
            delay(DonationHub.backoff[minOf(attempt++, DonationHub.backoff.size - 1)] * 1000)
            continue
        }
        attempt = 0
        jsonOf(body)?.optJSONObject("data")?.let { d ->
            md5 = DonationParse.text(d.opt("md5"))
            md5o = DonationParse.text(d.opt("md5overlaydata"))
            val now = DonationParse.text(d.opt("now"))
            if (started == "0" && now.isNotEmpty()) started = now
            // lastupdate is echoed back as received: its text from the raw body, not a re-formatted double.
            last = Regex("\"lastupdate\":\\s*([0-9.]+)").find(body)?.groupValues?.get(1) ?: DonationParse.text(d.opt("lastupdate"))
            d.optJSONObject("testdonation")?.let { t ->
                val time = DonationParse.text(t.opt("time"))
                // Once per time; one already old at startup is not replayed.
                val stale = first && (now.toDoubleOrNull() ?: 0.0) - (time.toDoubleOrNull() ?: 0.0) > 60
                if (time.isNotEmpty() && time != lastTest) {
                    lastTest = time
                    if (!stale) {
                        DonationHub.announceTest(
                            Site.Reymit,
                            DonationParse.text(t.opt("name")),
                            DonationParse.text(t.opt("desc")),
                            t.opt("amount"),
                            "IRT"
                        )
                    }
                }
            }
        }
        first = false
        delay(1000)
    }
}
