package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import java.io.ByteArrayOutputStream

// ponytail: 60 frames per emote; longer animations are sampled evenly, and any frame that fails to decode makes it a still.
private const val MAX_FRAMES = 60
private const val DEFAULT_DELAY_MS = 100
private const val MIN_DELAY_MS = 20

/** An emote: one bitmap, or a looping animation whose frame n shows until `ends[n]` ms into the loop. */
internal class Emote(val frames: List<Bitmap>, private val ends: LongArray) {
    val animated get() = frames.size > 1
    val bytes get() = frames.sumOf { it.byteCount }

    fun at(t: Long) = frames[frameIndex(ends, t)]
}

/** Index of the frame showing at [t] ms: the first whose cumulative end passes t modulo the loop length. */
internal fun frameIndex(ends: LongArray, t: Long): Int {
    val total = ends.lastOrNull() ?: return 0
    if (total <= 0) return 0
    val m = Math.floorMod(t, total)
    return ends.indexOfFirst { it > m }.coerceAtLeast(0)
}

/** One decoded frame before compositing: its bitmap, where it sits on the canvas, how long it shows, how it ends. */
private class Raw(val bmp: Bitmap, val x: Int, val y: Int, val ms: Int, val blend: Boolean, val clear: Boolean)

private fun delayMs(ms: Int) = if (ms <= 0) DEFAULT_DELAY_MS else maxOf(ms, MIN_DELAY_MS)

private fun u16(b: ByteArray, i: Int) = (b[i].toInt() and 0xFF) or ((b[i + 1].toInt() and 0xFF) shl 8)
private fun u24(b: ByteArray, i: Int) = u16(b, i) or ((b[i + 2].toInt() and 0xFF) shl 16)
private fun u32(b: ByteArray, i: Int) = u24(b, i) or ((b[i + 3].toInt() and 0xFF) shl 24)
private fun le(n: Int, bytes: Int) = ByteArray(bytes) { (n shr (8 * it)).toByte() }

private fun ByteArray.tag(i: Int, s: String) = i + s.length <= size && s.indices.all { this[i + it].toInt() == s[it].code }

/**
 * Decodes [b] into an [Emote] scaled to [px] tall (at most 3x as wide). GIF and animated WebP get every frame composited
 * onto a full canvas; anything else, or any failure, is the first frame as a still. Null when it isn't an image at all.
 */
internal fun decodeEmote(b: ByteArray, px: Int): Emote? {
    val gif = b.tag(0, "GIF8")
    val raws = if (gif || (b.tag(0, "RIFF") && b.tag(8, "WEBP"))) {
        runCatching { if (gif) gifFrames(b) else webpFrames(b) }.getOrNull()
    } else {
        null
    }
    val anim = raws?.takeIf { it.size > 1 }?.let { runCatching { composite(it, px) }.getOrNull() }
    if (anim != null) return anim
    val still = BitmapFactory.decodeByteArray(b, 0, b.size) ?: return null
    return Emote(listOf(fit(still, px)), longArrayOf(1))
}

private fun fit(src: Bitmap, px: Int): Bitmap {
    val w = (src.width.toFloat() * px / src.height).toInt().coerceIn(1, px * 3)
    return if (src.height == px && src.width == w) src else Bitmap.createScaledBitmap(src, w, px, true)
}

private fun composite(raws: List<Raw>, px: Int): Emote {
    val canvasBmp = Bitmap.createBitmap(raws.maxOf { it.x + it.bmp.width }, raws.maxOf { it.y + it.bmp.height }, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(canvasBmp)
    val replace = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC) }
    val wipe = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR) }
    val n = minOf(MAX_FRAMES, raws.size)
    val picks = (0 until n).map { it * raws.size / n }.toSet()
    val frames = mutableListOf<Bitmap>()
    val ends = mutableListOf<Long>()
    var total = 0L
    raws.forEachIndexed { i, r ->
        canvas.drawBitmap(r.bmp, r.x.toFloat(), r.y.toFloat(), if (r.blend) null else replace)
        if (i in picks) {
            frames += fit(canvasBmp.copy(Bitmap.Config.ARGB_8888, false), px)
            ends += 0
        }
        total += r.ms
        ends[ends.lastIndex] = total
        if (r.clear) canvas.drawRect(r.x.toFloat(), r.y.toFloat(), (r.x + r.bmp.width).toFloat(), (r.y + r.bmp.height).toFloat(), wipe)
    }
    return Emote(frames, ends.toLongArray())
}

/** Each GIF frame is rewrapped as a one-frame GIF (header, palette, its own control block, image data) for BitmapFactory. */
private fun gifFrames(b: ByteArray): List<Raw> {
    val packed = b[10].toInt() and 0xFF
    val palette = if (packed and 0x80 != 0) 3 shl ((packed and 7) + 1) else 0
    var i = 13 + palette
    val out = mutableListOf<Raw>()
    var gce: ByteArray? = null
    while (i < b.size && b[i].toInt() != 0x3B) {
        when (b[i].toInt() and 0xFF) {
            0x21 -> {
                if (b[i + 1].toInt() and 0xFF == 0xF9) gce = b.copyOfRange(i, i + 8)
                i += 2
                while (b[i].toInt() != 0) i += (b[i].toInt() and 0xFF) + 1
                i++
            }
            0x2C -> {
                val local = b[i + 9].toInt() and 0xFF
                var end = i + 10 + if (local and 0x80 != 0) 3 shl ((local and 7) + 1) else 0
                end++ // LZW minimum code size
                while (b[end].toInt() != 0) end += (b[end].toInt() and 0xFF) + 1
                end++
                val one = ByteArrayOutputStream()
                one.write(b, 0, 6)
                one.write(b, i + 5, 4) // the frame is its own logical screen
                one.write(b, 10, 3 + palette)
                gce?.let { one.write(it) }
                one.write(0x2C)
                one.write(ByteArray(4))
                one.write(b, i + 5, end - i - 5)
                one.write(0x3B)
                val bmp = BitmapFactory.decodeByteArray(one.toByteArray(), 0, one.size()) ?: error("frame")
                val flags = gce?.get(3)?.toInt() ?: 0
                val ms = gce?.let { u16(it, 4) * 10 } ?: 0
                out += Raw(bmp, u16(b, i + 1), u16(b, i + 3), delayMs(ms), true, (flags shr 2) and 7 == 2)
                gce = null
                i = end
            }
            else -> error("bad gif")
        }
    }
    return out
}

/** Animated WebP: each ANMF chunk's image data is rewrapped as a standalone extended WebP and decoded on its own. */
private fun webpFrames(b: ByteArray): List<Raw> {
    val out = mutableListOf<Raw>()
    var i = 12
    while (i + 8 <= b.size) {
        val size = u32(b, i + 4)
        if (b.tag(i, "ANMF")) {
            val p = i + 8
            val w = u24(b, p + 6) + 1
            val h = u24(b, p + 9) + 1
            val flags = b[p + 15].toInt()
            val body = b.copyOfRange(p + 16, p + size)
            val one = ByteArrayOutputStream()
            one.write("RIFF".toByteArray())
            one.write(le(4 + 18 + body.size, 4))
            one.write("WEBPVP8X".toByteArray())
            one.write(le(10, 4))
            one.write(byteArrayOf(0x10, 0, 0, 0))
            one.write(le(w - 1, 3))
            one.write(le(h - 1, 3))
            one.write(body)
            val bmp = BitmapFactory.decodeByteArray(one.toByteArray(), 0, one.size()) ?: error("frame")
            out += Raw(bmp, u24(b, p) * 2, u24(b, p + 3) * 2, delayMs(u24(b, p + 12)), flags and 2 == 0, flags and 1 != 0)
        }
        i += 8 + size + (size and 1)
    }
    return out
}
