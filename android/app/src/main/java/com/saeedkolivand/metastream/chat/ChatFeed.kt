package com.saeedkolivand.metastream.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.platforms.YouTube
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.speech.SpeechSettings
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Process-wide chat: the last 200 messages and alerts, plus the channel names (persisted) that drive the providers.
 * Each origin is owned by exactly one provider: Kick by its Pusher socket, Twitch by EventSub when signed in (else
 * anonymous IRC for the typed channel), YouTube by polling once signed in. Per-platform chat toggles stop an origin.
 */
object ChatFeed {
    private lateinit var scope: CoroutineScope
    private lateinit var onMessage: (ChatEvent) -> Unit

    private val _chat = MutableStateFlow<List<ChatEvent>>(emptyList())
    val chat: StateFlow<List<ChatEvent>> = _chat

    var kickSlug by mutableStateOf("")
        private set
    var twitchChannel by mutableStateOf("")
        private set

    /** Latest follower/subscriber names for the {follower}/{sub} text tokens. */
    var lastFollower by mutableStateOf("")
        private set
    var lastSubscriber by mutableStateOf("")
        private set
    private var kickJob: Job? = null
    private var twitchJob: Job? = null
    private var youtubeJob: Job? = null
    private val seq = AtomicLong()

    /** [onMessage] sees every new message (read-aloud hooks in here). Restores and reconnects the saved channels. */
    fun init(scope: CoroutineScope, onMessage: (ChatEvent) -> Unit) {
        this.scope = scope
        this.onMessage = onMessage
        kickSlug = Prefs.string("kick")
        twitchChannel = Prefs.string("twitch")
        restartKick(0)
        // Signing in/out switches Twitch between EventSub and anonymous IRC, and starts/stops YouTube polling.
        scope.launch { snapshotFlow { Twitch.connected }.collect { restartTwitch(0) } }
        scope.launch { snapshotFlow { YouTube.connected }.collect { restartYouTube() } }
        // Channel emote sets need the Twitch user id, which arrives with the first refresh after sign-in.
        scope.launch { snapshotFlow { if (Twitch.connected) Twitch.userId else "" }.collect { Emotes.load(twitchId = it) } }
    }

    private fun onChat(e: ChatEvent) {
        _chat.update { (it + e.copy(id = seq.incrementAndGet())).takeLast(200) }
        when (e.kind) {
            Kind.Follow -> lastFollower = e.user
            Kind.Subscribe -> lastSubscriber = e.user
            else -> Unit
        }
        onMessage(e)
    }

    private fun launchSource(label: String, wait: Long, work: suspend () -> Unit) = scope.launch {
        delay(wait)
        backoff(label, work)
    }

    // Chat follows the field text (debounced so typing doesn't reconnect per keystroke) and runs whether or not we're live.
    fun setKick(slug: String) {
        kickSlug = slug
        Prefs.put("kick", slug)
        restartKick(DEBOUNCE_MS)
    }

    fun setTwitch(channel: String) {
        twitchChannel = channel
        Prefs.put("twitch", channel)
        restartTwitch(DEBOUNCE_MS)
    }

    fun restartKick(wait: Long = 0) {
        kickJob?.cancel()
        val slug = kickSlug.trim()
        kickJob = if (slug.isEmpty() || !SpeechSettings.kickChat.value) {
            null
        } else {
            launchSource("kick", wait) {
                scope.launch { Emotes.load(kickSlug = slug) }
                kickChat(slug, ::onChat)
            }
        }
        updateOrigins()
    }

    fun restartTwitch(wait: Long = 0) {
        twitchJob?.cancel()
        val channel = twitchChannel.trim()
        twitchJob = when {
            !SpeechSettings.twitchChat.value -> null
            Twitch.connected -> launchSource("twitch eventsub", wait) { twitchEventSub(::onChat) }
            channel.isNotEmpty() -> launchSource("twitch", wait) { twitchChat(channel, ::onChat) }
            else -> null
        }
        updateOrigins()
    }

    fun restartYouTube() {
        youtubeJob?.cancel()
        youtubeJob =
            if (YouTube.connected && SpeechSettings.youtubeChat.value) launchSource("youtube", 0) { youtubeChat(::onChat) } else null
        updateOrigins()
    }

    // Only prefix "on Kick, ..." when more than one origin is live; otherwise it is noise on every line.
    private fun updateOrigins() {
        Speaker.showOrigin = listOfNotNull(kickJob, twitchJob, youtubeJob).size > 1
    }

    /** True when at least one origin could produce chat (drives the sheet's empty state). */
    val configured get() = kickSlug.isNotEmpty() || twitchChannel.isNotEmpty() || Twitch.connected || YouTube.connected

    private const val DEBOUNCE_MS = 800L
}
