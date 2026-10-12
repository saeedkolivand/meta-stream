package com.saeedkolivand.metastream.overlay

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import com.saeedkolivand.metastream.chat.Kind
import kotlin.math.cos
import kotlin.math.sin

// Flat vector glyphs drawn with Paths: no icon font, so nothing depends on a glyph being in the typeface.
private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
private const val WHITE = -1

/** Event colours shared by chat pills, the event list and alert icons. */
internal fun eventColor(k: Kind): Int = when (k) {
    Kind.Follow -> 0xFFFF2D55.toInt()
    Kind.Subscribe -> 0xFFAF52DE.toInt()
    Kind.Tip -> 0xFF34C759.toInt()
    Kind.Cheer -> 0xFFFF9500.toInt()
    Kind.Raid -> 0xFF0A84FF.toInt()
    Kind.Message -> WHITE
}

/** Brand accents, not UI tints: on video the real brand colours read instantly. */
internal fun brandColor(platform: String): Int = when (platform) {
    "twitch" -> 0xFF9146FF.toInt()
    "youtube" -> 0xFFFF0033.toInt()
    else -> 0xFF53FC18.toInt()
}

private fun badgeColor(role: String): Int = when (role) {
    "broadcaster" -> 0xFFFF3B30.toInt()
    "staff" -> 0xFF8E8E93.toInt()
    "moderator" -> 0xFF34C759.toInt()
    "vip" -> 0xFFFF5FA2.toInt()
    "founder" -> 0xFFFFC107.toInt()
    "subscriber" -> 0xFF9146FF.toInt()
    "verified" -> 0xFF3B9CFF.toInt()
    else -> 0xFFFF9500.toInt()
}

private fun polygon(cx: Float, cy: Float, r: Float, n: Int, startDeg: Float) = Path().apply {
    for (i in 0 until n) {
        val a = Math.toRadians((startDeg + 360.0 * i / n))
        val x = cx + r * cos(a).toFloat()
        val y = cy + r * sin(a).toFloat()
        if (i == 0) moveTo(x, y) else lineTo(x, y)
    }
    close()
}

private fun star(cx: Float, cy: Float, r: Float, points: Int, inner: Float) = Path().apply {
    for (i in 0 until points * 2) {
        val a = Math.toRadians(-90.0 + 180.0 * i / points)
        val rr = if (i % 2 == 0) r else r * inner
        val x = cx + rr * cos(a).toFloat()
        val y = cy + rr * sin(a).toFloat()
        if (i == 0) moveTo(x, y) else lineTo(x, y)
    }
    close()
}

private fun heart(cx: Float, cy: Float, r: Float) = Path().apply {
    moveTo(cx, cy + r * 0.9f)
    cubicTo(cx - r * 1.5f, cy - r * 0.2f, cx - r * 0.5f, cy - r * 1.1f, cx, cy - r * 0.35f)
    cubicTo(cx + r * 0.5f, cy - r * 1.1f, cx + r * 1.5f, cy - r * 0.2f, cx, cy + r * 0.9f)
    close()
}

private fun Canvas.fill(path: Path, color: Int) {
    paint.style = Paint.Style.FILL
    paint.color = color
    drawPath(path, paint)
}

private fun Canvas.check(cx: Float, cy: Float, r: Float, color: Int) {
    paint.style = Paint.Style.STROKE
    paint.color = color
    paint.strokeWidth = r * 0.28f
    paint.strokeCap = Paint.Cap.ROUND
    paint.strokeJoin = Paint.Join.ROUND
    drawPath(
        Path().apply {
            moveTo(cx - r * 0.45f, cy)
            lineTo(cx - r * 0.1f, cy + r * 0.35f)
            lineTo(cx + r * 0.5f, cy - r * 0.35f)
        },
        paint
    )
}

/** Role badge as a small tinted icon, no pill behind it. */
internal fun Canvas.badgeIcon(role: String, cx: Float, cy: Float, r: Float) {
    val color = badgeColor(role)
    when (role) {
        "founder", "subscriber" -> fill(star(cx, cy, r * 1.15f, 5, 0.45f), color)
        "vip" -> fill(polygon(cx, cy, r * 1.1f, 4, 0f), color)
        "staff" -> fill(polygon(cx, cy, r, 6, 0f), color)
        "moderator" -> fill(
            Path().apply {
                moveTo(cx - r * 0.8f, cy - r * 0.8f)
                lineTo(cx + r * 0.8f, cy - r * 0.8f)
                lineTo(cx + r * 0.8f, cy + r * 0.1f)
                quadTo(cx + r * 0.8f, cy + r * 0.9f, cx, cy + r * 1.1f)
                quadTo(cx - r * 0.8f, cy + r * 0.9f, cx - r * 0.8f, cy + r * 0.1f)
                close()
            },
            color
        )
        "broadcaster" -> {
            fill(Path().apply { addCircle(cx, cy, r, Path.Direction.CW) }, color)
            fill(Path().apply { addCircle(cx, cy, r * 0.4f, Path.Direction.CW) }, WHITE)
        }
        "verified" -> {
            fill(Path().apply { addCircle(cx, cy, r, Path.Direction.CW) }, color)
            check(cx, cy, r, WHITE)
        }
        else -> fill(polygon(cx, cy, r, 6, 30f), color)
    }
}

/** Glyph per event kind, [r] is the half-size; [color] is white on a pill and the event colour on a dark row. */
internal fun Canvas.kindIcon(k: Kind, cx: Float, cy: Float, r: Float, color: Int) {
    when (k) {
        Kind.Follow -> fill(heart(cx, cy, r), color)
        Kind.Subscribe -> fill(star(cx, cy, r * 1.1f, 5, 0.45f), color)
        Kind.Cheer -> fill(star(cx, cy, r * 1.15f, 4, 0.3f), color)
        Kind.Tip -> {
            paint.style = Paint.Style.STROKE
            paint.color = color
            paint.strokeWidth = r * 0.22f
            drawCircle(cx, cy, r * 0.9f, paint)
            paint.style = Paint.Style.FILL
            paint.textAlign = Paint.Align.CENTER
            paint.textSize = r * 1.3f
            paint.isFakeBoldText = true
            drawText("$", cx, cy + r * 0.45f, paint)
            paint.isFakeBoldText = false
            paint.textAlign = Paint.Align.LEFT
        }
        Kind.Raid -> {
            fill(Path().apply { addCircle(cx, cy - r * 0.35f, r * 0.38f, Path.Direction.CW) }, color)
            fill(Path().apply { addCircle(cx - r * 0.75f, cy - r * 0.15f, r * 0.3f, Path.Direction.CW) }, color)
            fill(Path().apply { addCircle(cx + r * 0.75f, cy - r * 0.15f, r * 0.3f, Path.Direction.CW) }, color)
            paint.style = Paint.Style.FILL
            paint.color = color
            drawRoundRect(RectF(cx - r * 0.55f, cy + r * 0.1f, cx + r * 0.55f, cy + r * 0.9f), r * 0.4f, r * 0.4f, paint)
        }
        Kind.Message -> {
            paint.style = Paint.Style.FILL
            paint.color = color
            drawRoundRect(RectF(cx - r, cy - r * 0.8f, cx + r, cy + r * 0.6f), r * 0.4f, r * 0.4f, paint)
        }
    }
}
