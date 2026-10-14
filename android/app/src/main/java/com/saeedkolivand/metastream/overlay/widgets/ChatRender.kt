package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Shader
import androidx.core.graphics.ColorUtils
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.Kind
import com.saeedkolivand.metastream.speech.eventSummary
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.pow

private const val ENTER_MS = 320f
private const val RAMP_MS = 2000f
private const val FADE_TOP = 0.18f

/** Events that survive the filters and the fade, oldest first, at most maxMessages. */
internal fun chatRows(events: List<ChatEvent>, style: ChatStyle, now: Long): List<ChatEvent> {
    val bots = style.botNames.split(',').map { it.trim().lowercase() }.toSet()
    val fadeMs = style.fadeSeconds * 1000L
    return events.filter { e ->
        when {
            fadeMs > 0 && now - e.time > fadeMs -> false
            e.kind != Kind.Message -> style.showEvents
            style.hideCommands && e.text.startsWith("!") -> false
            else -> !(style.hideBots && e.user.lowercase() in bots)
        }
    }.takeLast(style.maxMessages)
}

/** 1 until the last 2 s before the fade deadline, then ramps to 0. */
internal fun chatOpacity(e: ChatEvent, style: ChatStyle, now: Long): Float {
    if (style.fadeSeconds <= 0) return 1f
    return ((style.fadeSeconds * 1000f - (now - e.time)) / RAMP_MS).coerceIn(0f, 1f)
}

/** Entry motion: 0 -> 1 over the first 320 ms of a message's life, ease-out cubic. */
internal fun chatAppear(e: ChatEvent, now: Long): Float {
    val t = ((now - e.time) / ENTER_MS).coerceIn(0f, 1f)
    return 1f - (1f - t).pow(3)
}

/** A laid-out row: [draw] paints it with its top-left at x, y. */
private class Row(val w: Float, val h: Float, val draw: (Canvas, Float, Float) -> Unit)

/** Names are read on video: lighten dark colours until they pass a minimum luminance. */
private fun readable(hex: String?, fallback: Int): Int {
    val c = hex?.removePrefix("#")?.takeIf { it.length == 6 }?.toIntOrNull(16)?.let { it or (0xFF shl 24) } ?: return fallback
    var out = c
    var t = 0f
    while (ColorUtils.calculateLuminance(out) < 0.25 && t < 1f) {
        t += 0.1f
        out = ColorUtils.blendARGB(c, Color.WHITE, t)
    }
    return out
}

private fun highlighted(e: ChatEvent, style: ChatStyle, channel: String): Boolean {
    val t = e.text.lowercase()
    val words = style.highlight.split(',').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
    val me = channel.split(',').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
    return (words + me).any { t.contains(it) }
}

/**
 * Flat, minimal card: who on top (platform chip, icon badges, name), what they said underneath. One solid fill, no
 * gradients or borders; with the background off the text sits flush left on the video. The layout never mirrors; only
 * the message text runs RTL.
 */
private fun messageCard(e: ChatEvent, st: ChatStyle, size: Float, avail: Float, s: Float, channel: String, animMs: Long): Row {
    val padL = if (st.background) size * 0.5f else 0f
    val padR = if (st.background) size * 0.55f else 0f
    val padV = size * if (st.background) 0.36f else 0.15f
    val gap = size * 0.12f
    val iconD = size * 0.62f
    val iconGap = size * 0.22f
    val inner = max(1f, avail - padL - padR)
    val textShadow = if (!st.background && st.shadow) size * 0.12f else 0f
    val (letter, letterColor) = brandLetter(e.platform)
    val chip = if (st.platform) textLayout(letter, widgetPaint(st.face, 800, size * 0.55f, letterColor), size.toInt()) else null
    val chipPad = size * 0.16f
    val chipW = chip?.let { it.widest() + 2 * chipPad } ?: 0f
    val chipH = chip?.let { it.height + chipPad } ?: 0f
    val roles = if (st.badges) e.badges.take(3) else emptyList()
    val iconsW = (if (chip != null) chipW + iconGap else 0f) + roles.size * (iconD + iconGap)
    val nameColor = if (st.senderColors) readable(e.color, brandColor(e.platform)) else withAlpha(st.textColor, 0.75f)
    val namePaint = widgetPaint(st.face, 700, size, nameColor, textShadow)
    // Laid out at its own width: a Persian name in a full-width box would right-align away from the badges.
    val nameW = minOf(inner - iconsW, ceil(namePaint.measureText(e.user)) + 1f)
    val name = textLayout(e.user, namePaint, nameW.toInt(), maxLines = 1)
    val msgPaint = widgetPaint(st.face, if (st.bold) 600 else 400, size, st.textColor, textShadow)
    val text = emoteText(e.text, size * 1.3f, animMs)
    val spacing = size * 0.08f
    val wide = textLayout(text, msgPaint, inner.toInt(), spacing = spacing)
    val blockW = max(iconsW + name.widest(), wide.widest())
    // Re-wrap at the shrunk width so an RTL line sits against the right edge of its own block, not of the whole card.
    val msg = textLayout(text, msgPaint, ceil(blockW).toInt(), spacing = spacing)
    val headerH = max(max(name.height.toFloat(), iconD), chipH)
    val w = padL + blockW + padR
    val h = padV * 2 + headerH + gap + msg.height
    val fill = fillPaint(st.backgroundColor, if (st.shadow) size * 0.35f else 0f)
    val brand = fillPaint(brandColor(e.platform))
    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2 * s
        color = st.highlightColor
    }
    val hot = highlighted(e, st, channel)
    return Row(w, h) { c, x, y ->
        val r = RectF(x, y, x + w, y + h)
        val radius = size * 0.55f
        if (st.background) c.drawRoundRect(r, radius, radius, fill)
        val cy = y + padV + headerH / 2
        var hx = x + padL
        if (chip != null) {
            c.drawRoundRect(hx, cy - chipH / 2, hx + chipW, cy + chipH / 2, size * 0.15f, size * 0.15f, brand)
            c.drawLayout(chip, hx + chipPad, cy - chip.height / 2f)
            hx += chipW + iconGap
        }
        for (role in roles) {
            c.badgeIcon(role, hx + iconD / 2, cy, iconD / 2)
            hx += iconD + iconGap
        }
        c.drawLayout(name, hx, cy - name.height / 2f)
        c.drawLayout(msg, x + padL, y + padV + headerH + gap)
        if (hot) {
            r.inset(s, s)
            c.drawRoundRect(r, radius, radius, stroke)
        }
    }
}

/** Follows/subs/tips/raids/cheers: one flat pill in the event's colour, so they pop without shouting. */
private fun eventPill(e: ChatEvent, st: ChatStyle, size: Float, avail: Float): Row {
    val padH = size * 0.55f
    val padV = size * 0.3f
    val iconD = size * 0.8f
    val gap = size * 0.3f
    val text =
        textLayout(
            eventSummary(e),
            widgetPaint(st.face, 700, size * 0.82f, Color.WHITE),
            (avail - 2 * padH - iconD - gap).toInt(),
            maxLines = 2
        )
    val w = 2 * padH + iconD + gap + text.widest()
    val h = 2 * padV + max(text.height.toFloat(), iconD)
    val fill = fillPaint(eventColor(e.kind), if (st.shadow) size * 0.3f else 0f, 0x59)
    return Row(w, h) { c, x, y ->
        c.drawRoundRect(RectF(x, y, x + w, y + h), h / 2, h / 2, fill)
        c.kindIcon(e.kind, x + padH + iconD / 2, y + h / 2, iconD / 2, Color.WHITE)
        c.drawLayout(text, x + padH + iconD + gap, y + (h - text.height) / 2)
    }
}

/** Newest at the bottom, clipped, with the top 18% dissolving into the video; animated emotes show their frame at [animMs]; [burst] skips the entry slide. Null when nothing is drawn. */
internal fun renderChat(
    events: List<ChatEvent>,
    style: ChatStyle,
    now: Long,
    scale: Float,
    channel: String,
    animMs: Long = 0,
    burst: Boolean = false
): Bitmap? {
    val rows = chatRows(events, style, now)
    if (rows.isEmpty()) return null
    val size = style.fontSize * scale
    val pad = 8 * scale
    val bmp = newBitmap(style.width * scale, style.height * scale)
    val c = Canvas(bmp)
    val avail = bmp.width - 2 * pad
    var y = bmp.height - pad
    for (e in rows.asReversed()) {
        val isMsg = e.kind == Kind.Message
        val row = if (isMsg) messageCard(e, style, size, avail, scale, channel, animMs) else eventPill(e, style, size, avail)
        y -= row.h
        val appear = if (burst) 1f else chatAppear(e, now)
        val top = y + (1f - appear) * size * 0.7f
        val bounds = RectF(pad - size, top - size, pad + row.w + size, top + row.h + size)
        c.withOpacity(bounds, chatOpacity(e, style, now) * appear) { row.draw(c, pad, top) }
        y -= size * 0.32f
        if (y < 0) break
    }
    // DST_IN keeps the rows' alpha times the mask: transparent at the top, solid from 18% down (CLAMP holds the last stop).
    val mask = Paint().apply {
        shader = LinearGradient(
            0f,
            0f,
            0f,
            bmp.height.toFloat(),
            intArrayOf(Color.TRANSPARENT, Color.BLACK),
            floatArrayOf(0f, FADE_TOP),
            Shader.TileMode.CLAMP
        )
        xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
    }
    c.drawRect(0f, 0f, bmp.width.toFloat(), bmp.height.toFloat(), mask)
    return bmp
}
