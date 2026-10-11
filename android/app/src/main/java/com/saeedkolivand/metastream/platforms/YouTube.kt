package com.saeedkolivand.metastream.platforms

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.BuildConfig
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject

/** One page of liveChat/messages. */
class ChatPage(val items: List<JSONObject>, val nextPageToken: String?, val pollingIntervalMillis: Int)

/**
 * YouTube Google OAuth (PKCE, no secret, custom-scheme redirect), broadcast discovery, metadata apply and live-chat
 * send/poll. Port of iOS YouTubeService. It reuses the iOS Google client: that client type only validates the
 * redirect URI (bundle-id scheme), and MainActivity registers the same scheme, so no extra Google console setup is needed.
 */
object YouTube : Account("YouTube", "yt") {
    override val origin = "youtube"
    override val hasApp get() = BuildConfig.YOUTUBE_CLIENT_ID.isNotEmpty()
    override val missingSecrets = "YOUTUBE_CLIENT_ID"
    override val canSendChat = true
    override val ingest get() = ingestUrl

    var title by mutableStateOf("")
        private set
    var description by mutableStateOf("")
        private set
    var privacy by mutableStateOf("public")
        private set
    var latency by mutableStateOf("normal")
        private set
    private var ingestUrl by mutableStateOf("rtmps://a.rtmps.youtube.com:443/live2")
    private var videoId = ""
    private var liveChatId = ""
    private var broadcast = JSONObject()

    private val api = Endpoint("https://www.googleapis.com/youtube/v3", "ytAccess") {
        saveTokens(
            Net.form(
                "https://oauth2.googleapis.com/token",
                mapOf("grant_type" to "refresh_token", "client_id" to BuildConfig.YOUTUBE_CLIENT_ID, "refresh_token" to refreshToken())
            )
        )
    }

    override fun connect() = launchFlow {
        val verifier = Pkce.random(64)
        val state = Pkce.random(16)
        val url = "https://accounts.google.com/o/oauth2/v2/auth".toHttpUrl().newBuilder()
            .addQueryParameter("client_id", BuildConfig.YOUTUBE_CLIENT_ID)
            .addQueryParameter("redirect_uri", PlatformConfig.GOOGLE_REDIRECT)
            .addQueryParameter("response_type", "code")
            .addQueryParameter("scope", "https://www.googleapis.com/auth/youtube.force-ssl")
            .addQueryParameter("code_challenge", Pkce.s256(verifier))
            .addQueryParameter("code_challenge_method", "S256")
            .addQueryParameter("access_type", "offline")
            .addQueryParameter("prompt", "consent")
            .addQueryParameter("state", state)
            .build().toString()
        codeFlow(url, state) { code ->
            Net.form(
                "https://oauth2.googleapis.com/token",
                mapOf(
                    "client_id" to BuildConfig.YOUTUBE_CLIENT_ID,
                    "code" to code,
                    "code_verifier" to verifier,
                    "grant_type" to "authorization_code",
                    "redirect_uri" to PlatformConfig.GOOGLE_REDIRECT
                )
            )
        }
    }

    override suspend fun refresh() {
        try {
            api.call("GET", "/channels", mapOf("part" to "snippet", "mine" to "true")).objects("items").firstOrNull()?.let {
                user = it.optJSONObject("snippet")?.optString("title").orEmpty()
            }
            val items = api.call(
                "GET",
                "/liveBroadcasts",
                mapOf("part" to "id,snippet,contentDetails,status", "mine" to "true", "maxResults" to "10")
            ).objects("items")
            pickBroadcast(items)?.let { readBroadcast(it) }
            val cdn = api.call("GET", "/liveStreams", mapOf("part" to "cdn", "mine" to "true")).objects("items").firstOrNull()
            cdn?.optJSONObject("cdn")?.optJSONObject("ingestionInfo")?.let {
                streamKey = it.optString("streamName")
                it.optString("rtmpsIngestionAddress").takeIf(String::isNotEmpty)?.let { a -> ingestUrl = a }
            }
            Accounts.say("YouTube updated")
        } catch (e: PlatformException) {
            Accounts.say(e.message.orEmpty())
        }
    }

    private suspend fun readBroadcast(b: JSONObject) {
        broadcast = b
        videoId = b.optString("id")
        val sn = b.optJSONObject("snippet") ?: JSONObject()
        title = sn.optString("title")
        description = sn.optString("description")
        liveChatId = sn.optString("liveChatId")
        val status = b.optJSONObject("status")
        privacy = status?.optString("privacyStatus")?.ifEmpty { null } ?: "public"
        latency = b.optJSONObject("contentDetails")?.optString("latencyPreference")?.ifEmpty { null } ?: "normal"
        live = status?.optString("lifeCycleStatus") == "live"
        val video = api.call("GET", "/videos", mapOf("part" to "liveStreamingDetails", "id" to videoId)).objects("items").firstOrNull()
        viewers = video?.optJSONObject("liveStreamingDetails")?.optString("concurrentViewers")?.toIntOrNull() ?: 0
    }

    /**
     * `liveBroadcasts.update` REPLACES every field in each part you send, so each part is rebuilt from the last full
     * fetch with only the intended field changed. A bare title would wipe description, scheduledStartTime and the rest.
     */
    suspend fun apply(title: String, description: String, privacy: String, latency: String) {
        val sn = broadcast.optJSONObject("snippet")
        if (videoId.isEmpty() || sn == null) return Accounts.say("No YouTube broadcast found. Create one in YouTube Studio first.")
        val status = JSONObject((broadcast.optJSONObject("status") ?: JSONObject()).toString()).put("privacyStatus", privacy)
        val details = JSONObject((broadcast.optJSONObject("contentDetails") ?: JSONObject()).toString()).put("latencyPreference", latency)
        val body = JSONObject().put("id", videoId)
            .put(
                "snippet",
                JSONObject().put("title", title).put("description", description).put(
                    "scheduledStartTime",
                    sn.opt("scheduledStartTime") ?: ""
                )
            )
            .put("status", status).put("contentDetails", details)
        mutate("YouTube updated") { api.call("PUT", "/liveBroadcasts", mapOf("part" to "snippet,status,contentDetails"), body) }
    }

    override suspend fun send(text: String) {
        if (liveChatId.isEmpty()) return Accounts.say("No live chat on this broadcast yet")
        attempt {
            val details = JSONObject().put("messageText", text)
            val snippet = JSONObject().put("liveChatId", liveChatId).put("type", "textMessageEvent").put("textMessageDetails", details)
            api.call("POST", "/liveChatMessages", mapOf("part" to "snippet"), JSONObject().put("snippet", snippet))
        }
    }

    /**
     * One page of liveChat/messages (youtube.force-ssl already covers reading). Null when there is no live chat yet
     * (broadcast not started/found), so the poller backs off instead of erroring.
     */
    suspend fun pollLiveChat(pageToken: String?): ChatPage? {
        if (liveChatId.isEmpty()) return null
        val query = buildMap {
            put("liveChatId", liveChatId)
            put("part", "snippet,authorDetails")
            pageToken?.let { put("pageToken", it) }
        }
        val json = api.call("GET", "/liveChat/messages", query)
        return ChatPage(json.objects("items"), json.optString("nextPageToken").ifEmpty { null }, json.optInt("pollingIntervalMillis", 5000))
    }

    override fun disconnect() {
        signedOut()
        title = ""
        description = ""
        privacy = "public"
        latency = "normal"
        videoId = ""
        liveChatId = ""
        broadcast = JSONObject()
    }
}

/** The broadcast YouTube Studio calls "your stream": the most alive one, else the newest. */
internal fun pickBroadcast(items: List<JSONObject>): JSONObject? {
    fun lifecycle(b: JSONObject) = b.optJSONObject("status")?.optString("lifeCycleStatus")
    return listOf("live", "liveStarting", "testing", "ready", "created").firstNotNullOfOrNull { s ->
        items.firstOrNull { lifecycle(it) == s }
    }
        ?: items.firstOrNull()
}
