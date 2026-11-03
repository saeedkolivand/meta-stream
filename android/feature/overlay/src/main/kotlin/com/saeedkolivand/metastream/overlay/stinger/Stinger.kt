package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.core.storage.Prefs
import kotlin.math.roundToInt
import org.json.JSONObject

/** iOS StingerStyle: how the built-in stingers look. Colours are ARGB, like the widget styles. JSON in Prefs "stingerStyle". */
data class StingerStyle(
    val speed: Float = 1f, // 0.4...2, multiplies the board's tempo
    val accent: Int = 0xFF53FC18.toInt(),
    val ink: Int = 0xFF0B0B0C.toInt(), // the panel colour that covers the frame
    val showName: Boolean = true,
    val name: String = "", // empty = no name drawn
    val tone: String = "warm", // film burn: "warm" | "cool" | "accent"
    // lens: the tally light
    val tally: Int = 0xFFE8101E.toInt()
) {
    fun save() = Prefs.put(
        KEY,
        JSONObject().put("speed", speed.toDouble()).put("accent", accent).put("ink", ink).put("showName", showName)
            .put("name", name).put("tone", tone).put("tally", tally).toString()
    )

    companion object {
        private const val KEY = "stingerStyle"

        fun load(): StingerStyle = runCatching {
            val o = JSONObject(Prefs.string(KEY, "{}"))
            val d = StingerStyle()
            StingerStyle(
                o.optDouble("speed", d.speed.toDouble()).toFloat(),
                o.optInt("accent", d.accent),
                o.optInt("ink", d.ink),
                o.optBoolean("showName", d.showName),
                o.optString("name", d.name),
                o.optString("tone", d.tone),
                o.optInt("tally", d.tally)
            )
        }.getOrDefault(StingerStyle())
    }
}

/**
 * The built-in stingers (iOS StingerKind), drawn live on the GPU (StingerFilter), so speed, colours and the name follow the
 * settings with no video file. `q` is the position in the design board's 6 s loop (0...1); [span] says where each one moves.
 */
enum class StingerKind(val title: String, val start: Double, val cut: Double, val end: Double) {
    Lens("Lens", 0.245, 0.46, 0.65),
    Aperture("Aperture", 0.25, 0.45, 0.67),
    Route("Route & pin", 0.24, 0.50, 0.64),
    Viewfinder("Viewfinder", 0.25, 0.46, 0.66),
    Liquid("Liquid", 0.23, 0.50, 0.77),
    Ripple("Ripple", 0.25, 0.49, 0.77),
    Tunnel("Tunnel", 0.25, 0.51, 0.82),
    Burn("Film burn", 0.25, 0.484, 0.72);

    /** The stored id, same as iOS ("lens", "aperture", ...). */
    val id get() = name.lowercase()

    private fun speed(s: StingerStyle) = s.speed.toDouble().coerceIn(0.2, 4.0)
    fun seconds(s: StingerStyle) = (end - start) * LOOP_SECONDS / speed(s)

    /** When the frame is fully covered: the scene switches underneath here. */
    fun cutSeconds(s: StingerStyle) = (cut - start) * LOOP_SECONDS / speed(s)

    /** Board loop position [t] seconds in. */
    fun q(t: Double, s: StingerStyle) = start + t * speed(s) / LOOP_SECONDS

    companion object {
        const val LOOP_SECONDS = 6.0
        fun of(id: String) = entries.firstOrNull { it.id == id }
    }
}

/** A CSS cubic-bezier timing function. */
class Curve(private val x1: Double, private val y1: Double, private val x2: Double, private val y2: Double) {
    operator fun invoke(x: Double): Double {
        if (x <= 0) return 0.0
        if (x >= 1) return 1.0
        fun bez(t: Double, a: Double, b: Double) = 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t
        var lo = 0.0
        var hi = 1.0
        var t = x
        repeat(40) {
            // bisection: x(t) is monotonic for 0 <= x1, x2 <= 1
            t = (lo + hi) / 2
            if (bez(t, x1, x2) < x) lo = t else hi = t
        }
        return bez(t, y1, y2)
    }

    /** CSS keyframes: the value at [q] for (position, value) stops, each segment eased by this curve; holds at the ends. */
    fun track(q: Double, vararg stops: Pair<Double, Double>): Double {
        val first = stops.firstOrNull() ?: return 0.0
        if (q <= first.first) return first.second
        for (i in 1 until stops.size) {
            val (a, b) = stops[i - 1] to stops[i]
            if (q <=
                b.first
            ) {
                return if (b.first <=
                    a.first
                ) {
                    b.second
                } else {
                    a.second + (b.second - a.second) * this((q - a.first) / (b.first - a.first))
                }
            }
        }
        return stops.last().second
    }

    companion object {
        val linear = Curve(0.0, 0.0, 1.0, 1.0)
        val easeInOut = Curve(0.42, 0.0, 0.58, 1.0)
        val pop = Curve(0.33, 1.0, 0.68, 1.0)
        val inOut = Curve(0.65, 0.0, 0.35, 1.0)
        val blade = Curve(0.76, 0.0, 0.24, 1.0)
    }
}

/** CSS color-mix(in srgb, argb, white f). */
fun mixWhite(argb: Int, f: Double): Int {
    fun ch(s: Int) = (((argb shr s) and 0xFF) * (1 - f) + 255 * f).roundToInt() shl s
    return (argb and 0xFF000000.toInt()) or ch(16) or ch(8) or ch(0)
}

/** Text colour on [ink]: near-black on light panels, off-white on dark ones (the boards' --fg). */
fun fgOn(ink: Int): Int {
    val lum = 0.299 * ((ink shr 16) and 0xFF) + 0.587 * ((ink shr 8) and 0xFF) + 0.114 * (ink and 0xFF)
    return if (lum > 150) 0xFF0B0B0C.toInt() else 0xFFF2F1EC.toInt()
}
