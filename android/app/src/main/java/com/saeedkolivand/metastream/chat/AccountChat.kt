package com.saeedkolivand.metastream.chat

import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.platforms.YouTube
import java.io.IOException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val EVENTSUB = "wss://eventsub.wss.twitch.tv/ws"

/**
 * Authenticated Twitch chat + alerts over EventSub (iOS TwitchEventSubProvider). Subscriptions are created once per
 * session; a `session_reconnect` carries them over to the new URL, so only the first welcome subscribes.
 */
suspend fun twitchEventSub(emit: (ChatEvent) -> Unit): Unit = coroutineScope {
    var url = EVENTSUB
    while (isActive) {
        var next: String? = null
        try {
            socket(url, {}, { ws, text ->
                when (val f = parseEventSubFrame(text)) {
                    is EventSubFrame.Welcome -> if (url == EVENTSUB) {
                        applog("chat", "twitch eventsub connected")
                        launch { Twitch.subscribeEventSub(f.sessionId) }
                    }
                    is EventSubFrame.Reconnect -> {
                        next = f.url
                        ws.cancel() // the old socket is done; cancel surfaces as an IOException below
                    }
                    is EventSubFrame.Notification -> emit(f.event)
                    EventSubFrame.Ignored -> Unit
                }
            })
        } catch (e: IOException) {
            if (next == null) throw e
        }
        url = next ?: return@coroutineScope // plain close: let backoff start a fresh session
    }
}

/** YouTube live chat has no push channel: poll at the interval the API hands back (iOS YouTubePollProvider). */
suspend fun youtubeChat(emit: (ChatEvent) -> Unit) {
    var token: String? = null
    while (true) {
        val page = YouTube.pollLiveChat(token)
        if (page == null) {
            delay(5000) // no live chat yet (broadcast not started): wait quietly
            continue
        }
        token = page.nextPageToken
        page.items.mapNotNull(::parseYouTubeItem).forEach(emit)
        delay(maxOf(page.pollingIntervalMillis, 2000).toLong())
    }
}
