package com.saeedkolivand.metastream.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.platforms.Net
import com.saeedkolivand.metastream.platforms.objects
import com.saeedkolivand.metastream.platforms.parseJson
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject

/**
 * 7TV, BTTV and FFZ global + per-channel sets as one name -> image URL map, fetched once per Twitch identity.
 * Kick emotes need no fetch: they arrive inline as `[emote:id:name]` and [tokenize] turns them into CDN URLs.
 */
object Emotes {
    var byName by mutableStateOf<Map<String, String>>(emptyMap())
        private set
    private var loadedFor: String? = null // twitch user id the map was built for; "" = globals only

    /** Loads globals, plus the channel's sets when [twitchId] is given. No-ops if already loaded for that identity. */
    suspend fun load(twitchId: String) {
        if (twitchId == loadedFor) return
        loadedFor = twitchId
        val map = coroutineScope {
            val sources = buildList {
                add(async { sevenTv(null) })
                add(async { bttv(null) })
                add(async { ffz(null) })
                if (twitchId.isNotEmpty()) {
                    add(async { sevenTv(twitchId) })
                    add(async { bttv(twitchId) })
                    add(async { ffz(twitchId) })
                }
            }
            // Later (channel) sets override earlier (global) ones, as on iOS.
            sources.fold(emptyMap<String, String>()) { acc, d -> acc + d.await() }
        }
        byName = map
        applog("chat", "emotes loaded: ${map.size} names (twitch=${twitchId.ifEmpty { "none" }})")
    }

    private suspend fun sevenTv(id: String?): Map<String, String> = if (id == null) {
        (fetch("https://7tv.io/v3/emote-sets/global") as? JSONObject)?.let { sevenTvEmotes(it.optJSONArray("emotes")) }.orEmpty()
    } else {
        (fetch("https://7tv.io/v3/users/twitch/$id") as? JSONObject)?.optJSONObject("emote_set")
            ?.let { sevenTvEmotes(it.optJSONArray("emotes")) }.orEmpty()
    }

    private suspend fun bttv(id: String?): Map<String, String> = if (id == null) {
        bttvEmotes((fetch("https://api.betterttv.net/3/cached/emotes/global") as? JSONArray).objects())
    } else {
        (fetch("https://api.betterttv.net/3/cached/users/twitch/$id") as? JSONObject)
            ?.let { bttvEmotes(it.objects("channelEmotes") + it.objects("sharedEmotes")) }.orEmpty()
    }

    private suspend fun ffz(id: String?): Map<String, String> = if (id == null) {
        (fetch("https://api.frankerfacez.com/v1/set/global") as? JSONObject)?.let { j ->
            ffzEmotes(j, j.optJSONArray("default_sets")?.let { a -> List(a.length()) { a.optInt(it) } }.orEmpty())
        }.orEmpty()
    } else {
        (fetch("https://api.frankerfacez.com/v1/room/id/$id") as? JSONObject)?.let { j ->
            j.optJSONObject("room")?.takeIf { it.has("set") }?.let { ffzEmotes(j, listOf(it.optInt("set"))) }
        }.orEmpty()
    }

    private suspend fun fetch(url: String): Any? = try {
        val (code, text) = Net.exec(Request.Builder().url(url).build())
        if (code == 200) parseJson(text) else null
    } catch (e: CancellationException) {
        throw e
    } catch (e: java.io.IOException) {
        applog("chat", "emote fetch failed $url: ${e.message}")
        null
    }
}
