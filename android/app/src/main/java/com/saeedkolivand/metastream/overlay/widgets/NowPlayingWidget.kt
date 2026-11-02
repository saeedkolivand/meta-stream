package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.RectF
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.platforms.NowPlayingTrack
import com.saeedkolivand.metastream.platforms.Spotify
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val ENTER_S = 0.4f
private const val EXIT_S = 0.3f
private const val ART_WAIT_MS = 1200L

/**
 * The Now playing (Spotify) widget on the GPU (iOS NowPlayingPlayer / NowPlayingArt). Holds a still scene while a song
 * plays, re-shown only when the second, the bar's pixel width or the cover changes; a song change plays the old card out
 * and the new one in as one moving scene. Eight designs as on iOS (slab, island, disc, ticker, text, two lines, text with
 * cover, pop-up). ponytail: one fade-and-slide motion for all of them, and the disc and equaliser bars hold still (iOS spins
 * and bounces them); animate them with a moving scene if a still card ever reads as frozen.
 */
internal fun nowPlayingWidget(l: Layer, box: Box, scope: CoroutineScope): WidgetBuild? {
    val style = NowPlayingStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val scale = box.w / style.natural.first
    val filter = SpriteFilter().place(box, l.rotation)
    val job = scope.launch {
        Spotify.retain()
        try {
            var shown: Pair<NowPlayingTrack, Bitmap?>? = null
            var openedAt = 0L
            var hidden = false
            var waiting: Long? = null
            var sig = ""
            fun art(t: NowPlayingTrack, a: Bitmap?) = NowPlayingArt(style, t, a, scale)
            while (isActive) {
                val now = System.currentTimeMillis()
                val live = Spotify.track
                val cur = shown
                if (live == null && cur != null) {
                    if (!hidden) filter.show(art(cur.first, cur.second).scene(exit = true)).also { delay((EXIT_S * 1000).toLong()) }
                    filter.show(null)
                    shown = null
                    hidden = false
                    sig = ""
                } else if (live != null && live.id != cur?.first?.id) {
                    waiting = waiting ?: now
                    if (Spotify.art != null || now - waiting > ART_WAIT_MS) {
                        waiting = null
                        if (cur != null &&
                            !hidden
                        ) {
                            filter.show(art(cur.first, cur.second).scene(exit = true)).also { delay((EXIT_S * 1000).toLong()) }
                        }
                        shown = live to Spotify.art
                        applog("overlay", "now playing widget: ${style.design} ${live.title}")
                        filter.show(art(live, Spotify.art).scene(enter = true))
                        delay((ENTER_S * 1000).toLong())
                        openedAt = now
                        hidden = false
                        sig = ""
                    }
                } else if (live != null && cur != null) {
                    if (cur.second == null && Spotify.art != null) sig = ""
                    shown = live to (cur.second ?: Spotify.art)
                    if (style.design == "popup" && !hidden && now - openedAt > style.popupSeconds * 1000L) {
                        filter.show(art(live, shown.second).scene(exit = true))
                        delay((EXIT_S * 1000).toLong())
                        filter.show(null)
                        hidden = true
                    }
                    val next =
                        "${live.id}|${shown.second != null}|${if (style.design == "slab" || style.design == "disc") {
                            live.elapsedMs(
                                now
                            ) / 1000
                        } else {
                            0
                        }}|" +
                            (live.progress(now) * box.w).toInt()
                    if (!hidden && next != sig) {
                        sig = next
                        filter.show(art(live, shown.second).scene())
                    }
                }
                delay(250)
            }
        } finally {
            Spotify.release()
        }
    }
    return WidgetBuild(filter, job)
}

/** One card in natural units; text rasterised once at the stream's pixel size. */
private class NowPlayingArt(
    private val st: NowPlayingStyle,
    private val tr: NowPlayingTrack,
    private val cover: Bitmap?,
    private val scale: Float
) {
    private val w = st.natural.first
    private val h = st.natural.second
    private val box = 0x33000000 // the text widget's 20% box
    private val dim = 0xB3FFFFFF.toInt()

    private fun t(s: String, size: Float, weight: Int, color: Int) = ink(s, size * scale, weight, color, face = st.face)

    private fun Txt.put(x: Float, y: Float, align: Int, alpha: Float, maxW: Float): Item {
        val r = at(x * scale, y * scale, align, alpha, maxW * scale).rect
        return Item(RectF(r.left / scale, r.top / scale, r.right / scale, r.bottom / scale), bmp, alpha = alpha)
    }

    private val card = 0xFF141518.toInt()
    private val grey = 0xFFA9ADB5.toInt()
    private val trackBar = 0xFF2C2F35.toInt()
    private val big = st.design in setOf("slab", "island", "disc")

    private val line = when (st.design) {
        "slab", "twoLine", "island", "disc" -> null
        else -> t("${tr.title} · ${tr.artist}".trimEnd(' ', '·'), if (st.design == "ticker") 32f else h * 0.5f, 600, 0xFFFFFFFF.toInt())
    }
    private val title = t(
        tr.title,
        if (st.design == "slab") {
            44f
        } else if (big) {
            39f
        } else {
            30f
        },
        700,
        0xFFFFFFFF.toInt()
    )
    private val artist = t(
        tr.artist,
        if (st.design == "slab") {
            32f
        } else if (big) {
            29f
        } else {
            24f
        },
        500,
        if (big) grey else dim
    )
    private val time = if (st.design == "slab" || st.design == "disc") {
        t("${clock(tr.elapsedMs())} / ${clock(tr.durationMs)}", 24f, 500, if (st.design == "disc") grey else dim)
    } else {
        null
    }

    /** enter: fade in rising 12 units; exit: fade out rising; neither: settled. */
    fun scene(enter: Boolean = false, exit: Boolean = false) = GpuScene(w, h, enter || exit) { s ->
        val p = (s / if (enter) ENTER_S else EXIT_S).coerceIn(0f, 1f)
        val a = if (enter) {
            dEaseOut(p)
        } else if (exit) {
            1 - dEaseIn(p)
        } else {
            1f
        }
        val dy = if (enter) {
            12f * (1 - dEaseOut(p))
        } else if (exit) {
            -12f * dEaseIn(p)
        } else {
            0f
        }
        items().map {
            val clip = it.clip?.let { c -> RectF(c.left, c.top + dy, c.right, c.bottom + dy) }
            Item(
                RectF(it.rect.left, it.rect.top + dy, it.rect.right, it.rect.bottom + dy),
                it.image,
                it.color,
                it.alpha * a,
                it.radius,
                clip,
                it.clipRadius
            )
        }
    }

    private fun items(): List<Item> {
        val out = ArrayList<Item>()
        val textA = 1f // the fade is applied by scene()
        when (st.design) {
            "slab" -> {
                out += Item(RectF(0f, 0f, w, h), color = 0xE6101014.toInt(), radius = 28f)
                art(RectF(28f, 28f, 228f, 228f), 16f, out)
                val x = 256f
                val maxW = w - x - 28f
                title?.let { out += it.put(x, 76f, -1, textA, maxW) }
                artist?.let { out += it.put(x, 126f, -1, textA, maxW) }
                bar(RectF(x, 182f, x + maxW, 190f), out)
                time?.let { out += it.put(w - 28f, 220f, 1, textA, maxW) }
            }
            "island" -> {
                out += Item(RectF(0f, 0f, w, h), color = 0xFF111214.toInt(), radius = h / 2)
                art(RectF(20f, 20f, 132f, 132f), 56f, out)
                title?.let { out += it.put(160f, 56f, -1, textA, 568f) }
                artist?.let { out += it.put(160f, 102f, -1, textA, 568f) }
                eq(756f, 76f, 44f, out)
            }
            "disc" -> {
                out += Item(RectF(0f, 0f, w, h), color = card, radius = 36f)
                val cx = 116f
                val cy = 112f
                out += Item(RectF(cx - 90f, cy - 90f, cx + 90f, cy + 90f), color = trackBar, radius = 90f)
                out += Item(RectF(cx - 82f, cy - 82f, cx + 82f, cy + 82f), color = card, radius = 82f)
                // The progress ring: dots round the circle from 12 o'clock, overlapping into a stroke (rects only on the GPU).
                for (k in 0..(96 * tr.progress()).toInt()) {
                    val a = -Math.PI / 2 + 2 * Math.PI * k / 96
                    val x = cx + 86f * kotlin.math.cos(a).toFloat()
                    val y = cy + 86f * kotlin.math.sin(a).toFloat()
                    out += Item(RectF(x - 4f, y - 4f, x + 4f, y + 4f), color = st.accentColor, radius = 4f)
                }
                art(RectF(42f, 38f, 190f, 186f), 74f, out)
                out += Item(RectF(cx - 8f, cy - 8f, cx + 8f, cy + 8f), color = card, radius = 8f)
                title?.let { out += it.put(240f, 72f, -1, textA, 584f) }
                artist?.let { out += it.put(240f, 122f, -1, textA, 584f) }
                time?.let { out += it.put(240f, 162f, -1, textA, 584f) }
            }
            "ticker" -> {
                val textW = minOf(720f, (line?.w ?: 0f) / scale)
                out += Item(RectF(0f, 0f, minOf(w, 158f + textW + 32f), h), color = card, radius = 20f)
                art(RectF(12f, 12f, 84f, 84f), 12f, out)
                eq(108f, 48f, 32f, out)
                line?.let { out += it.put(158f, 48f, -1, textA, 720f) }
            }
            "twoLine" -> {
                out += Item(RectF(0f, 0f, w, h), color = box, radius = 12f)
                title?.let { out += it.put(16f, 28f, -1, textA, w - 32f) }
                artist?.let { out += it.put(16f, 62f, -1, textA, w - 32f) }
                bar(RectF(16f, 84f, w - 16f, 88f), out)
            }
            else -> {
                val popup = st.design == "popup"
                out += Item(RectF(0f, 0f, w, h), color = if (popup) 0xE6101014.toInt() else box, radius = 12f)
                if (popup) out += Item(RectF(0f, 0f, 6f, h), color = st.accentColor, clip = RectF(0f, 0f, w, h), clipRadius = 12f)
                var x = 16f
                if (st.design == "cover" || popup) {
                    art(RectF(x, 7f, x + h - 14f, h - 7f), 8f, out)
                    x += h - 14f + 12f
                } else {
                    eq(x, h / 2, h * 0.4f, out)
                    x += h * 0.4f + 12f
                }
                line?.let { out += it.put(x, h / 2, -1, textA, w - x - 16f) }
            }
        }
        return out
    }

    private fun art(r: RectF, radius: Float, out: MutableList<Item>) {
        out += if (cover != null) Item(r, cover, radius = radius) else Item(r, color = st.accentColor, alpha = 0.25f, radius = radius)
    }

    private fun bar(r: RectF, out: MutableList<Item>) {
        val rad = r.height() / 2
        out += Item(RectF(r), color = 0x33FFFFFF, radius = rad)
        val x = r.left + r.width() * tr.progress()
        if (x > r.left + 0.5f) out += Item(RectF(r.left, r.top, x, r.bottom), color = st.accentColor, radius = rad)
    }

    /** Three equaliser bars as the music icon (icons on-stream, never emoji). */
    private fun eq(x: Float, cy: Float, size: Float, out: MutableList<Item>) {
        val bw = size / 4
        listOf(0.55f, 1f, 0.75f).forEachIndexed { i, k ->
            val bh = size * k
            out +=
                Item(
                    RectF(x + i * bw * 1.5f, cy + size / 2 - bh, x + i * bw * 1.5f + bw, cy + size / 2),
                    color = st.accentColor,
                    radius =
                    bw / 3
                )
        }
    }

    private fun clock(ms: Int) = (ms / 1000).let { "%d:%02d".format(it / 60, it % 60) }
}
