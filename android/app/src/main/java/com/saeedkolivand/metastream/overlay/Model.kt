package com.saeedkolivand.metastream.overlay

import org.json.JSONArray
import org.json.JSONObject

enum class LayerType { Browser, Image, Media, Text, Color, Slideshow, Chat, Alerts, Events, Qr }

/**
 * Frame-relative placement for in-app widgets, so a layout survives portrait/landscape: [anchor] 0..8 row-major
 * (0 TL, 1 TC, 2 TR, 3 ML, 4 C, 5 MR, 6 BL, 7 BC, 8 BR); [dx]/[dy] are offsets as a fraction of output width/height
 * (+ right/down); [scale] multiplies the natural size, which is defined for a 1080 px short side.
 */
data class WidgetLayout(val anchor: Int = 6, val dx: Float = 0f, val dy: Float = 0f, val scale: Float = 1f) {
    companion object {
        /** Keeps clear of the screen edge (2.5% W / 4% H), nothing on centre axes. */
        fun inset(anchor: Int, scale: Float = 1f): WidgetLayout {
            val dx = when (anchor % 3) {
                0 -> INSET_X
                2 -> -INSET_X
                else -> 0f
            }
            val dy = when (anchor / 3) {
                0 -> INSET_Y
                2 -> -INSET_Y
                else -> 0f
            }
            return WidgetLayout(anchor, dx, dy, scale)
        }

        const val INSET_X = 0.025f
        const val INSET_Y = 0.04f
    }
}

/**
 * One OBS scene item, flattened (group transforms already applied). Position/scale/bounds are canvas px.
 * [data] holds the type's payload as strings: browser url/width/height/css, image/media file, text/face/size/color,
 * color/width/height. [files] is the slideshow list. A non-null [layout] means an in-app widget (OBS transform fields unused).
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
    val files: List<String> = emptyList(),
    val layout: WidgetLayout? = null
)

/** [camera] is "back"|"front"|"external"|"glasses"|"auto", or null to keep whatever is current. */
data class Scene(val name: String, val layers: List<Layer>, val camera: String? = null)

/** A visible in-app widget with neutral OBS fields; placement comes from [layout]. */
fun widgetLayer(type: LayerType, name: String, layout: WidgetLayout, data: Map<String, String>) = Layer(
    type, name, true, 0f, 0f, 1f, 1f, 5, 0, 0f, 0f, 0, 0f, listOf(0, 0, 0, 0), data, emptyList(), layout
)

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
        .put("scenes", JSONArray(scenes.map(::sceneJson)))
        .toString()

    companion object {
        fun fromJson(text: String): Pack {
            val o = JSONObject(text)
            val sk = o.getJSONObject("skipped")
            return Pack(
                o.getInt("w"),
                o.getInt("h"),
                o.getJSONArray("scenes").objects().map { s ->
                    Scene(
                        s.getString("name"),
                        s.getJSONArray("layers").objects().map(::layerOf),
                        s.optString("cam").takeIf { it.isNotEmpty() }
                    )
                },
                sk.keys().asSequence().associateWith { sk.getInt(it) }
            )
        }
    }
}

private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }

private fun sceneJson(s: Scene) = JSONObject().put("name", s.name).put("layers", JSONArray(s.layers.map(::layerJson))).apply {
    s.camera?.let { put("cam", it) }
}

private fun layerJson(l: Layer) = JSONObject().put("t", l.type.name).put("n", l.name).put("v", l.visible)
    .put("pos", JSONArray(listOf(l.x, l.y, l.sx, l.sy, l.bw, l.bh, l.rotation)))
    .put("ints", JSONArray(listOf(l.align, l.boundsType, l.boundsAlign) + l.crop))
    .put("d", JSONObject(l.data as Map<*, *>)).put("f", JSONArray(l.files)).apply {
        l.layout?.let { put("lay", JSONArray(listOf(it.anchor, it.dx, it.dy, it.scale))) }
    }

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
        (0 until f.length()).map { f.getString(it) },
        o.optJSONArray("lay")?.let {
            WidgetLayout(it.getInt(0), it.getDouble(1).toFloat(), it.getDouble(2).toFloat(), it.getDouble(3).toFloat())
        }
    )
}
