package com.saeedkolivand.metastream.camera

import org.json.JSONObject

/**
 * Every phone-camera knob, mirroring iOS CameraSettings. Manual modes (ISO/shutter, white balance, lens position)
 * only act when their toggle is on; everything else defaults to "let the camera decide".
 */
data class CameraSettings(
    val zoom: Float = 1f,
    val focusMode: String = "continuous", // continuous | auto | manual
    val lensPosition: Float = 0.5f, // 0 closest .. 1 furthest, manual focus only
    val smoothAf: Boolean = true, // continuous-video AF: slower but little visible hunting
    val faceAf: Boolean = true,
    val exposureManual: Boolean = false,
    val biasEv: Float = 0f,
    val iso: Float = 200f,
    val shutterMs: Float = 16.7f,
    val lowLight: Boolean = true,
    val wbLock: Boolean = false, // strip button: freeze auto white balance
    val wbManual: Boolean = false,
    val wbKelvin: Float = 5500f,
    val wbTint: Float = 0f,
    val hdr: String = "auto", // auto | on | off
    val torch: Float = 0f, // 0 off, else 0<level<=1
    val mirrored: Boolean = false,
    val distortion: Boolean = true,
    val stabilization: String = "off", // off | standard | ois
    val grid: Boolean = false,
    val level: Boolean = false,
    val order: List<LiveControl> = LiveControl.defaultOrder
) {
    fun toJson(): String = JSONObject().apply {
        put("zoom", zoom.toDouble())
        put("focusMode", focusMode)
        put("lensPosition", lensPosition.toDouble())
        put("smoothAf", smoothAf)
        put("faceAf", faceAf)
        put("exposureManual", exposureManual)
        put("biasEv", biasEv.toDouble())
        put("iso", iso.toDouble())
        put("shutterMs", shutterMs.toDouble())
        put("lowLight", lowLight)
        put("wbLock", wbLock)
        put("wbManual", wbManual)
        put("wbKelvin", wbKelvin.toDouble())
        put("wbTint", wbTint.toDouble())
        put("hdr", hdr)
        put("torch", torch.toDouble())
        put("mirrored", mirrored)
        put("distortion", distortion)
        put("stabilization", stabilization)
        put("grid", grid)
        put("level", level)
        put("order", LiveControl.serialize(order))
    }.toString()

    companion object {
        /** Absent or corrupt keys keep the defaults, never the zero value (zoom 0x, torch forever on). */
        fun fromJson(json: String): CameraSettings {
            val d = CameraSettings()
            val o = try {
                JSONObject(json)
            } catch (e: org.json.JSONException) {
                return d
            }
            fun f(k: String, def: Float) = o.optDouble(k, def.toDouble()).toFloat()
            return CameraSettings(
                zoom = f("zoom", d.zoom),
                focusMode = o.optString("focusMode", d.focusMode),
                lensPosition = f("lensPosition", d.lensPosition),
                smoothAf = o.optBoolean("smoothAf", d.smoothAf),
                faceAf = o.optBoolean("faceAf", d.faceAf),
                exposureManual = o.optBoolean("exposureManual", d.exposureManual),
                biasEv = f("biasEv", d.biasEv),
                iso = f("iso", d.iso),
                shutterMs = f("shutterMs", d.shutterMs),
                lowLight = o.optBoolean("lowLight", d.lowLight),
                wbLock = o.optBoolean("wbLock", d.wbLock),
                wbManual = o.optBoolean("wbManual", d.wbManual),
                wbKelvin = f("wbKelvin", d.wbKelvin),
                wbTint = f("wbTint", d.wbTint),
                hdr = o.optString("hdr", d.hdr),
                torch = f("torch", d.torch),
                mirrored = o.optBoolean("mirrored", d.mirrored),
                distortion = o.optBoolean("distortion", d.distortion),
                stabilization = o.optString("stabilization", d.stabilization),
                grid = o.optBoolean("grid", d.grid),
                level = o.optBoolean("level", d.level),
                order = LiveControl.parse(o.optString("order", ""))
            )
        }
    }
}
