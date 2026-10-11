package com.saeedkolivand.metastream.chat

import com.saeedkolivand.metastream.core.applog
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

private val http = OkHttpClient()

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

private const val PUSHER = "wss://ws-us2.pusher.com/app/32cbd69e4b950bf97679?protocol=7&client=js&version=8.4.0-rc2&flash=false"
private const val KICK_UA = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"

/** KickChatProvider: anonymous Pusher socket on chatrooms.<id>.v2. */
suspend fun kickChat(slug: String, emit: (ChatEvent) -> Unit) {
    val id = withContext(Dispatchers.IO) {
        val c = URL("https://kick.com/api/v2/channels/$slug").openConnection() as HttpURLConnection
        c.setRequestProperty("User-Agent", KICK_UA)
        try {
            check(c.responseCode == 200) { "Kick channel lookup failed for $slug (HTTP ${c.responseCode})" }
            JSONObject(c.inputStream.bufferedReader().readText()).getJSONObject("chatroom").getInt("id")
        } finally {
            c.disconnect()
        }
    }
    applog("chat", "kick chat connecting room=$id")
    socket(
        PUSHER,
        {
            it.send(
                JSONObject().put(
                    "event",
                    "pusher:subscribe"
                ).put("data", JSONObject().put("auth", "").put("channel", "chatrooms.$id.v2")).toString()
            )
        },
        { ws, text ->
            if (isKickPing(text)) ws.send("""{"event":"pusher:pong"}""") else parseKickFrame(text)?.let(emit)
        }
    )
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
