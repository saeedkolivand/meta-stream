package com.saeedkolivand.metastream.platforms

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.applog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject

data class Category(val id: String, val name: String)

/** Client IDs/secrets (BuildConfig, from local.properties or CI env), the web redirect and the ingest URLs in one place. */
internal object PlatformConfig {
    const val WEB_REDIRECT = "https://metastream.iamsaeed.dev/oauth.html"
    const val GOOGLE_REDIRECT = "com.saeedkolivand.metastream:/oauth2redirect"
    const val KICK_INGEST = "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/"
    const val TWITCH_INGEST = "rtmps://live.twitch.tv:443/app/"
    const val RESTREAM_INGEST = "rtmp://live.restream.io/live"
}

/** Process-wide wiring: the app context/scope for sign-in flows, the shared status line, and chat routing. */
object Accounts {
    internal lateinit var app: Context
    internal lateinit var scope: CoroutineScope

    /** Last result line shown under Stream Manager (iOS `Platforms.status`). */
    var status by mutableStateOf("")
        internal set

    val all: List<Account> get() = listOf(Kick, Twitch, Restream, YouTube)

    fun init(context: Context, scope: CoroutineScope) {
        app = context.applicationContext
        this.scope = scope
        TokenStore.init(app)
        for (a in all) {
            a.restore()
            if (a.connected) scope.launch { a.refresh() }
        }
    }

    internal fun say(message: String) {
        applog("api", "status: $message")
        status = message
    }

    /** Sends [text] to the account for chat origin [platform] ("kick"/"twitch"/"youtube"); failures land in [status]. */
    suspend fun send(platform: String, text: String) {
        val account = when (platform) {
            "kick" -> Kick
            "twitch" -> Twitch
            "youtube" -> YouTube
            else -> return
        }
        account.send(text.trim().ifEmpty { return })
    }

    /** Chat origins the compose bar can send to: Kick when a channel is set (it posts as the connected account), Twitch/YouTube when connected. */
    fun sendOrigins(kickSlug: String): List<String> = buildList {
        if (kickSlug.isNotBlank() && Kick.connected) add("kick")
        if (Twitch.connected) add("twitch")
        if (YouTube.connected) add("youtube")
    }
}

/** State and behaviour shared by the four services (iOS PlatformAdapter + TokenStore helpers). Subclasses are singleton objects. */
abstract class Account(val label: String, internal val prefix: String) {
    var connected by mutableStateOf(false)
        private set
    var user by mutableStateOf("")
        protected set
    var live by mutableStateOf(false)
        protected set
    var viewers by mutableStateOf(0)
        protected set
    var streamKey by mutableStateOf("")
        protected set

    /** Chat-origin id ("kick"/"twitch"/"youtube") used by the compose bar and notifications. */
    open val origin: String get() = prefix

    abstract val hasApp: Boolean
    abstract val ingest: String
    open val hasCategory = false
    open val canSendChat = false

    /** Env/secret names to show when [hasApp] is false. */
    abstract val missingSecrets: String

    internal open fun restore() {
        connected = TokenStore.has(prefix + "Access")
    }

    abstract fun connect()

    abstract suspend fun refresh()

    abstract fun disconnect()

    open suspend fun send(text: String) = Unit

    /** Stores access/refresh tokens; returns the scope list when the provider sent one as an array (only Twitch does). */
    protected fun saveTokens(json: JSONObject): List<String>? {
        val access = json.optString("access_token").ifEmpty { throw PlatformException("no access_token in response") }
        TokenStore.set(prefix + "Access", access)
        json.optString("refresh_token").takeIf { it.isNotEmpty() }?.let { TokenStore.set(prefix + "Refresh", it) }
        connected = true
        return json.optJSONArray("scope")?.strings()
    }

    protected fun signedOut() {
        TokenStore.forget(prefix)
        connected = false
        user = ""
        live = false
        viewers = 0
        streamKey = ""
    }

    protected fun refreshToken() = TokenStore.get(prefix + "Refresh").orEmpty()

    /** Authorize in the browser -> token exchange -> persist -> refresh (iOS PlatformFlow.codeFlow). */
    protected suspend fun codeFlow(authUrl: String, state: String, exchange: suspend (code: String) -> JSONObject) {
        val code = OAuth.await(Accounts.app, authUrl, state) ?: return Accounts.say("$label login cancelled")
        try {
            saveTokens(exchange(code))
            Accounts.say("$label connected")
            refresh()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Accounts.say("$label token error: ${e.message}")
        }
    }

    /** Runs a mutation: failures surface as status, success shows [done] and re-fetches. */
    protected suspend fun mutate(done: String, work: suspend () -> Unit) {
        try {
            work()
            Accounts.say(done)
            refresh()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Accounts.say(e.message.orEmpty())
        }
    }

    /** Fire-and-forget call (chat send, quick actions): only failures surface, plus [done] when given. */
    internal suspend fun attempt(done: String? = null, work: suspend () -> Unit) {
        try {
            work()
            done?.let(Accounts::say)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Accounts.say(e.message.orEmpty())
        }
    }

    protected fun launchFlow(block: suspend () -> Unit) {
        Accounts.scope.launch { block() }
    }
}
