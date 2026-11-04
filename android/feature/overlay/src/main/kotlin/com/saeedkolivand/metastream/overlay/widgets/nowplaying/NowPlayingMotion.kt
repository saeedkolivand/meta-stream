package com.saeedkolivand.metastream.overlay.widgets.nowplaying

/** CSS cubic-bezier(x1, y1, x2, y2) timing function (iOS Cubic); y may leave 0..1, which is the overshoot. */
class Cubic(private val x1: Double, private val y1: Double, private val x2: Double, private val y2: Double) {
    /** Eased value at progress [x] (clamped to 0..1). x(t) is monotonic for x1, x2 in 0..1, so bisect for t. */
    fun at(x: Double): Double {
        if (x <= 0) return 0.0
        if (x >= 1) return 1.0
        var lo = 0.0
        var hi = 1.0
        var p = x
        repeat(30) {
            val inv = 1 - p
            if (3 * inv * inv * p * x1 + 3 * inv * p * p * x2 + p * p * p < x) lo = p else hi = p
            p = (lo + hi) / 2
        }
        val inv = 1 - p
        return 3 * inv * inv * p * y1 + 3 * inv * p * p * y2 + p * p * p
    }

    companion object {
        val standard = Cubic(0.2, 0.8, 0.2, 1.0) // slide / wipe in
        val easeIn = Cubic(0.42, 0.0, 1.0, 1.0)
        val easeOut = Cubic(0.0, 0.0, 0.58, 1.0)
        val easeInOut = Cubic(0.42, 0.0, 0.58, 1.0)
        val slideOut = Cubic(0.4, 0.0, 1.0, 1.0)
        val wipeOut = Cubic(0.6, 0.0, 0.8, 0.4) // text / cover / pop-up box closing
        val tickerOut = Cubic(0.5, 0.0, 0.9, 0.5)
        val collapse = Cubic(0.5, 0.0, 0.75, 0.0) // island capsule closing
        val spring = Cubic(0.34, 1.4, 0.64, 1.0) // island capsule opening (peaks at 1.05)
        val pop = Cubic(0.34, 1.8, 0.64, 1.0) // island cover popping back
        val dropOut = Cubic(0.5, 0.0, 0.9, 0.4)
        val dropIn = Cubic(0.2, 1.25, 0.4, 1.0)
        val flip = Cubic(0.2, 1.4, 0.4, 1.0)
    }
}

/** One animated element: offset from its resting place, visibility, scale (scaleX extra: the cover flip), degrees. */
data class NpLane(
    val dx: Float = 0f,
    val dy: Float = 0f,
    val alpha: Float = 1f,
    val scale: Float = 1f,
    val scaleX: Float = 1f,
    val rot: Float = 0f
)

/**
 * One frame of the widget (iOS NowPlayingPose). [useNew] false = still drawing the outgoing song; [reveal] 0 shut .. 1 open
 * (the island's spring overshoots); [trail] is how far the ticker wipe's left edge has moved right. Default = settled.
 */
data class NpPose(
    val useNew: Boolean = true,
    val alpha: Float = 1f,
    val reveal: Float = 1f,
    val trail: Float = 0f,
    val cover: NpLane = NpLane(),
    val line1: NpLane = NpLane(),
    val line2: NpLane = NpLane()
)

/**
 * Now playing motion, ported from iOS NowPlayingMotion: every frame is a pure function of the seconds since the song
 * changed, copied from the mockups' CSS transitions. A change plays an "out" half on the old song, switches, then the "in"
 * half; a first appearance plays only the in half, a song going away only the out half. Offsets are natural units.
 */
object NowPlayingMotion {
    /** (switchAt, inLen): seconds into a change when the new song replaces the old; seconds until the in half settles. */
    fun timing(design: String): Pair<Double, Double> = when (design) {
        "slab" -> 0.32 to 0.67
        "island" -> 0.42 to 0.78
        "disc" -> 0.38 to 0.68
        "ticker" -> 0.30 to 0.66
        "text" -> 0.34 to 0.62
        "twoLine" -> 0.30 to 0.60
        "cover" -> 0.34 to 0.74
        else -> 0.34 to 0.66 // popup
    }

    fun total(design: String) = timing(design).let { it.first + it.second }

    fun enterTotal(design: String) = timing(design).second

    fun exitTotal(design: String) = timing(design).first

    /** Designs that keep moving while a song plays (equaliser bars, the spinning disc). */
    fun continuous(design: String) = design == "island" || design == "disc" || design == "ticker"

    fun change(design: String, t: Double): NpPose {
        val sw = timing(design).first
        return if (t < sw) out(design, t) else inHalf(design, t - sw)
    }

    fun enter(design: String, t: Double) = inHalf(design, t)

    /** The out half on the leaving song, then a fade of the whole widget over its second half. */
    fun exit(design: String, t: Double): NpPose {
        val sw = timing(design).first
        return out(design, t).copy(useNew = true, alpha = 1 - ((t - sw / 2) / (sw / 2)).coerceIn(0.0, 1.0).toFloat())
    }

    /** Disc: one turn every 5 s, in degrees. */
    fun spin(clock: Double) = (360 * ((clock % 5 + 5) % 5) / 5).toFloat()

    /** One equaliser bar's scaleY: [low] -> 1 -> [low] every [period], ease-in-out each way. */
    fun eq(clock: Double, period: Double, offset: Double, low: Float): Float {
        val ph = (((clock + offset) / period) % 1 + 1) % 1
        val tri = if (ph < 0.5) ph * 2 else (1 - ph) * 2
        return low + (1 - low) * Cubic.easeInOut.at(tri).toFloat()
    }

    private fun ease(c: Cubic, t: Double, dur: Double, delay: Double = 0.0) = c.at((t - delay) / dur).toFloat()

    /** Exact at both ends (no -0.0), so a settled pose equals NpPose(). */
    private fun mix(a: Float, b: Float, f: Float) = if (f <= 0f) {
        a
    } else if (f == 1f) {
        b
    } else {
        a * (1 - f) + b * f
    }

    private fun out(design: String, t: Double): NpPose = when (design) {
        "slab" -> {
            val move = ease(Cubic.slideOut, t, 0.30)
            val fade = ease(Cubic.easeIn, t, 0.26)
            val line = NpLane(dy = 0f - 32 * move, alpha = 1 - fade)
            NpPose(false, cover = NpLane(alpha = 1 - fade, scale = mix(1f, 0.82f, move)), line1 = line, line2 = line)
        }
        "island" -> {
            val wide = ease(Cubic.easeIn, t, 0.38)
            val line = NpLane(alpha = 1 - ease(Cubic.easeIn, t, 0.14))
            NpPose(
                false,
                reveal = 1 - ease(Cubic.collapse, t, 0.38),
                cover = NpLane(alpha = mix(1f, 0.4f, wide), scale = mix(1f, 0.6f, wide)),
                line1 = line,
                line2 = line
            )
        }
        "disc" -> {
            val move = ease(Cubic.dropOut, t, 0.36)
            NpPose(
                false,
                cover = NpLane(dy = 240 * move, rot = 120 * move),
                line1 = NpLane(dx = 0f - 48 * ease(Cubic.easeIn, t, 0.30), alpha = 1 - ease(Cubic.easeIn, t, 0.24))
            )
        }
        "ticker" -> NpPose(false, trail = ease(Cubic.tickerOut, t, 0.28), cover = NpLane(scaleX = 1 - ease(Cubic.easeIn, t, 0.15)))
        "twoLine" -> {
            val line = NpLane(dy = 0f - 24 * ease(Cubic.slideOut, t, 0.28), alpha = 1 - ease(Cubic.easeIn, t, 0.24))
            NpPose(false, line1 = line, line2 = line)
        }
        "cover" -> NpPose(false, reveal = 1 - ease(Cubic.wipeOut, t, 0.32), cover = NpLane(scaleX = 1 - ease(Cubic.easeIn, t, 0.16, 0.16)))
        else -> NpPose(false, reveal = 1 - ease(Cubic.wipeOut, t, 0.32)) // text, popup
    }

    /** The new song arriving; [since] seconds from the switch (<= 0 is the pre-roll pose: hidden or off to the side). */
    private fun inHalf(design: String, since: Double): NpPose = when (design) {
        "slab" -> {
            val s = since - 0.04 // the mockup waits 40 ms before the "in" transitions start
            NpPose(
                cover = NpLane(alpha = ease(Cubic.easeOut, s, 0.42), scale = mix(1.12f, 1f, ease(Cubic.standard, s, 0.52))),
                line1 = NpLane(dy = mix(32f, 0f, ease(Cubic.standard, s, 0.52, 0.04)), alpha = ease(Cubic.easeOut, s, 0.42, 0.04)),
                line2 = NpLane(dy = mix(32f, 0f, ease(Cubic.standard, s, 0.52, 0.11)), alpha = ease(Cubic.easeOut, s, 0.42, 0.11))
            )
        }
        "island" -> {
            // The cover pops back in over the closed capsule (160 ms), then the capsule springs open and the text fades in.
            val line = NpLane(alpha = ease(Cubic.easeOut, since, 0.32, 0.42))
            NpPose(
                reveal = ease(Cubic.spring, since, 0.62, 0.16),
                cover = NpLane(
                    alpha = mix(0.4f, 1f, ease(Cubic.easeOut, since, 0.12)),
                    scale = mix(0.6f, 1f, ease(Cubic.pop, since, 0.16))
                ),
                line1 = line,
                line2 = line
            )
        }
        "disc" -> {
            val s = since - 0.04
            val move = ease(Cubic.dropIn, s, 0.64)
            NpPose(
                cover = NpLane(dy = mix(-240f, 0f, move), rot = mix(-120f, 0f, move)),
                line1 = NpLane(dx = mix(48f, 0f, ease(Cubic.standard, s, 0.52, 0.12)), alpha = ease(Cubic.easeOut, s, 0.40, 0.12))
            )
        }
        "ticker" -> {
            val s = since - 0.04
            NpPose(reveal = ease(Cubic.standard, s, 0.56, 0.06), cover = NpLane(scaleX = ease(Cubic.flip, s, 0.30)))
        }
        "text" -> NpPose(reveal = ease(Cubic.standard, since - 0.06, 0.56))
        "twoLine" -> {
            val s = since - 0.04
            NpPose(
                line1 = NpLane(dy = mix(24f, 0f, ease(Cubic.standard, s, 0.48)), alpha = ease(Cubic.easeOut, s, 0.38)),
                line2 = NpLane(dy = mix(24f, 0f, ease(Cubic.standard, s, 0.48, 0.08)), alpha = ease(Cubic.easeOut, s, 0.38, 0.08))
            )
        }
        "cover" -> {
            val s = since - 0.06
            NpPose(reveal = ease(Cubic.standard, s, 0.56, 0.12), cover = NpLane(scaleX = ease(Cubic.flip, s, 0.26)))
        }
        else -> NpPose(reveal = ease(Cubic.standard, since - 0.06, 0.60)) // popup
    }
}
