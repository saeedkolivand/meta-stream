package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Shader
import android.text.TextUtils

/** One styled piece of text (iOS GoalRun); sizes and tracking in board points, [mid] = y is the line's centre. */
internal data class GoalRun(
    val text: String,
    val size: Float,
    val weight: Int = 700,
    val face: String = "Manrope",
    val color: Int = 0xFFFFFFFF.toInt(),
    val alpha: Float = 1f,
    val tracking: Float = 0f,
    val mid: Boolean = false
) {
    fun with(other: String) = copy(text = other)

    fun fading(v: Float) = copy(alpha = v)

    fun colored(argb: Int) = copy(color = argb)

    fun tracked(points: Float) = copy(tracking = points)

    fun centred() = copy(mid = true)
}

internal class GoalSize(val w: Float, val h: Float, val asc: Float)

/**
 * One goal widget's rasters at the stream's pixel size ([unit] px per board point): text drawn white once per string and
 * tinted on the GPU, metrics, and the few shapes (wave crest, pin, car, halo, sweep) drawn once and then only moved. Shared by
 * every frame and scene of the widget; the GL thread and the widget task both read it, hence the locks.
 */
internal class GoalPen(val unit: Float) {
    private val texts = HashMap<String, Txt?>()
    private val sizes = HashMap<String, GoalSize>()

    private fun key(r: GoalRun) = "${r.text}|${r.size}|${r.weight}|${r.face}|${r.tracking}"

    private fun paint(r: GoalRun) = widgetPaint(r.face, r.weight, r.size * unit, -1).apply { letterSpacing = r.tracking / r.size }

    @Synchronized
    fun txt(r: GoalRun): Txt? {
        if (texts.size > 96) texts.clear()
        return texts.getOrPut(key(r)) { ink(r.text, r.size * unit, r.weight, -1, r.tracking / r.size, face = r.face) }
    }

    @Synchronized
    fun metrics(r: GoalRun): GoalSize {
        if (sizes.size > 256) sizes.clear()
        return sizes.getOrPut(key(r)) {
            val p = paint(r)
            val fm = p.fontMetrics
            GoalSize(if (r.text.isEmpty()) 0f else p.measureText(r.text) / unit, (fm.bottom - fm.top) / unit, -fm.top / unit)
        }
    }

    fun ellipsize(r: GoalRun, width: Float) = TextUtils.ellipsize(r.text, paint(r), width * unit, TextUtils.TruncateAt.END).toString()

    private fun shape(w: Float, h: Float, draw: Canvas.() -> Unit): Bitmap = newBitmap(w * unit, h * unit).also {
        Canvas(it).apply {
            scale(unit, unit)
            draw()
        }
    }

    /** A soft white disc for glows. */
    val halo: Bitmap by lazy {
        newBitmap(128f, 128f).also {
            val g = RadialGradient(64f, 64f, 64f, intArrayOf(-1, 0xCCFFFFFF.toInt(), 0), floatArrayOf(0f, 0.4f, 1f), Shader.TileMode.CLAMP)
            Canvas(it).drawCircle(64f, 64f, 64f, fillPaint(-1).apply { shader = g })
        }
    }

    /** Clear -> white -> clear, left to right (the hairline's sweep). */
    val sweep: Bitmap by lazy {
        newBitmap(64f, 2f).also {
            val g = LinearGradient(0f, 0f, 64f, 0f, intArrayOf(0, -1, 0), null, Shader.TileMode.CLAMP)
            Canvas(it).drawRect(0f, 0f, 64f, 2f, fillPaint(-1).apply { shader = g })
        }
    }

    /** The liquid board's quadratic crest: 8 periods of 64 points, 512 x 16. */
    val wave: Bitmap by lazy {
        shape(512f, 16f) {
            val p = Path().apply { moveTo(0f, 8f) }
            for (step in 0 until 16) p.quadTo(step * 32f + 16, if (step % 2 == 0) 0f else 16f, step * 32f + 32, 8f)
            p.lineTo(512f, 16f)
            p.lineTo(0f, 16f)
            p.close()
            drawPath(p, fillPaint(-1))
        }
    }

    /** The road's map pin, 12 x 16 (a 22 x 30 board path). */
    val pin: Bitmap by lazy {
        shape(12f, 16f) {
            scale(12f / 22, 16f / 30)
            val p = Path().apply {
                moveTo(11f, 29f)
                cubicTo(11f, 29f, 21f, 18f, 21f, 11f)
                cubicTo(21f, 5.48f, 16.52f, 1f, 11f, 1f)
                cubicTo(5.48f, 1f, 1f, 5.48f, 1f, 11f)
                cubicTo(1f, 18f, 11f, 29f, 11f, 29f)
                close()
            }
            drawPath(p, fillPaint(-1))
        }
    }

    private var carFor = 0
    private var carBmp: Bitmap? = null

    /** The board's car (64 x 36 viewBox at 36 x 20): [accent] shell, dark window, two wheels. */
    @Synchronized
    fun car(accent: Int): Bitmap = carBmp?.takeIf { carFor == accent } ?: shape(36f, 20f) {
        scale(36f / 64, 36f / 64)
        val shell = Path().apply {
            moveTo(6f, 24f)
            lineTo(8f, 15f)
            quadTo(10f, 11f, 15f, 11f)
            lineTo(23f, 11f)
            lineTo(30f, 4f)
            quadTo(32f, 2f, 36f, 2f)
            lineTo(46f, 2f)
            quadTo(50f, 2f, 52f, 6f)
            lineTo(56f, 12f)
            quadTo(62f, 13f, 62f, 19f)
            lineTo(62f, 24f)
            close()
        }
        drawPath(shell, fillPaint(accent))
        val window = Path().apply {
            moveTo(30f, 11f)
            lineTo(35f, 5f)
            lineTo(45f, 5f)
            lineTo(49f, 11f)
            close()
        }
        drawPath(window, fillPaint(withAlpha(GoalDraw.INK, 0.55f)))
        for (wheel in listOf(10f, 42f)) {
            drawCircle(wheel + 7, 26f, 7f, fillPaint(GoalDraw.INK))
            drawCircle(wheel + 7, 26f, 3f, fillPaint(GoalDraw.STEEL))
        }
    }.also {
        carBmp = it
        carFor = accent
    }
}
