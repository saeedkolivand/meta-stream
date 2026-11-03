package com.saeedkolivand.metastream.streaming

import com.saeedkolivand.metastream.core.storage.Prefs
import org.json.JSONObject

/**
 * A source's colour treatment (iOS Look), stored per source as JSON under "look.<key>" (back | front | external). Glasses
 * passthrough never reaches the GL chain, so it can't be graded on Android. Ranges: brightness -0.5...0.5, contrast
 * 0.5...1.5, saturation 0...2, warmth -1 (cool)...1 (warm); [lut] is a file name in filesDir/luts.
 */
data class Look(
    val brightness: Float = 0f,
    val contrast: Float = 1f,
    val saturation: Float = 1f,
    val warmth: Float = 0f,
    val lut: String? = null
) {
    val neutral get() = brightness == 0f && contrast == 1f && saturation == 1f && warmth == 0f && lut == null

    companion object {
        fun load(key: String): Look = runCatching {
            val o = JSONObject(Prefs.string("look.$key").ifEmpty { return Look() })
            Look(
                o.optDouble("brightness", 0.0).toFloat(),
                o.optDouble("contrast", 1.0).toFloat(),
                o.optDouble("saturation", 1.0).toFloat(),
                o.optDouble("warmth", 0.0).toFloat(),
                o.optString("lut").ifEmpty { null }
            )
        }.getOrDefault(Look())

        fun save(look: Look, key: String) = Prefs.put(
            "look.$key",
            if (look.neutral) {
                ""
            } else {
                JSONObject().put("brightness", look.brightness.toDouble()).put("contrast", look.contrast.toDouble())
                    .put("saturation", look.saturation.toDouble()).put("warmth", look.warmth.toDouble()).put("lut", look.lut ?: "")
                    .toString()
            }
        )
    }
}

/** A 3D LUT: [size] per edge, RGB floats with red fastest, then green, then blue (the .cube order). */
class Cube(val size: Int, val rgb: FloatArray)

class CubeError(message: String) : Exception(message)

/** Adobe/Resolve .cube text, 3D only. ponytail: DOMAIN_MIN/MAX are ignored (assumed 0...1), as is TITLE, like iOS. */
fun parseCube(text: String): Cube {
    var size = 0
    var rgb = FloatArray(0)
    var n = 0
    for (raw in text.lineSequence()) {
        val line = raw.trim()
        if (line.isEmpty() || line.startsWith("#")) continue
        val parts = line.split(Regex("\\s+"))
        when (parts[0]) {
            "LUT_1D_SIZE" -> throw CubeError("1D LUTs aren't supported, use a 3D .cube file")
            "LUT_3D_SIZE" -> {
                val s = parts.getOrNull(1)?.toIntOrNull()?.takeIf { it >= 2 } ?: throw CubeError("Bad LUT_3D_SIZE")
                if (s > 64) throw CubeError("LUT size $s is too big (64 at most)")
                size = s
                rgb = FloatArray(s * s * s * 3)
            }
            "TITLE", "DOMAIN_MIN", "DOMAIN_MAX" -> continue
            else -> {
                val v = parts.mapNotNull { it.toFloatOrNull() }
                if (parts.size != 3 || v.size != 3) throw CubeError("Unreadable line: ${line.take(40)}")
                if (size == 0 || n + 3 > rgb.size) throw CubeError("More entries than LUT_3D_SIZE allows")
                v.forEach { rgb[n++] = it }
            }
        }
    }
    if (size == 0) throw CubeError("No LUT_3D_SIZE found")
    if (n != rgb.size) throw CubeError("Expected ${size * size * size} entries, found ${n / 3}")
    return Cube(size, rgb)
}
