package com.saeedkolivand.metastream.chat

import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.network.Net
import com.saeedkolivand.metastream.core.network.http
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

/** Port of iOS runWithBackoff: reruns [work] forever with 1/2/4/8/15 s waits until the caller cancels. */
suspend fun backoff(label: String, work: suspend () -> Unit) {
    var wait = 1000L
    while (true) {
        try {
            work()
            wait = 1000
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            applog("chat", "$label error: ${e.message}")
        }
        delay(wait)
        wait = minOf(wait * 2, 15000)
    }
}

/** One WebSocket lifetime: returns on close, throws on failure, closes the socket when cancelled. */
internal suspend fun socket(url: String, onOpen: (WebSocket) -> Unit, onText: (WebSocket, String) -> Unit) {
    val done = CompletableDeferred<Unit>()
    val ws = http.newWebSocket(
        Request.Builder().url(url).build(),
        object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) = onOpen(webSocket)

            override fun onMessage(webSocket: WebSocket, text: String) = onText(webSocket, text)

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                done.complete(Unit)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                done.completeExceptionally(t)
            }
        }
    )
    try {
        done.await()
    } finally {
        ws.cancel()
    }
}

/** Last known Pusher app; Kick rotates it, so [pusherUrl] asks Kick for the live one first. */
private val FALLBACK_PUSHER = "34bf7a0ff419a2a775b9" to "us2"
private const val KICK_UA = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"

/** kick.com's channel lookup (chatroom.id, id, user_id), with the User-Agent the site's own client sends. */
internal suspend fun kickChannel(slug: String): JSONObject {
    val req = Request.Builder().url("https://kick.com/api/v2/channels/$slug").header("User-Agent", KICK_UA).build()
    val (code, text) = Net.exec(req)
    check(code == 200) { "Kick channel lookup failed for $slug (HTTP $code)" }
    return JSONObject(text)
}

/** KickChatProvider: anonymous Pusher socket on the channels from the Kick rules; alerts are parsed by those rules. */
suspend fun kickChat(slug: String, emit: (ChatEvent) -> Unit) {
    val j = kickChannel(slug)
    val id = j.getJSONObject("chatroom").getInt("id")
    val rules = loadKickRules()
    applog("chat", "kick chat connecting room=$id")
    socket(
        pusherUrl(),
        { ws ->
            for (ch in kickChannels(rules, id, j.optInt("id"))) {
                ws.send(
                    JSONObject().put("event", "pusher:subscribe")
                        .put("data", JSONObject().put("auth", "").put("channel", ch)).toString()
                )
            }
        },
        { ws, text ->
            if (isKickPing(text)) {
                ws.send("""{"event":"pusher:pong"}""")
            } else {
                val name = kickEventName(text).orEmpty()
                val o = JSONObject(text)
                parseKickModeration(name, o.optString("data"))?.let { ChatFeed.moderate("kick", it) }
                val e = if (name == KICK_MESSAGE) parseKickFrame(text) else parseKickRule(rules, name, o.optString("data"))
                logKickEvent(name, o)
                e?.let(emit)
            }
        }
    )
}

private val loggedKick = mutableSetOf<String>()

/** Logs the first occurrence of each non-chat Kick event name, so real payloads show up in device logs once. */
private fun logKickEvent(name: String, frame: JSONObject) {
    if (name.isEmpty() || name.startsWith("pusher:") || name.startsWith("pusher_internal:") || name == KICK_MESSAGE) return
    if (!synchronized(loggedKick) { loggedKick.add(name) }) return
    applog("chat", "kick event $name on ${frame.optString("channel")}: ${frame.optString("data").take(300)}")
}

/** Same anonymous call kick.com's own web client makes to learn which Pusher app/cluster is live. */
private suspend fun pusherUrl(): String {
    val (key, cluster) = try {
        val body = """{"client":{"id":"${java.util.UUID.randomUUID()}","type":"web"},""" +
            """"capabilities":{"accepted_providers":[{"provider":"pusher"}]}}"""
        val req = Request.Builder().url("https://web.kick.com/api/v1/realtime/connection")
            .post(body.toRequestBody("application/json".toMediaType())).build()
        val conns = JSONObject(Net.exec(req).second).getJSONObject("data").getJSONArray("connections")
        val creds = (0 until conns.length()).map(conns::getJSONObject)
            .first { it.optString("provider") == "pusher" }.getJSONObject("credentials")
        creds.getString("app_key") to creds.getString("cluster")
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        applog("chat", "kick realtime lookup failed, using fallback pusher key: ${e.message}")
        FALLBACK_PUSHER
    }
    val source = if (key to cluster == FALLBACK_PUSHER) "fallback" else "live"
    applog("chat", "kick pusher key ${key.take(6)}… cluster $cluster ($source)")
    return "wss://ws-$cluster.pusher.com/app/$key?protocol=7&client=js&version=8.4.0-rc2&flash=false"
}

/** Anonymous read-only Twitch IRC (justinfan login), display-name from the tags capability. */
suspend fun twitchChat(channel: String, emit: (ChatEvent) -> Unit) {
    applog("chat", "twitch chat connecting #$channel")
    socket(
        "wss://irc-ws.chat.twitch.tv:443",
        {
            it.send("CAP REQ :twitch.tv/tags")
            it.send("NICK justinfan${(10000..99999).random()}")
            it.send("JOIN #${channel.lowercase()}")
        },
        { ws, text ->
            for (line in text.split("\r\n")) {
                if (isTwitchPing(line)) ws.send("PONG :tmi.twitch.tv") else parseTwitchLine(line)?.let(emit)
            }
        }
    )
}
