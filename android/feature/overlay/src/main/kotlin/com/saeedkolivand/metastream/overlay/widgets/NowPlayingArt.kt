package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.RectF
import com.saeedkolivand.metastream.platforms.NowPlayingTrack

/**
 * One Now playing card in natural units (iOS NowPlayingArt*): text rasterised once at the stream's pixel size, every frame
 * a pure function of (pose, clock), so the motion is GPU work only. The pose lanes apply per element about that element's
 * centre like iOS's lane(); the island and the text wipes clip on the GPU.
 */
class NowPlayingArt(
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

    private fun Txt.put(x: Float, y: Float, align: Int, maxW: Float): Item {
        val r = at(x * scale, y * scale, align, 1f, maxW * scale).rect
        return Item(RectF(r.left / scale, r.top / scale, r.right / scale, r.bottom / scale), bmp)
    }

    private val card = 0xFF141518.toInt()
    private val grey = 0xFFA9ADB5.toInt()
    private val trackBar = 0xFF2C2F35.toInt()
    private val big = st.design in setOf("slab", "island", "disc")

    private val line = when (st.design) {
        "slab", "twoLine", "island", "disc" -> null
        else -> t(
            if (tr.artist.isEmpty()) tr.title else "${tr.artist} - ${tr.title}",
            if (st.design ==
                "ticker"
            ) {
                32f
            } else {
                h * 0.5f
            },
            600,
            0xFFFFFFFF.toInt()
        )
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

    /** One frame: [p] the pose, [clock] seconds on a steady clock (spin and equaliser phase never jump between scenes). */
    fun items(p: NpPose, clock: Double): List<Item> {
        val out = ArrayList<Item>()
        when (st.design) {
            "slab" -> {
                out += Item(RectF(0f, 0f, w, h), color = 0xE6101014.toInt(), radius = 28f)
                out += art(RectF(28f, 28f, 228f, 228f), 16f).lane(p.cover, 128f, 128f)
                val x = 256f
                val maxW = w - x - 28f
                title?.let { out += it.put(x, 76f, -1, maxW).lane(p.line1, x, 76f) }
                artist?.let { out += it.put(x, 126f, -1, maxW).lane(p.line2, x, 76f) }
                bar(RectF(x, 182f, x + maxW, 190f), out)
                time?.let { out += it.put(w - 28f, 220f, 1, maxW) }
            }
            "island" -> {
                // The content is laid out at the open width and only clipped narrower, so text never reflows.
                val cw = minOf(w, maxOf(h, h + (w - h) * p.reveal))
                val capsule = RectF(0f, 0f, cw, h)
                out += Item(capsule, color = 0xFF111214.toInt(), radius = h / 2)
                val inside = ArrayList<Item>()
                inside += art(RectF(20f, 20f, 132f, 132f), 56f).lane(p.cover, 76f, 76f)
                val words = ArrayList<Item>()
                title?.let { words += it.put(160f, 56f, -1, 568f) }
                artist?.let { words += it.put(160f, 102f, -1, 568f) }
                bars(756f, 98f, 8f, 44f, 6f, 4f, 0.9, 0.3, 0.35f, clock, words)
                inside += words.map { it.lane(p.line1, 0f, 0f) }
                out += inside.map { it.clipped(capsule, h / 2) }
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
                // The record spins all the time; a change drops it out through the card's bottom and a new one in from the top.
                val record = p.cover.copy(rot = p.cover.rot + NowPlayingMotion.spin(clock))
                out += art(RectF(42f, 38f, 190f, 186f), 74f).lane(record, cx, cy)
                out += Item(RectF(cx - 8f, cy - 8f, cx + 8f, cy + 8f), color = card, radius = 8f).lane(p.cover.copy(rot = 0f), cx, cy)
                title?.let { out += it.put(240f, 72f, -1, 584f).lane(p.line1, 532f, 112f) }
                artist?.let { out += it.put(240f, 122f, -1, 584f).lane(p.line1, 532f, 112f) }
                time?.let { out += it.put(240f, 162f, -1, 584f).lane(p.line1, 532f, 112f) }
            }
            "ticker" -> {
                val textW = minOf(720f, (line?.w ?: 0f) / scale)
                out += Item(RectF(0f, 0f, minOf(w, 158f + textW + 32f), h), color = card, radius = 20f)
                out += art(RectF(12f, 12f, 84f, 84f), 12f).lane(p.cover, 48f, 48f)
                bars(108f, 64f, 6f, 32f, 4f, 0f, 0.8, 0.25, 0.3f, clock, out)
                // The text clip-wipes out to the right and in from the left; the strip keeps hugging it.
                val wipe = RectF(158f + textW * p.trail, 0f, 158f + textW * p.reveal, h)
                if (wipe.width() > 0f) line?.let { out += it.put(158f, 48f, -1, 720f).clipped(wipe, 0f) }
            }
            "twoLine" -> {
                out += Item(RectF(0f, 0f, w, h), color = box, radius = 12f)
                title?.let { out += it.put(16f, 28f, -1, w - 32f).lane(p.line1, 0f, 0f) }
                artist?.let { out += it.put(16f, 62f, -1, w - 32f).lane(p.line2, 0f, 0f) }
                bar(RectF(16f, 84f, w - 16f, 88f), out)
            }
            else -> wiped(p, out)
        }
        return if (p.alpha >= 1f) out else out.map { it.copy(alpha = it.alpha * p.alpha) }
    }

    /** Text, Pop-up and Text with cover: the box hugs its content and wipes from the left; at reveal 0 only `shut` shows. */
    private fun wiped(p: NpPose, out: MutableList<Item>) {
        val popup = st.design == "popup"
        val withCover = st.design == "cover" || popup
        var x = 16f
        val icon = ArrayList<Item>()
        if (withCover) {
            icon += art(RectF(x, 7f, x + h - 14f, h - 7f), 8f).lane(p.cover, x + (h - 14f) / 2, h / 2)
            x += h - 14f + 12f
        } else {
            eq(x, h / 2, h * 0.4f, icon)
            x += h * 0.4f + 12f
        }
        val size = minOf(w, x + (line?.w ?: 0f) / scale + 16f)
        val shut = if (popup) {
            0f
        } else if (withCover) {
            h + 6f
        } else {
            x
        }
        val wipe = RectF(size * p.trail, 0f, shut + (size - shut) * p.reveal, h)
        if (wipe.width() <= 0f) return
        val all = ArrayList<Item>()
        all += Item(RectF(0f, 0f, size, h), color = if (popup) 0xE6101014.toInt() else box, radius = 12f)
        if (popup) all += Item(RectF(0f, 0f, 6f, h), color = st.accentColor)
        all += icon
        line?.let { all += it.put(x, h / 2, -1, size - x - 16f) }
        out += all.map { it.clipped(wipe, 0f) }
    }

    private fun art(r: RectF, radius: Float) =
        if (cover != null) Item(r, cover, radius = radius) else Item(r, color = st.accentColor, alpha = 0.25f, radius = radius)

    private fun bar(r: RectF, out: MutableList<Item>) {
        val rad = r.height() / 2
        out += Item(RectF(r), color = 0x33FFFFFF, radius = rad)
        val x = r.left + r.width() * tr.progress()
        if (x > r.left + 0.5f) out += Item(RectF(r.left, r.top, x, r.bottom), color = st.accentColor, radius = rad)
    }

    /** Three bottom-anchored equaliser bars that bounce all the time (iOS NPBars). */
    private fun bars(
        left: Float,
        bottom: Float,
        bw: Float,
        bh: Float,
        gap: Float,
        radius: Float,
        period: Double,
        step: Double,
        low: Float,
        clock: Double,
        out: MutableList<Item>
    ) {
        for (i in 0..2) {
            val k = NowPlayingMotion.eq(clock, period, step * i, low)
            val x = left + i * (bw + gap)
            out += Item(RectF(x, bottom - bh * k, x + bw, bottom), color = st.accentColor, radius = radius)
        }
    }

    /** Three still equaliser bars as the music icon of the text designs (icons on-stream, never emoji). */
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

internal fun Item.copy(alpha: Float = this.alpha) = Item(rect, image, color, alpha, radius, clip, clipRadius, rotation)

fun Item.clipped(c: RectF, r: Float) = Item(rect, image, color, alpha, radius, c, r, rotation)

/** [l] applied about ([px], [py]): scale (with the flip), then offset, fade and turn (about the item's own centre). */
fun Item.lane(l: NpLane, px: Float, py: Float): Item {
    if (l == NpLane()) return this
    val sx = maxOf(0.001f, l.scale * l.scaleX)
    val sy = maxOf(0.001f, l.scale)
    val r = RectF(
        px + (rect.left - px) * sx + l.dx,
        py + (rect.top - py) * sy + l.dy,
        px + (rect.right - px) * sx + l.dx,
        py + (rect.bottom - py) * sy + l.dy
    )
    return Item(r, image, color, alpha * l.alpha, radius * minOf(sx, sy), clip, clipRadius, rotation + l.rot)
}
