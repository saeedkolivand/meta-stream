package com.saeedkolivand.metastream.overlay

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.PowerManager
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.ReplacementSpan
import androidx.core.graphics.ColorUtils
import com.saeedkolivand.metastream.chat.Emotes
import com.saeedkolivand.metastream.chat.Run
import com.saeedkolivand.metastream.chat.tokenize
import com.saeedkolivand.metastream.platforms.Accounts
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Application context for emote loading, location and the thermal check; Accounts is wired first in App.onCreate. */
internal val appContext: Context get() = Accounts.app

/** Doubles a render/poll delay while the phone is hot, same backoff as the browser snapshot loop. */
internal fun thermalDelay(ms: Long): Long = if (thermalHot()) ms * 2 else ms

internal fun thermalHot() = appContext.getSystemService(PowerManager::class.java).currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE

internal fun newBitmap(w: Float, h: Float): Bitmap =
    Bitmap.createBitmap(max(1, w.roundToInt()), max(1, h.roundToInt()), Bitmap.Config.ARGB_8888)

/** What a widget shows when it has nothing to draw: RootEncoder's ImageFilterRender can't take a null bitmap. */
internal fun blankBitmap(): Bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)

internal fun withAlpha(color: Int, a: Float): Int = ColorUtils.setAlphaComponent(color, (Color.alpha(color) * a).roundToInt())

/** [shadowPx] > 0 adds a soft drop shadow under the glyphs (used when the card has no fill to carry it). */
internal fun widgetPaint(face: String, weight: Int, px: Float, color: Int, shadowPx: Float = 0f) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
    typeface = WidgetFonts.typeface(face, weight)
    textSize = px
    this.color = color
    if (shadowPx > 0f) setShadowLayer(shadowPx, 0f, shadowPx / 2, 0xCC000000.toInt())
}

internal fun fillPaint(color: Int, shadowPx: Float = 0f, shadowAlpha: Int = 0x73) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    this.color = color
    if (shadowPx > 0f) setShadowLayer(shadowPx, 0f, shadowPx / 3, shadowAlpha shl 24)
}

/**
 * Bidi comes from FIRSTSTRONG_LTR: a line whose first strong character is Persian/Arabic/Hebrew is an RTL paragraph, so
 * ALIGN_NORMAL puts it against the right edge of its own text block while the surrounding card never mirrors.
 */
internal fun textLayout(
    text: CharSequence,
    paint: TextPaint,
    width: Int,
    maxLines: Int = Int.MAX_VALUE,
    spacing: Float = 0f,
    align: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL
): StaticLayout = StaticLayout.Builder.obtain(text, 0, text.length, paint, max(1, width))
    .setTextDirection(TextDirectionHeuristics.FIRSTSTRONG_LTR)
    .setAlignment(align)
    .setIncludePad(false)
    .setMaxLines(maxLines)
    .setEllipsize(TextUtils.TruncateAt.END)
    .setLineSpacing(spacing, 1f)
    .build()

internal fun StaticLayout.widest(): Float = (0 until lineCount).maxOfOrNull { getLineWidth(it) } ?: 0f

internal fun Canvas.drawLayout(l: Layout, x: Float, y: Float) {
    save()
    translate(x, y)
    l.draw(this)
    restore()
}

/** Runs [draw] at [a] opacity; the offscreen layer is only paid for while a row is actually fading. */
internal fun Canvas.withOpacity(bounds: RectF, a: Float, draw: () -> Unit) {
    val save = if (a < 1f) saveLayerAlpha(bounds, (a * 255).roundToInt()) else save()
    draw()
    restoreToCount(save)
}

private val emotePaint = Paint(Paint.FILTER_BITMAP_FLAG)

/** An emote drawn inline at [h] px tall; with no bitmap yet it takes no room, like iOS dropping it until it loads. */
private class EmoteSpan(private val bmp: Bitmap?, private val h: Float) : ReplacementSpan() {
    private val w get() = bmp?.let { h * it.width / it.height } ?: 0f

    override fun getSize(paint: Paint, text: CharSequence?, start: Int, end: Int, fm: Paint.FontMetricsInt?): Int {
        if (bmp != null && fm != null) {
            fm.ascent = min(fm.ascent, -(h * 0.8f).toInt())
            fm.descent = max(fm.descent, (h * 0.2f).toInt())
            fm.top = fm.ascent
            fm.bottom = fm.descent
        }
        return w.roundToInt()
    }

    override fun draw(canvas: Canvas, text: CharSequence?, start: Int, end: Int, x: Float, top: Int, y: Int, bottom: Int, paint: Paint) {
        bmp ?: return
        canvas.drawBitmap(bmp, null, RectF(x, y - h * 0.8f, x + w, y + h * 0.2f), emotePaint)
    }
}

/** The message as one string so bidi resolves mixed-script lines; emotes are ReplacementSpans of height [emotePx]; [animMs] picks the frame of animated ones. */
internal fun emoteText(text: String, emotePx: Float, animMs: Long = 0): CharSequence {
    val out = SpannableStringBuilder()
    for (run in tokenize(text, Emotes.byName)) {
        when (run) {
            is Run.Text -> out.append(run.text)
            is Run.Emote -> {
                out.append('￼')
                val span = EmoteSpan(EmoteBitmaps.get(run.url, emotePx.roundToInt(), animMs), emotePx)
                out.setSpan(span, out.length - 1, out.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
    }
    return out
}
