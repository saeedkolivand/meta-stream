package com.saeedkolivand.metastream.overlay

// iOS GoalArtLine: GoalHairlineView and GoalSparkView, a line with a glowing tip, text above, a drop shadow under it all.

/** Hairline: TITLE and percentage, a big rolling amount, "of target" and a 2 pt line with sweep, tip and "+delta" ghost. */
fun GoalDraw.hairline(): GoalPiece {
    val roll = GoalMotion.lp(prog, 44f, 52f)
    val head = run(input.title.uppercase(), 11f, 700).tracked(2.2f).fading(0.72f)
    val big = run("", 32f, 800).centred()
    val sub = run("of " + input.targetText, 14f, 600).fading(0.6f)
    val pct = GoalFlip(goalPct(input.from), goalPct(input.to), roll, 14f, -14f, 34f)
    val amount = GoalFlip(input.beforeText, input.afterText, roll, 38f, -38f, 96f)
    val row1 = metrics(head).w + if (style.showPercent) 24 + flipWidth(pct, head) else 0f
    val inner = maxOf(340f, row1, flipWidth(amount, big) + 8 + metrics(sub).w)
    val headH = maxOf(metrics(head).h, if (style.showPercent) 14f else 0f)
    val row2 = 8 + headH + 6
    val bar = row2 + 38 + 6
    val base2 = row2 + 19 - metrics(big).h / 2 + metrics(big).asc
    val content = ArrayList<Item>()
    text(fit(head, inner - 24), 12f, 8 + metrics(head).asc)?.let { content += it }
    if (style.showPercent) {
        val pw = flipWidth(pct, head)
        content += flip(pct, head, 12 + inner, 8 + metrics(head).asc, 1).within(area(12 + inner - pw, 8 + metrics(head).h / 2 - 7, pw, 14f))
    }
    content += flip(amount, big, 12f, row2 + 19, -1).within(area(12f, row2, flipWidth(amount, big), 38f))
    text(sub, 12 + flipWidth(amount, big) + 8, base2)?.let { content += it }
    content += hairBar(inner).moved(12f, bar)
    val wide = inner + 24
    val high = bar + 2 + 8
    val out = ArrayList<Item>()
    if (style.background) out += pill(area(0f, 0f, wide, high), 12f, style.backgroundColor)
    out += shadowed(content, 0.55f, 1f)
    return GoalPiece(out, wide, high)
}

/** The 2 pt line: track, accent fill with a white sweep, the bright tip with its glow, and the floating "+delta". */
private fun GoalDraw.hairBar(wide: Float): List<Item> {
    val fw = wide * level(GoalMotion.lp(prog, 40f, 56f))
    val sweepX = GoalMotion.kf(prog, 42f to -0.3f, 64f to 1.05f) * fw
    val sweepO = GoalMotion.kf(prog, 42f to 0f, 46f to 1f, 64f to 0f)
    val tip = GoalMotion.kf(prog, 40f to 1f, 48f to 1.8f, 66f to 1f)
    val glowR = GoalMotion.kf(prog, 40f to 0f, 48f to 8f, 66f to 3f)
    val ghostO = GoalMotion.kf(prog, 42f to 0f, 48f to 1f, 70f to 0f)
    val ghostY = GoalMotion.kf(prog, 42f to 4f, 48f to -6f, 70f to -22f)
    val ghost = run(if (input.deltaText.isEmpty()) "" else "+" + input.deltaText, 13f, 800).colored(accent).centred()
    val out = ArrayList<Item>()
    out += fill(area(0f, 0f, wide, 2f), GoalDraw.WHITE, 0.14f)
    if (fw > 0f) {
        out += capsule(area(0f, 0f, fw, 2f), accent)
        if (sweepO > 0.001f) out += listOf(Item(area(sweepX, 0f, 60f, 2f), pen.sweep, alpha = sweepO)).within(area(0f, 0f, fw, 2f))
    }
    glow(fw, 1f, 3 * tip, accent, glowR)?.let { out += it }
    out += disc(fw, 1f, 3 * tip, GoalDraw.WHITE)
    text(ghost.fading(ghostO), fw + 18, -22 + ghostY + metrics(ghost).h / 2, 1)?.let { out += it }
    return out
}

/** Spark: title and "total / target" over a 4 pt line whose tip flares and throws nine sparks. */
fun GoalDraw.spark(): GoalPiece {
    val title = run(input.title, 13f, 800)
    val amount = run("", 15f, 800)
    val tail = run("/ " + input.targetText, 13f, 600).fading(0.6f)
    val spec = GoalFlip(input.beforeText, input.afterText, GoalMotion.lp(prog, 50f, 56f), minWidth = 40f)
    val group = flipWidth(spec, amount) + 4 + metrics(tail).w
    val inner = maxOf(380f, metrics(title).w + 24 + group)
    val rowAsc = maxOf(metrics(title).asc, metrics(amount).asc, metrics(tail).asc)
    val rowH = rowAsc + maxOf(metrics(title).h - metrics(title).asc, metrics(amount).h - metrics(amount).asc)
    val wide = inner + 24
    val high = 8 + rowH + 10 + 4 + 8
    val line = ArrayList<Item>()
    text(fit(title, inner - group - 24), 12f, 8 + rowAsc)?.let { line += it }
    line += flip(spec, amount, 12 + inner - metrics(tail).w - 4, 8 + rowAsc, 1)
    text(tail, 12 + inner - metrics(tail).w, 8 + rowAsc)?.let { line += it }
    line += sparkBar(inner).moved(12f, 8 + rowH + 10)
    val out = ArrayList<Item>()
    if (style.background) out += pill(area(0f, 0f, wide, high), 12f, style.backgroundColor)
    out += shadowed(line, 0.55f, 1f)
    return GoalPiece(out, wide, high)
}

/** The board's nine particle targets, up and back from the tip. */
private val bits = listOf(
    -26f to -22f, -40f to -8f, -18f to -34f, -48f to -26f, -10f to -18f, -34f to 6f, -22f to 12f, -56f to -4f,
    -6f to -40f
)

private fun GoalDraw.sparkBar(wide: Float): List<Item> {
    val fw = wide * level(GoalMotion.lp(prog, 40f, 52f))
    val flash = GoalMotion.kf(prog, 40f to 0f, 50f to 1f, 66f to 0f)
    val core = GoalMotion.kf(prog, 40f to 1f, 52f to 1.9f, 70f to 1f)
    val coreGlow = GoalMotion.kf(prog, 40f to 5f, 52f to 12f, 70f to 5f)
    val out = ArrayList<Item>()
    out += capsule(area(0f, 0f, wide, 4f), GoalDraw.WHITE, 0.12f)
    if (fw > 0f) out += listOf(capsule(area(0f, 0f, fw, 4f), accent), capsule(area(0f, 0f, fw, 4f), GoalDraw.WHITE, 0.3f * flash))
    glow(fw, 2f, 5 * core, accent, coreGlow)?.let { out += it }
    out += disc(fw, 2f, 5 * core, GoalDraw.WHITE)
    bits.indices.forEach { out += bit(it, fw) }
    return out
}

/** Particle i: appears at the tip, flies out (eased) and shrinks away, each 0.33 loop-% after the last. */
private fun GoalDraw.bit(index: Int, fw: Float): List<Item> {
    val late = index * 0.33f
    val seen = GoalMotion.kf(prog, 50f to 0f, 52f to 1f, 72f to 0f, delay = late)
    if (seen < 0.001f) return emptyList()
    val lin = GoalMotion.kf(prog, 50f to 0f, 72f to 1f, delay = late)
    val ease = 1 - (1 - lin) * (1 - lin)
    val (tx, ty) = bits[index]
    val x = fw + tx * ease
    val y = ty * ease + 2
    val r = 2 * (1 - 0.7f * lin)
    return listOfNotNull(glow(x, y, r, accent, 3f, seen), disc(x, y, r, GoalDraw.WHITE, seen))
}
