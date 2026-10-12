package com.saeedkolivand.metastream.overlay

import com.pedro.encoder.input.gl.render.filters.`object`.ImageFilterRender
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.ChatFeed
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

private const val ENTER_TICK_MS = 50L
private const val RAMP_TICK_MS = 250L
private const val RAMP_LEAD_MS = 2000L

/** Suspends until the chat list or the emote set changes, or [timeoutMs] passes (null = wait for a change only). */
private suspend fun awaitChange(chat: List<ChatEvent>, version: Int, timeoutMs: Long?) {
    val wait = suspend {
        combine(ChatFeed.chat, EmoteBitmaps.version) { c, v -> c to v }.first { (c, v) -> c !== chat || v != version }
    }
    if (timeoutMs == null) wait() else withTimeoutOrNull(timeoutMs) { wait() }
}

/**
 * The chat widget: one bitmap, re-rendered only when the visible rows, a loaded emote or an in-progress motion changes.
 * Idle chat costs nothing; a new row ticks at 20 fps for its 320 ms entry, a fade-out ramp at 4 fps.
 */
internal fun chatWidget(l: Layer, box: Box, outW: Int, outH: Int, scope: CoroutineScope): WidgetBuild? {
    val style = ChatStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val scale = box.w / style.width
    val channel = "${ChatFeed.kickSlug},${ChatFeed.twitchChannel}"
    val filter = ImageFilterRender()
    filter.placeIn(box, outW, outH, l.rotation)
    filter.setImage(renderChat(ChatFeed.chat.value, style, System.currentTimeMillis(), scale, channel) ?: blankBitmap())
    val job = scope.launch {
        var last = ""
        while (isActive) {
            val chat = ChatFeed.chat.value
            val version = EmoteBitmaps.version.value
            val now = System.currentTimeMillis()
            val rows = chatRows(chat, style, now)
            val entering = rows.any { chatAppear(it, now) < 1f }
            val ramping = rows.any { chatOpacity(it, style, now) < 1f }
            // Time joins the signature only while something moves; otherwise the picture is static.
            val tick = if (entering) {
                now / ENTER_TICK_MS
            } else if (ramping) {
                now / RAMP_TICK_MS
            } else {
                0L
            }
            val sig = "${rows.map { it.id }.hashCode()}|$version|$tick"
            if (sig != last) {
                last = sig
                // ponytail: the replaced bitmap is left to GC; RootEncoder's GL thread may still be uploading it.
                filter.setImage(renderChat(chat, style, now, scale, channel) ?: blankBitmap())
            }
            when {
                entering -> awaitChange(chat, version, thermalDelay(ENTER_TICK_MS))
                ramping -> awaitChange(chat, version, thermalDelay(RAMP_TICK_MS))
                else -> awaitChange(chat, version, nextRampIn(rows, style, now))
            }
        }
    }
    return WidgetBuild(filter, job)
}

/** Time until the oldest row starts its fade-out ramp, or null when nothing will ever fade. */
private fun nextRampIn(rows: List<ChatEvent>, style: ChatStyle, now: Long): Long? {
    if (style.fadeSeconds <= 0 || rows.isEmpty()) return null
    val start = rows.minOf { it.time } + style.fadeSeconds * 1000L - RAMP_LEAD_MS
    return (start - now).coerceAtLeast(1L)
}
