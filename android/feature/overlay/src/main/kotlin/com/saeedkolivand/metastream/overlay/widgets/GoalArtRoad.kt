package com.saeedkolivand.metastream.overlay

import android.graphics.RectF
import kotlin.math.roundToInt

// iOS GoalArtRoad: GoalRoadView and GoalSegmentsView. Pin and car are rasters drawn once (GoalPen) and only moved.

/** Road trip: "Road to: title" and amounts over a road with 25/50/75 % pins, a finish flag and the car at the fill. */
fun GoalDraw.road(): GoalPiece {
    val title = run(if (input.celebrating) input.title else "Road to: ${input.title}", 14f, 700, "Unbounded")
    val amount = run("", 14f, 800)
    val tail = amount.with("/ " + input.targetText).colored(GoalDraw.DIM)
    val ink = maxOf(metrics(title).asc, metrics(amount).asc)
    val head = ink + maxOf(metrics(title).h - metrics(title).asc, metrics(amount).h - metrics(amount).asc)
    val top = (74 - (head + 2 + 40)) / 2
    val spec = GoalFlip(input.beforeText, input.afterText, GoalMotion.seg(prog, 0.5f, 0.8f))
    val amountRight = 478 - metrics(tail).w - 5
    val room = amountRight - flipWidth(spec, amount) - 8 - 8 - 18
    val out = ArrayList<Item>()
    if (style.background) out += pill(area(0f, 0f, 500f, 74f), 16f, style.backgroundColor)
    text(fit(title, room), 18f, top + ink)?.let { out += it }
    out += flip(spec, amount, amountRight, top + ink, 1)
    text(tail, 478f, top + ink, 1)?.let { out += it }
    out += roadStrip(460f).moved(18f, top + head + 2)
    return GoalPiece(out, 500f, 74f)
}

/** The 460 x 40 road in its own points. */
private fun GoalDraw.roadStrip(wide: Float): List<Item> {
    val cx = wide * level(GoalMotion.move(prog))
    val puff = if (prog < 0.2f) prog / 0.2f * 0.7f else 0.7f * (1 - (prog - 0.2f) / 0.8f)
    val lane = ArrayList<Item>()
    lane += fill(area(0f, 26f, wide, 9f), style.trackColor)
    var x = 0f
    while (x < wide) {
        lane += fill(area(x, 30f, minOf(12f, wide - x), 1f), GoalDraw.WHITE, 0.35f)
        x += 24
    }
    if (cx > 0f) lane += fill(area(0f, 26f, cx, 9f), accent)
    val out = ArrayList<Item>()
    out += lane
    (0..2).forEach { out += pin(it, wide) }
    out += flag(wide - 12)
    if (puff > 0.001f) out += disc(cx - 36 - 22 * prog + 4, 25 - 6 * prog + 4, 4 * (0.4f + prog), GoalDraw.STEEL, puff)
    out += Item(area(cx - 30, 13f, 36f, 20f), pen.car(accent))
    return out
}

private fun GoalDraw.pin(index: Int, wide: Float): List<Item> {
    val mark = (index + 1) * 0.25f
    val left = wide * mark - 24
    val reached = input.to >= mark - 1e-6f
    val label = run(input.pins.getOrElse(index) { "" }, 10f, 600).colored(GoalDraw.DIM).centred()
    return listOfNotNull(
        text(fit(label, 48f), left + 24, -3 + metrics(label).h / 2, 0),
        Item(area(left + 18, 9f, 12f, 16f), pen.pin, if (reached) accent else 0xFF4A4A4A.toInt()),
        disc(left + 24, 9 + 5.87f, 2.15f, GoalDraw.INK)
    )
}

/** The finish flag: a pole and a 2 x 2 chequered cloth (the lower squares half height, like the board's). */
private fun GoalDraw.flag(left: Float): List<Item> = listOf(pill(area(left + 2, 8f, 2f, 28f), 1f, GoalDraw.STEEL)) +
    (0..3).map { sq ->
        val dark = (sq / 2 + sq % 2) % 2 == 0
        fill(area(left + 4 + (sq % 2) * 6, 8f + (sq / 2) * 6, 6f, if (sq < 2) 6f else 3f), if (dark) GoalDraw.INK else GoalDraw.WHITE)
    }

/** Segments: TITLE, 20 blocks that flash white and settle to the accent, "total / target" and a floating "+delta". */
fun GoalDraw.segments(): GoalPiece {
    val nb = (input.from * 20).roundToInt().coerceIn(0, 20)
    val na = (input.to * 20).roundToInt().coerceIn(nb, 20)
    val mono = "JetBrainsMono"
    val title = run(input.title.uppercase(), 13f, 800, mono).tracked(0.78f).centred()
    val amount = run("", 13f, 800, mono).centred()
    val tail = run("/ " + input.targetText, 13f, 500, mono).fading(0.7f).centred()
    val spec = GoalFlip(input.beforeText, input.afterText, GoalMotion.seg(prog, 0.4f, 0.65f))
    val amountW = flipWidth(spec, amount)
    val titleW = metrics(title).w
    val wide = 14 + titleW + 12 + 197 + 12 + amountW + 5 + metrics(tail).w + 14
    val blocks = 14 + titleW + 12
    val amountX = blocks + 197 + 12 + amountW
    val plus = GoalMotion.seg(prog, 0f, 0.2f) * (1 - GoalMotion.seg(prog, 0.6f, 1f))
    val delta = run(if (input.deltaText.isEmpty()) "" else "+" + input.deltaText, 12f, 800, mono).colored(accent)
    val out = ArrayList<Item>()
    if (style.background) out += pill(area(0f, 1f, wide, 38f), 12f, style.backgroundColor)
    text(fit(title, 480 - (wide - titleW)), 14f, 20f)?.let { out += it }
    out += flip(spec, amount, amountX, 20f, 1)
    text(tail, amountX + 5, 20f)?.let { out += it }
    text(delta.centred().fading(plus), wide + 8, 28 - 18 * prog)?.let { out += it }
    (0 until 20).forEach { out += block(it, nb, na, blocks + it * 10) }
    return GoalPiece(out, 480f, 40f)
}

/** Blocks nb until na are the new ones: flash white and grow, then settle to the accent, each a little after the last. */
private fun GoalDraw.block(index: Int, nb: Int, na: Int, x: Float): List<Item> {
    val isNew = index in nb until na
    val late = prog - minOf(0.35f, 0.05f * (index - nb))
    val flash = if (isNew) GoalMotion.seg(late, 0.2f, 0.35f) else 0f
    val settle = if (index < nb) {
        1f
    } else if (isNew) {
        GoalMotion.seg(late, 0.35f, 0.6f)
    } else {
        0f
    }
    val grow = 1 + 0.6f * (if (isNew) flash - settle else 0f)
    val cell = RectF(x, 20 - 7.5f * grow, x + 7, 20 + 7.5f * grow)
    return listOf(pill(cell, 2f, style.trackColor), pill(RectF(cell), 2f, GoalDraw.WHITE, flash), pill(RectF(cell), 2f, accent, settle))
}
