package com.saeedkolivand.metastream.camera

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

// Pure camera maths, kept free of android.* so it runs in plain JVM unit tests.

/** iOS caps usable zoom well below the digital-only range, which looks like mush; same ceiling here. */
const val MAX_USABLE_ZOOM = 15f

fun clamp(v: Float, lo: Float, hi: Float): Float = min(max(v, lo), max(lo, hi))

/** One lens chip: [label] is the zoom multiplier text ("0.5", "1", "5"), [zoom] the CONTROL_ZOOM_RATIO that frames it. */
data class LensOption(val label: String, val zoom: Float)

/** iOS multiplierLabel: whole numbers from 2x up (hardware noise like 2.98 reads "3"), half-steps below. */
fun roundMultiplier(m: Float): Float = if (m < 2f) (m * 2).roundToInt() / 2f else m.roundToInt().toFloat()

fun multiplierLabel(m: Float): String = roundMultiplier(m).let { if (it % 1f == 0f) it.toInt().toString() else "%.1f".format(it) }

/** 35mm-equivalent focal length (width-based), which makes lenses on different sensors comparable. */
fun equivFocal(focalMm: Float, sensorWidthMm: Float): Float = focalMm * 36f / sensorWidthMm

/**
 * Chips for one facing, ascending by zoom, labelled with THIS device's real multipliers (as iOS lensOptions).
 * [equivs] are the physical lenses' equivalent focal lengths; the "main" lens is the 1x one. When the logical camera
 * zooms below 1x ([zoomMin] < 1) the shortest lens is an ultra-wide, so main is the second shortest. Fewer than two
 * lenses gives no chips (iOS shows nothing for a single-lens position).
 */
fun lensOptions(equivs: List<Float>, zoomMin: Float, zoomMax: Float): List<LensOption> {
    val sorted = equivs.filter { it > 0f }.sorted()
    if (sorted.size < 2) return emptyList()
    val main = sorted[if (zoomMin < 0.99f) 1 else 0]
    val options = sorted.map {
        val z = clamp(roundMultiplier(it / main), zoomMin, min(zoomMax, MAX_USABLE_ZOOM))
        LensOption(multiplierLabel(z), z)
    }
    return options.distinctBy { it.label }.sortedBy { it.zoom }
}

/**
 * Maps a point normalised to the preview view (0..1, top-left origin) into the sensor's active array
 * (0..1, sensor's natural landscape orientation). [rotation] is how far the sensor image is turned clockwise on
 * screen: back = sensorOrientation - displayRotation, front = sensorOrientation + displayRotation.
 * [flipX] undoes a horizontally mirrored preview. Same conventions as iOS devicePoint.
 */
fun viewToSensor(vx: Float, vy: Float, rotation: Int, flipX: Boolean): Pair<Float, Float> {
    val x = if (flipX) 1f - vx else vx
    val (sx, sy) = when (((rotation % 360) + 360) % 360) {
        90 -> vy to 1f - x
        180 -> 1f - x to 1f - vy
        270 -> 1f - vy to x
        else -> x to vy
    }
    return clamp(sx, 0f, 1f) to clamp(sy, 0f, 1f)
}

/** Metering box (x, y, w, h in active-array pixels) around a normalised sensor point, fully inside the array. */
fun meteringBox(nx: Float, ny: Float, width: Int, height: Int): IntArray {
    val side = (min(width, height) * 0.15f).roundToInt()
    val x = (nx * width - side / 2).roundToInt().coerceIn(0, width - side)
    val y = (ny * height - side / 2).roundToInt().coerceIn(0, height - side)
    return intArrayOf(x, y, side, side)
}

/**
 * RGGB white-balance gains for a colour temperature and tint (green/magenta). Illuminant colour from the
 * Tanner Helland blackbody fit, inverted so the light neutralises, then scaled so the smallest gain is 1.
 * Approximate on purpose: no per-sensor calibration, so it reads as "warmer/cooler", not as exact Kelvin.
 */
fun kelvinToGains(kelvin: Float, tint: Float): FloatArray {
    val t = clamp(kelvin, 1000f, 40000f) / 100f
    val r = if (t <= 66) 255.0 else 329.698727446 * (t - 60.0).pow(-0.1332047592)
    val g = if (t <= 66) 99.4708025861 * ln(t.toDouble()) - 161.1195681661 else 288.1221695283 * (t - 60.0).pow(-0.0755148492)
    val b = if (t >= 66) {
        255.0
    } else if (t <= 19) {
        0.0
    } else {
        138.5177312231 * ln(t - 10.0) - 305.0447927307
    }
    // Gain per channel is the inverse of the illuminant; tint scales the green gain (positive = magenta = less green).
    val raw = floatArrayOf(
        (1.0 / max(r, 1.0)).toFloat(),
        ((1.0 - tint / 300.0) / max(g, 1.0)).toFloat(),
        ((1.0 - tint / 300.0) / max(g, 1.0)).toFloat(),
        (1.0 / max(b, 1.0)).toFloat()
    )
    val lowest = raw.min()
    return FloatArray(4) { raw[it] / lowest }
}

fun shutterLabel(ms: Float): String = "1/${max(1, (1000f / max(ms, 0.1f)).roundToInt())}s"

/**
 * Horizon roll in degrees from the accelerometer's x/y (device axes), turned into screen axes by the display
 * rotation (0/90/180/270). 0 = level; positive = phone turned clockwise, so the horizon line draws at -roll.
 */
fun rollDegrees(ax: Float, ay: Float, displayRotation: Int): Float {
    val (sx, sy) = when (displayRotation) {
        90 -> -ay to ax
        180 -> -ax to -ay
        270 -> ay to -ax
        else -> ax to ay
    }
    return (atan2(-sx, sy) * 180.0 / PI).toFloat()
}

fun isLevel(roll: Float): Boolean = abs(roll) < 1.5f

/** Strip controls; [key] doubles as the storage token and matches iOS LiveCameraControl rawValues. */
enum class LiveControl(val key: String, val label: String) {
    Lens("lens", "Lens"),
    Zoom("zoom", "Zoom"),
    Exposure("exposure", "Exposure"),
    Torch("torch", "Torch"),
    WhiteBalanceLock("whiteBalanceLock", "White balance lock"),
    Stabilization("stabilization", "Stabilisation"),
    Mirror("mirror", "Mirror");

    companion object {
        val defaultOrder = entries.toList()

        /** Unknown tokens are dropped; empty or all-unknown falls back to the default so the strip is never blank. */
        fun parse(raw: String): List<LiveControl> {
            val parsed = raw.split(',').mapNotNull { t -> entries.firstOrNull { it.key == t.trim() } }.distinct()
            return parsed.ifEmpty { defaultOrder }
        }

        fun serialize(order: List<LiveControl>): String = order.joinToString(",") { it.key }
    }
}
