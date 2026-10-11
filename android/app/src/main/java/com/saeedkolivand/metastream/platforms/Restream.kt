package com.saeedkolivand.metastream.platforms

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.BuildConfig
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONArray
import org.json.JSONObject

data class Destination(val id: Int, val name: String, val url: String, val active: Boolean)

/** Restream OAuth 2 code flow (Basic-auth token exchange, no PKCE offered), destinations and titles. Port of iOS RestreamService. */
object Restream : Account("Restream", "restream") {
    override val hasApp get() = BuildConfig.RESTREAM_CLIENT_ID.isNotEmpty()
    override val missingSecrets = "RESTREAM_CLIENT_ID / RESTREAM_CLIENT_SECRET"
    override val ingest = PlatformConfig.RESTREAM_INGEST

    var title by mutableStateOf("")
        private set
    var destinations by mutableStateOf<List<Destination>>(emptyList())
        private set
    var chatUrl by mutableStateOf("")
        private set

    private val basic get() = BuildConfig.RESTREAM_CLIENT_ID to BuildConfig.RESTREAM_CLIENT_SECRET

    private val api = Endpoint("https://api.restream.io/v2", "restreamAccess") {
        saveTokens(
            Net.form(TOKEN_URL, mapOf("grant_type" to "refresh_token", "refresh_token" to refreshToken()), basic = basic)
        )
    }

    override fun connect() = launchFlow {
        val state = Pkce.random(16)
        val url = "https://api.restream.io/login".toHttpUrl().newBuilder()
            .addQueryParameter("response_type", "code")
            .addQueryParameter("client_id", BuildConfig.RESTREAM_CLIENT_ID)
            .addQueryParameter("redirect_uri", PlatformConfig.WEB_REDIRECT)
            .addQueryParameter("state", state)
            .build().toString()
        codeFlow(url, state) { code ->
            Net.form(
                TOKEN_URL,
                mapOf("grant_type" to "authorization_code", "redirect_uri" to PlatformConfig.WEB_REDIRECT, "code" to code),
                basic = basic
            )
        }
    }

    override suspend fun refresh() {
        try {
            (api.callAny("GET", "/user/profile") as? JSONObject)?.let { user = it.optString("username") }
            // The list comes back wrapped as {"channels":[...]}; older docs show a bare array, so accept both.
            val raw = api.callAny("GET", "/user/channels")
            val list = (raw as? JSONArray).objects().ifEmpty { (raw as? JSONObject)?.objects("channels").orEmpty() }
            // The list omits the on/off state, so ask each channel for it.
            destinations = list.filter { it.has("id") }.map { c ->
                val id = c.optInt("id")
                val detail = runCatching { api.callAny("GET", "/user/channels/$id") }.getOrNull() as? JSONObject
                val on = detail?.let { d -> if (d.has("active")) d.optBoolean("active") else d.optBoolean("enabled", true) } ?: true
                Destination(id, c.optString("displayName").ifEmpty { "channel $id" }, c.optString("channelUrl"), on)
            }
            destinations.firstOrNull()?.let { first ->
                (api.callAny("GET", "/user/channel-meta/${first.id}") as? JSONObject)?.let { title = it.optString("title") }
            }
            (api.callAny("GET", "/user/streamKey") as? JSONObject)?.let { streamKey = it.optString("streamKey") }
            (api.callAny("GET", "/user/webchat/url") as? JSONObject)?.let { chatUrl = it.optString("webchatUrl") }
            Accounts.say("Restream updated")
        } catch (e: PlatformException) {
            Accounts.say(e.message.orEmpty())
        }
    }

    /** One title for every destination Restream fans out to. */
    suspend fun apply(title: String) = mutate("Restream titles updated") {
        for (d in destinations) api.callAny("PATCH", "/user/channel-meta/${d.id}", body = JSONObject().put("title", title))
    }

    /** Restream documents the update under the singular path; some deployments answer on the plural one, so try both. */
    suspend fun setActive(d: Destination, on: Boolean) {
        val body = JSONObject().put("active", on)
        val ok = listOf("/user/channel/${d.id}", "/user/channels/${d.id}").firstOrNull { path ->
            try {
                api.callAny("PATCH", path, body = body)
                true
            } catch (e: PlatformException) {
                Accounts.say(e.message.orEmpty())
                false
            }
        }
        if (ok != null) {
            destinations = destinations.map { if (it.id == d.id) it.copy(active = on) else it }
            Accounts.say("${d.name} ${if (on) "enabled" else "disabled"}")
        }
    }

    override fun disconnect() {
        signedOut()
        title = ""
        destinations = emptyList()
        chatUrl = ""
    }

    private const val TOKEN_URL = "https://api.restream.io/oauth/token"
}
