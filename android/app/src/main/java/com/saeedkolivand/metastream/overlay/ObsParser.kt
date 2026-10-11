package com.saeedkolivand.metastream.overlay

import org.json.JSONArray
import org.json.JSONObject

// ponytail: OBS doesn't store the canvas size in the scene collection (it lives in the profile), so assume 1920x1080.
// Upgrade path: a canvas size field in the import UI.
const val OBS_CANVAS_W = 1920
const val OBS_CANVAS_H = 1080

private const val MAX_DEPTH = 8

private val CAMERAS = setOf("dshow_input", "v4l2_input", "av_capture_input", "av_capture_input_v2", "decklink-input")
private val CAPTURES = setOf("game_capture", "window_capture", "monitor_capture", "display_capture", "xshm_input", "screen_capture")

private fun category(id: String) = when {
    id == "browser_source" -> "non-web browser pages"
    id in CAMERAS -> "cameras"
    id in CAPTURES -> "game/window/monitor capture"
    id.startsWith("wasapi") || id.startsWith("pulse") || id.startsWith("coreaudio") || id.startsWith("alsa") -> "audio"
    else -> "other ($id)"
}

private fun JSONObject.f(key: String, default: Float) = if (has(key)) optDouble(key, default.toDouble()).toFloat() else default

private fun JSONObject.xy(key: String, d: Float): Pair<Float, Float> = optJSONObject(key)?.let { it.f("x", d) to it.f("y", d) } ?: (d to d)

private fun JSONArray?.items(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

/** OBS colors are 0xAABBGGRR; Android wants ARGB. A zero alpha means "unset" in OBS text sources, so it becomes opaque. */
internal fun obsColor(v: Long): Long {
    val a = if (v ushr 24 and 255 == 0L) 255L else v ushr 24 and 255
    return a shl 24 or (v and 255 shl 16) or (v ushr 8 and 255 shl 8) or (v ushr 16 and 255)
}

/** Parser state: where a nested item sits (origin + scale of its parent group) plus the running skipped tally. */
private class Ctx(val byUuid: Map<String, JSONObject>, val byName: Map<String, JSONObject>) {
    val skipped = linkedMapOf<String, MutableSet<String>>()
    val layers = mutableListOf<Layer>()
}

private data class Xf(val ox: Float, val oy: Float, val sx: Float, val sy: Float, val visible: Boolean)

/** Pure: OBS scene collection JSON in, [Pack] out. Never logs or keeps the source text. */
fun parseObs(json: String): Pack {
    val sources = JSONObject(json).optJSONArray("sources").items()
    val ctx = Ctx(
        sources.filter { it.has("uuid") }.associateBy { it.getString("uuid") },
        sources.associateBy { it.optString("name") }
    )
    val scenes = sources.filter { it.optString("id") == "scene" }.map { sc ->
        ctx.layers.clear()
        walk(ctx, sc.optJSONObject("settings").optItems(), Xf(0f, 0f, 1f, 1f, true), 0)
        Scene(sc.optString("name"), ctx.layers.toList())
    }
    return Pack(OBS_CANVAS_W, OBS_CANVAS_H, scenes, ctx.skipped.mapValues { it.value.size })
}

private fun JSONObject?.optItems() = this?.optJSONArray("items").items()

private fun walk(ctx: Ctx, items: List<JSONObject>, xf: Xf, depth: Int) {
    for (item in items) {
        val src = item.optString("source_uuid").let { ctx.byUuid[it] } ?: ctx.byName[item.optString("name")] ?: continue
        val (px, py) = item.xy("pos", 0f)
        val (isx, isy) = item.xy("scale", 1f)
        val visible = xf.visible && item.optBoolean("visible", true)
        val id = src.optString("id")
        if (id == "group" || id == "scene") {
            // ponytail: group rotation, crop and alignment are ignored; children keep their own transforms scaled by the group's.
            if (depth < MAX_DEPTH) {
                val child = Xf(xf.ox + xf.sx * px, xf.oy + xf.sy * py, xf.sx * isx, xf.sy * isy, visible)
                walk(ctx, src.optJSONObject("settings").optItems(), child, depth + 1)
            }
            continue
        }
        val layer = layerOf(src, item, Xf(xf.ox + xf.sx * px, xf.oy + xf.sy * py, xf.sx * isx, xf.sy * isy, visible), xf)
        if (layer == null) {
            ctx.skipped.getOrPut(category(id)) { mutableSetOf() }.add(src.optString("name"))
        } else {
            ctx.layers.add(layer)
        }
    }
}

private fun layerOf(src: JSONObject, item: JSONObject, w: Xf, parent: Xf): Layer? {
    val s = src.optJSONObject("settings") ?: JSONObject()
    val (type, data, files) = payload(src.optString("id"), s) ?: return null
    val (bx, by) = item.xy("bounds", 0f)
    return Layer(
        type,
        src.optString("name"),
        w.visible,
        w.ox,
        w.oy,
        w.sx,
        w.sy,
        item.optInt("align", 5),
        item.optInt("bounds_type", 0),
        bx * parent.sx,
        by * parent.sy,
        item.optInt("bounds_align", 0),
        item.f("rot", 0f),
        listOf("crop_left", "crop_top", "crop_right", "crop_bottom").map { item.optInt(it, 0) },
        data,
        files
    )
}

private fun JSONObject.long(key: String, d: Long) = if (has(key)) optLong(key, d) else d

private fun payload(id: String, s: JSONObject): Triple<LayerType, Map<String, String>, List<String>>? = when (id) {
    "browser_source" -> {
        val url = s.optString("url")
        // Only http(s) pages can load: local-file pages and anything else would need file access, which stays off.
        if (s.optBoolean("is_local_file") || !(url.startsWith("http://") || url.startsWith("https://"))) {
            null
        } else {
            Triple(
                LayerType.Browser,
                mapOf(
                    "url" to url,
                    "width" to s.optInt("width", 800).toString(),
                    "height" to s.optInt("height", 600).toString(),
                    "css" to s.optString("css")
                ),
                emptyList()
            )
        }
    }
    "image_source" -> s.optString("file").takeIf { it.isNotEmpty() }?.let { Triple(LayerType.Image, mapOf("file" to it), emptyList()) }
    // ponytail: media audio is muted on the stream (a player can't feed RootEncoder's mic mix). Upgrade path: AudioSource mixing.
    "ffmpeg_source" -> s.optString("local_file").takeIf { s.optBoolean("is_local_file", true) && it.isNotEmpty() }
        ?.let { Triple(LayerType.Media, mapOf("file" to it, "loop" to s.optBoolean("looping", false).toString()), emptyList()) }
    "text_gdiplus", "text_gdiplus_v2", "text_gdiplus_v3", "text_ft2_source", "text_ft2_source_v2" -> {
        val font = s.optJSONObject("font")
        val color = if (s.has("color")) s.long("color", 0xFFFFFFFFL) else s.long("color1", 0xFFFFFFFFL)
        Triple(
            LayerType.Text,
            mapOf(
                "text" to s.optString("text"),
                "face" to (font?.optString("face") ?: ""),
                "size" to (font?.optInt("size", 36) ?: 36).toString(),
                "bold" to ((font?.optInt("flags", 0) ?: 0) and 1 != 0).toString(),
                "color" to obsColor(color).toString()
            ),
            emptyList()
        )
    }
    "color_source", "color_source_v2", "color_source_v3" -> Triple(
        LayerType.Color,
        mapOf(
            "color" to obsColor(s.long("color", 0xFFFFFFFFL)).toString(),
            "width" to s.optInt("width", 1920).toString(),
            "height" to s.optInt("height", 1080).toString()
        ),
        emptyList()
    )
    "slideshow" -> s.optJSONArray("files").items().map { it.optString("value") }.filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() }
        ?.let { Triple(LayerType.Slideshow, mapOf("time" to s.optInt("slide_time", 8000).toString()), it) }
    else -> null
}
