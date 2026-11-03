package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.TextUtils
import com.saeedkolivand.metastream.bot.BotRules
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import com.saeedkolivand.metastream.core.model.Money
import com.saeedkolivand.metastream.goal.DonationPrices
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.goal.Rates
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * Donation alerts drawn live on the GPU (iOS DonationAlert.swift, the "Donation Alerts" boards). Each design rasterises its
 * text once when the alert starts and returns a pure function of the progress p (0..1) to [Item]s in canvas px, so a frame
 * is only quads. Designs are laid out on the boards' 1280x720 and fitted around the Alerts widget by [Board].
 * Faces match the iOS boards: Unbounded, Tilt Neon, JetBrains Mono, Manrope (bundled, Persian falls through to Vazirmatn).
 */
/** A board rect (left, top, right, bottom); plain floats so the fitting math runs in unit tests. */
class Area(val l: Float, val t: Float, val r: Float, val b: Float)

enum class DonationKind(val id: String, val title: String, val focus: Area, val seconds: Float) {
    Island("island", "Island", Area(0f, 0f, 1280f, 720f), 0f),
    CoinBurst("coinBurst", "Coin burst", Area(240f, 60f, 1040f, 260f), 6f),
    Neon("neon", "Neon sign", Area(300f, 80f, 980f, 420f), 6f),
    Receipt("receipt", "Receipt", Area(820f, 38f, 1200f, 720f), 7f),
    Holo("holo", "Holo card", Area(120f, 100f, 480f, 610f), 7f),
    Shockwave("shockwave", "Shockwave", Area(240f, 100f, 1040f, 480f), 7f),
    GoalSurge("goalSurge", "Goal surge", Area(80f, 560f, 380f, 640f), 6f);

    companion object {
        fun of(id: String) = entries.firstOrNull { it.id == id } ?: Island
    }
}

internal class GoalInfo(val title: String, val before: String, val after: String, val target: String, val from: Float, val to: Float)

/** What an alert shows, built once when it starts. */
internal class DonationInfo(
    val name: String,
    val amount: String,
    val message: String,
    val source: String,
    val rate: String,
    val toGoal: String,
    // 0 rare, 1 epic, 2 legendary: under $10, under $50, $50 and up
    val tier: Int,
    val date: String,
    val time: String,
    val goal: GoalInfo?
) {
    val initial get() = name.take(1).uppercase()
}

private fun symbol(code: String) = when (code) {
    "IRT" -> "₮"
    "USD" -> "$"
    "EUR" -> "€"
    else -> code
}

internal fun donationInfo(e: ChatEvent): DonationInfo {
    val cfg = GoalStore.config
    val money = if (e.kind == Kind.Tip) e.money ?: DonationPrices.money(e) else DonationPrices.money(e)
    fun shown(d: BigDecimal) = Money(d.setScale(2, RoundingMode.HALF_UP), cfg.currency).display
    var rate = ""
    val m = money?.inToman
    if (e.kind == Kind.Tip && m != null && m.currency != cfg.currency) {
        Rates.convert(Money(BigDecimal.ONE, m.currency), cfg.currency)?.let {
            rate =
                Money(it.setScale(if (cfg.currency == "IRT") 0 else 2, RoundingMode.HALF_UP), cfg.currency).display + "/" +
                symbol(m.currency)
        }
    }
    // What it added to the goal: the ledger's value when recorded, else converted now.
    val entry = e.msgId.takeIf { it.isNotEmpty() }?.let { id -> GoalStore.entries.firstOrNull { it.id == "${e.platform}:$id" } }
    val value = entry?.value ?: money?.let { Rates.convert(it, cfg.currency) }
    val usd = money?.let { Rates.convert(it, "USD") } ?: BigDecimal.ZERO
    val goal = if (cfg.target.signum() > 0) {
        val v = value ?: BigDecimal.ZERO
        val after = if (entry == null) GoalStore.total + v else GoalStore.total // not recorded yet: it is about to be
        val before = (after - v).max(BigDecimal.ZERO)
        fun share(x: BigDecimal) = x.divide(cfg.target, MathContext.DECIMAL64).toFloat().coerceIn(0f, 1f)
        GoalInfo(cfg.title, shown(before), shown(after), shown(cfg.target), share(before), share(after))
    } else {
        null
    }
    val day = Date(e.time)
    return DonationInfo(
        BotRules.safeName(e.user), alertAmount(e), e.text, e.platform.uppercase(), rate, value?.let(::shown).orEmpty(),
        if (usd < BigDecimal(10)) {
            0
        } else if (usd < BigDecimal(50)) {
            1
        } else {
            2
        },
        SimpleDateFormat("d MMM yyyy", Locale.US).format(day).uppercase(), SimpleDateFormat("HH:mm", Locale.US).format(day), goal
    )
}

/** The design's accent (0 = its own colour), second tube colour, and speed (duration = seconds / speed). */
internal class DonationLook(private val accent: Int, private val second: Int, val speed: Float) {
    fun accent(own: Long) = if (accent == 0) own.toInt() else accent or (0xFF shl 24)

    fun second(own: Long) = if (second == 0) own.toInt() else second or (0xFF shl 24)
}

/**
 * The 1280x720 board on the canvas, scaled by the Alerts widget's layer scale with the design's [DonationKind.focus] centred
 * on the widget box and kept inside the canvas.
 */
internal class Board(val s: Float, private val ox: Float, private val oy: Float) {
    fun x(v: Float) = ox + v * s

    fun y(v: Float) = oy + v * s

    fun len(v: Float) = v * s

    fun rect(x: Float, y: Float, w: Float, h: Float) = RectF(x(x), y(y), x(x + w), y(y + h))

    companion object {
        fun of(w: Float, h: Float, focus: Area, box: Box?): Board {
            val base = minOf(w / 1280f, h / 720f)
            if (box == null || box.w <= 0f) return Board(base, (w - 1280f * base) / 2, 0f)
            val sc = base * box.w / (900f * minOf(w, h) / 1080f)
            fun place(want: Float, lo: Float, hi: Float, size: Float): Float {
                val minO = -lo
                val maxO = size - hi
                return if (minO > maxO) (minO + maxO) / 2 else want.coerceIn(minO, maxO)
            }
            return Board(
                sc,
                place(box.x + box.w / 2 - (focus.l + focus.r) / 2 * sc, focus.l * sc, focus.r * sc, w),
                place(box.y + box.h / 2 - (focus.t + focus.b) / 2 * sc, focus.t * sc, focus.b * sc, h)
            )
        }
    }
}

// Keyframes: percent-of-loop windows like the boards' CSS.
internal fun dLinear(t: Float) = t

internal fun dEaseOut(t: Float) = 1 - (1 - t).pow(3)

internal fun dEaseIn(t: Float) = t * t * t

internal fun dEaseInOut(t: Float) = if (t < 0.5f) 4 * t * t * t else 1 - (-2 * t + 2).pow(3) / 2

/** Overshoots past 1 then settles (the boards' pops). */
internal fun dBack(t: Float): Float {
    val u = t - 1
    return 1 + 2.7f * u * u * u + 1.7f * u * u
}

/** Value at [p] between keyframes (p, value), eased inside each segment; held before the first and after the last. */
internal fun track(p: Float, ease: (Float) -> Float, vararg k: Pair<Float, Float>): Float {
    if (p <= k[0].first) return k[0].second
    for (i in 1 until k.size) {
        val (p1, v1) = k[i]
        val (p0, v0) = k[i - 1]
        if (p <= p1) return if (p1 <= p0) v1 else v0 + (v1 - v0) * ease((p - p0) / (p1 - p0))
    }
    return k.last().second
}

private const val MAX_CHARS = 300
private const val MAX_TEXT_PX = 2048f

/** Text rasterised once, w x h canvas px (padding for a glow included). */
internal class Txt(val bmp: Bitmap, val w: Float, val h: Float) {
    /** Hugging the left (-1), centre (0) or right (1) of [x], centred on [y]; shrunk to fit [maxW], then scaled by [k]. */
    fun at(x: Float, y: Float, align: Int = 0, alpha: Float = 1f, maxW: Float = Float.MAX_VALUE, k: Float = 1f): Item {
        val sc = minOf(1f, maxW / w) * k
        val ww = w * sc
        val hh = h * sc
        val left = if (align < 0) {
            x
        } else if (align > 0) {
            x - ww
        } else {
            x - ww / 2
        }
        return Item(RectF(left, y - hh / 2, left + ww, y + hh / 2), bmp, alpha = alpha)
    }
}

internal fun ink(
    text: String,
    px: Float,
    weight: Int,
    color: Int,
    tracking: Float = 0f,
    mono: Boolean = false,
    glowPx: Float = 0f,
    glow: Int = 0,
    face: String = ""
): Txt? {
    if (text.isEmpty() || px < 1f) return null
    val p = widgetPaint(face, weight, px, color).apply {
        letterSpacing = tracking
        if (mono) typeface = WidgetFonts.typeface("JetBrainsMono", weight)
        if (glowPx > 0f) setShadowLayer(glowPx, 0f, 0f, glow)
    }
    val fm = p.fontMetrics
    val pad = glowPx * 1.5f
    // Viewer text (names, messages) is unbounded: cut it to the widest texture GLES guarantees, with an ellipsis.
    val shown = TextUtils.ellipsize(text.take(MAX_CHARS), p, MAX_TEXT_PX - 2 * pad, TextUtils.TruncateAt.END).toString().ifEmpty {
        return null
    }
    val w = ceil(p.measureText(shown) + 2 * pad)
    val h = ceil(fm.bottom - fm.top + 2 * pad)
    val bmp = newBitmap(w, h)
    Canvas(bmp).drawText(shown, pad, pad - fm.top, p)
    return Txt(bmp, w, h)
}

/** A group transform about (cx, cy): scale, turn (degrees), move, fade. Applied to items that were laid out unmoved. */
internal class Tf(
    val cx: Float,
    val cy: Float,
    val sx: Float = 1f,
    val sy: Float = sx,
    val rot: Float = 0f,
    val dx: Float = 0f,
    val dy: Float = 0f,
    val alpha: Float = 1f
)

internal fun Item.by(x: Tf): Item {
    val mcx = rect.centerX()
    val mcy = rect.centerY()
    val ox = (mcx - x.cx) * x.sx
    val oy = (mcy - x.cy) * x.sy
    val rad = Math.toRadians(x.rot.toDouble())
    val c = cos(rad).toFloat()
    val s = sin(rad).toFloat()
    val ncx = x.cx + ox * c - oy * s + x.dx
    val ncy = x.cy + ox * s + oy * c + x.dy
    fun map(r: RectF) = RectF(
        ncx + (r.left - mcx) * x.sx,
        ncy + (r.top - mcy) * x.sy,
        ncx + (r.right - mcx) * x.sx,
        ncy + (r.bottom - mcy) * x.sy
    )
    val k = minOf(x.sx, x.sy)
    return Item(map(rect), image, color, alpha * x.alpha, radius * k, clip?.let(::map), clipRadius * k, rotation + x.rot)
}

internal fun List<Item>.by(x: Tf) = map { it.by(x) }

internal fun disc(cx: Float, cy: Float, r: Float, color: Int, alpha: Float = 1f) =
    Item(RectF(cx - r, cy - r, cx + r, cy + r), color = color, alpha = alpha, radius = r)

private val rings = HashMap<Int, Bitmap>()

/** A white ring (inner radius = [inner] of the outer) tinted [color]; one 256 px bitmap per thickness, scaled. */
internal fun ring(cx: Float, cy: Float, r: Float, inner: Float, color: Int, alpha: Float = 1f): Item {
    val key = (inner * 100).toInt()
    val bmp = rings.getOrPut(key) {
        newBitmap(256f, 256f).also {
            Canvas(it).drawCircle(
                128f,
                128f,
                128f * (1 + inner) / 2,
                fillPaint(-1).apply {
                    style = Paint.Style.STROKE
                    strokeWidth =
                        128f * (1 - inner)
                }
            )
        }
    }
    return Item(RectF(cx - r, cy - r, cx + r, cy + r), bmp, color, alpha)
}

/** A 4-point sparkle: two thin crossed bars, [half] long each way, turned [rot] degrees. */
internal fun star(cx: Float, cy: Float, half: Float, rot: Float, alpha: Float): List<Item> {
    if (half < 0.5f || alpha < 0.01f) return emptyList()
    val r = RectF(cx - half * 0.17f, cy - half, cx + half * 0.17f, cy + half)
    return listOf(
        Item(r, alpha = alpha, radius = half * 0.17f, rotation = rot),
        Item(
            RectF(r),
            alpha = alpha,
            radius = half * 0.17f,
            rotation =
            rot + 90
        )
    )
}

/** Every design's scene: one moving [GpuScene] over the whole canvas for the alert's length. */
internal fun donationScene(e: ChatEvent, style: AlertStyle, outW: Int, outH: Int, box: Box): GpuScene? {
    val kind = DonationKind.of(style.design)
    if (kind == DonationKind.Island) return null
    val look = DonationLook(style.designAccent, style.designSecond, style.speed)
    val b = Board.of(outW.toFloat(), outH.toFloat(), kind.focus, box)
    val info = donationInfo(e)
    val frame: (Float) -> List<Item> = when (kind) {
        DonationKind.CoinBurst -> coinBurst(info, look, b)
        DonationKind.Neon -> neon(info, look, b)
        DonationKind.Receipt -> receipt(info, look, b)
        DonationKind.Holo -> holo(info, look, b)
        DonationKind.Shockwave -> shockwave(info, look, b, outW.toFloat(), outH.toFloat())
        else -> goalSurge(info, look, b, outW.toFloat(), outH.toFloat())
    }
    val dur = kind.seconds / look.speed
    return GpuScene(outW.toFloat(), outH.toFloat(), moving = true, canvas = true) { t -> frame((t / dur).coerceIn(0f, 1f)) }
}

/** Seconds the alert plays: the board's loop over the speed, plus a beat so the last frame clears. */
internal fun donationSeconds(style: AlertStyle) = DonationKind.of(style.design).seconds / style.speed + 0.15f
