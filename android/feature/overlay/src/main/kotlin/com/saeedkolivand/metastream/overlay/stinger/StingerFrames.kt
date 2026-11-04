package com.saeedkolivand.metastream.overlay

import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

const val STINGER_PARAMS = 20

/** One frame for the shader: the kind's scalars [p] (see StingerGlsl), the name's centre/scale/alpha, and whether anything shows. */
class StingerFrame {
    val p = FloatArray(STINGER_PARAMS)
    var on = false
    var nameX = 0f
    var nameY = 0f
    var nameScale = 1f
    var nameAlpha = 0f
}

/** The name's text look per kind: size in board px (x unit), bold, ARGB colour, tracking in em. */
class NameLook(val size: Float, val bold: Boolean, val color: Int, val tracking: Float)

/** Lens, burn (tone) and the rest: the colours the shader reads as uCol[0..4]. */
fun StingerKind.colors(s: StingerStyle): IntArray = when (this) {
    StingerKind.Lens -> intArrayOf(s.tally, if (s.tally == 0xFFE8101E.toInt()) 0xFFFF5A3C.toInt() else mixWhite(s.tally, 0.3))
    StingerKind.Aperture -> intArrayOf(s.ink, mixWhite(s.ink, 0.05), s.accent)
    StingerKind.Route, StingerKind.Liquid -> intArrayOf(s.accent, s.ink)
    StingerKind.Viewfinder -> intArrayOf(s.ink, s.accent)
    StingerKind.Ripple -> intArrayOf(s.accent, mixWhite(s.ink, 0.08), s.accent, s.ink)
    StingerKind.Tunnel -> intArrayOf(s.accent, mixWhite(s.ink, 0.12), mixWhite(s.ink, 0.07), mixWhite(s.ink, 0.03), s.ink)
    StingerKind.Burn -> burnTone(s)
}

/** Film burn: colour, colour, colour, peak and name colour for the tone (the board's tones table). */
private fun burnTone(s: StingerStyle): IntArray = when (s.tone) {
    "cool" -> intArrayOf(0xFF3B82F6.toInt(), 0xFF22D3EE.toInt(), 0xFFA855F7.toInt(), 0xFFE3F1FF.toInt(), 0xFF0B1A33.toInt())
    "accent" -> intArrayOf(s.accent, mixWhite(s.accent, 0.4), s.accent, mixWhite(s.accent, 0.85), 0xFF0B0B0C.toInt())
    else -> intArrayOf(0xFFFF5A1F.toInt(), 0xFFFFB000.toInt(), 0xFFFF2E63.toInt(), 0xFFFFE7C7.toInt(), 0xFF3A1C08.toInt())
}

/** ponytail: tracking is the settled value; iOS re-renders the text as lens/burn tighten it during the fade-in. */
fun StingerKind.nameLook(s: StingerStyle): NameLook = when (this) {
    StingerKind.Lens -> NameLook(52f, false, -1, 0.2f)
    StingerKind.Route -> NameLook(44f, true, fgOn(s.ink), -0.02f)
    StingerKind.Viewfinder -> NameLook(72f, true, fgOn(s.ink), -0.02f)
    StingerKind.Burn -> NameLook(56f, true, burnTone(s)[4], -0.01f)
    else -> NameLook(56f, true, fgOn(s.ink), -0.02f)
}

/** (x, y, delay) per Liquid drop on the board; the goo merges them. */
val LIQUID_DROPS = arrayOf(
    doubleArrayOf(1080.0, 660.0, 0.0), doubleArrayOf(420.0, 300.0, 0.012), doubleArrayOf(1680.0, 360.0, 0.02),
    doubleArrayOf(300.0, 980.0, 0.03), doubleArrayOf(1500.0, 1060.0, 0.016), doubleArrayOf(820.0, 1180.0, 0.04),
    doubleArrayOf(2000.0, 900.0, 0.026), doubleArrayOf(640.0, 640.0, 0.034), doubleArrayOf(1360.0, 140.0, 0.046)
)

/** Fills [f] for board position [q] on a [w] x [h] canvas: the iOS StingerArt keyframes, number for number. */
fun StingerKind.frame(q: Double, s: StingerStyle, w: Float, h: Float, f: StingerFrame) {
    val u = min(w, h) / 1080.0
    val hd = hypot(w.toDouble(), h.toDouble()) / 2
    val cx = w / 2.0
    val cy = h / 2.0
    val p = f.p
    p.fill(0f)
    fun name(a: Double, x: Double = cx, y: Double = cy, scale: Double = 1.0) {
        f.nameAlpha = if (s.showName && s.name.isNotEmpty()) a.toFloat() else 0f
        f.nameX = x.toFloat()
        f.nameY = y.toFloat()
        f.nameScale = scale.toFloat()
    }
    fun atY(y: Double) = cy + (y - 540) * u
    val pop = Curve.pop
    when (this) {
        StingerKind.Lens -> {
            f.on = q > 0.24 && q < 0.66
            val big = max(1250 * u, hd + 24)
            val hv = Curve.inOut.track(q, 0.25 to 1250.0, 0.38 to 215.0, 0.55 to 215.0, 0.64 to 1250.0)
            val hole = 215 * u + (hv - 215) / 1035 * (big - 215 * u)
            p[0] = hole.toFloat()
            p[1] = Curve.easeInOut.track(q, 0.36 to 0.0, 0.40 to 1.0, 0.52 to 1.0, 0.55 to 0.0).toFloat()
            p[2] = Curve.easeInOut.track(q, 0.37 to 0.0, 0.42 to 1.0, 0.52 to 1.0, 0.55 to 0.0).toFloat()
            p[3] = pop.track(q, 0.39 to 0.0, 0.42 to 0.9, 0.46 to 0.65, 0.52 to 0.65, 0.535 to 0.0).toFloat()
            p[4] = (42 * u * pop.track(q, 0.39 to 1.4, 0.42 to 1.9, 0.46 to 2.2)).toFloat()
            p[5] = pop.track(q, 0.39 to 0.0, 0.44 to 1.0, 0.52 to 1.0, 0.535 to 0.0).toFloat()
            p[6] = pop.track(q, 0.39 to 0.9, 0.44 to 1.0).toFloat()
            p[7] = if (hole - 12 * u < hd + 1) Curve.linear.track(q, 0.245 to 0.0, 0.27 to 1.0, 0.62 to 1.0, 0.65 to 0.0).toFloat() else 0f
            name(pop.track(q, 0.41 to 0.0, 0.47 to 0.92, 0.52 to 0.92, 0.54 to 0.0), y = atY(911 + pop.track(q, 0.41 to 16.0, 0.47 to 0.0)))
        }
        StingerKind.Aperture -> {
            f.on = q in 0.25..0.67
            val kk = hd / 1101
            val t = Curve.blade.track(q, 0.25 to 0.0, 0.40 to 1.0, 0.52 to 1.0, 0.67 to 0.0)
            val open = -1400 * kk
            p[0] = (open + (30 * u - open) * t).toFloat()
            p[1] = Curve.blade.track(q, 0.25 to -50.0, 0.40 to 0.0, 0.52 to 0.0, 0.67 to 50.0).toFloat()
            p[2] = Curve.linear.track(q, 0.36 to 1.0, 0.40 to 0.0, 0.52 to 0.0, 0.56 to 1.0).toFloat()
            p[3] = kk.toFloat()
            name(
                pop.track(q, 0.41 to 0.0, 0.45 to 1.0, 0.50 to 1.0, 0.53 to 0.0),
                scale = pop.track(q, 0.41 to 0.96, 0.45 to 1.0, 0.50 to 1.0, 0.53 to 1.02)
            )
        }
        StingerKind.Route -> {
            f.on = q in 0.24..0.64
            p[0] = (1 - Curve.inOut.track(q, 0.24 to 1.0, 0.35 to 0.0, 0.54 to 0.0)).toFloat()
            p[1] = Curve.inOut.track(q, 0.24 to 1.0, 0.54 to 1.0, 0.58 to 0.0).toFloat()
            // circle(pct): 80% is the whole frame. ponytail: iOS divides by 0.8 here, which floods at once; this follows the board.
            p[2] = (Curve.blade.track(q, 0.37 to 0.0, 0.46 to 80.0, 0.54 to 80.0, 0.64 to 0.0) / 80 * hd * 1.02).toFloat()
            p[3] = pop.track(q, 0.34 to 0.0, 0.365 to 1.25, 0.38 to 1.0, 0.54 to 1.0, 0.62 to 0.0).toFloat()
            name(
                pop.track(q, 0.44 to 0.0, 0.475 to 1.0, 0.51 to 1.0, 0.535 to 0.0),
                y = atY(616 + pop.track(q, 0.44 to 12.0, 0.475 to 0.0))
            )
        }
        StingerKind.Viewfinder -> viewfinder(q, w, h, f)
        StingerKind.Liquid -> {
            val m = max(w, h) / 1920.0
            val stops = arrayOf(
                arrayOf(0.23 to 0.0, 0.38 to 1.0, 0.57 to 1.0, 0.72 to 0.0),
                arrayOf(0.25 to 0.0, 0.40 to 1.0, 0.55 to 1.0, 0.70 to 0.0)
            )
            for (layer in 0..1) {
                for ((i, d) in LIQUID_DROPS.withIndex()) {
                    p[layer * 9 + i] =
                        (1500 * Curve.inOut.track(q - d[2], *stops[layer]) * m).toFloat()
                }
            }
            p[18] = (36 * m).toFloat()
            f.on = (0 until 18).any { p[it] > 0.5f }
            name(pop.track(q, 0.46 to 0.0, 0.49 to 1.0, 0.53 to 1.0, 0.55 to 0.0), y = cy + pop.track(q, 0.46 to 16.0, 0.49 to 0.0) * u)
        }
        StingerKind.Ripple -> {
            for (i in 0..3) {
                val r = Curve.inOut.track(q - i * 0.02, 0.25 to 0.0, 0.40 to 80.0) / 80 * hd * 1.02
                val hole = Curve.inOut.track(q - (3 - i) * 0.03, 0.53 to 0.0, 0.68 to 1300.0) / 1101 * hd
                p[2 * i] = if (r > 0.5 && hole < r) r.toFloat() else 0f
                p[2 * i + 1] = hole.toFloat()
            }
            f.on = (0..3).any { p[2 * it] > 0f }
            name(
                pop.track(q, 0.44 to 0.0, 0.48 to 1.0, 0.52 to 1.0, 0.54 to 0.0),
                scale = pop.track(q, 0.44 to 0.97, 0.48 to 1.0, 0.52 to 1.0, 0.54 to 1.02)
            )
        }
        StingerKind.Tunnel -> {
            for (i in 0..4) {
                val qi = q - i * 0.015
                val qo = q - (4 - i) * 0.03
                p[2 * i] = (Curve.blade.track(qi, 0.25 to 0.0, 0.41 to 1.0) * Curve.blade.track(qo, 0.55 to 1.0, 0.70 to 0.0)).toFloat()
                p[2 * i + 1] =
                    (Curve.blade.track(qi, 0.25 to -10.0, 0.41 to 0.0) + Curve.blade.track(qo, 0.55 to 0.0, 0.70 to 10.0)).toFloat()
            }
            f.on = (0..4).any { p[2 * it] > 0.001f }
            name(
                pop.track(q, 0.47 to 0.0, 0.50 to 1.0, 0.54 to 1.0, 0.56 to 0.0),
                scale = pop.track(q, 0.47 to 0.9, 0.50 to 1.0, 0.54 to 1.0, 0.56 to 0.9)
            )
        }
        StingerKind.Burn -> {
            val curve = Curve(0.45, 0.0, 0.55, 1.0)
            val kk = hd / 1101
            // (clear-at fraction, start, end, from x, from y, to x, to y) per blob
            val blobs = arrayOf(
                doubleArrayOf(0.62, 0.25, 0.70, -2400.0, -120.0, 2400.0, 80.0),
                doubleArrayOf(0.60, 0.28, 0.66, 2400.0, 260.0, -2400.0, -200.0),
                doubleArrayOf(0.58, 0.30, 0.72, -2400.0, 420.0, 2400.0, -300.0)
            )
            for ((i, b) in blobs.withIndex()) {
                if (q <= b[1] || q >= b[2]) continue
                p[3 * i] = (cx + curve.track(q, b[1] to b[3], b[2] to b[5]) * kk).toFloat()
                p[3 * i + 1] = (cy + curve.track(q, b[1] to b[4], b[2] to b[6]) * kk).toFloat()
                p[3 * i + 2] = (b[0] * 1100 * sqrt(2.0) * kk).toFloat() // CSS "circle" gradients reach the box's far corner
            }
            p[9] = Curve.easeInOut.track(q, 0.38 to 0.0, 0.45 to 1.0, 0.52 to 1.0, 0.64 to 0.0).toFloat()
            f.on = p[9] > 0.001f || (0..2).any { p[3 * it + 2] > 0f }
            name(pop.track(q, 0.455 to 0.0, 0.48 to 1.0, 0.51 to 1.0, 0.53 to 0.0))
        }
    }
    p[19] = u.toFloat()
}

/** Ink opens like a framed shot (inset rect), accent corner brackets trace an inset rect of their own. */
private fun viewfinder(q: Double, w: Float, h: Float, f: StingerFrame) {
    f.on = q in 0.25..0.66
    val e = Curve.blade
    val iv = e.track(q, 0.25 to 50.0, 0.33 to 38.0, 0.35 to 38.0, 0.42 to 0.0, 0.52 to 0.0, 0.59 to 38.0, 0.61 to 38.0, 0.66 to 50.0)
    val ih = e.track(q, 0.25 to 50.0, 0.33 to 34.0, 0.35 to 34.0, 0.42 to 0.0, 0.52 to 0.0, 0.59 to 34.0, 0.61 to 34.0, 0.66 to 50.0)
    val p = f.p
    inset(p, 0, w, h, ih, iv)
    val stops = doubleArrayOf(0.25, 0.27, 0.33, 0.35, 0.42, 0.52, 0.53, 0.59, 0.61, 0.66)
    fun track(vararg v: Double) = e.track(q, *stops.indices.map { stops[it] to v[it] }.toTypedArray())
    val fv = track(5.0, 5.0, 38.0, 38.0, 5.0, 5.0, 5.0, 38.0, 38.0, 50.0)
    val fh = track(3.0, 3.0, 34.0, 34.0, 3.0, 3.0, 3.0, 34.0, 34.0, 50.0)
    inset(p, 4, w, h, fh, fv)
    p[8] = if (p[6] > 0f && p[7] > 0f) track(0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0).toFloat() else 0f
    f.nameAlpha = Curve.easeInOut.track(q, 0.42 to 0.0, 0.46 to 1.0, 0.50 to 1.0, 0.52 to 0.0).toFloat()
    f.nameX = w / 2
    f.nameY = h / 2
    f.nameScale = 1f
}

/** CSS inset(v% h%) of the canvas as x, y, w, h at p[i..i+3]. */
private fun inset(p: FloatArray, i: Int, w: Float, h: Float, ih: Double, iv: Double) {
    p[i] = (w * ih / 100).toFloat()
    p[i + 1] = (h * iv / 100).toFloat()
    p[i + 2] = (w * (1 - 2 * ih / 100)).toFloat()
    p[i + 3] = (h * (1 - 2 * iv / 100)).toFloat()
}
