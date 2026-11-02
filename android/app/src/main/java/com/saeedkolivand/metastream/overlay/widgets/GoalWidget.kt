package com.saeedkolivand.metastream.overlay

import android.graphics.RectF
import androidx.compose.runtime.snapshotFlow
import com.saeedkolivand.metastream.goal.GoalConfig
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.goal.Money
import com.saeedkolivand.metastream.goal.Rates
import java.math.BigDecimal
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

private const val REACTION_SECONDS = 1.6f
private const val CELEBRATE_MS = 6000L

/**
 * The donation goal on the GPU (iOS GoalArt / GoalPlayer): a still scene while nothing changes; a donation that raises the
 * total plays one moving reaction (the fill surges, the total flips, "+amount" rises), then settles. Reaching the goal shows
 * "Goal reached!" for six seconds. ponytail: four meters (bar, segments, hairline, dots) in one layout, not iOS's nine boards.
 */
internal fun goalWidget(l: Layer, box: Box, scope: CoroutineScope): WidgetBuild? {
    val style = GoalStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val scale = box.w / style.natural.first
    val filter = SpriteFilter().place(box, l.rotation)
    val job = scope.launch {
        var total = GoalStore.total
        var progress = GoalStore.progress.toFloat()
        var wasReached = GoalStore.reached
        snapshotFlow { Triple(GoalStore.total, GoalStore.config, GoalStore.reached) }.collectLatest { (now, cfg, reached) ->
            val celebrate = reached && !wasReached
            wasReached = reached
            val p = GoalStore.progress.toFloat()
            if (now > total) {
                filter.show(GoalArt(style, cfg, total, now, progress, p, celebrate, scale).scene(moving = true))
                delay((REACTION_SECONDS * 1000).toLong())
            }
            total = now
            progress = p
            filter.show(GoalArt(style, cfg, now, now, p, p, celebrate, scale).scene(moving = false))
            if (celebrate) {
                delay(CELEBRATE_MS)
                filter.show(GoalArt(style, cfg, now, now, p, p, false, scale).scene(moving = false))
            }
        }
    }
    return WidgetBuild(filter, job)
}

/** One look of the goal in natural units; text rasterised once at the stream's pixel size. */
private class GoalArt(
    private val st: GoalStyle,
    cfg: GoalConfig,
    from: BigDecimal,
    to: BigDecimal,
    private val fromP: Float,
    private val toP: Float,
    private val celebrating: Boolean,
    private val scale: Float
) {
    private val w = st.natural.first
    private val h = st.natural.second
    private val f = st.fontSize
    private val dim = (st.textColor and 0xFFFFFF) or (0xD9 shl 24)

    private fun t(s: String, size: Float, weight: Int, color: Int) = ink(s, size * scale, weight, color, face = st.face)

    private val currency = cfg.currency

    private fun money(d: BigDecimal) = Money(d, currency).display

    private val title = t(if (celebrating) "Goal reached!" else cfg.title, f, 700, st.textColor)
    private val before = t("${money(from)} / ${money(cfg.target)}", f, 700, st.textColor)
    private val after = t("${money(to)} / ${money(cfg.target)}", f, 700, st.textColor)
    private val pctFrom = if (st.showPercent) t("${(fromP * 100).roundToInt()}%", f * 0.7f, 600, dim) else null
    private val pctTo = if (st.showPercent) t("${(toP * 100).roundToInt()}%", f * 0.7f, 600, dim) else null
    private val other = if (st.showOther) {
        listOf("IRT", "USD", "EUR").filter { it != currency }
            .mapNotNull { c -> Rates.convert(Money(to, currency), c)?.let { Money(it, c).display } }
            .takeIf { it.isNotEmpty() }?.let { t("≈ " + it.joinToString(" · "), f * 0.7f, 600, dim) }
    } else {
        null
    }
    private val delta = if (to > from) t("+" + money(to - from), f * 0.8f, 700, st.barColor) else null

    fun scene(moving: Boolean) = GpuScene(w, h, moving) { s -> items(if (moving) (s / REACTION_SECONDS).coerceIn(0f, 1f) else 1f) }

    /** [Txt.at] in natural units (it works in px). */
    private fun Txt.put(x: Float, y: Float, align: Int, alpha: Float = 1f, maxW: Float = Float.MAX_VALUE): Item {
        val r = at(x * scale, y * scale, align, alpha, maxW * scale).rect
        return Item(RectF(r.left / scale, r.top / scale, r.right / scale, r.bottom / scale), bmp, alpha = alpha)
    }

    private fun items(p: Float): List<Item> {
        val out = ArrayList<Item>()
        val pad = 16f
        if (st.background) out += Item(RectF(0f, 0f, w, h), color = st.backgroundColor, radius = 14f)
        val headH = (before?.h ?: (f * scale)) / scale
        val meterH = f * 0.6f
        val footH = if (pctTo != null || other != null || delta != null) f * 0.7f * 1.4f else 0f
        val gap = f * 0.3f
        val top = (h - headH - gap - meterH - (if (footH > 0f) gap + footH else 0f)) / 2
        val headY = top + headH / 2
        val k = dEaseOut(((p - 0.05f) / 0.3f).coerceIn(0f, 1f)) // the numbers flip
        val numW = maxOf(before?.w ?: 0f, after?.w ?: 0f) / scale
        title?.let { out += it.put(pad, headY, -1, maxW = w - 2 * pad - numW - 12f) }
        before?.let { if (k < 1f) out += it.put(w - pad, headY - 8f * k, 1, 1 - k) }
        after?.let { if (k > 0f) out += it.put(w - pad, headY + 8f * (1 - k), 1, k) }
        val my = top + headH + gap
        val v = fromP + (toP - fromP) * dEaseInOut(((p - 0.1f) / 0.6f).coerceIn(0f, 1f))
        meter(RectF(pad, my, w - pad, my + meterH), v.coerceIn(0f, 1f), p, out)
        if (footH > 0f) {
            val fy = my + meterH + gap + footH / 2
            other?.let { out += it.put(pad, fy, -1, maxW = w * 0.6f) }
            pctFrom?.let { if (k < 1f) out += it.put(w - pad, fy, 1, 1 - k) }
            pctTo?.let { if (k > 0f) out += it.put(w - pad, fy, 1, k) }
            delta?.let {
                val a = track(p, ::dLinear, 0f to 0f, 0.12f to 1f, 0.75f to 1f, 1f to 0f)
                if (a > 0f) out += it.put(w / 2, fy - 10f * dEaseOut(p), 0, a)
            }
        }
        return out
    }

    private fun meter(r: RectF, v: Float, p: Float, out: MutableList<Item>) {
        val fill = if (celebrating) st.textColor else st.barColor
        when (st.design) {
            "segments" -> {
                val n = 20
                val g = 4f
                val sw = (r.width() - g * (n - 1)) / n
                for (i in 0 until n) {
                    val x = r.left + i * (sw + g)
                    val cell = RectF(x, r.top, x + sw, r.bottom)
                    out += Item(cell, color = st.trackColor, radius = 3f)
                    val lit = (v * n - i).coerceIn(0f, 1f)
                    if (lit > 0f) out += Item(RectF(cell), color = fill, alpha = lit, radius = 3f)
                }
            }
            "hairline" -> {
                val cy = r.centerY()
                out += Item(RectF(r.left, cy - 1.5f, r.right, cy + 1.5f), color = st.trackColor, radius = 1.5f)
                val x = r.left + r.width() * v
                if (v > 0f) out += Item(RectF(r.left, cy - 1.5f, x, cy + 1.5f), color = fill, radius = 1.5f)
                out += disc(x, cy, r.height() * 0.4f, fill)
            }
            "dots" -> {
                val n = 10
                val step = r.width() / n
                val rad = minOf(r.height() * 0.7f, step * 0.32f)
                for (i in 0 until n) {
                    val cx = r.left + step * (i + 0.5f)
                    out += disc(cx, r.centerY(), rad, st.trackColor)
                    val lit = (v * n - i).coerceIn(0f, 1f)
                    if (lit > 0f) out += disc(cx, r.centerY(), rad, fill, lit)
                }
            }
            else -> {
                val rad = r.height() / 2
                out += Item(RectF(r), color = st.trackColor, radius = rad)
                val bar = RectF(r.left, r.top, r.left + r.width() * v, r.bottom)
                if (bar.width() > 0.5f) {
                    out += Item(bar, color = fill, radius = rad)
                    val ga = track(p, ::dEaseOut, 0.1f to 0f, 0.2f to 1f, 0.7f to 0f)
                    if (ga > 0f) {
                        val gx = bar.left + track(p, ::dEaseOut, 0.1f to -0.2f, 0.7f to 1.1f) * bar.width()
                        out += Item(RectF(gx, bar.top, gx + 60f, bar.bottom), alpha = 0.6f * ga, clip = RectF(bar), clipRadius = rad)
                    }
                }
            }
        }
    }
}
