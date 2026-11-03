package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

private const val WHITE = -1

/** Holo foil: the board's five rainbow bands, turned 25 degrees, drawn once at twice the card's width (it slides). */
private fun foil(w: Float, h: Float, band: Float): Bitmap = newBitmap(w, h).also { bmp ->
    val c = Canvas(bmp)
    c.rotate(25f, w / 2, h / 2)
    val cols = longArrayOf(0xFFFF6AD5, 0xFFFFD36B, 0xFF6BFFB8, 0xFF6BC8FF, 0xFFB46BFF)
    var x = -(w + h)
    var n = 0
    while (x < 2 * w + h) {
        c.drawRect(x, -(w + h), x + band, 2 * h + w, fillPaint(cols[n++ % 5].toInt()))
        x += band
    }
}

/** A white bar turned 25 degrees, for the glare sweep. */
private fun glare(barW: Float, h: Float): Bitmap = newBitmap(barW + h * 0.47f, h).also { bmp ->
    val c = Canvas(bmp)
    c.rotate(25f, bmp.width / 2f, h / 2)
    c.drawRect(bmp.width / 2f - barW / 2, -h, bmp.width / 2f + barW / 2, 2 * h, fillPaint(WHITE))
}

/** A trading card flips in (tier by the dollar value), foil and glare sweep across, sparkles twinkle, it flips away. */
fun holo(i: DonationInfo, look: DonationLook, b: Board): (Float) -> List<Item> {
    val tier = i.tier.coerceIn(0, 2)
    val acc = look.accent(longArrayOf(0xFF6B9BFF, 0xFFC46BFF, 0xFFF5C542)[tier])
    val card = b.rect(120f, 100f, 360f, 510f)
    val inner = b.rect(122f, 102f, 356f, 506f)
    val cx = card.centerX()
    val cy = card.centerY()
    val foilBmp = foil(inner.width() * 2, inner.height(), b.len(71.6f))
    val glareBmp = glare(b.len(70f), inner.height())
    val left = b.x(144f)
    val right = b.x(456f)
    val hash = i.name.fold(7) { h, c -> (h * 31 + c.code) % 9973 }
    val gray = 0xFF8B8D96.toInt()
    val texts = listOfNotNull(
        ink(listOf("RARE", "EPIC", "LEGENDARY")[tier], b.len(15f), 700, acc, 0.18f, face = "Unbounded")?.at(left, b.y(134f), -1),
        ink("No. %04d".format(hash % 999 + 1), b.len(14f), 700, 0xFF9A9CA6.toInt(), face = "Manrope")?.at(right, b.y(134f), 1),
        ink(i.initial, b.len(64f), 700, acc, face = "Unbounded")?.at(b.x(300f), b.y(258f)),
        ink(i.name.uppercase(), b.len(34f), 700, WHITE, face = "Unbounded")?.at(left, b.y(393f), -1, maxW = right - left),
        ink(i.amount, b.len(46f), 700, acc, face = "Unbounded")?.at(left, b.y(451f), -1, maxW = right - left),
        ink(i.message.take(60), b.len(18f), 400, 0xFFC8C9D0.toInt(), face = "Manrope")?.at(left, b.y(500f), -1, maxW = right - left),
        ink(i.source, b.len(13f), 700, gray, 0.14f, face = "Manrope")?.at(left, b.y(577f), -1),
        ink(i.date, b.len(13f), 700, gray, 0.14f, face = "Manrope")?.at(right, b.y(577f), 1)
    )
    val spots = listOf(-20f to 30f, 330f to -16f, 372f to 220f, -34f to 300f, 300f to 470f, 150f to -30f)
    return { p ->
        val ry = track(p, ::dEaseOut, 0f to 540f, 0.12f to -14f, 0.17f to 6f, 0.21f to 0f, 0.5f to -10f, 0.8f to 0f, 0.92f to 90f)
        val alpha = track(p, ::dEaseOut, 0f to 0f, 0.12f to 1f, 0.8f to 1f, 0.92f to 0f)
        val tx = track(p, ::dEaseOut, 0f to -520f, 0.12f to 0f)
        val rz = track(p, ::dEaseOut, 0f to -8f, 0.12f to 0f)
        val ty = track(p, ::dEaseOut, 0.8f to 0f, 0.92f to 40f)
        val sc = track(p, ::dEaseOut, 0.8f to 1f, 0.92f to 0.9f)
        buildList {
            spots.forEachIndexed { n, (sx, sy) ->
                val q = p - n * 0.18f * look.speed / 7
                if (q <= 0.18f) return@forEachIndexed
                val sz = track(q, ::dEaseInOut, 0.18f to 0f, 0.24f to 1.2f, 0.32f to 0.4f, 0.46f to 0f, 0.52f to 1f, 0.6f to 0f)
                val a = track(q, ::dEaseInOut, 0.18f to 0f, 0.24f to 1f, 0.32f to 0f, 0.46f to 0f, 0.52f to 1f, 0.6f to 0f)
                val rot = track(q, ::dEaseInOut, 0.18f to 0f, 0.24f to 45f, 0.32f to 90f, 0.46f to 90f, 0.52f to 45f, 0.6f to 90f)
                addAll(star(b.x(135f + sx), b.y(115f + sy), b.len(15f * sz), rot, a.coerceIn(0f, 1f)))
            }
            val cosA = cos(Math.toRadians(ry.toDouble())).toFloat()
            if (alpha < 0.01f || abs(cosA) < 0.004f) return@buildList
            val r22 = b.len(22f)
            val face = ArrayList<Item>()
            face += Item(RectF(card), color = acc, radius = b.len(24f))
            if (cosA >= 0) {
                face += Item(RectF(inner), color = 0xFF0C0D11.toInt(), radius = r22)
                val fx = inner.left - p * inner.width()
                face +=
                    Item(
                        RectF(fx, inner.top, fx + foilBmp.width, inner.bottom),
                        foilBmp,
                        alpha = 0.3f,
                        clip = RectF(inner),
                        clipRadius = r22
                    )
                val gx = b.x(155f + track(p, ::dEaseInOut, 0f to -140f, 0.2f to -140f, 0.34f to 224f, 0.55f to -140f, 0.68f to 224f))
                face +=
                    Item(
                        RectF(gx - glareBmp.width / 2f, inner.top, gx + glareBmp.width / 2f, inner.bottom),
                        glareBmp,
                        alpha = 0.28f,
                        clip = RectF(inner),
                        clipRadius = r22
                    )
                face += Item(b.rect(144f, 158f, 312f, 200f), color = 0xFF17181D.toInt(), radius = b.len(16f))
                face += ring(b.x(300f), b.y(258f), b.len(66f), 63f / 66, acc)
                face += texts
            } else {
                face += ring(cx, cy, b.len(75f), 65f / 75, 0xFF0C0D11.toInt())
            }
            addAll(face.by(Tf(cx, cy, abs(cosA) * sc, sc, rz, b.len(tx), b.len(ty), alpha)))
        }
    }
}

/** 24 white wedges (3 degrees on, 12 off) under a radial mask: clear to 18%, full at 34%, clear at 70%. Drawn once. */
private fun rays(side: Float): Bitmap = newBitmap(side, side).also { bmp ->
    val c = Canvas(bmp)
    val m = side / 2
    val box = RectF(-m, -m, 3 * m, 3 * m)
    val white = fillPaint(WHITE)
    for (n in 0 until 24) c.drawArc(box, n * 15f, 3f, true, white)
    val mask = Paint().apply {
        shader =
            RadialGradient(m, m, m * 1.414f, intArrayOf(0, 0, WHITE, 0, 0), floatArrayOf(0f, 0.18f, 0.34f, 0.7f, 1f), Shader.TileMode.CLAMP)
        xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
    }
    c.drawRect(0f, 0f, side, side, mask)
}

/** Rays and rings burst, the amount slams in, the picture shakes, then zooms away. */
fun shockwave(i: DonationInfo, look: DonationLook, b: Board, w: Float, h: Float): (Float) -> List<Item> {
    val acc = look.accent(0xFFFF5A36)
    val side = minOf(b.len(1000f), 1024f) // ponytail: capped at 1024 px and scaled up past that; softer on 4K
    val raysBmp = rays(side)
    val raysW = b.len(1000f)
    val head = ink("NEW TOP DONATION", b.len(18f), 700, acc, 0.3f, face = "Manrope")
    val name = ink(i.name.uppercase(), b.len(40f), 600, WHITE, 0.32f, face = "Unbounded")
    val top = ink(i.amount, b.len(150f), 700, WHITE, face = "Unbounded")
    val shadow = ink(i.amount, b.len(150f), 700, acc, face = "Unbounded")
    val msg = ink(i.message.take(100), b.len(26f), 400, 0xFFD4D5DC.toInt(), face = "Manrope")
    val mx = b.x(640f)
    return { p ->
        val g = ArrayList<Item>()
        val ro = track(p, ::dLinear, 0.03f to 0f, 0.08f to 0.55f, 0.84f to 0.4f, 0.92f to 0f)
        if (ro > 0.001f) {
            val s = raysW * track(p, ::dLinear, 0.03f to 0.6f, 0.08f to 1f, 0.84f to 1.05f, 0.92f to 1.3f) / 2
            val rr = track(p, ::dLinear, 0.03f to 0f, 0.08f to 8f, 0.84f to 40f, 0.92f to 46f)
            g += Item(RectF(mx - s, b.y(220f) - s, mx + s, b.y(220f) + s), raysBmp, acc, ro, rotation = rr)
        }
        for (n in 0 until 3) {
            val q = p - floatArrayOf(0f, 0.12f, 0.26f)[n] * look.speed / 7
            if (q <= 0.03f) continue
            val a = track(q, ::dEaseOut, 0.03f to 0f, 0.04f to 1f, 0.3f to 0f)
            val s = track(q, ::dEaseOut, 0.03f to 0.15f, 0.3f to 5.5f)
            g += ring(mx, b.y(280f), b.len(100f * s), (100f - (10 - n * 3)) / 100, acc, a)
        }
        head?.let { g += it.at(mx, b.y(122.5f)) }
        val na = track(p, ::dEaseOut, 0.06f to 0f, 0.16f to 1f)
        if (na > 0.001f) name?.let { g += it.at(mx, b.y(178f), alpha = na, maxW = b.len(1100f)) }
        val aa = track(p, ::dLinear, 0.025f to 0f, 0.06f to 1f)
        if (aa > 0.001f) {
            val k = track(p, ::dEaseOut, 0.025f to 3.4f, 0.06f to 0.92f, 0.085f to 1f)
            shadow?.let { g += it.at(mx, b.y(302f), alpha = aa, maxW = b.len(1100f), k = k) }
            top?.let { g += it.at(mx, b.y(296f), alpha = aa, maxW = b.len(1100f), k = k) }
        }
        val ma = track(p, ::dEaseOut, 0.14f to 0f, 0.22f to 1f)
        if (ma >
            0.001f
        ) {
            msg?.let { g += it.at(mx, b.y(407f + track(p, ::dEaseOut, 0.14f to 16f, 0.22f to 0f)), alpha = ma, maxW = b.len(760f)) }
        }
        val dx = track(p, ::dLinear, 0.03f to 0f, 0.04f to -14f, 0.05f to 12f, 0.06f to -9f, 0.07f to 8f, 0.08f to -4f, 0.095f to 0f)
        val dy = track(p, ::dLinear, 0.03f to 0f, 0.04f to 8f, 0.05f to -10f, 0.06f to -6f, 0.07f to 7f, 0.08f to 3f, 0.095f to 0f)
        val es = track(p, ::dEaseIn, 0.84f to 1f, 0.93f to 1.35f)
        val eo = track(p, ::dEaseIn, 0.84f to 1f, 0.93f to 0f)
        val fl = track(p, ::dEaseOut, 0.02f to 0f, 0.03f to 0.85f, 0.09f to 0f)
        g.by(Tf(mx, b.y(360f), es, dx = b.len(dx), dy = b.len(dy), alpha = eo)) + Item(RectF(0f, 0f, w, h), alpha = fl)
    }
}

private fun bezier(t: Float, p: List<Pair<Float, Float>>): Pair<Float, Float> {
    val u = 1 - t
    val k = floatArrayOf(u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
    return p.indices.sumOf { (k[it] * p[it].first).toDouble() }.toFloat() to p.indices.sumOf { (k[it] * p[it].second).toDouble() }.toFloat()
}

/**
 * A chip pops bottom-left, shrinks into an orb that flies into the goal bar, which surges from before to after.
 * ponytail: the bar sits at the board's top centre; following the scene's Goal widget comes with that widget.
 */
fun goalSurge(i: DonationInfo, look: DonationLook, b: Board, w: Float, h: Float): (Float) -> List<Item> {
    val acc = look.accent(0xFF53FC18)
    val ub = Board.of(w, h, DonationKind.GoalSurge.focus, null)
    val box = ub.rect(280f, 40f, 720f, 120f)
    val f = box.width() / 720f
    val ox = box.left
    val oy = box.centerY() - 60 * f
    fun px(x: Float) = ox + x * f
    fun py(y: Float) = oy + y * f
    val goal = i.goal
    val target = if (goal == null) ub.x(640f) to ub.y(100f) else px(16 + 688 * goal.to) to py(66.5f)
    val bar = goal?.let { goalBar(it, acc, f, ::px, ::py) }
    val ink0 = 0xFF0B0C0F.toInt()
    val chip = listOfNotNull(
        Item(b.rect(80f, 560f, 300f, 80f), color = acc, radius = b.len(40f)),
        Item(b.rect(82f, 562f, 296f, 76f), color = ink0, radius = b.len(38f)),
        disc(b.x(122f), b.y(600f), b.len(30f), acc),
        ink(i.initial, b.len(26f), 700, ink0, face = "Manrope")?.at(b.x(122f), b.y(600f)),
        ink(i.name, b.len(16f), 600, 0xFFB9BAC2.toInt(), face = "Manrope")?.at(b.x(166f), b.y(585f), -1, maxW = b.len(190f)),
        ink("+" + i.amount, b.len(30f), 700, WHITE)?.at(b.x(166f), b.y(611f), -1, maxW = b.len(190f))
    )
    val path = listOf(b.x(230f) to b.y(600f), b.x(170f) to b.y(340f), b.x(540f) to b.y(330f), target)
    return { p ->
        buildList {
            bar?.let { addAll(it(p)) }
            val ringA = track(p, ::dEaseOut, 0.49f to 0f, 0.51f to 1f, 0.64f to 0f)
            if (ringA >
                0.01f
            ) {
                add(ring(target.first, target.second, b.len(20f * track(p, ::dEaseOut, 0.49f to 0.3f, 0.64f to 3.2f)), 0.8f, acc, ringA))
            }
            val bitA = track(p, ::dEaseOut, 0.49f to 0f, 0.51f to 1f, 0.66f to 0f)
            if (bitA > 0.01f) {
                val d = track(p, ::dEaseOut, 0.49f to 0f, 0.66f to 1f)
                for (n in 0 until 10) {
                    val a = n / 10.0 * 2 * PI
                    add(
                        disc(
                            target.first + (cos(a) * b.len(90f) * d).toFloat(),
                            target.second + (sin(a) * b.len(60f) * d).toFloat(),
                            b.len(4f),
                            acc,
                            bitA
                        )
                    )
                }
            }
            for (n in 0 until 4) {
                val q = p - n * 0.05f * look.speed / 6
                val op = track(q, ::dLinear, 0.31f to 0f, 0.33f to 1f, 0.5f to 1f, 0.51f to 0f)
                if (op < 0.01f) continue
                val (x, y) = bezier(dEaseInOut(((q - 0.33f) / 0.17f).coerceIn(0f, 1f)), path)
                val r = b.len(floatArrayOf(30f, 20f, 14f, 9f)[n]) / 2
                val a = op * floatArrayOf(1f, 0.55f, 0.4f, 0.25f)[n]
                add(disc(x, y, r * 2.1f, acc, a * 0.25f))
                add(disc(x, y, r, acc, a))
            }
            val ca = track(p, ::dBack, 0.03f to 0f, 0.08f to 1f, 0.27f to 1f, 0.33f to 0f).coerceIn(0f, 1f)
            val cs = track(p, ::dBack, 0.03f to 0.5f, 0.08f to 1.05f, 0.11f to 1f, 0.27f to 1f, 0.33f to 0.08f).coerceAtLeast(0f)
            if (ca > 0.01f && cs > 0.005f) {
                addAll(chip.by(Tf(b.x(230f), b.y(600f), cs, dy = b.len(track(p, ::dBack, 0.03f to 30f, 0.08f to 0f)) * cs, alpha = ca)))
            }
        }
    }
}

/** The goal bar in the board's 720x120 box units ([px]/[py] map them): header, numbers flipping, the fill surging. */
private fun goalBar(g: GoalInfo, acc: Int, f: Float, px: (Float) -> Float, py: (Float) -> Float): (Float) -> List<Item> {
    val box = RectF(px(0f), py(0f), px(720f), py(120f))
    val rx = px(704f)
    val rowY = py(33f)
    val targetT = ink("/ " + g.target, 28 * f, 700, WHITE)
    val numRight = rx - (targetT?.w ?: 0f) - 10 * f
    val title = ink(g.title, 28 * f, 700, WHITE)?.at(px(16f), rowY, -1, maxW = numRight - 88 * f - px(16f))
    val before = ink(g.before, 28 * f, 700, WHITE)
    val after = ink(g.after, 28 * f, 700, WHITE)
    val dim = 0xD9FFFFFF.toInt()
    val fromT = ink("${(g.from * 100).toInt()}%", 20 * f, 600, dim)
    val toT = ink("${(g.to * 100).toInt()}%", 20 * f, 600, dim)
    val trackR = RectF(px(16f), py(58f), px(704f), py(75f))
    return { p ->
        val glow = track(p, ::dEaseOut, 0.49f to 0f, 0.52f to 1f, 0.68f to 0f)
        val oldA = track(p, ::dLinear, 0.5f to 1f, 0.51f to 0f, 0.96f to 0f, 0.98f to 1f)
        val newA = track(p, ::dBack, 0.5f to 0f, 0.54f to 1f, 0.95f to 1f, 0.97f to 0f).coerceIn(0f, 1f)
        val dy = track(p, ::dBack, 0.5f to 14f, 0.54f to 0f) * f
        val l = ArrayList<Item>()
        if (glow > 0.01f) {
            l +=
                Item(
                    RectF(box.left - 10 * f, box.top - 10 * f, box.right + 10 * f, box.bottom + 10 * f),
                    color = acc,
                    alpha = glow * 0.25f,
                    radius =
                    24 * f
                )
            l +=
                Item(
                    RectF(box.left - 3 * f, box.top - 3 * f, box.right + 3 * f, box.bottom + 3 * f),
                    color = acc,
                    alpha = glow,
                    radius =
                    17 * f
                )
        }
        l += Item(RectF(box), color = 0xFF101014.toInt(), alpha = 0.85f, radius = 14 * f)
        title?.let { l += it }
        targetT?.let { l += it.at(rx, rowY, 1) }
        before?.let { l += it.at(numRight, rowY, 1, oldA) }
        after?.let { l += it.at(numRight, rowY + dy, 1, newA) }
        fromT?.let { l += it.at(rx, py(96.5f), 1, oldA) }
        toT?.let { l += it.at(rx, py(96.5f) + dy, 1, newA) }
        l += Item(RectF(trackR), color = 0xFF26262B.toInt(), radius = 9 * f)
        val wv = track(p, ::dEaseOut, 0.5f to g.from, 0.58f to g.to, 0.95f to g.to, 0.99f to g.from)
        val fill = RectF(trackR.left, trackR.top, trackR.left + trackR.width() * wv, trackR.bottom)
        if (fill.width() > 0.5f) {
            l += Item(fill, color = acc, radius = 9 * f)
            val ga = track(p, ::dEaseOut, 0.5f to 0f, 0.52f to 1f, 0.66f to 0f)
            if (ga > 0.01f) {
                val gx = fill.left + track(p, ::dEaseOut, 0.5f to -0.2f, 0.66f to 1.1f) * fill.width()
                l += Item(RectF(gx, fill.top, gx + 60 * f, fill.bottom), alpha = 0.7f * ga, clip = RectF(fill), clipRadius = 9 * f)
            }
        }
        l.by(Tf(px(360f), py(60f), 1 + 0.03f * glow))
    }
}
