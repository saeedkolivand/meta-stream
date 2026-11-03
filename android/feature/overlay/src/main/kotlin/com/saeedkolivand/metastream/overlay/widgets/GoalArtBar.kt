package com.saeedkolivand.metastream.overlay

import android.graphics.RectF
import kotlin.math.roundToInt

// iOS GoalArtBar: GoalView (the bar) and GoalLiquidView, in their points.

/** The bar: title and "total / target" over a flat capsule bar, other currencies and the percentage under it. */
fun GoalDraw.bar(): GoalPiece {
    val wide = style.width
    val high = style.height
    val size = style.fontSize
    val progress = input.to
    val total = run("${input.afterText} / ${input.targetText}", size, 700, style.face).centred()
    val title = fit(run(input.title, size, 700, style.face).centred(), wide - 32 - 12 - 8 - metrics(total).w)
    val note = run(input.otherText, size * 0.7f, 600, style.face).fading(0.85f).centred()
    val hasNote = style.showOther && input.otherText.isNotEmpty()
    val headH = metrics(title).h
    val gap = size * 0.3f
    val barH = size * 0.6f
    val footH = if (hasNote || style.showPercent) metrics(note).h else 0f
    val top = (high - (headH + gap + barH + gap + footH)) / 2
    val barY = top + headH + gap
    val footY = barY + barH + gap + footH / 2
    val out = ArrayList<Item>()
    if (style.background) out += pill(area(0f, 0f, wide, high), 14f, style.backgroundColor)
    out += listOfNotNull(text(title, 16f, top + headH / 2), text(total, wide - 16, top + headH / 2, 1))
    out += capsule(area(16f, barY, wide - 32, barH), style.trackColor)
    val fw = (wide - 32) * progress.coerceIn(0f, 1f)
    if (fw > 0f) out += capsule(area(16f, barY, fw, barH), if (input.celebrating) style.textColor else accent)
    if (hasNote) text(note, 16f, footY)?.let { out += it }
    if (style.showPercent) text(note.with("${(progress * 100).roundToInt()}%"), wide - 16, footY, 1)?.let { out += it }
    return GoalPiece(out, wide, high)
}

/** Liquid: title and amounts over a capsule tank whose fill has waves, bubbles and a splash ring. */
fun GoalDraw.liquid(): GoalPiece {
    val swap = GoalMotion.seg(prog, 0.2f, 0.5f)
    val filled = level(GoalMotion.move(prog))
    val title = run(input.title, 17f, 700, "Unbounded")
    val amount = run("", 17f, 800)
    val tail = amount.with("/ " + input.targetText).fading(0.77f)
    val ink = maxOf(metrics(title).asc, metrics(amount).asc)
    val head = ink + maxOf(metrics(title).h - metrics(title).asc, metrics(amount).h - metrics(amount).asc)
    val top = (76 - (head + 7 + 34)) / 2
    val spec = GoalFlip(input.beforeText, input.afterText, swap)
    val amountRight = 410 - metrics(tail).w - 8
    val titleRoom = amountRight - flipWidth(spec, amount) - 8 - 8 - 10
    val out = ArrayList<Item>()
    if (style.background) out += pill(area(0f, 0f, 420f, 76f), 14f, style.backgroundColor)
    text(fit(title, titleRoom), 10f, top + ink)?.let { out += it }
    out += flip(spec, amount, amountRight, top + ink, 1)
    text(tail, 410f, top + ink, 1)?.let { out += it }
    out += tank(filled, swap).moved(10f, top + head + 7)
    return GoalPiece(out, 420f, 76f)
}

/** The tank in its own 400 x 34 points. ponytail: no 8% white rim (needs a shape subtract). */
private fun GoalDraw.tank(fraction: Float, swap: Float): List<Item> {
    val wide = 400f
    val high = 34f
    val fw = wide * fraction
    val phase = (prog * 64) % 64
    val splashT = GoalMotion.seg(prog, 0.1f, 1f)
    val splash = if (splashT < 0.17f) splashT / 0.17f * 0.9f else 0.9f * (1 - (splashT - 0.17f) / 0.83f)
    val grow = 0.4f + 1.2f * splashT
    val water = ArrayList<Item>()
    water += fill(area(0f, 7f, fw, high - 7), accent)
    water += wave(phase, accent, 1f, 0f)
    water += wave((96 - phase) % 64, GoalDraw.WHITE, 0.45f, 2f)
    water += (0 until 6).mapNotNull { bubble(it, fw, high) }
    val out = ArrayList<Item>()
    out += capsule(area(0f, 0f, wide, high), style.trackColor)
    if (fw > 0f) out += water.within(area(0f, 0f, fw, high), high / 2)
    if (splash > 0.001f) out += outline(fw, 17f, 14 * grow, 2 * grow, GoalDraw.WHITE, splash)
    if (style.showPercent) {
        out += flip(GoalFlip(goalPct(input.from), goalPct(input.to), swap), run("", 14f, 800).centred(), wide - 12, 17f, 1)
    }
    return out.within(area(0f, 0f, wide, high), high / 2)
}

/** The crest strip slid by [phase], tinted. */
private fun GoalDraw.wave(phase: Float, color: Int, alpha: Float, y: Float) =
    Item(RectF(-64 + phase, y, 448 + phase, y + 16), pen.wave, color, alpha)

private fun GoalDraw.bubble(index: Int, fw: Float, high: Float): Item? {
    val life = (prog * 0.9f + index * 0.17f) % 1
    val fade = if (life < 0.2f) life / 0.2f * 0.8f else 0.8f * (1 - life) / 0.8f
    if (fade < 0.001f || fw <= 0f) return null
    val k = 0.6f + 0.4f * life
    return outline(fw * (0.1f + 0.16f * index), high - 6 - 30 * life, 3 * k, 1.5f * k, GoalDraw.WHITE, 0.7f * fade)
}
