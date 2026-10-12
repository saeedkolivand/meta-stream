package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.text.Layout
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.pedro.encoder.input.gl.render.filters.`object`.ImageFilterRender
import kotlin.math.floor
import kotlin.math.min

/**
 * Square code (width of the box) with the caption underneath. Modules are drawn as rects rather than scaled from a bitmap,
 * so their edges stay crisp for scanners at any size. Null for empty text.
 */
internal fun renderQr(style: QrStyle, scale: Float): Bitmap? {
    if (style.text.isEmpty()) return null
    val (nw, nh) = style.natural
    val w = nw * scale
    val h = nh * scale
    if (w < 8f || h < 8f) return null
    // Requested size 0 returns the raw module grid (quiet zone included), which is what we want to draw ourselves.
    val matrix = runCatching {
        QRCodeWriter().encode(style.text, BarcodeFormat.QR_CODE, 0, 0, mapOf(EncodeHintType.MARGIN to 1))
    }.getOrNull() ?: return null
    val bmp = newBitmap(w, h)
    val c = Canvas(bmp)
    c.drawColor(style.background)
    val pad = w * 0.06f
    val avail = w - 2 * pad
    val n = matrix.width
    // Whole pixels per module when they fit, so modules never blur into each other.
    val cell = if (avail >= n) floor(avail / n) else avail / n
    val origin = (w - cell * n) / 2
    val dark = Path()
    for (y in 0 until n) {
        for (x in 0 until n) {
            if (matrix[x, y]) {
                dark.addRect(
                    origin + x * cell,
                    origin + y * cell,
                    origin + (x + 1) * cell,
                    origin + (y + 1) * cell,
                    Path.Direction.CW
                )
            }
        }
    }
    c.drawPath(dark, Paint().apply { color = style.foreground })
    if (style.caption.isNotEmpty() && h > w) {
        val area = h - w
        val paint = widgetPaint(style.face, 600, min(area * 0.45f, w * 0.085f), style.foreground)
        val text = textLayout(style.caption, paint, (w - 2 * pad).toInt(), maxLines = 2, align = Layout.Alignment.ALIGN_CENTER)
        c.drawLayout(text, pad, w + (area - text.height) / 2)
    }
    return bmp
}

/** Static, so it is rendered once and has no job. */
internal fun qrWidget(l: Layer, box: Box, outW: Int, outH: Int): WidgetBuild? {
    val style = QrStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val bmp = renderQr(style, box.w / style.natural.first) ?: return null
    val filter = ImageFilterRender()
    filter.placeIn(box, outW, outH, l.rotation)
    filter.setImage(bmp)
    return WidgetBuild(filter, null)
}
