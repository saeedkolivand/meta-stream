package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import java.io.File
import kotlin.math.max

/** An image decoded (down-sampled to roughly [box]) and cropped; [w]/[h] are the cropped size in the file's own pixels. */
internal class Decoded(val bitmap: Bitmap, val w: Int, val h: Int)

internal fun imageSize(f: File): Pair<Int, Int>? {
    val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(f.path, o)
    return if (o.outWidth > 0) o.outWidth to o.outHeight else null
}

/** [crop] is left, top, right, bottom in source px. [targetW] is the on-screen width, used to pick the sample size. */
internal fun decode(f: File, crop: List<Int>, targetW: Float): Decoded? {
    val (w, h) = imageSize(f) ?: return null
    val cw = w - crop[0] - crop[2]
    val ch = h - crop[1] - crop[3]
    if (cw <= 0 || ch <= 0) return null
    var sample = 1
    while (cw / (sample * 2) >= targetW) sample *= 2
    val bmp = BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
    val out = if (crop.all { it == 0 }) {
        bmp
    } else {
        Bitmap.createBitmap(bmp, crop[0] / sample, crop[1] / sample, max(1, cw / sample), max(1, ch / sample))
    }
    return Decoded(out, cw, ch)
}

/** Multi-line text drawn at [px] pixel size. OBS text sizes are canvas px, so callers pass size * canvas-to-output scale. */
internal fun textBitmap(text: String, face: String, bold: Boolean, px: Float, argb: Int): Bitmap? {
    if (text.isBlank()) return null
    val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
        textSize = px
        color = argb
        typeface = Typeface.create(face.ifEmpty { null }, if (bold) Typeface.BOLD else Typeface.NORMAL)
    }
    val width = text.lines().maxOf { Layout.getDesiredWidth(it, paint) }.toInt() + 2
    val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, width).build()
    return Bitmap.createBitmap(width, max(1, layout.height), Bitmap.Config.ARGB_8888).also { layout.draw(Canvas(it)) }
}

internal fun colorBitmap(argb: Int): Bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888).also { it.eraseColor(argb) }
