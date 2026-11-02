package com.saeedkolivand.metastream.platforms

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.applog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import org.json.JSONObject

/** What Spotify says is playing; [at] is when [progressMs] was read. */
data class NowPlayingTrack(
    val id: String,
    val title: String,
    val artist: String,
    val artURL: String,
    val durationMs: Int,
    val progressMs: Int,
    val at: Long,
    val url: String = ""
) {
    /** Playback position now, extrapolated from the last poll. */
    fun elapsedMs(now: Long = System.currentTimeMillis()) = minOf(durationMs.toLong(), progressMs + (now - at)).toInt()

    fun progress(now: Long = System.currentTimeMillis()) = if (durationMs > 0) elapsedMs(now).toFloat() / durationMs else 0f
}

/**
 * Spotify "now playing" for the Now playing widget, {song} / {artist} and !song (iOS SpotifyNowPlaying). PKCE login (no
 * client secret), then /me/player/currently-playing every 3 s while something uses it (retain / release). Spotify reports
 * whatever the account plays on any device. A Development Mode app only works while its owner has Premium.
 */
object Spotify {
    // ponytail: public PKCE client id (no secret exists), so it lives in code.
    const val CLIENT_ID = "b8b8964ddeab49809d9f9ae1cf9b468e"
    private const val TOKEN_URL = "https://accounts.spotify.com/api/token"

    /** null while nothing plays (paused, stopped, an ad, not connected): widgets hide. */
    var track by mutableStateOf<NowPlayingTrack?>(null)
        private set
    var art by mutableStateOf<Bitmap?>(null)
        private set
    var connected by mutableStateOf(false)
        private set
    var status by mutableStateOf("")
    private var users = 0
    private var poll: Job? = null
    private var artFor = ""

    /** After [Accounts.init] (the token store). */
    fun init() {
        connected = TokenStore.get("spotifyRefresh") != null
    }

    fun retain() {
        if (++users == 1) poll = Accounts.scope.launch { loop() }
    }

    fun release() {
        users = maxOf(0, users - 1)
        if (users == 0) poll?.cancel().also { poll = null }
    }

    fun connect() = Accounts.scope.launch {
        val verifier = Pkce.random(64)
        val state = Pkce.random(16)
        val url = "https://accounts.spotify.com/authorize".toHttpUrl().newBuilder()
            .addQueryParameter("response_type", "code").addQueryParameter("client_id", CLIENT_ID)
            .addQueryParameter("redirect_uri", PlatformConfig.WEB_REDIRECT)
            .addQueryParameter("scope", "user-read-currently-playing user-read-playback-state")
            .addQueryParameter("code_challenge", Pkce.s256(verifier)).addQueryParameter("code_challenge_method", "S256")
            .addQueryParameter("state", state).build().toString()
        val code = OAuth.await(Accounts.app, url, state) ?: return@launch run { status = "Spotify login cancelled" }
        try {
            val form = mapOf(
                "grant_type" to "authorization_code",
                "client_id" to CLIENT_ID,
                "redirect_uri" to PlatformConfig.WEB_REDIRECT,
                "code_verifier" to verifier,
                "code" to code
            )
            save(Net.form(TOKEN_URL, form))
            connected = true
            status = "Spotify connected"
            if (users > 0) poll?.cancel().also { poll = Accounts.scope.launch { loop() } }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            status = "Spotify token error: ${e.message}"
        }
    }

    fun disconnect() {
        TokenStore.forget("spotify")
        connected = false
        track = null
        art = null
        artFor = ""
        status = "Spotify disconnected"
    }

    private fun save(json: JSONObject) {
        TokenStore.set("spotifyAccess", json.optString("access_token").ifEmpty { throw PlatformException("no access_token in response") })
        json.optString("refresh_token").takeIf { it.isNotEmpty() }?.let { TokenStore.set("spotifyRefresh", it) }
    }

    private suspend fun loop() {
        while (Accounts.scope.isActive && users > 0) {
            val wait = if (!connected) {
                3000L
            } else {
                try {
                    fetch()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    applog("spotify", "now playing failed: ${e.message}")
                    status = e.message.orEmpty()
                    15_000L
                }
            }
            delay(wait)
        }
    }

    /** One poll; returns ms until the next. Near a song's end it polls right after it, so the widget changes with the music. */
    private suspend fun fetch(): Long {
        val (code, body, retry) = get("https://api.spotify.com/v1/me/player/currently-playing")
        if (code == 429) return maxOf(5, retry ?: 30) * 1000L
        if (code == 204) return 3000L.also { set(null) }
        if (code != 200) throw PlatformException("Spotify → HTTP $code")
        val playing = runCatching { parse(JSONObject(body), System.currentTimeMillis()) }.getOrNull()
        set(playing)
        playing ?: return 3000
        val left = playing.durationMs - playing.progressMs
        return if (left in 501..2999) left + 400L else 3000L
    }

    private fun set(next: NowPlayingTrack?) {
        if (next?.id != track?.id) applog("spotify", next?.let { "now playing: ${it.title} · ${it.artist}" } ?: "nothing playing")
        track = next
        val url = next?.artURL?.takeIf { it.isNotEmpty() && it != artFor } ?: return
        artFor = url
        art = null
        Accounts.scope.launch {
            val bmp = withContext(Dispatchers.IO) {
                runCatching {
                    http.newCall(Request.Builder().url(url).build()).execute().use { BitmapFactory.decodeStream(it.body?.byteStream()) }
                }.getOrNull()
            }
            if (artFor == url) art = bmp
        }
    }

    /** GET with the access token; one refresh + retry on 401. Successful polls aren't logged (one every 3 s). */
    private suspend fun get(url: String, retried: Boolean = false): Triple<Int, String, Int?> {
        val req = Request.Builder().url(url).header("Authorization", "Bearer ${TokenStore.get("spotifyAccess").orEmpty()}").build()
        val r = withContext(Dispatchers.IO) {
            http.newCall(req).execute().use { Triple(it.code, it.body?.string().orEmpty(), it.header("Retry-After")?.toIntOrNull()) }
        }
        if (r.first == 401 && !retried) {
            save(
                Net.form(
                    TOKEN_URL,
                    mapOf(
                        "grant_type" to "refresh_token",
                        "client_id" to CLIENT_ID,
                        "refresh_token" to TokenStore.get("spotifyRefresh").orEmpty()
                    )
                )
            )
            return get(url, true)
        }
        if (r.first >= 400) applog("spotify", "HTTP ${r.first}")
        return r
    }

    /** null unless a track is actually playing (paused, podcasts and ads all hide the widget). */
    fun parse(o: JSONObject, at: Long): NowPlayingTrack? {
        if (!o.optBoolean("is_playing") || o.optString("currently_playing_type") != "track") return null
        val item = o.optJSONObject("item") ?: return null
        val id = item.optString("id").ifEmpty { item.optString("uri") }.ifEmpty { return null }
        val name = item.optString("name").ifEmpty { return null }
        val artists = item.optJSONArray("artists")?.let { a ->
            (0 until a.length()).mapNotNull { a.optJSONObject(it)?.optString("name") }
        }.orEmpty()
        val images = item.optJSONObject("album")?.optJSONArray("images")
            ?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } }.orEmpty().sortedBy { it.optInt("width") }
        // The smallest cover that is still sharp at widget size (Spotify sends 64, 300 and 640 px).
        val cover = images.firstOrNull { it.optInt("width") >= 300 } ?: images.lastOrNull()
        return NowPlayingTrack(
            id,
            name,
            artists.joinToString(", "),
            cover?.optString("url").orEmpty(),
            item.optInt("duration_ms"),
            o.optInt("progress_ms"),
            at,
            item.optJSONObject("external_urls")?.optString("spotify").orEmpty()
        )
    }
}
