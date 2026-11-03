package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.RectF
import android.text.TextPaint
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import kotlin.math.ceil

internal const val BOX_W = 900f
internal const val BOX_H = 240f
internal const val ALERT_TRAVEL = 1.5f
private const val MAX_W = 860f
private const val WHITE_74 = 0xBDFFFFFF.toInt()
private const val TEXT_GAP = 24f
private const val INSET_RIGHT = 14f
private const val GLYPHS = "0123456789$.,-"

/** One alert laid out once, in 900x240 box units. Nothing here depends on a frame. */
private class AlertArt(val e: ChatEvent, style: AlertStyle) {
    val big = alertIsBig(e)
    val h = if (big) 154f else 124f
    val icon = if (big) 120f else 84f
    val inset = (h - icon) / 2
    val color = alertColor(e, style.accentColor)
    private val size = style.fontSize
    private val amountText = alertAmount(e)
    val amountPaint = widgetPaint(style.face, 700, size * (if (big) 1.8f else 1.3f), color).apply { fontFeatureSettings = "tnum" }
    val amountW = if (amountText.isEmpty()) 0f else amountPaint.measureText(amountText)
    private val labelPaint = widgetPaint(style.face, 700, size * 0.45f, WHITE_74).apply { letterSpacing = 0.12f }
    private val namePaint = widgetPaint(style.face, 700, size, Color.WHITE)
    private val msgPaint = widgetPaint(style.face, 400, size * 0.55f, WHITE_74)
    private val label = alertLabel(e)
    private val fixed = inset + icon + TEXT_GAP + (if (amountW > 0) TEXT_GAP + amountW else 0f) + inset + INSET_RIGHT
    private val wanted = maxOf(
        labelPaint.measureText(label),
        namePaint.measureText(e.user),
        if (e.text.isEmpty()) 0f else msgPaint.measureText(e.text)
    ) + 2f
    private val textW = wanted.coerceAtMost(MAX_W - fixed)
    val w = fixed + textW
    private val labelL = textLayout(label, labelPaint, textW.toInt(), maxLines = 1)
    private val nameL = textLayout(e.user, namePaint, textW.toInt(), maxLines = 1)
    private val msgL = if (e.text.isEmpty()) null else textLayout(e.text, msgPaint, textW.toInt(), maxLines = 1)
    private val gap = 4f
    private val textH = labelL.height + gap + nameL.height + (msgL?.let { gap + it.height } ?: 0f)
    private val bg = fillPaint(0xFF0D0D10.toInt())
    private val dot = fillPaint(color)

    /** [amountStart] is where the amount's pen begins, relative to the content's left edge. */
    val amountStart get() = w - inset - INSET_RIGHT - amountW

    fun content(scale: Float): Bitmap {
        val bmp = newBitmap(w * scale, h * scale)
        val c = Canvas(bmp)
        c.scale(scale, scale)
        val cy = h / 2
        val cx = inset + icon / 2
        c.drawCircle(cx, cy, icon / 2, dot)
        c.kindIcon(e.kind, cx, cy, icon * 0.24f, if (e.kind == Kind.Follow) 0xFF111111.toInt() else Color.WHITE)
        val x = inset + icon + TEXT_GAP
        var y = cy - textH / 2
        c.drawLayout(labelL, x, y)
        y += labelL.height + gap
        c.drawLayout(nameL, x, y)
        msgL?.let { c.drawLayout(it, x, y + nameL.height + gap) }
        return bmp
    }

    /** The finished banner, for the in-app preview (the live path draws the same layout on the GPU). */
    fun draw(f: AlertFrame, scale: Float): Bitmap {
        val bmp = newBitmap(BOX_W * scale, BOX_H * scale)
        val c = Canvas(bmp)
        c.scale(scale, scale)
        val cap = capsule(f)
        c.withOpacity(RectF(0f, -BOX_H, BOX_W, BOX_H), f.alpha) {
            c.drawRoundRect(cap, h / 2, h / 2, bg)
            if (big && f.flash > 0f) c.drawRoundRect(cap, h / 2, h / 2, fillPaint(withAlpha(color, f.flash)))
            if (f.contentAlpha > 0f) {
                c.save()
                c.clipPath(Path().apply { addRoundRect(cap, h / 2, h / 2, Path.Direction.CW) })
                c.withOpacity(cap, f.contentAlpha) {
                    val top = cap.top + f.rise
                    c.drawBitmap(content(1f), (BOX_W - w) / 2, top, null)
                    drawAmount(c, top, f.amount)
                }
                c.restore()
            }
        }
        return bmp
    }

    private fun drawAmount(c: Canvas, top: Float, progress: Float) {
        if (amountW <= 0f) return
        val fm = amountPaint.fontMetrics
        val base = top + h / 2 - (fm.ascent + fm.descent) / 2
        c.drawText(alertAmount(e, progress), (BOX_W - w) / 2 + amountStart, base, amountPaint)
    }

    fun capsule(f: AlertFrame): RectF {
        val top = -ALERT_TRAVEL * h * (1 - f.drop) - ALERT_TRAVEL * h * f.away
        val cw = (h + (w - h) * f.open).coerceIn(h, BOX_W)
        val left = (BOX_W - cw) / 2
        return RectF(left, top, left + cw, top + h)
    }

    fun glyphs(scale: Float): Map<Char, Glyph> = GLYPHS.associateWith { Glyph.of(it.toString(), amountPaint, scale) }

    fun suffix(scale: Float, suffix: String): Glyph? = if (suffix.isEmpty()) null else Glyph.of(suffix, amountPaint, scale)
}

/** A rasterised text run and where its ink sits above the baseline, in natural units. */
private class Glyph(val bmp: Bitmap, val w: Float, val h: Float, val top: Float) {
    companion object {
        fun of(text: String, paint: TextPaint, scale: Float): Glyph {
            val p = TextPaint(paint).apply { textSize *= scale }
            val fm = p.fontMetrics
            val w = ceil(p.measureText(text)).toInt().coerceAtLeast(1)
            val h = ceil(fm.bottom - fm.top).toInt().coerceAtLeast(1) // top/bottom, not ascent: tall glyphs must not clip
            val bmp = newBitmap(w.toFloat(), h.toFloat())
            Canvas(bmp).drawText(text, 0f, -fm.top, p)
            return Glyph(bmp, w / scale, h / scale, fm.top / scale)
        }
    }
}

/** A still of the finished banner (held state), for the in-app preview. */
internal fun renderAlert(e: ChatEvent, style: AlertStyle, scale: Float): Bitmap? {
    if (e.kind == Kind.Message) return null
    return AlertArt(e, style).draw(alertFrame(ALERT_MOTION_END, style.holdSeconds.toFloat()), scale)
}

/**
 * Bakes the alert's bitmaps once and builds a [GpuScene] per phase: the count-up digits are individual quads over a static
 * content bitmap, so the per-frame CPU work is nil and only moving frames are pushed to the GL thread.
 */
internal class AlertGpu(private val e: ChatEvent, style: AlertStyle, private val scale: Float, private val hold: Float) {
    private val art = AlertArt(e, style)
    private val content = art.content(scale)
    private val glyphs = art.glyphs(scale)
    private val suffix = art.suffix(scale, alertAmountParts(e).suffix)

    private val held = ALERT_MOTION_END + 0.01f

    fun scene(from: Long, moving: Boolean): GpuScene =
        GpuScene(BOX_W, BOX_H, moving, from) { t -> items(e, alertFrame(if (moving) t else held, hold)) }

    private fun items(e: ChatEvent, f: AlertFrame): List<Item> {
        val out = ArrayList<Item>(8)
        val cap = art.capsule(f)
        out += Item(RectF(cap), color = 0xFF0D0D10.toInt(), alpha = f.alpha, radius = art.h / 2)
        if (art.big && f.flash > 0f) {
            out += Item(RectF(cap), color = art.color, alpha = f.alpha * f.flash, radius = art.h / 2)
        }
        if (f.contentAlpha > 0f) {
            val alpha = f.alpha * f.contentAlpha
            val left = (BOX_W - art.w) / 2
            val top = cap.top + f.rise
            out += Item(RectF(left, top, left + art.w, top + art.h), content, alpha = alpha, clip = RectF(cap), clipRadius = art.h / 2)
            amountItems(e, f, left, top, alpha, cap, out)
        }
        return out
    }

    private fun amountItems(e: ChatEvent, f: AlertFrame, left: Float, top: Float, alpha: Float, cap: RectF, out: MutableList<Item>) {
        val parts = alertAmountParts(e, f.amount)
        if (parts.number.isEmpty()) return
        val base = top + art.h / 2 - (art.amountPaint.ascent() + art.amountPaint.descent()) / 2
        var pen = 0f
        for (ch in parts.number) {
            val g = glyphs[ch] ?: continue
            out += glyph(g, left + art.amountStart + pen, base, alpha, cap)
            pen += g.w
        }
        suffix?.let { out += glyph(it, left + art.amountStart + pen, base, alpha, cap) }
    }

    private fun glyph(g: Glyph, x: Float, base: Float, alpha: Float, cap: RectF): Item {
        val y = base + g.top
        return Item(RectF(x, y, x + g.w, y + g.h), g.bmp, alpha = alpha, clip = RectF(cap), clipRadius = art.h / 2)
    }
}

internal fun alertGpu(e: ChatEvent, style: AlertStyle, scale: Float, hold: Float) = AlertGpu(e, style, scale, hold)
