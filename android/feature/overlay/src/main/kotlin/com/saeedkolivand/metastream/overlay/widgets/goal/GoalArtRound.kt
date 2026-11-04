package com.saeedkolivand.metastream.overlay.widgets.goal

import com.saeedkolivand.metastream.overlay.Item
import com.saeedkolivand.metastream.overlay.Tf
import com.saeedkolivand.metastream.overlay.by
import com.saeedkolivand.metastream.overlay.disc
import com.saeedkolivand.metastream.overlay.ring
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

// iOS GoalArtRound: GoalIslandView, GoalMiniRingView and GoalDotsView, in their points.

private fun GoalDraw.width(text: String, size: Float, weight: Int, spacing: Float = 0f) =
    metrics(run(text, size, weight).tracked(spacing)).w

/** Island pill: a ring and "total / target" that bursts open on a donation to show the title and "+delta". */
fun GoalDraw.island(): GoalPiece {
    val amountW = maxOf(width(input.beforeText, 15f, 800), width(input.afterText, 15f, 800))
    val rest = 10 + 26 + 10 + amountW + width(" / " + input.targetText, 15f, 600) + 16 + 8
    val titleW = width(input.title.uppercase(), 11f, 600, 0.88f)
    val lineW = width(input.afterText, 17f, 800) + width(" / " + input.targetText, 14f, 600)
    val burst = maxOf(12 + 32 + 10 + maxOf(titleW, lineW) + 16 + width("+" + input.deltaText, 20f, 800) + 18 + 10, rest + 60)
    val rise = GoalMotion.seg(prog, 0f, 0.2f) - 1
    val spring = 1 + 2.2f * rise * rise * rise + 1.2f * rise * rise // overshoot
    val swell = spring * (1 - GoalMotion.smooth(GoalMotion.seg(prog, 0.75f, 1f)))
    val wide = rest + (burst - rest) * swell
    val high = 44 + 12 * swell
    val shown = level(GoalMotion.smooth(GoalMotion.seg(prog, 0.12f, 0.55f)))
    val glowing = GoalMotion.seg(prog, 0f, 0.12f) * (1 - GoalMotion.seg(prog, 0.12f, 0.7f))
    val restO = minOf(1f, (1 - GoalMotion.seg(prog, 0f, 0.08f)) + GoalMotion.seg(prog, 0.78f, 0.9f))
    val burstO = GoalMotion.seg(prog, 0.03f, 0.18f) * (1 - GoalMotion.seg(prog, 0.7f, 0.8f))
    val shape = area(0f, 0f, wide, high)
    val out = ArrayList<Item>()
    // ponytail: the accent glow is two soft capsules round the pill, not a blur.
    if (glowing > 0.001f) {
        out += capsule(area(-7f, -7f, wide + 14, high + 14), accent, 0.3f * glowing)
        out += capsule(area(-14f, -14f, wide + 28, high + 28), accent, 0.15f * glowing)
    }
    if (style.background) out += capsule(shape, style.backgroundColor)
    val inside = ArrayList<Item>()
    if (restO > 0.001f) inside += restLayer(shown, amountW, high).faded(restO)
    if (burstO > 0.001f) inside += burstLayer(shown, wide, high).faded(burstO)
    out += inside.within(shape, high / 2)
    return GoalPiece(out, wide, high)
}

private fun GoalDraw.restLayer(shown: Float, amountW: Float, high: Float): List<Item> {
    val amount = run(if (prog < 0.5f) input.beforeText else input.afterText, 15f, 800).centred()
    val tail = run(" / " + input.targetText, 15f, 600).fading(0.55f).centred()
    return ring(26f, shown, 23f, high / 2) + listOfNotNull(text(amount, 46f, high / 2), text(tail, 46 + amountW, high / 2))
}

private fun GoalDraw.burstLayer(shown: Float, wide: Float, high: Float): List<Item> {
    val title = run(input.title.uppercase(), 11f, 600).tracked(0.88f).fading(0.65f).centred()
    val after = run(input.afterText, 17f, 800)
    val tail = run(" / " + input.targetText, 14f, 600).fading(0.55f)
    val asc = maxOf(metrics(after).asc, metrics(tail).asc)
    val lineH = asc + maxOf(metrics(after).h - metrics(after).asc, metrics(tail).h - metrics(tail).asc)
    val titleH = metrics(title).h
    val top = high / 2 - (titleH + 1 + lineH) / 2
    val plus = run("+" + input.deltaText, 20f, 800).colored(accent).centred()
    val layer = ring(32f, shown, 28f, high / 2) + listOfNotNull(
        text(title, 54f, top + titleH / 2),
        text(after, 54f, top + titleH + 1 + asc),
        text(tail, 54 + metrics(after).w, top + titleH + 1 + asc),
        text(plus, wide - 18, high / 2, 1)
    )
    return layer.by(Tf(wide / 2, high / 2, 0.92f + 0.08f * GoalMotion.seg(prog, 0.03f, 0.18f)))
}

/** Mini ring: a 72 pt ring (comet and pulse on a donation) with the title, amount and "+delta just now" beside it. */
fun GoalDraw.miniRing(): GoalPiece {
    val shown = level(GoalMotion.lp(prog, 42f, 60f))
    val swap = GoalMotion.lp(prog, 56f, 62f)
    val title = run(input.title.uppercase(), 11f, 600).tracked(1.54f).fading(0.65f)
    val amount = run("", 18f, 800)
    val tail = run("of " + input.targetText, 14f, 600).fading(0.55f)
    val delta = run(if (input.deltaText.isEmpty()) " " else "+${input.deltaText} just now", 12f, 800).colored(accent)
    val spec = GoalFlip(input.beforeText, input.afterText, swap, minWidth = 44f)
    val asc = maxOf(metrics(amount).asc, metrics(tail).asc)
    val lineH = asc + maxOf(metrics(amount).h - metrics(amount).asc, metrics(tail).h - metrics(tail).asc)
    val colH = metrics(title).h + 2 + lineH + 2 + metrics(delta).h
    val colW = maxOf(metrics(title).w, flipWidth(spec, amount) + 4 + metrics(tail).w, metrics(delta).w)
    val wide = 10 + 72 + 14 + colW + 18
    val high = maxOf(72f, colH) + 20
    val top = high / 2 - colH / 2
    val lineTop = top + metrics(title).h + 2
    val plusO = GoalMotion.kf(prog, 42f to 0f, 48f to 1f, 70f to 1f, 75f to 0f)
    val plusY = GoalMotion.kf(prog, 42f to 6f, 48f to 0f, 70f to 0f, 75f to -6f)
    val out = ArrayList<Item>()
    if (style.background) out += capsule(area(0f, 0f, wide, high), style.backgroundColor)
    out += ringBlock(shown, swap, 46f, high / 2)
    text(title.centred(), 96f, top + metrics(title).h / 2)?.let { out += it }
    out += flip(spec, amount, 96f, lineTop + asc, -1)
    text(tail, 96 + flipWidth(spec, amount) + 4, lineTop + asc)?.let { out += it }
    text(delta.centred().fading(plusO), 96f, lineTop + lineH + 2 + metrics(delta).h / 2 + plusY)?.let { out += it }
    return GoalPiece(out, wide, high)
}

private fun GoalDraw.ringBlock(shown: Float, swap: Float, cx: Float, cy: Float): List<Item> {
    val pulse = GoalMotion.kf(prog, 58f to 0.9f, 75f to 1.45f)
    val pulseO = GoalMotion.kf(prog, 58f to 0f, 61f to 0.8f, 75f to 0f)
    val cometO = GoalMotion.kf(prog, 41f to 0f, 43f to 1f, 60f to 1f, 68f to 0f)
    val ang = 2 * Math.PI * shown
    val x = cx + 30 * sin(ang).toFloat()
    val y = cy - 30 * cos(ang).toFloat()
    val out = ArrayList<Item>()
    if (pulseO > 0.001f) out += outline(cx, cy, 36 * pulse, 2 * pulse, accent, pulseO)
    out += outline(cx, cy, 32.5f, 5f, style.trackColor)
    out += arc(30f, 5f, shown, cx, cy, accent)
    if (cometO > 0.001f) {
        out +=
            listOfNotNull(glow(x, y, 5f, accent, 11f, cometO), glow(x, y, 5f, accent, 5f, cometO), disc(x, y, 5f, GoalDraw.WHITE, cometO))
    }
    out += flip(GoalFlip(goalPct(input.from), goalPct(input.to), swap, minWidth = 40f), run("", 17f, 800).centred(), cx, cy, 0)
    return out
}

/** Dot wave: title and amounts over a row of 24 dots that ripple and pop on a donation. */
fun GoalDraw.dots(): GoalPiece {
    val count = 24
    val nb = (input.from * count).roundToInt().coerceIn(0, count)
    val na = (input.to * count).roundToInt().coerceIn(nb, count)
    val title = run(input.title.uppercase(), 11f, 600).tracked(1.76f).fading(0.65f)
    val amount = run("", 15f, 800)
    val tail = run("/ " + input.targetText, 13f, 600).fading(0.55f)
    val spec = GoalFlip(input.beforeText, input.afterText, GoalMotion.lp(prog, 52f, 58f), minWidth = 40f)
    val group = flipWidth(spec, amount) + 4 + metrics(tail).w
    val inner = maxOf(metrics(title).w + 20 + group, 307f)
    val asc = maxOf(metrics(title).asc, metrics(amount).asc, metrics(tail).asc)
    val headH = asc + maxOf(metrics(title).h - metrics(title).asc, metrics(amount).h - metrics(amount).asc)
    val wide = inner + 32
    val high = 12 + headH + 9 + 8 + 12
    val plusO = GoalMotion.kf(prog, 48f to 0f, 54f to 1f, 66f to 1f, 75f to 0f)
    val plusX = GoalMotion.kf(prog, 48f to -6f, 54f to 0f)
    val plus = run(if (input.deltaText.isEmpty()) "" else "+" + input.deltaText, 12f, 800).colored(accent).centred().fading(plusO)
    val right = 16 + inner
    val out = ArrayList<Item>()
    if (style.background) out += pill(area(0f, 0f, wide, high), 14f, style.backgroundColor)
    text(title, 16f, 12 + asc)?.let { out += it }
    out += flip(spec, amount, right - metrics(tail).w - 4, 12 + asc, 1)
    text(tail, right - metrics(tail).w, 12 + asc)?.let { out += it }
    text(plus, right - group - 8 + plusX, 12 + headH / 2, 1)?.let { out += it }
    (0 until count).forEach { out += dot(it, nb, na, 20f + it * 13, 12 + headH + 9 + 4) }
    return GoalPiece(out, wide, high)
}

/** Lit dots ripple (scale + brightness, each a little after the last); new dots pop white, then settle to the accent. */
private fun GoalDraw.dot(index: Int, nb: Int, na: Int, cx: Float, cy: Float): List<Item> {
    val lit = index < nb
    val isNew = index in nb until na
    val late = index * 0.58f
    val newLate = (index - nb).coerceIn(0, 8).toFloat()
    val wave = if (lit) GoalMotion.kf(prog, 40f to 0f, 44f to 1f, 50f to 0f, delay = late) else 0f
    val pop = if (isNew) GoalMotion.kf(prog, 50f to 1f, 54f to 1.9f, 60f to 1f, delay = newLate) else 1f
    val white = if (isNew) GoalMotion.kf(prog, 50f to 0f, 54f to 1f, delay = newLate) else 0f
    val settled = if (lit) {
        1f
    } else if (isNew) {
        GoalMotion.kf(prog, 54f to 0f, 60f to 1f, delay = newLate)
    } else {
        0f
    }
    val r = 4 * (if (lit) 1 + 0.7f * wave else pop)
    return listOf(
        disc(cx, cy, r, style.trackColor),
        disc(cx, cy, r, GoalDraw.WHITE, white),
        disc(cx, cy, r, accent, settled),
        disc(cx, cy, r, GoalDraw.WHITE, 0.3f * wave)
    )
}
