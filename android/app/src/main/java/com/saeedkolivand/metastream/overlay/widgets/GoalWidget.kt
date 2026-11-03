package com.saeedkolivand.metastream.overlay

import android.graphics.RectF
import androidx.compose.runtime.snapshotFlow
import com.saeedkolivand.metastream.core.model.Money
import com.saeedkolivand.metastream.goal.GoalConfig
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.goal.Rates
import java.math.BigDecimal
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

private const val CELEBRATE_MS = 6000L

/**
 * The donation goal on the GPU (iOS GoalPlayer / GoalArt): a still scene while nothing changes; a donation that raises the
 * total plays the design's own reaction as one moving scene (1.6 s, the island 2.4 s), then settles. The bar has no
 * reaction, like iOS. Reaching the goal shows "Goal reached!" for six seconds. Designs are laid out in the iOS boards' points
 * (GoalArt*.kt, one file per iOS file) and scaled to the box; variable-width ones hug their side of it.
 */
internal fun goalWidget(l: Layer, box: Box, scope: CoroutineScope): WidgetBuild? {
    val style = GoalStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val filter = SpriteFilter().place(box, l.rotation)
    val bar = style.design == "bar"
    val (nw, nh) = style.natural
    val per = if (bar) 1f else 1.5f // the boards are 1280 wide; a stream canvas is 1920
    val pen = GoalPen(box.w / nw * per)
    val seconds = if (style.design == "island") 2.4f else 1.6f

    fun scene(input: GoalInput, moving: Boolean) = GpuScene(nw / per, nh / per, moving) { t ->
        val draw = GoalDraw(input, pen, if (moving) (t / seconds).coerceIn(0f, 1f) else 1f)
        val piece = draw.design()
        val slack = nw / per - piece.w
        val left = if (style.design == "spark") {
            slack
        } else if (style.design == "island") {
            slack / 2
        } else {
            0f
        }
        val top = if (bar) 0f else (nh / per - piece.h) / 2
        if (left == 0f && top == 0f) piece.items else piece.items.by(Tf(0f, 0f, dx = left, dy = top))
    }

    val job = scope.launch {
        var shown = GoalStore.total to GoalStore.progress.toFloat()
        var wasReached = GoalStore.reached
        snapshotFlow { Triple(GoalStore.total, GoalStore.config, GoalStore.reached) }.collectLatest { (now, cfg, reached) ->
            val celebrate = reached && !wasReached
            wasReached = reached
            val p = GoalStore.progress.toFloat()
            if (!bar && now > shown.first) {
                filter.show(scene(goalInput(style, cfg, shown.first, now, shown.second, p, celebrate), moving = true))
                delay((seconds * 1000).toLong())
            }
            shown = now to p
            filter.show(scene(goalInput(style, cfg, now, now, p, p, celebrate), moving = false))
            if (celebrate) {
                delay(CELEBRATE_MS)
                filter.show(scene(goalInput(style, cfg, now, now, p, p, false), moving = false))
            }
        }
    }
    return WidgetBuild(filter, job)
}

/** What one scene shows (iOS GoalInput). For the bar `to` is the progress and `afterText` the total. */
internal class GoalInput(
    val style: GoalStyle,
    val title: String,
    val beforeText: String,
    val afterText: String,
    val targetText: String,
    val deltaText: String,
    val otherText: String,
    val from: Float,
    val to: Float,
    val pins: List<String>,
    val celebrating: Boolean
)

private fun goalInput(
    st: GoalStyle,
    cfg: GoalConfig,
    from: BigDecimal,
    to: BigDecimal,
    fromP: Float,
    toP: Float,
    celebrating: Boolean
): GoalInput {
    fun money(d: BigDecimal) = Money(d, cfg.currency).display
    val other = listOf("IRT", "USD", "EUR").filter { it != cfg.currency }
        .mapNotNull { c -> Rates.convert(Money(to, cfg.currency), c)?.let { Money(it, c).display } }
    return GoalInput(
        st,
        if (celebrating) "Goal reached!" else cfg.title,
        money(from),
        money(to),
        money(cfg.target),
        if (to > from) money(to - from) else "",
        if (other.isEmpty()) "" else "≈ " + other.joinToString(" · "),
        fromP,
        toP,
        listOf(25, 50, 75).map { money(cfg.target * BigDecimal(it) / BigDecimal(100)) },
        celebrating
    )
}

/** iOS GoalMotion: windows, smoothstep and the boards' loop keyframes (the donation sits at 40..75 % of a 6 s loop). */
internal object GoalMotion {
    fun seg(t: Float, a: Float, b: Float) = ((t - a) / (b - a)).coerceIn(0f, 1f)

    fun smooth(s: Float) = s * s * (3 - 2 * s)

    /** The move itself (fill, car) takes the first 75% of the reaction, eased. */
    fun move(t: Float) = smooth(seg(t, 0f, 0.75f))

    fun lp(t: Float, a: Float, b: Float) = smooth(seg(40 + 35 * t, a, b))

    /** Piecewise-linear keyframes (loop %, value) at t; [delay] shifts them later (loop %). */
    fun kf(t: Float, vararg pts: Pair<Float, Float>, delay: Float = 0f): Float {
        val l = 40 + 35 * t - delay
        if (l <= pts[0].first) return pts[0].second
        for (i in 1 until pts.size) {
            val (a, va) = pts[i - 1]
            val (b, vb) = pts[i]
            if (l <= b) return va + (vb - va) * (l - a) / (b - a)
        }
        return pts.last().second
    }
}

internal fun goalPct(v: Float) = "${(v.coerceIn(0f, 1f) * 100).roundToInt()}%"

/** A drawn design and its size in board points. */
internal class GoalPiece(val items: List<Item>, val w: Float, val h: Float)

/** Old text leaving (by [drop], fading) while the new one comes in (from [rise] below), like iOS GoalFlip. */
internal class GoalFlip(
    val before: String,
    val after: String,
    val progress: Float,
    val rise: Float = 8f,
    val drop: Float = 0f,
    val minWidth: Float = 0f
)

/** One frame's drawing helpers in board points (iOS GoalDraw); the designs live in GoalArt*.kt. */
internal class GoalDraw(val input: GoalInput, val pen: GoalPen, val prog: Float) {
    val style get() = input.style
    val accent get() = style.barColor

    fun design(): GoalPiece = when (style.design) {
        "liquid" -> liquid()
        "road" -> road()
        "segments" -> segments()
        "hairline" -> hairline()
        "island" -> island()
        "miniring" -> miniRing()
        "dots" -> dots()
        "spark" -> spark()
        else -> bar()
    }

    /** The reaction's fill level for designs that ease it with [ease]. */
    fun level(ease: Float) = (input.from + (input.to - input.from) * ease).coerceIn(0f, 1f)

    fun run(text: String, size: Float, weight: Int, face: String = "Manrope") = GoalRun(text, size, weight, face, style.textColor)

    fun area(x: Float, y: Float, w: Float, h: Float) = RectF(x, y, x + w, y + h)

    fun fill(r: RectF, color: Int, alpha: Float = 1f) = Item(r, color = color, alpha = alpha)

    fun pill(r: RectF, radius: Float, color: Int, alpha: Float = 1f) = Item(r, color = color, alpha = alpha, radius = radius)

    fun capsule(r: RectF, color: Int, alpha: Float = 1f) = pill(r, minOf(r.width(), r.height()) / 2, color, alpha)

    /** A circle outline [width] thick, its outer edge at [radius]. */
    fun outline(cx: Float, cy: Float, radius: Float, width: Float, color: Int, alpha: Float = 1f) =
        com.saeedkolivand.metastream.overlay.ring(cx, cy, radius, ((radius - width) / radius).coerceIn(0f, 0.99f), color, alpha)

    /** SwiftUI .shadow round a disc. ponytail: a cached radial halo, not a true blur of the shape. */
    fun glow(cx: Float, cy: Float, r: Float, color: Int, blur: Float, alpha: Float = 1f): Item? = if (blur < 0.1f ||
        alpha < 0.001f
    ) {
        null
    } else {
        Item(RectF(cx - r - blur, cy - r - blur, cx + r + blur, cy + r + blur), pen.halo, color, alpha)
    }

    /** The text widgets' drop shadow: the same items in black, [dy] lower. ponytail: no blur. */
    fun shadowed(items: List<Item>, alpha: Float, dy: Float) = items.map {
        Item(
            RectF(it.rect.left, it.rect.top + dy, it.rect.right, it.rect.bottom + dy),
            it.image,
            0xFF000000.toInt(),
            it.alpha * alpha * 0.6f,
            it.radius,
            it.clip,
            it.clipRadius
        )
    } +
        items

    fun metrics(r: GoalRun) = pen.metrics(r)

    /** [r] cut with an ellipsis to fit [width] points (SwiftUI lineLimit(1)). */
    fun fit(r: GoalRun, width: Float) = if (width <= 0f || metrics(r).w <= width) r else r.with(pen.ellipsize(r, width))

    /** [r] anchored at [x] (side -1 lead, 1 trail, 0 centre) on baseline [y], or centred on [y] when r.mid. */
    fun text(r: GoalRun, x: Float, y: Float, side: Int = -1): Item? {
        if (r.text.isEmpty() || r.alpha <= 0.001f) return null
        val t = pen.txt(r) ?: return null
        val w = t.w / pen.unit
        val h = t.h / pen.unit
        val left = if (side < 0) {
            x
        } else if (side > 0) {
            x - w
        } else {
            x - w / 2
        }
        val top = if (r.mid) y - h / 2 else y - metrics(r).asc
        return Item(RectF(left, top, left + w, top + h), t.bmp, r.color, r.alpha)
    }

    fun flipWidth(s: GoalFlip, r: GoalRun) = maxOf(s.minWidth, metrics(r.with(s.before)).w, metrics(r.with(s.after)).w)

    fun flip(s: GoalFlip, r: GoalRun, x: Float, y: Float, side: Int) = listOfNotNull(
        text(r.with(s.before).fading(r.alpha * (1 - s.progress)), x, y + s.drop * s.progress, side),
        text(r.with(s.after).fading(r.alpha * s.progress), x, y + s.rise * (1 - s.progress), side)
    )

    /** A progress arc of [radius], [width] thick, [fraction] round clockwise from 12 o'clock. ponytail: overlapping dots. */
    fun arc(radius: Float, width: Float, fraction: Float, cx: Float, cy: Float, color: Int): List<Item> = if (fraction <= 0f) {
        emptyList()
    } else {
        (0..(96 * fraction.coerceIn(0f, 1f)).toInt()).map { k ->
            val a = 2 * Math.PI * k / 96
            disc(cx + radius * kotlin.math.sin(a).toFloat(), cy - radius * kotlin.math.cos(a).toFloat(), width / 2, color)
        }
    }

    /** Track and progress arc of the boards' ring (a [diameter] frame, 3.5 stroke at 26) centred on (cx, cy). */
    fun ring(diameter: Float, progress: Float, cx: Float, cy: Float): List<Item> {
        val k = diameter / 26
        val radius = 10 * k
        val width = 3.5f * k
        return listOf(outline(cx, cy, radius + width / 2, width, style.trackColor)) + arc(radius, width, progress, cx, cy, accent)
    }

    companion object {
        const val WHITE = 0xFFFFFFFF.toInt()
        const val INK = 0xFF121318.toInt()
        const val STEEL = 0xFFD7D8DE.toInt()
        const val DIM = 0xFFA9ABB5.toInt()
    }
}

internal fun List<Item>.moved(dx: Float, dy: Float) = by(Tf(0f, 0f, dx = dx, dy = dy))

internal fun List<Item>.faded(k: Float) = if (k >=
    1f
) {
    this
} else {
    map { Item(it.rect, it.image, it.color, it.alpha * k, it.radius, it.clip, it.clipRadius, it.rotation) }
}

/** Clipped to [c] (rounded by [r]) as well as any clip they already have; items wholly outside are dropped. */
internal fun List<Item>.within(c: RectF, r: Float = 0f) = mapNotNull {
    val k = RectF(c)
    if (it.clip != null && !k.intersect(it.clip)) return@mapNotNull null
    if (!RectF.intersects(k, it.rect)) return@mapNotNull null
    Item(it.rect, it.image, it.color, it.alpha, it.radius, k, maxOf(r, it.clipRadius), it.rotation)
}
