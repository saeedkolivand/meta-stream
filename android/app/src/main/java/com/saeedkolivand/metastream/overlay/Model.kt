package com.saeedkolivand.metastream.overlay

import org.json.JSONArray
import org.json.JSONObject

enum class LayerType { Browser, Image, Media, Text, Color, Slideshow }

/**
 * One OBS scene item, flattened (group transforms already applied). Position/scale/bounds are canvas px.
 * [data] holds the type's payload as strings: browser url/width/height/css, image/media file, text/face/size/color,
 * color/width/height. [files] is the slideshow list.
 */
data class Layer(
    val type: LayerType,
    val name: String,
    val visible: Boolean,
    val x: Float,
    val y: Float,
    val sx: Float,
    val sy: Float,
    val align: Int,
    val boundsType: Int,
    val bw: Float,
    val bh: Float,
    val boundsAlign: Int,
    val rotation: Float,
    val crop: List<Int>,
    val data: Map<String, String>,
    val files: List<String> = emptyList()
)

data class Scene(val name: String, val layers: List<Layer>)

/** [skipped] maps a PC-only category ("cameras", "game capture"...) to how many sources were left out. */
data class Pack(val canvasW: Int, val canvasH: Int, val scenes: List<Scene>, val skipped: Map<String, Int>) {
    fun skippedText(): String {
        val n = skipped.values.sum()
        return if (n == 0) "" else "Skipped $n PC-only sources: " + skipped.entries.joinToString(", ") { it.key }
    }

    /** Every local file the scenes reference (images, media, slideshow frames). */
    fun files(): Set<String> = scenes.flatMap { s ->
        s.layers.flatMap { l ->
            val own = if (l.type == LayerType.Image || l.type == LayerType.Media) listOfNotNull(l.data["file"]) else emptyList()
            own + l.files
        }
    }.toSet()

    fun toJson(): String = JSONObject().put("w", canvasW).put("h", canvasH).put("skipped", JSONObject(skipped as Map<*, *>))
        .put("scenes", JSONArray(scenes.map { s -> JSONObject().put("name", s.name).put("layers", JSONArray(s.layers.map(::layerJson))) }))
        .toString()

    companion object {
        fun fromJson(text: String): Pack {
            val o = JSONObject(text)
            val sk = o.getJSONObject("skipped")
            return Pack(
                o.getInt("w"),
                o.getInt("h"),
                o.getJSONArray("scenes").objects().map { s ->
                    Scene(s.getString("name"), s.getJSONArray("layers").objects().map(::layerOf))
                },
                sk.keys().asSequence().associateWith { sk.getInt(it) }
            )
        }
    }
}

private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }

private fun layerJson(l: Layer) = JSONObject().put("t", l.type.name).put("n", l.name).put("v", l.visible)
    .put("pos", JSONArray(listOf(l.x, l.y, l.sx, l.sy, l.bw, l.bh, l.rotation)))
    .put("ints", JSONArray(listOf(l.align, l.boundsType, l.boundsAlign) + l.crop))
    .put("d", JSONObject(l.data as Map<*, *>)).put("f", JSONArray(l.files))

private fun layerOf(o: JSONObject): Layer {
    val p = o.getJSONArray("pos")
    val i = o.getJSONArray("ints")
    val d = o.getJSONObject("d")
    val f = o.getJSONArray("f")
    return Layer(
        LayerType.valueOf(o.getString("t")),
        o.getString("n"),
        o.getBoolean("v"),
        p.getDouble(0).toFloat(),
        p.getDouble(1).toFloat(),
        p.getDouble(2).toFloat(),
        p.getDouble(3).toFloat(),
        i.getInt(0),
        i.getInt(1),
        p.getDouble(4).toFloat(),
        p.getDouble(5).toFloat(),
        i.getInt(2),
        p.getDouble(6).toFloat(),
        (3..6).map { i.getInt(it) },
        d.keys().asSequence().associateWith { d.getString(it) },
        (0 until f.length()).map { f.getString(it) }
    )
}
