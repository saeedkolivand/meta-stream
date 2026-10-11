package com.saeedkolivand.metastream.platforms

import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.BuildConfig
import com.saeedkolivand.metastream.core.applog
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** Twitch Device Code Grant (public client, no secret), Helix channel reads/writes and EventSub subscriptions. Port of iOS TwitchService. */
object Twitch : Account("Twitch", "twitch") {
    override val hasApp get() = BuildConfig.TWITCH_CLIENT_ID.isNotEmpty()
    override val missingSecrets = "TWITCH_CLIENT_ID"
    override val hasCategory = true
    override val canSendChat = true
    override val ingest = PlatformConfig.TWITCH_INGEST

    var title by mutableStateOf("")
        private set
    var category by mutableStateOf<Category?>(null)
        private set
    var tags by mutableStateOf<List<String>>(emptyList())
        private set
    var labels by mutableStateOf<Set<String>>(emptySet())
        private set
    var delay by mutableStateOf(0)
        private set
    var language by mutableStateOf("")
        private set
    var scopes by mutableStateOf<Set<String>>(emptySet())
        private set
    var adNextAt by mutableStateOf<Instant?>(null)
        internal set
    var adSnoozeCount by mutableStateOf(0)
        internal set
    var userCode by mutableStateOf("")
        private set
    var verifyUrl by mutableStateOf("")
        private set
    var labelCatalog by mutableStateOf<List<Pair<String, String>>>(emptyList())
        private set
    var userId by mutableStateOf("")
        private set
    private var loginJob: Job? = null

    internal val api = Endpoint("https://api.twitch.tv/helix", "twitchAccess", mapOf("Client-Id" to BuildConfig.TWITCH_CLIENT_ID)) {
        val json = Net.form(
            TOKEN_URL,
            mapOf("grant_type" to "refresh_token", "client_id" to BuildConfig.TWITCH_CLIENT_ID, "refresh_token" to refreshToken())
        )
        saveTokens(json)?.let(::setScopes)
    }

    override fun restore() {
        super.restore()
        scopes = TokenStore.get("twitchScopes").orEmpty().split(' ').filter(String::isNotEmpty).toSet()
    }

    /** True when every scope in [required] was granted at the last auth. */
    fun hasScopes(required: Set<String>) = scopes.containsAll(required)

    val missingScopeFeatures get() = TwitchScopes.missingFeatures(scopes)

    private fun setScopes(granted: List<String>) {
        scopes = granted.toSet()
        TokenStore.set("twitchScopes", granted.joinToString(" "))
    }

    override fun connect() {
        loginJob?.cancel()
        loginJob = Accounts.scope.launch {
            try {
                deviceLogin()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Accounts.say(e.message.orEmpty())
            } finally {
                userCode = ""
            }
        }
    }

    fun cancelLogin() {
        loginJob?.cancel()
    }

    private suspend fun deviceLogin() {
        val id = BuildConfig.TWITCH_CLIENT_ID
        val dev = Net.form("https://id.twitch.tv/oauth2/device", mapOf("client_id" to id, "scopes" to TwitchScopes.REQUESTED))
        val deviceCode = dev.optString("device_code").ifEmpty { throw PlatformException("no device_code in response") }
        userCode = dev.optString("user_code")
        verifyUrl = dev.optString("verification_uri").ifEmpty { "https://www.twitch.tv/activate" }
        val interval = maxOf(dev.optInt("interval", 5), 5)
        Accounts.say("Enter code $userCode on Twitch")
        Accounts.app.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(verifyUrl)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        repeat(900 / interval) {
            // 15 min ceiling
            delay(interval * 1000L)
            val r = Net.form(
                TOKEN_URL,
                mapOf(
                    "client_id" to id,
                    "scopes" to TwitchScopes.REQUESTED,
                    "device_code" to deviceCode,
                    "grant_type" to "urn:ietf:params:oauth:grant-type:device_code"
                ),
                allowError = true
            )
            if (r.has("access_token")) {
                saveTokens(r)?.let(::setScopes)
                userCode = ""
                Accounts.say("Twitch connected")
                refresh()
                return
            }
            if (r.optString("message") != "authorization_pending") throw PlatformException("Twitch: ${r.optString("message")}")
        }
        Accounts.say("Twitch login timed out")
    }

    override suspend fun refresh() {
        try {
            api.call("GET", "/users").objects("data").firstOrNull()?.let {
                userId = it.optString("id")
                user = it.optString("display_name").ifEmpty { it.optString("login") }
            }
            val bid = mapOf("broadcaster_id" to userId)
            api.call("GET", "/channels", bid).objects("data").firstOrNull()?.let(::readChannel)
            val stream = api.call("GET", "/streams", mapOf("user_id" to userId)).objects("data").firstOrNull()
            live = stream != null
            viewers = stream?.optInt("viewer_count") ?: 0
            api.call("GET", "/streams/key", bid).objects("data").firstOrNull()?.let { streamKey = it.optString("stream_key") }
            if (hasScopes(setOf("channel:read:ads"))) refreshAdSchedule()
            fetchLabelCatalog()
            Accounts.say("Twitch updated")
        } catch (e: PlatformException) {
            Accounts.say(e.message.orEmpty())
        }
    }

    private fun readChannel(ch: JSONObject) {
        title = ch.optString("title")
        ch.optString("game_id").takeIf { it.isNotEmpty() }?.let { category = Category(it, ch.optString("game_name")) }
        tags = ch.optJSONArray("tags").strings()
        labels = ch.optJSONArray("content_classification_labels").strings().toSet()
        delay = ch.optInt("delay")
        language = ch.optString("broadcaster_language")
    }

    suspend fun search(q: String): List<Category> {
        if (q.length < 2) return emptyList()
        val r = runCatching { api.call("GET", "/search/categories", mapOf("query" to q, "first" to "8")) }.getOrNull()
        return r?.objects("data").orEmpty().filter { it.has("id") }.map { Category(it.optString("id"), it.optString("name")) }
    }

    /** Live label catalog with human names; cached per session, left empty on error so callers use the fallback ids. */
    private suspend fun fetchLabelCatalog() {
        if (labelCatalog.isNotEmpty()) return
        val data = runCatching { api.call("GET", "/content_classification_labels") }.getOrNull()?.objects("data").orEmpty()
        labelCatalog = data.filter { it.has("id") }.map { it.optString("id") to it.optString("name").ifEmpty { it.optString("id") } }
    }

    /** Label rows the UI should show: the live catalog, else the fallback ids. */
    val labelOptions get() = labelCatalog.ifEmpty { TwitchScopes.labelFallback.toList() }

    /**
     * tags/labels/delay/language are all "omit when unchanged" against the last-loaded values, so an untouched
     * (or not-yet-loaded) field can never silently wipe what's on the channel.
     */
    suspend fun apply(title: String, category: Category?, tags: List<String>, labels: Map<String, Boolean>, delay: Int, language: String) {
        val body = JSONObject().put("title", title)
        category?.let { body.put("game_id", it.id) }
        // Drop invalid tags instead of 400ing: no spaces, <=25 chars, <=10 tags (Twitch's own limits).
        val clean = tags.map(String::trim).filter { it.isNotEmpty() && ' ' !in it && it.length <= 25 }.take(10)
        if (clean != this.tags) body.put("tags", JSONArray(clean))
        val wanted = labels.filterValues { it }.keys
        if (wanted != this.labels.intersect(labels.keys)) {
            body.put(
                "content_classification_labels",
                JSONArray(
                    labels.keys.map {
                        JSONObject().put("id", it).put("is_enabled", it in wanted)
                    }
                )
            )
        }
        if (delay != this.delay) body.put("delay", delay) // Partner-only anti-stream-sniping delay
        val lang = language.trim()
        if (lang.isNotEmpty() && lang != this.language) body.put("broadcaster_language", lang)
        mutate("Twitch channel updated") { api.call("PATCH", "/channels", mapOf("broadcaster_id" to userId), body) }
    }

    override suspend fun send(text: String) = attempt {
        api.call("POST", "/chat/messages", body = JSONObject().put("broadcaster_id", userId).put("sender_id", userId).put("message", text))
    }

    override fun disconnect() {
        cancelLogin()
        signedOut()
        title = ""
        category = null
        tags = emptyList()
        labels = emptySet()
        delay = 0
        language = ""
        scopes = emptySet()
        adNextAt = null
        adSnoozeCount = 0
    }

    /**
     * Subscribes one EventSub WebSocket session to everything ChatFeed speaks. A type whose scope is missing is skipped,
     * not attempted: [missingScopeFeatures] is the one place that explains the gap.
     */
    suspend fun subscribeEventSub(sessionId: String) {
        if (userId.isEmpty()) return applog("chat", "twitch eventsub subscribe skipped: no user id yet")
        val transport = JSONObject().put("method", "websocket").put("session_id", sessionId)
        val me = userId
        val subs = buildList {
            add(Triple("channel.raid", "1", mapOf("to_broadcaster_user_id" to me)))
            if (hasScopes(setOf("user:read:chat"))) {
                add(
                    Triple(
                        "channel.chat.message",
                        "1",
                        mapOf(
                            "broadcaster_user_id" to me,
                            "user_id" to me
                        )
                    )
                )
            }
            if (hasScopes(setOf("moderator:read:followers"))) {
                add(Triple("channel.follow", "2", mapOf("broadcaster_user_id" to me, "moderator_user_id" to me)))
            }
            if (hasScopes(setOf("channel:read:subscriptions"))) add(Triple("channel.subscribe", "1", mapOf("broadcaster_user_id" to me)))
            if (hasScopes(setOf("bits:read"))) add(Triple("channel.cheer", "1", mapOf("broadcaster_user_id" to me)))
        }
        for ((type, version, condition) in subs) {
            try {
                val body = JSONObject().put(
                    "type",
                    type
                ).put("version", version).put("condition", JSONObject(condition)).put("transport", transport)
                api.call("POST", "/eventsub/subscriptions", body = body)
            } catch (e: PlatformException) {
                applog("chat", "twitch eventsub subscribe $type failed: ${e.message}")
            }
        }
    }

    private const val TOKEN_URL = "https://id.twitch.tv/oauth2/token"
}
