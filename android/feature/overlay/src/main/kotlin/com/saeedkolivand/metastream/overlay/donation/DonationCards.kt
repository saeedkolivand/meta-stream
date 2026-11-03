package com.saeedkolivand.metastream.overlay

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

private const val WHITE = -1
private const val INK = 0xFF0B0C0F.toInt()
private const val SOFT = 0xFFC8C9D0.toInt()

/** A rounded-rect outline [w] x [h] with stroke [stroke] and corner [r], white (tinted) or [color] with a glow. */
private fun outline(w: Float, h: Float, r: Float, stroke: Float, color: Int = WHITE, glowPx: Float = 0f): Txt {
    val pad = stroke + glowPx * 1.5f
    val bmp = newBitmap(w + 2 * pad, h + 2 * pad)
    val p = fillPaint(color).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        if (glowPx > 0f) setShadowLayer(glowPx, 0f, 0f, color)
    }
    Canvas(bmp).drawRoundRect(RectF(pad, pad, pad + w, pad + h), r, r, p)
    return Txt(bmp, w + 2 * pad, h + 2 * pad)
}

/** A dark card pops in with a ring pulse and 18 coins flying out; the amount's digits roll up like an odometer (iOS). */
fun coinBurst(i: DonationInfo, look: DonationLook, b: Board): (Float) -> List<Item> {
    val acc = look.accent(0xFFF5C542)
    val label = ink("${i.name.uppercase().take(24)} DONATED", b.len(18f), 700, acc, 0.2f, face = "Manrope")
    val amount = ink(i.amount, b.len(76f), 700, WHITE, face = "Unbounded")
    val msg = ink(i.message, b.len(22f), 400, SOFT, face = "Manrope")
    val initial = ink(i.initial, b.len(40f), 700, INK, face = "Unbounded")
    // Odometer: digits 0-9 rasterised once; each digit column scrolls 10 + d digit heights, the next 0.07 s behind (the alert runs 6 s).
    val digits = (0..9).map { ink("$it", b.len(76f), 700, WHITE, face = "Unbounded") }
    val chars = i.amount.map { c -> if (c.isDigit()) null else ink("$c", b.len(76f), 700, WHITE, face = "Unbounded") }
    val digitW = digits.maxOf { it?.w ?: 0f }
    val colW = maxOf(label?.w ?: 0f, amount?.w ?: 0f, minOf(msg?.w ?: 0f, b.len(760f)))
    val cardW = b.len(188f) + colW
    val colH = b.len(107f) + if (msg != null) b.len(36f) else 0f
    val inner = maxOf(b.len(92f), colH)
    val cardH = b.len(52f) + inner
    val card = RectF(b.x(640f) - cardW / 2, b.y(84f), b.x(640f) + cardW / 2, b.y(84f) + cardH)
    val cx = card.centerX()
    val cy = card.centerY()
    val colX = card.left + b.len(144f)
    val colTop = card.top + b.len(26f) + (inner - colH) / 2
    val pulse = outline(cardW + b.len(36f), cardH + b.len(36f), b.len(44f), b.len(3f))
    return { p ->
        if (p >= 0.93f) {
            emptyList()
        } else {
            buildList {
                val ra = track(p, ::dEaseOut, 0.06f to 0f, 0.08f to 0.9f, 0.26f to 0f)
                if (ra > 0.005f) {
                    val rs = track(p, ::dEaseOut, 0.06f to 0.6f, 0.26f to 1.9f)
                    add(
                        Item(
                            RectF(cx - pulse.w * rs / 2, cy - pulse.h * rs / 2, cx + pulse.w * rs / 2, cy + pulse.h * rs / 2),
                            pulse.bmp,
                            acc,
                            ra
                        )
                    )
                }
                for (n in 0 until 18) {
                    val a = n / 18.0 * 2 * PI + 0.2
                    val r = 260f + (n % 3) * 80f
                    val q = p - (n % 4) * 0.005f
                    val al = track(q, ::dEaseOut, 0.05f to 0f, 0.07f to 1f, 0.32f to 0f)
                    if (al < 0.01f) continue
                    val e = track(q, ::dEaseOut, 0.05f to 0f, 0.32f to 1f)
                    val x = cx + b.len((cos(a) * r * e).toFloat())
                    val y = cy + b.len((sin(a) * r * 0.6 * e).toFloat())
                    val rad = b.len(14f) * (0.3f + 0.7f * e)
                    add(disc(x, y, rad, acc, al))
                    add(ring(x, y, rad, 9f / 14, 0xFF000000.toInt(), al * 0.22f))
                }
                val g = ArrayList<Item>()
                g += Item(RectF(card), color = WHITE, alpha = 0.09f, radius = b.len(30f))
                g += Item(RectF(card.left + 1, card.top + 1, card.right - 1, card.bottom - 1), color = INK, radius = b.len(29f))
                val sx = card.left + b.len(90f * track(p, ::dEaseInOut, 0.12f to -1.6f, 0.26f to 4.2f))
                g +=
                    Item(
                        RectF(sx, card.top, sx + b.len(90f), card.bottom),
                        color = WHITE,
                        alpha = 0.12f,
                        clip = RectF(card),
                        clipRadius = b.len(30f)
                    )
                val ax = card.left + b.len(72f)
                g += disc(ax, cy, b.len(46f), acc)
                initial?.let { g += it.at(ax, cy) }
                label?.let { g += it.at(colX, colTop + b.len(12.5f), -1) }
                if (amount != null) {
                    val lineH = b.len(76f)
                    val mid = colTop + b.len(69f)
                    val clip = RectF(colX, mid - lineH / 2, colX + amount.w * 1.5f, mid + lineH / 2)
                    var x = colX
                    var di = 0
                    i.amount.forEachIndexed { n, c ->
                        val d = c.digitToIntOrNull()
                        val w = if (d != null) digitW else chars[n]?.w ?: 0f
                        if (d == null) {
                            chars[n]?.let { g += it.at(x, mid, -1) }
                        } else {
                            val o = (10 + d) * track(p - di * 0.07f / 6f, ::dEaseOut, 0.08f to 0f, 0.36f to 1f)
                            val k0 = o.toInt()
                            val f = o - k0
                            for (k in k0..(if (f > 0.001f) k0 + 1 else k0)) {
                                digits[k % 10]?.at(x + w / 2, mid + (k - k0 - f) * lineH)?.let { g += Item(it.rect, it.image, clip = clip) }
                            }
                            di++
                        }
                        x += w
                    }
                }
                msg?.let { g += it.at(colX, colTop + b.len(125f), -1, maxW = b.len(760f)) }
                val k = track(p, ::dBack, 0.04f to 0.6f, 0.11f to 1f, 0.86f to 1f, 0.93f to 0.9f)
                val al = track(p, ::dLinear, 0.04f to 0f, 0.07f to 1f, 0.86f to 1f, 0.93f to 0f)
                addAll(g.by(Tf(cx, cy, k, alpha = al)))
            }
        }
    }
}

/** A neon tube panel flickers on; name and amount glow; it flickers off. */
fun neon(i: DonationInfo, look: DonationLook, b: Board): (Float) -> List<Item> {
    val a = look.accent(0xFFFF3EA5)
    val sec = look.second(0xFF3EE8FF)
    val panel = b.rect(300f, 80f, 680f, 340f)
    val tube = outline(panel.width(), panel.height(), b.len(28f), b.len(4f), a, b.len(16f))
    val head = ink("NEW DONATION", b.len(20f), 700, sec, 0.3f, glowPx = b.len(8f), glow = sec, face = "TiltNeon")
    val name = ink(i.name, b.len(48f), 700, WHITE, glowPx = b.len(12f), glow = a, face = "TiltNeon")
    val amount = ink(i.amount, b.len(92f), 700, sec, glowPx = b.len(18f), glow = sec, face = "TiltNeon")
    val msg = ink(i.message, b.len(24f), 400, 0xFFE6E6F0.toInt(), face = "Vazirmatn")
    fun power(p: Float) = when {
        p < 0.02f -> 0f
        p < 0.03f -> 1f
        p < 0.05f -> 0.2f
        p < 0.07f -> 1f
        p < 0.08f -> 0.3f
        p < 0.86f -> 1f
        p < 0.87f -> 0.3f
        p < 0.88f -> 1f
        p < 0.90f -> 0f
        p < 0.92f -> 0.6f
        else -> 0f
    }
    val mx = panel.centerX()
    return { p ->
        val on = power(p)
        val txt = power(p - 0.03f).coerceAtMost(on)
        val box = track(p, ::dLinear, 0f to 0f, 0.02f to 1f, 0.9f to 1f, 0.93f to 0f)
        buildList {
            add(Item(RectF(panel), color = 0xFF0A0A12.toInt(), alpha = 0.88f * box, radius = b.len(28f)))
            if (on >
                0f
            ) {
                add(
                    Item(
                        RectF(mx - tube.w / 2, panel.centerY() - tube.h / 2, mx + tube.w / 2, panel.centerY() + tube.h / 2),
                        tube.bmp,
                        alpha = on
                    )
                )
            }
            if (txt > 0f) {
                head?.let { add(it.at(mx, b.y(140f), alpha = txt)) }
                name?.let { add(it.at(mx, b.y(205f), alpha = txt, maxW = b.len(620f))) }
                amount?.let { add(it.at(mx, b.y(292f), alpha = txt * (0.88f + 0.12f * sin(p * 60f)), maxW = b.len(640f))) }
                msg?.let { add(it.at(mx, b.y(375f), alpha = txt, maxW = b.len(600f))) }
            }
        }
    }
}

/** Greedy word wrap by characters (the receipt is monospace), long words cut, an ellipsis past [maxLines]. */
fun wrap(s: String, n: Int, maxLines: Int): List<String> {
    val lines = ArrayList<String>()
    var cur = ""
    for (w0 in s.split(' ').filter { it.isNotEmpty() }) {
        var w = w0
        while (w.length > n) {
            if (cur.isNotEmpty()) lines += cur.also { cur = "" }
            lines += w.take(n)
            w = w.drop(n)
        }
        cur = if (cur.isEmpty()) {
            w
        } else if (cur.length + 1 + w.length <= n) {
            "$cur $w"
        } else {
            w.also { lines += cur }
        }
    }
    if (cur.isNotEmpty()) lines += cur
    if (lines.size > maxLines) return lines.take(maxLines - 1) + (lines[maxLines - 1].take(n - 1) + "…")
    return lines
}

/** A paper receipt prints down out of a slot, holds, and is pulled back up. */
fun receipt(i: DonationInfo, look: DonationLook, b: Board): (Float) -> List<Item> {
    val ink0 = 0xFF1A1A1A.toInt()
    val dim = 0xFF77736B.toInt()
    val acc = look.accent(0xFF1A1A1A)
    val left = b.x(844f)
    val right = b.x(1176f)
    val mid = b.x(1010f)
    val rows = ArrayList<Pair<Float, (Float) -> List<Item>>>() // height, items at that row's centre y
    fun gap(h: Float) = rows.add(b.len(h) to { _ -> emptyList() })
    fun center(t: String, size: Float, weight: Int, color: Int, tracking: Float = 0f) {
        val x = ink(t, b.len(size), weight, color, tracking, mono = true) ?: return
        rows += b.len(size * 1.5f) to { y -> listOf(x.at(mid, y, maxW = right - left)) }
    }
    fun pair(k: String, v: String) {
        if (v.isEmpty()) return
        val kx = ink(k, b.len(16f), 400, dim, mono = true)!!
        val vx = ink(v, b.len(16f), 700, ink0, mono = true)!!
        rows += b.len(26f) to { y -> listOf(kx.at(left, y, -1), vx.at(right, y, 1, maxW = right - left - kx.w - b.len(12f))) }
    }
    fun dashes() = center("- ".repeat(16), 14f, 400, dim)
    center("METASTREAM", 26f, 700, ink0, 0.1f)
    center("DONATION RECEIPT", 14f, 400, dim, 0.2f)
    dashes()
    pair("DATE", i.date)
    pair("TIME", i.time)
    pair("FROM", i.name.uppercase())
    dashes()
    center(i.amount, 42f, 700, acc)
    pair("RATE", i.rate)
    pair("TO GOAL", i.toGoal)
    if (i.message.isNotEmpty()) {
        dashes()
        for (line in wrap(i.message, 28, 4)) {
            val x = ink(line, b.len(16f), 400, ink0, mono = true) ?: continue
            rows += b.len(24f) to { y -> listOf(x.at(left, y, -1, maxW = right - left)) }
        }
    }
    dashes()
    pair("SOURCE", i.source)
    gap(8f)
    // barcode: bar widths from the name, so the same donor prints the same code
    var seed = i.name.fold(7) { h, c -> (h * 31 + c.code) % 9973 }
    val bars = (0 until 34).map {
        seed = (seed * 1103 + 12345) % 9973
        1 + seed % 3
    }
    rows += b.len(56f) to { y ->
        var x = mid - b.len(bars.sum() * 2.2f) / 2
        bars.mapIndexedNotNull { n, w ->
            val bw = b.len(w * 1.6f)
            Item(RectF(x, y - b.len(24f), x + bw, y + b.len(24f)), color = ink0).takeIf { n % 2 == 0 }.also { x += bw + b.len(w * 0.6f) }
        }
    }
    center("THANK YOU", 18f, 700, ink0, 0.3f)
    gap(14f)
    val paperH = minOf(rows.sumOf { it.first.toDouble() }.toFloat() + b.len(30f), b.len(682f))
    val top = b.y(38f)
    val slot = RectF(b.x(806f), top - b.len(8f), b.x(1214f), top + b.len(4f))
    return { p ->
        val e = track(p, ::dEaseOut, 0.04f to 0f, 0.22f to 1f, 0.86f to 1f, 0.96f to 0f)
        val alpha = track(p, ::dLinear, 0f to 0f, 0.03f to 1f, 0.94f to 1f, 0.98f to 0f)
        val y0 = top - paperH * (1 - e)
        val clip = RectF(b.x(820f), top, b.x(1200f), top + paperH)
        buildList {
            add(Item(RectF(b.x(820f), y0, b.x(1200f), y0 + paperH), color = 0xFFF6F3EC.toInt(), alpha = alpha, clip = clip))
            var y = y0 + b.len(15f)
            for ((h, items) in rows) {
                items(y + h / 2).forEach { add(Item(it.rect, it.image, it.color, alpha, clip = clip)) }
                y += h
            }
            add(Item(slot, color = 0xFF222222.toInt(), alpha = alpha, radius = b.len(6f)))
        }
    }
}
