package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import com.pedro.encoder.input.gl.render.filters.`object`.ImageFilterRender
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.Kind
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val QUEUE_CAP = 20
private const val STEP_MS = 80L
private const val GAP_MS = 300L

private fun alertLabel(e: ChatEvent) = when (e.kind) {
    Kind.Follow -> "NEW FOLLOWER"
    Kind.Subscribe -> "NEW SUBSCRIBER"
    Kind.Tip -> "TIPPED $" + String.format(Locale.US, "%.2f", e.amountCents / 100.0)
    Kind.Cheer -> "CHEERED ${e.count} BITS"
    Kind.Raid -> "RAID · ${e.count} VIEWERS"
    Kind.Message -> ""
}

/** The 900x240 banner: dark rounded card, accent outline, kind icon in an accent circle, label / name / message. */
internal fun renderAlert(e: ChatEvent, style: AlertStyle, scale: Float): Bitmap? {
    if (e.kind == Kind.Message) return null
    val s = scale
    val bmp = newBitmap(900 * s, 240 * s)
    val c = Canvas(bmp)
    val card = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xC7000000.toInt() }
    val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = style.accentColor
        this.style = Paint.Style.STROKE
        strokeWidth = 4 * s
    }
    val r = RectF(2 * s, 2 * s, 898 * s, 238 * s)
    c.drawRoundRect(r, 30 * s, 30 * s, card)
    c.drawRoundRect(r, 30 * s, 30 * s, ring)
    val cx = (36 + 59) * s
    c.drawCircle(cx, 120 * s, 59 * s, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = style.accentColor })
    c.kindIcon(e.kind, cx, 120 * s, 28 * s, Color.WHITE)
    val x = (36 + 118 + 28) * s
    val w = (900 - 36) * s - x
    val size = style.fontSize * s
    val label = textLayout(alertLabel(e), widgetPaint(style.face, 700, size * 0.5f, style.accentColor), w.toInt(), maxLines = 1)
    // iOS shrinks a long name down to half size before truncating; same here, in two steps.
    var namePaint = widgetPaint(style.face, 700, size, style.textColor)
    if (namePaint.measureText(e.user) > w) namePaint = widgetPaint(style.face, 700, size * 0.75f, style.textColor)
    if (namePaint.measureText(e.user) > w) namePaint = widgetPaint(style.face, 700, size * 0.5f, style.textColor)
    val name = textLayout(e.user, namePaint, w.toInt(), maxLines = 1)
    val msg = if (e.text.isEmpty()) {
        null
    } else {
        textLayout(
            e.text,
            widgetPaint(style.face, 400, size * 0.55f, style.textColor),
            w.toInt(),
            maxLines = 2
        )
    }
    val gap = 4 * s
    val total = label.height + gap + name.height + if (msg != null) gap + msg.height else 0f
    var y = (240 * s - total) / 2
    c.drawLayout(label, x, y)
    y += label.height + gap
    c.drawLayout(name, x, y)
    msg?.let { c.drawLayout(it, x, y + name.height + gap) }
    return bmp
}

/**
 * Queues follow/sub/raid/tip/cheer events and shows each in turn. Starts from the newest id so a scene switch never replays
 * old follows. One render per alert; the fade is the filter's own alpha, so no bitmap work happens during it.
 */
internal fun alertWidget(l: Layer, box: Box, outW: Int, outH: Int, scope: CoroutineScope): WidgetBuild? {
    val style = AlertStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val scale = box.w / 900f
    val filter = ImageFilterRender()
    filter.placeIn(box, outW, outH, l.rotation)
    filter.setImage(blankBitmap())
    filter.alpha = 0f
    val job = scope.launch {
        var seen = ChatFeed.chat.value.lastOrNull()?.id ?: 0L
        val queue = ArrayDeque<ChatEvent>()
        while (isActive) {
            val fresh = ChatFeed.chat.value.filter { it.id > seen }
            if (fresh.isNotEmpty()) seen = fresh.last().id
            queue += fresh.filter { style.shows(it.kind) }
            while (queue.size > QUEUE_CAP) queue.removeFirst() // a raid train shouldn't queue minutes of banners
            val next = queue.removeFirstOrNull()
            if (next == null) {
                ChatFeed.chat.first { (it.lastOrNull()?.id ?: 0L) > seen }
                continue
            }
            val bmp = renderAlert(next, style, scale) ?: continue
            filter.setImage(bmp)
            for (a in listOf(0.33f, 0.66f, 1f)) {
                filter.alpha = a
                delay(thermalDelay(STEP_MS))
            }
            delay(style.holdSeconds * 1000L)
            for (a in listOf(0.66f, 0.33f, 0f)) {
                filter.alpha = a
                delay(thermalDelay(STEP_MS))
            }
            filter.setImage(blankBitmap())
            delay(GAP_MS)
        }
    }
    return WidgetBuild(filter, job)
}
