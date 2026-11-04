package com.saeedkolivand.metastream.overlay.widgets.text

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.RectF
import com.pedro.encoder.input.gl.render.filters.`object`.ImageFilterRender
import com.saeedkolivand.metastream.overlay.Box
import com.saeedkolivand.metastream.overlay.Layer
import com.saeedkolivand.metastream.overlay.TextStyle
import com.saeedkolivand.metastream.overlay.WidgetBuild
import com.saeedkolivand.metastream.overlay.WidgetLocation
import com.saeedkolivand.metastream.overlay.blankBitmap
import com.saeedkolivand.metastream.overlay.drawLayout
import com.saeedkolivand.metastream.overlay.fillPaint
import com.saeedkolivand.metastream.overlay.newBitmap
import com.saeedkolivand.metastream.overlay.placeIn
import com.saeedkolivand.metastream.overlay.textLayout
import com.saeedkolivand.metastream.overlay.thermalDelay
import com.saeedkolivand.metastream.overlay.widest
import com.saeedkolivand.metastream.overlay.widgetBox
import com.saeedkolivand.metastream.overlay.widgetPaint
import com.saeedkolivand.metastream.overlay.widgets.nowplaying.copy
import com.saeedkolivand.metastream.platforms.Spotify
import kotlin.math.ceil
import kotlin.math.min
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val MEASURE_WIDTH = 8192
private const val TICK_MS = 1000L

/** The line of [template] to show at [nowMs] when rotating: one per [seconds], blank lines skipped. */
fun rotatingLine(template: String, seconds: Int, nowMs: Long): String {
    val lines = template.split('\n').filter { it.isNotBlank() }
    if (lines.isEmpty()) return template
    return lines[((nowMs / 1000) / seconds.coerceAtLeast(1) % lines.size).toInt()]
}

/**
 * In-app text (shadow, optional rounded background) at [scale] output px per canvas px of font size. Null for blank text.
 * The same function sizes the layer for the editor, so the box and the picture always agree.
 */
fun inAppTextBitmap(style: TextStyle, scale: Float): Bitmap? {
    if (style.text.isBlank()) return null
    val px = style.size * scale
    val pad = if (style.background) px * 0.3f else 0f
    val paint = widgetPaint(style.face, if (style.bold) 700 else 400, px, style.color, if (style.shadow) px * 0.06f else 0f)
    val text = InlineIcons.spans(style.text)
    val wide = textLayout(text, paint, MEASURE_WIDTH)
    val layout = textLayout(text, paint, ceil(wide.widest()).toInt() + 1)
    val bmp = newBitmap(layout.width + 2 * pad, layout.height + 2 * pad)
    val c = Canvas(bmp)
    if (style.background) {
        c.drawRoundRect(
            RectF(0f, 0f, bmp.width.toFloat(), bmp.height.toFloat()),
            pad,
            pad,
            fillPaint(style.backgroundColor)
        )
    }
    c.drawLayout(layout, pad, pad)
    return bmp
}

/**
 * Text with {tokens}: re-resolved once a second, redrawn and re-placed only when the string changes. In-app layers re-anchor
 * from their new natural size so a growing "9:59" -> "10:00" stays put.
 */
fun liveTextWidget(l: Layer, box: Box, outW: Int, outH: Int, scope: CoroutineScope): WidgetBuild? {
    val template = l.data["text"].orEmpty()
    if (template.isBlank()) return null
    val layout = l.layout
    // Imported OBS text has no in-app shadow; its scale is fixed from the box the engine placed for the first string.
    val style = TextStyle.from(l.data).let { if (layout == null) it.copy(shadow = false) else it }
    fun current() = WidgetVariables.resolve(
        if (style.rotate) rotatingLine(template, style.rotateSeconds, System.currentTimeMillis()) else template
    )
    val first = current()
    val scale = if (layout != null) {
        layout.scale * min(outW, outH) / 1080f
    } else {
        box.h / (inAppTextBitmap(style.copy(text = first), 1f)?.height ?: return null)
    }
    val filter = ImageFilterRender()
    fun show(text: String) {
        // ponytail: the replaced bitmap is left to GC; RootEncoder's GL thread may still be uploading it.
        val bmp = inAppTextBitmap(style.copy(text = text), scale) ?: blankBitmap()
        val b = if (layout != null) {
            widgetBox(layout, bmp.width / scale, bmp.height / scale, outW.toFloat(), outH.toFloat())
        } else {
            Box(box.x, box.y, bmp.width.toFloat(), bmp.height.toFloat())
        }
        filter.placeIn(b, outW, outH, l.rotation)
        filter.setImage(bmp)
    }
    show(first)
    val job = scope.launch {
        val location = WidgetVariables.needsLocation(template)
        if (location) WidgetLocation.retain()
        val spotify = WidgetVariables.needsSpotify(template)
        if (spotify) Spotify.retain()
        try {
            var shown = first
            while (isActive) {
                delay(thermalDelay(TICK_MS))
                val now = current()
                if (now != shown) {
                    shown = now
                    show(now)
                }
            }
        } finally {
            if (location) WidgetLocation.release()
            if (spotify) Spotify.release()
        }
    }
    return WidgetBuild(filter, job)
}
