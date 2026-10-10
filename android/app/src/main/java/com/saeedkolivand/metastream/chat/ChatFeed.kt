package com.saeedkolivand.metastream.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.Prefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Process-wide read-only chat: the last 200 messages, plus the channel names (persisted) that drive the providers. */
object ChatFeed {
    private lateinit var scope: CoroutineScope
    private lateinit var onMessage: (ChatEvent) -> Unit

    private val _chat = MutableStateFlow<List<ChatEvent>>(emptyList())
    val chat: StateFlow<List<ChatEvent>> = _chat

    var kickSlug by mutableStateOf("")
        private set
    var twitchChannel by mutableStateOf("")
        private set
    private var kickJob: Job? = null
    private var twitchJob: Job? = null

    /** [onMessage] sees every new message (read-aloud hooks in here). Restores and reconnects the saved channels. */
    fun init(scope: CoroutineScope, onMessage: (ChatEvent) -> Unit) {
        this.scope = scope
        this.onMessage = onMessage
        setKick(Prefs.string("kick"))
        setTwitch(Prefs.string("twitch"))
    }

    private fun onChat(e: ChatEvent) {
        _chat.update { (it + e).takeLast(200) }
        onMessage(e)
    }

    // Chat follows the field text (debounced so typing doesn't reconnect per keystroke) and runs whether or not we're live.
    fun setKick(slug: String) {
        kickSlug = slug
        Prefs.put("kick", slug)
        kickJob?.cancel()
        kickJob = if (slug.isBlank()) {
            null
        } else {
            scope.launch {
                delay(DEBOUNCE_MS)
                backoff("kick") { kickChat(slug.trim(), ::onChat) }
            }
        }
    }

    fun setTwitch(channel: String) {
        twitchChannel = channel
        Prefs.put("twitch", channel)
        twitchJob?.cancel()
        twitchJob = if (channel.isBlank()) {
            null
        } else {
            scope.launch {
                delay(DEBOUNCE_MS)
                backoff("twitch") { twitchChat(channel.trim(), ::onChat) }
            }
        }
    }

    private const val DEBOUNCE_MS = 800L
}
