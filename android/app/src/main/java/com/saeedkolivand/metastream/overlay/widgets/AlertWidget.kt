package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.RectF
import com.pedro.encoder.input.gl.render.filters.`object`.ImageFilterRender
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.Kind
import com.saeedkolivand.metastream.speech.offensive
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val QUEUE_CAP = 20
private const val FRAME_MS = 42L // ponytail: ~24 fps, only while something moves
private const val GAP_MS = 300L
private const val BOX_W = 900f
private const val BOX_H = 240f
private const val MAX_W = 860f
private const val WHITE_74 = 0xBDFFFFFF.toInt()
private const val TEXT_GAP = 24f

/** One alert laid out once, in 900x240 box units; [draw] paints any frame of its animation. */
private class AlertArt(val e: ChatEvent, style: AlertStyle) {
    private val big = alertIsBig(e)
    private val h = if (big) 154f else 124f
    private val icon = if (big) 120f else 84f
    private val inset = (h - icon) / 2
    private val color = alertColor(e, style.accentColor)
    private val size = style.fontSize
    private val amountText = alertAmount(e)
    private val amountPaint = widgetPaint(style.face, 700, size * (if (big) 1.8f else 1.3f), color).apply { fontFeatureSettings = "tnum" }
    private val amountW = if (amountText.isEmpty()) 0f else amountPaint.measureText(amountText)
    private val labelPaint = widgetPaint(style.face, 700, size * 0.45f, WHITE_74).apply { letterSpacing = 0.12f }
    private val namePaint = widgetPaint(style.face, 700, size, Color.WHITE)
    private val msgPaint = widgetPaint(style.face, 400, size * 0.55f, WHITE_74)
    private val label = alertLabel(e)
    private val fixed = inset + icon + TEXT_GAP + (if (amountW > 0) TEXT_GAP + amountW else 0f) + inset + 14f
    private val wanted = maxOf(
        labelPaint.measureText(label),
        namePaint.measureText(e.user),
        if (e.text.isEmpty()) 0f else msgPaint.measureText(e.text)
    ) + 2f
    private val textW = wanted.coerceAtMost(MAX_W - fixed)
    private val w = fixed + textW
    private val labelL = textLayout(label, labelPaint, textW.toInt(), maxLines = 1)
    private val nameL = textLayout(e.user, namePaint, textW.toInt(), maxLines = 1)
    private val msgL = if (e.text.isEmpty()) null else textLayout(e.text, msgPaint, textW.toInt(), maxLines = 1)
    private val gap = 4f
    private val textH = labelL.height + gap + nameL.height + (msgL?.let { gap + it.height } ?: 0f)
    private val bg = fillPaint(0xFF0D0D10.toInt())
    private val dot = fillPaint(color)

    fun draw(f: AlertFrame, scale: Float): Bitmap {
        val bmp = newBitmap(BOX_W * scale, BOX_H * scale)
        val c = Canvas(bmp)
        c.scale(scale, scale)
        val top = -1.5f * h * (1 - f.drop) - 1.5f * h * f.away
        val cw = (h + (w - h) * f.open).coerceIn(h, BOX_W)
        val left = (BOX_W - cw) / 2
        val cap = RectF(left, top, left + cw, top + h)
        c.withOpacity(RectF(0f, -BOX_H, BOX_W, BOX_H), f.alpha) {
            c.drawRoundRect(cap, h / 2, h / 2, bg)
            if (big && f.flash > 0f) c.drawRoundRect(cap, h / 2, h / 2, fillPaint(withAlpha(color, f.flash)))
            if (f.contentAlpha > 0f) {
                c.save()
                c.clipPath(Path().apply { addRoundRect(cap, h / 2, h / 2, Path.Direction.CW) })
                c.withOpacity(cap, f.contentAlpha) { content(c, (BOX_W - w) / 2, top + f.rise, f.amount) }
                c.restore()
            }
        }
        return bmp
    }

    // The capsule stays left-anchored; only each text run flows RTL.
    private fun content(c: Canvas, left: Float, top: Float, amount: Float) {
        val cy = top + h / 2
        val cx = left + inset + icon / 2
        c.drawCircle(cx, cy, icon / 2, dot)
        c.kindIcon(e.kind, cx, cy, icon * 0.24f, if (e.kind == Kind.Follow) 0xFF111111.toInt() else Color.WHITE)
        val x = left + inset + icon + TEXT_GAP
        var y = cy - textH / 2
        c.drawLayout(labelL, x, y)
        y += labelL.height + gap
        c.drawLayout(nameL, x, y)
        msgL?.let { c.drawLayout(it, x, y + nameL.height + gap) }
        if (amountW > 0) {
            val fm = amountPaint.fontMetrics
            c.drawText(alertAmount(e, amount), left + w - inset - 14f - amountW, cy - (fm.ascent + fm.descent) / 2, amountPaint)
        }
    }
}

/** A still of the finished banner (held state), for the in-app preview. */
internal fun renderAlert(e: ChatEvent, style: AlertStyle, scale: Float): Bitmap? {
    if (e.kind == Kind.Message) return null
    return AlertArt(e, style).draw(alertFrame(ALERT_MOTION_END, style.holdSeconds.toFloat()), scale)
}

/**
 * Queues follow/sub/raid/tip/cheer events and shows each in turn. Starts from the newest id so a scene switch never replays
 * old follows. Each frame is a pure function of elapsed time; it redraws at ~24 fps only while moving, never during the hold.
 */
internal fun alertWidget(l: Layer, box: Box, outW: Int, outH: Int, scope: CoroutineScope): WidgetBuild? {
    val style = AlertStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val scale = box.w / BOX_W
    val hold = style.holdSeconds.toFloat()
    val exitAt = alertExitAt(hold)
    val filter = ImageFilterRender()
    filter.placeIn(box, outW, outH, l.rotation)
    filter.setImage(blankBitmap())
    val job = scope.launch {
        var seen = ChatFeed.chat.value.lastOrNull()?.id ?: 0L
        val queue = ArrayDeque<ChatEvent>()
        while (isActive) {
            val fresh = ChatFeed.chat.value.filter { it.id > seen }
            if (fresh.isNotEmpty()) seen = fresh.last().id
            queue += fresh.filter { style.shows(it.kind) && !it.offensive }
            while (queue.size > QUEUE_CAP) queue.removeFirst() // a raid train shouldn't queue minutes of banners
            val next = queue.removeFirstOrNull()
            if (next == null) {
                ChatFeed.chat.first { (it.lastOrNull()?.id ?: 0L) > seen }
                continue
            }
            val art = AlertArt(next, style)
            val start = System.nanoTime()
            while (isActive) {
                val t = (System.nanoTime() - start) / 1e9f
                val f = alertFrame(t, hold)
                if (f.done) break
                val moving = t < ALERT_MOTION_END || t >= exitAt
                // ponytail: the replaced bitmap is left to GC; RootEncoder's GL thread may still be uploading it.
                if (moving) filter.setImage(art.draw(f, scale))
                delay(if (moving) thermalDelay(FRAME_MS) else ((exitAt - t) * 1000).toLong().coerceAtLeast(1L))
            }
            filter.setImage(blankBitmap())
            delay(GAP_MS)
        }
    }
    return WidgetBuild(filter, job)
}
