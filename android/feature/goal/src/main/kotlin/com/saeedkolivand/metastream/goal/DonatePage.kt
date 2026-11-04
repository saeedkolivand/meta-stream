package com.saeedkolivand.metastream.goal

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.model.Session
import com.saeedkolivand.metastream.core.network.http
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.storage.TokenStore
import java.math.BigDecimal
import java.math.RoundingMode
import java.net.URI
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

/**
 * Publishes the goal to the streamer's donate page (iOS DonatePagePublisher): POST <page>/api/goal with a bearer key, when the
 * goal changes, on going live / ending, and every 60 s while live (the page tells LIVE from OFFLINE by the heartbeat). At most
 * one request per 5 s. The key goes over HTTPS only and only to the host it was saved for, so a changed URL can't leak it.
 */
object DonatePage {
    const val DEFAULT_URL = "https://donate.iamsaeed.dev"
    var status by mutableStateOf("Off: no page key")
        private set
    private var lastSent = 0L
    private var scheduled = false
    private var failure = ""
    private lateinit var scope: CoroutineScope

    val pageURL get() = Prefs.string("donatePageURL", DEFAULT_URL)
    val hasToken get() = TokenStore.get("donatePageToken").orEmpty().isNotEmpty()

    /** The page for chat, scheme kept: Kick only makes a link tappable with it. */
    val chatURL get() = pageURL.trim().trimEnd('/').let { if (it.lowercase().startsWith("http")) it else "https://$it" }

    fun host(url: String) = runCatching { URI(url.trim()).host?.lowercase() }.getOrNull()

    fun setURL(url: String) {
        Prefs.put("donatePageURL", url.trim())
        request()
    }

    /** Binds the key to the page's current host; empty removes it. */
    fun setToken(raw: String) {
        val t = raw.trim()
        if (t.isEmpty()) TokenStore.remove("donatePageToken") else TokenStore.set("donatePageToken", t)
        Prefs.put("donatePageTokenHost", if (t.isEmpty()) "" else host(pageURL).orEmpty())
        request()
    }

    fun start(scope: CoroutineScope) {
        this.scope = scope
        scope.launch { snapshotFlow { GoalStore.total to GoalStore.config }.collect { request() } }
        scope.launch {
            Session.live.collectLatest { live ->
                request()
                while (live) {
                    delay(60_000)
                    request()
                }
            }
        }
    }

    /** Sends now, or once 5 s have passed since the last send; calls in between share that one request. */
    fun request() {
        if (!hasToken) {
            status = "Off: no page key"
            return
        }
        if (scheduled) return
        scheduled = true
        scope.launch {
            val wait = 5000 - (System.currentTimeMillis() - lastSent)
            if (wait > 0) delay(wait)
            scheduled = false
            send()
        }
    }

    /** Money as numbers rounded to 2 decimals (toman to 0). */
    fun body(title: String, total: BigDecimal, target: BigDecimal, currency: String, live: Boolean, at: Instant): String {
        fun num(d: BigDecimal) = d.setScale(if (currency == "IRT") 0 else 2, RoundingMode.HALF_UP).toDouble()
        return JSONObject().put("title", title).put("total", num(total)).put("target", num(target)).put("currency", currency)
            .put("live", live).put("updatedAt", at.toString()).toString()
    }

    /** [path] on the page; null unless https and the host the key was saved for (the key is a bearer secret). */
    fun endpoint(path: String): String? {
        val url = pageURL.trim().trim('/') + path
        return url.takeIf {
            it.lowercase().startsWith("https://") && host(it) != null && host(it) == Prefs.string("donatePageTokenHost", "")
        }
    }

    private suspend fun send() {
        val key = TokenStore.get("donatePageToken").orEmpty().ifEmpty { return }
        val url = endpoint("/api/goal") ?: run {
            status = "Needs an https:// URL, and the key saved for that address"
            return
        }
        lastSent = System.currentTimeMillis()
        // Test donations move the stream's bar for 10 s but never the public page.
        val tests = GoalStore.entries.filter { it.state == EntryState.Test }.fold(BigDecimal.ZERO) { s, e ->
            s +
                (e.value ?: BigDecimal.ZERO)
        }
        val c = GoalStore.config
        val json = body(c.title, GoalStore.total - tests, c.target, c.currency, Session.live.value, Instant.now())
        val code = withContext(Dispatchers.IO) {
            runCatching {
                val req = Request.Builder().url(url).header("Authorization", "Bearer $key")
                    .post(json.toRequestBody("application/json".toMediaType())).build()
                http.newCall(req).execute().use { it.code }
            }.getOrDefault(0)
        }
        val (text, kind) = when (code) {
            in 200..299 -> "Published at ${SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())}" to ""
            401, 403 -> "Key rejected" to "HTTP $code"
            0 -> "Can't reach the page" to "unreachable"
            else -> "Page answered HTTP $code" to "HTTP $code"
        }
        status = text
        if (kind != failure && kind.isNotEmpty()) applog("goal", "donate page: $kind") // once per kind of failure, never the key
        failure = kind
    }
}
