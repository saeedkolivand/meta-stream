package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.Kind
import com.saeedkolivand.metastream.core.applog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

private const val ENTER_TICK_MS = 50L
private const val RAMP_TICK_MS = 250L
private const val ANIM_TICK_MS = 100L // ponytail: animated emotes redraw at 10 fps
private const val RAMP_LEAD_MS = 2000L
private const val BURST_COUNT = 3 // ponytail: 3+ messages inside BURST_WINDOW_MS = a burst: no entry slide, coalesced redraws
private const val BURST_WINDOW_MS = 1000L
private const val BURST_RENDER_MS = 100L // ponytail: in a burst, at most one scene build per 100 ms
private const val PERF_LOG_MS = 10_000L

/** Only the newest rows play animated emotes; older ones hold their first frame. */
internal const val ANIMATED_ROWS = 3

/** True when at least [BURST_COUNT] of the message [times] fall in the last second. */
internal fun isBurst(times: List<Long>, now: Long) = times.count { now - it in 0..BURST_WINDOW_MS } >= BURST_COUNT

/** Scene-build timings (and whether the last one was in a burst) since the last report; [report] logs one "perf" line. */
private class RenderStats {
    private var n = 0
    private var totalMs = 0L
    private var maxMs = 0L
    private var burst = false

    @Synchronized
    fun add(ms: Long, inBurst: Boolean) {
        burst = inBurst
        n++
        totalMs += ms
        maxMs = maxOf(maxMs, ms)
    }

    @Synchronized
    fun report() {
        if (n == 0) return
        applog(
            "perf",
            "chat widget: $n scene builds/10s, avg ${"%.1f".format(
                totalMs.toFloat() / n
            )} ms, max $maxMs ms, burst ${if (burst) "on" else "off"}"
        )
        n = 0
        totalMs = 0
        maxMs = 0
    }
}

/** Suspends until the chat list or the emote set changes, or [timeoutMs] passes (null = wait for a change only). */
private suspend fun awaitChange(chat: List<ChatEvent>, version: Int, timeoutMs: Long?) {
    val wait = suspend {
        combine(ChatFeed.chat, EmoteBitmaps.version) { c, v -> c to v }.first { (c, v) -> c !== chat || v != version }
    }
    if (timeoutMs == null) wait() else withTimeoutOrNull(timeoutMs) { wait() }
}

/**
 * The chat widget: one cached bitmap per row, stacked into a [GpuScene]. The CPU only builds a scene when a row, an emote
 * or the motion state changes; the GPU animates entry, fade and emotes in between.
 */
internal fun chatWidget(l: Layer, box: Box, outW: Int, outH: Int, scope: CoroutineScope): WidgetBuild? {
    val style = ChatStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val scale = box.w / style.width
    val channel = "${ChatFeed.kickSlug},${ChatFeed.twitchChannel}"
    val filter = SpriteFilter().place(box, l.rotation)
    val scenes = ChatScenes(style, scale, channel)
    val stats = RenderStats()
    val job = scope.launch {
        launch {
            while (isActive) {
                delay(PERF_LOG_MS)
                stats.report()
            }
        }
        var last = ""
        var lastRender = 0L
        while (isActive) {
            val chat = ChatFeed.chat.value
            val version = EmoteBitmaps.version.value
            val now = System.currentTimeMillis()
            val rows = chatRows(chat, style, now)
            val burst = isBurst(rows.filter { it.kind == Kind.Message }.map { it.time }, now)
            val entering = !burst && rows.any { chatAppear(it, now) < 1f }
            val ramping = rows.any { chatOpacity(it, style, now) < 1f }
            // Hot phones freeze emotes on their first frame: streaming matters more than moving emotes.
            val animating = rows.takeLast(ANIMATED_ROWS).any(::hasAnimatedEmote) && !thermalHot()
            val moving = entering || ramping || animating
            val period = listOfNotNull(
                ENTER_TICK_MS.takeIf { entering },
                RAMP_TICK_MS.takeIf { ramping },
                ANIM_TICK_MS.takeIf { animating }
            ).minOrNull()
            val sig = "${rows.map { it.id }.hashCode()}|$version|$moving|$burst"
            if (sig != last) {
                val wait = if (burst) lastRender + BURST_RENDER_MS - now else 0L
                if (wait > 0) {
                    delay(wait)
                    continue // re-read the latest state, then build once
                }
                last = sig
                lastRender = now
                val t0 = System.nanoTime()
                filter.show(scenes.scene(rows, now, burst, animating))
                stats.add((System.nanoTime() - t0) / 1_000_000, burst)
            }
            awaitChange(chat, version, period?.let(::thermalDelay) ?: nextRampIn(rows, style, now))
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
