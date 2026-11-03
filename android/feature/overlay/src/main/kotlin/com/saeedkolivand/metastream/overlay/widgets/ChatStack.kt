package com.saeedkolivand.metastream.overlay

import android.graphics.Canvas
import android.graphics.RectF
import com.saeedkolivand.metastream.chat.Emotes
import com.saeedkolivand.metastream.chat.Run
import com.saeedkolivand.metastream.chat.tokenize
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import kotlin.math.roundToInt

const val CHAT_FADE_TOP = 0.18f
private const val PAD = 8f

/** Newest at the bottom: the stacked top of each row before its entry slide, oldest first. */
data class ChatPlacement(val event: ChatEvent, val y: Float, val alpha: Float)

fun chatPlacements(rows: List<ChatEvent>, heights: List<Float>, style: ChatStyle, now: Long, burst: Boolean): List<ChatPlacement> {
    val out = ArrayList<ChatPlacement>(rows.size)
    var y = style.height - PAD
    for (i in rows.indices.reversed()) {
        y -= heights[i]
        val appear = if (burst) 1f else chatAppear(rows[i], now)
        out += ChatPlacement(rows[i], y, chatOpacity(rows[i], style, now) * appear)
        y -= style.fontSize * 0.32f
        if (y < 0f) break
    }
    return out
}

fun hasAnimatedEmote(e: ChatEvent) = e.kind == Kind.Message &&
    tokenize(e.text, Emotes.byName).any { it is Run.Emote && EmoteBitmaps.isAnimated(it.url) }

private class CachedRow(val bmp: android.graphics.Bitmap, val h: Float, val slots: List<EmoteSlot>)

/**
 * Builds chat scenes from a per-row bitmap cache: a row is rasterised once (its animated emotes left blank) and reused until
 * its id or the emote set changes. Motion is a pure function of time, so the GPU animates between CPU wake-ups.
 */
class ChatScenes(private val style: ChatStyle, private val scale: Float, private val channel: String) {
    private val cache = HashMap<Long, Keyed>()

    fun scene(rows: List<ChatEvent>, now: Long, burst: Boolean, animating: Boolean): GpuScene? {
        if (rows.isEmpty()) return null
        val version = EmoteBitmaps.version.value
        val firstAnimated = rows.size - ANIMATED_ROWS
        val art = rows.mapIndexed { i, e -> rowFor(e, animating && i >= firstAnimated, version) }
        cache.keys.retainAll(rows.mapTo(HashSet()) { it.id })
        val places = chatPlacements(rows, art.map { it.h }, style, now, burst)
        val moving = isMoving(rows, style, now, burst, animating)
        val byId = rows.indices.associate { rows[it].id to art[it] }
        // Looked up here (widget coroutine): EmoteBitmaps may start a load, which must not happen on the GL thread.
        val emotes = if (!animating) {
            emptyMap()
        } else {
            art.flatMap { it.slots }.associate { s ->
                s to EmoteBitmaps.emote(s.url, (s.h * scale).roundToInt())
            }
        }
        return GpuScene(style.width, style.height, moving, System.nanoTime(), CHAT_FADE_TOP) { t ->
            val n = if (moving) now + (t * 1000).toLong() else now
            items(places, byId, emotes, n, burst)
        }
    }

    private fun rowFor(e: ChatEvent, animate: Boolean, version: Int): CachedRow {
        val key = if (animate) 1L + version * 2L else 0L
        val found = cache[e.id]
        if (found != null && found.key == key) return found.value
        // Laid out in output px (like the old whole-widget renderer), so the canvas is not scaled again.
        val size = style.fontSize * scale
        val pad = PAD * scale
        val row = chatRow(e, style, size, (style.width - 2 * PAD) * scale, scale, channel, 0, animate && hasAnimatedEmote(e))
        val bmp = newBitmap(style.width * scale, row.h + 2 * pad)
        row.draw(Canvas(bmp), pad, pad)
        val slots = row.slots.map { EmoteSlot(it.url, it.x / scale, it.y / scale, it.w / scale, it.h / scale) }
        val value = CachedRow(bmp, row.h / scale, slots)
        cache[e.id] = Keyed(key, value)
        return value
    }

    private fun items(
        places: List<ChatPlacement>,
        byId: Map<Long, CachedRow>,
        emotes: Map<EmoteSlot, Emote?>,
        now: Long,
        burst: Boolean
    ): List<Item> {
        val out = ArrayList<Item>(places.size + 2)
        for (p in places) {
            val row = byId[p.event.id] ?: continue
            val appear = if (burst) 1f else chatAppear(p.event, now)
            val top = p.y + (1f - appear) * style.fontSize * 0.7f
            val alpha = chatOpacity(p.event, style, now) * appear
            if (alpha <= 0f) continue
            out += Item(RectF(0f, top - PAD, style.width, top + row.h + PAD), row.bmp, alpha = alpha)
            for (s in row.slots) {
                val emote = emotes[s] ?: continue
                out += Item(RectF(PAD + s.x, top + s.y, PAD + s.x + s.w, top + s.y + s.h), emote.at(now), alpha = alpha)
            }
        }
        return out
    }

    private fun isMoving(rows: List<ChatEvent>, style: ChatStyle, now: Long, burst: Boolean, animating: Boolean): Boolean {
        if (animating) return true
        if (!burst && rows.any { chatAppear(it, now) < 1f }) return true
        return rows.any { chatOpacity(it, style, now) < 1f }
    }

    private class Keyed(val key: Long, val value: CachedRow)
}
