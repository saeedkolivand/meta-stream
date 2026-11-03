package com.saeedkolivand.metastream.core.model

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The stream session as the rest of the app sees it. Engine is the only writer; features that react to going live
 * (platform titles, the donate page, the bot, the session log) read it here instead of depending on Engine.
 */
object Session {
    private val _live = MutableStateFlow(false)
    val live: StateFlow<Boolean> = _live.asStateFlow()

    fun setLive(on: Boolean) {
        _live.value = on
    }
}
