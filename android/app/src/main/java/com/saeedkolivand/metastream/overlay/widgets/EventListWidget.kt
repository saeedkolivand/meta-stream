package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.RectF
import com.pedro.encoder.input.gl.render.filters.`object`.ImageFilterRender
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.Kind
import com.saeedkolivand.metastream.speech.eventSummary
import kotlin.math.max
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** Newest first, only the kinds the style shows. */
internal fun eventRows(events: List<ChatEvent>, style: EventListStyle): List<ChatEvent> =
    events.filter { it.kind != Kind.Message && style.shows(it.kind) }.takeLast(style.maxEvents).asReversed()

/** Recent follows/subs/tips/raids, newest on top, each a flat rounded row. Null when there are none. */
internal fun renderEventList(events: List<ChatEvent>, style: EventListStyle, scale: Float): Bitmap? {
    val rows = eventRows(events, style)
    if (rows.isEmpty()) return null
    val bmp = newBitmap(style.width * scale, style.height * scale)
    val c = Canvas(bmp)
    val size = style.fontSize * scale
    val pad = 8 * scale
    val padH = 10 * scale
    val padV = 5 * scale
    val gap = 8 * scale
    val fill = fillPaint(style.backgroundColor)
    var y = pad
    for (e in rows) {
        val tw = bmp.width - 2 * (pad + padH) - size - gap
        val text = textLayout(eventSummary(e), widgetPaint(style.face, 600, size, style.textColor, scale), tw.toInt(), maxLines = 2)
        val h = max(text.height.toFloat(), size) + 2 * padV
        if (style.background) c.drawRoundRect(RectF(pad, y, bmp.width - pad, y + h), 10 * scale, 10 * scale, fill)
        c.kindIcon(e.kind, pad + padH + size / 2, y + h / 2, size / 2, eventColor(e.kind))
        c.drawLayout(text, pad + padH + size + gap, y + (h - text.height) / 2)
        y += h + 6 * scale
        if (y > bmp.height) break
    }
    return bmp
}

/** Redrawn only when the newest relevant event changes; the feed is otherwise never touched. */
internal fun eventListWidget(l: Layer, box: Box, outW: Int, outH: Int, scope: CoroutineScope): WidgetBuild? {
    val style = EventListStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val scale = box.w / style.width
    val filter = ImageFilterRender()
    filter.placeIn(box, outW, outH, l.rotation)
    filter.setImage(renderEventList(ChatFeed.chat.value, style, scale) ?: blankBitmap())
    val job = scope.launch {
        ChatFeed.chat.map { chat -> eventRows(chat, style).map { it.id } }.distinctUntilChanged().collect {
            // ponytail: the replaced bitmap is left to GC; RootEncoder's GL thread may still be uploading it.
            filter.setImage(renderEventList(ChatFeed.chat.value, style, scale) ?: blankBitmap())
        }
    }
    return WidgetBuild(filter, job)
}
