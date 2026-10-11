package com.saeedkolivand.metastream.platforms

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.BuildConfig
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONArray
import org.json.JSONObject

/** Kick OAuth 2.1 + PKCE (with client secret), channel info and chat send. Port of iOS KickService. */
object Kick : Account("Kick", "kick") {
    override val hasApp get() = BuildConfig.KICK_CLIENT_ID.isNotEmpty()
    override val missingSecrets = "KICK_CLIENT_ID / KICK_CLIENT_SECRET"
    override val hasCategory = true
    override val canSendChat = true
    override val ingest get() = streamUrl.ifEmpty { PlatformConfig.KICK_INGEST }

    var title by mutableStateOf("")
        private set
    var category by mutableStateOf<Category?>(null)
        private set
    var tags by mutableStateOf<List<String>>(emptyList())
        private set
    var slug by mutableStateOf("")
        private set
    private var streamUrl = ""
    private var userId = 0

    private val api = Endpoint("https://api.kick.com", "kickAccess") {
        saveTokens(
            Net.form(
                TOKEN_URL,
                mapOf(
                    "grant_type" to "refresh_token",
                    "client_id" to BuildConfig.KICK_CLIENT_ID,
                    "client_secret" to BuildConfig.KICK_CLIENT_SECRET,
                    "refresh_token" to refreshToken()
                )
            )
        )
    }

    override fun connect() = launchFlow {
        val verifier = Pkce.random(64)
        val state = Pkce.random(16)
        val url = "https://id.kick.com/oauth/authorize".toHttpUrl().newBuilder()
            .addQueryParameter("response_type", "code")
            .addQueryParameter("client_id", BuildConfig.KICK_CLIENT_ID)
            .addQueryParameter("redirect_uri", PlatformConfig.WEB_REDIRECT)
            .addQueryParameter("scope", "user:read channel:read channel:write chat:write streamkey:read")
            .addQueryParameter("code_challenge", Pkce.s256(verifier))
            .addQueryParameter("code_challenge_method", "S256")
            .addQueryParameter("state", state)
            .build().toString()
        codeFlow(url, state) { code ->
            Net.form(
                TOKEN_URL,
                mapOf(
                    "grant_type" to "authorization_code",
                    "client_id" to BuildConfig.KICK_CLIENT_ID,
                    "client_secret" to BuildConfig.KICK_CLIENT_SECRET,
                    "redirect_uri" to PlatformConfig.WEB_REDIRECT,
                    "code_verifier" to verifier,
                    "code" to code
                )
            )
        }
    }

    override suspend fun refresh() {
        try {
            api.call("GET", "/public/v1/users").objects("data").firstOrNull()?.let {
                userId = it.optInt("user_id")
                user = it.optString("name")
            }
            api.call("GET", "/public/v1/channels").objects("data").firstOrNull()?.let(::readChannel)
            Accounts.say("Kick updated")
        } catch (e: PlatformException) {
            Accounts.say(e.message.orEmpty())
        }
    }

    private fun readChannel(ch: JSONObject) {
        title = ch.optString("stream_title")
        ch.optJSONObject("category")?.takeIf { it.has("id") }?.let { category = Category(it.optInt("id").toString(), it.optString("name")) }
        val st = ch.optJSONObject("stream")
        live = st?.optBoolean("is_live") ?: false
        viewers = st?.optInt("viewer_count") ?: 0
        streamKey = st?.optString("key").orEmpty()
        streamUrl = st?.optString("url").orEmpty()
        slug = ch.optString("slug")
        tags = ch.optJSONArray("custom_tags").strings()
        if (user.isEmpty()) user = slug
    }

    suspend fun search(q: String): List<Category> {
        if (q.length < 3) return emptyList()
        val r = runCatching { api.call("GET", "/public/v2/categories", mapOf("name" to q, "limit" to "8")) }.getOrNull()
        return r?.objects("data").orEmpty().filter { it.has("id") }.map { Category(it.optInt("id").toString(), it.optString("name")) }
    }

    suspend fun apply(title: String, category: Category?, tags: List<String>) {
        val body = JSONObject().put("stream_title", title)
        category?.id?.toIntOrNull()?.let { body.put("category_id", it) }
        val clean = tags.take(10) // Kick caps custom_tags at 10
        // Omit when unchanged: an empty/unloaded field must not wipe real tags.
        if (clean != this.tags) body.put("custom_tags", JSONArray(clean))
        mutate("Kick title updated") { api.call("PATCH", "/public/v1/channels", body = body) }
    }

    override suspend fun send(text: String) = attempt {
        api.call(
            "POST",
            "/public/v1/chat",
            body = JSONObject().put("content", text).put("type", "user").put("broadcaster_user_id", userId)
        )
    }

    override fun disconnect() {
        signedOut()
        title = ""
        category = null
        streamUrl = ""
        tags = emptyList()
    }

    private const val TOKEN_URL = "https://id.kick.com/oauth/token"
}
