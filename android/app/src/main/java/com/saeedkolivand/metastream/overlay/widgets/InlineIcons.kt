package com.saeedkolivand.metastream.overlay

import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ReplacementSpan
import androidx.core.graphics.PathParser

/**
 * Inline icons in text widgets (iOS TextRuns): "{i:clock} {time}" draws the named icon where it stands, sized to the text,
 * centred on its cap height, in the text colour. Names are the iOS SF Symbol names, so a scene reads the same on both apps;
 * each is a 24-unit vector path here (Material-style), drawn into the text bitmap once per string. Icons, never emoji.
 */
internal object InlineIcons {
    // circle(cx, cy, r) as two arcs, for the even-odd ring icons
    private fun o(cx: Float, cy: Float, r: Float) = "M${cx - r},${cy}a$r,$r 0,1 0,${2 * r},0a$r,$r 0,1 0,${-2 * r},0z"

    private const val CLOUD = "M19.35,10.04C18.67,6.59 15.64,4 12,4 9.11,4 6.6,5.64 5.35,8.04 2.34,8.36 0,10.91 0,14c0,3.31 2.69,6 6,6h13" +
        "c2.76,0 5,-2.24 5,-5 0,-2.64 -2.05,-4.78 -4.65,-4.96z"
    private const val HIGH_CLOUD =
        "M19.35,7.04C18.67,3.59 15.64,1 12,1 9.11,1 6.6,2.64 5.35,5.04 2.34,5.36 0,7.91 0,11c0,3.31 2.69,6 6,6h13" +
            "c2.76,0 5,-2.24 5,-5 0,-2.64 -2.05,-4.78 -4.65,-4.96z"
    private const val DROPS = "M7,19h2l-1.5,4h-2zM11,19h2l-1.5,4h-2zM15,19h2l-1.5,4h-2z"

    /** name -> (path data, even-odd). */
    private val paths: Map<String, Pair<String, Boolean>> = mapOf(
        "clock" to ("${o(12f, 12f, 10f)}${o(12f, 12f, 8f)}M11,6h1.5v5.25l4.5,2.67 -0.75,1.23L11,12z" to true),
        "record.circle" to ("${o(12f, 12f, 10f)}${o(12f, 12f, 8f)}${o(12f, 12f, 5f)}" to true),
        "eye" to (
            "M12,4.5C7,4.5 2.73,7.61 1,12c1.73,4.39 6,7.5 11,7.5s9.27,-3.11" +
                " 11,-7.5c-1.73,-4.39 -6,-7.5 -11,-7.5zM12,17c-2.76,0 -5,-2.24 -5,-5" +
                "s2.24,-5 5,-5 5,2.24 5,5 -2.24,5 -5,5zM12,9c-1.66,0 -3,1.34 -3,3s1.34,3 3,3 3,-1.34 3,-3 -1.34,-3 -3,-3z" to false
            ),
        "car.fill" to (
            "M18.92,6.01C18.72,5.42 18.16,5 17.5,5h-11c-0.66,0 -1.21,0.42" +
                " -1.42,1.01L3,12v8c0,0.55 0.45,1 1,1h1c0.55,0 1,-0.45 1,-1v-1h12v1" +
                "c0,0.55 0.45,1 1,1h1c0.55,0 1,-0.45 1,-1v-8zM5,11l1.5,-4.5h11L19,11z${o(6.5f, 14.5f, 1.5f)}${o(17.5f, 14.5f, 1.5f)}" to
                true
            ),
        "road.lanes" to ("M8,2h1.5L7,22H4.5zM14.5,2H16l3.5,20H17zM11.25,3h1.5v4h-1.5zM11.25,10h1.5v4h-1.5zM11.25,17h1.5v4h-1.5z" to false),
        "camera" to (
            "M9,2L7.17,4H4c-1.1,0 -2,0.9 -2,2v12c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V6c0,-1.1 -0.9,-2 -2,-2h-3.17L15,2z${o(
                12f,
                12f,
                5f
            )}" +
                o(12f, 12f, 3f) to true
            ),
        "music.note" to ("M12,3v10.55c-0.59,-0.34 -1.27,-0.55 -2,-0.55 -2.21,0 -4,1.79 -4,4s1.79,4 4,4 4,-1.79 4,-4V7h4V3h-6z" to false),
        "paperplane" to ("M2.01,21L23,12 2.01,3 2,10l15,2 -15,2z" to false),
        "flame" to (
            "M13.5,0.67s0.74,2.65 0.74,4.8c0,2.06 -1.35,3.73 -3.41,3.73 -2.07,0 -3.63,-1.67 -3.63,-3.73l0.03,-0.36C5.21,7.51 4,10.62 4,14" +
                "c0,4.42 3.58,8 8,8s8,-3.58 8,-8C20,8.61 17.41,3.8 13.5,0.67z" to false
            ),
        "stopwatch" to ("M9,1h6v2H9z${o(12f, 13f, 9f)}${o(12f, 13f, 7f)}M11,8h2v6h-2zM17.5,4.5l1.4,-1.4 1.5,1.5 -1.4,1.4z" to true),
        "mappin" to (
            "M12,2C8.13,2 5,5.13 5,9c0,5.25 7,13 7,13s7,-7.75 7,-13c0,-3.87 -3.13,-7 -7,-7z${o(12f, 9f, 2.5f)}" to true
            ),
        "heart.fill" to (
            "M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0" +
                " 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42" +
                " 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54z" to false
            ),
        "banknote" to ("M2,6h20v12H2z${o(12f, 12f, 3f)}M4,8h2v2H4zM18,14h2v2h-2z" to true),
        "target" to ("${o(12f, 12f, 10f)}${o(12f, 12f, 7.5f)}${o(12f, 12f, 5f)}${o(12f, 12f, 2.5f)}" to true),
        "star.fill" to ("M12,17.27L18.18,21l-1.64,-7.03L22,9.24l-7.19,-0.61L12,2 9.19,8.63 2,9.24l5.46,4.73L5.82,21z" to false),
        "bolt.fill" to ("M7,2v11h3v9l7,-12h-4l4,-8z" to false),
        "bell.fill" to (
            "M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 -1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5" +
                "s-1.5,0.67 -1.5,1.5v0.68C7.63,5.36 6,7.92 6,11v5l-2,2v1h16v-1z" to false
            ),
        "gift.fill" to ("M3,8h18v4H3zM4,13h7v8H4zM13,13h7v8h-7zM11,8h2v13h-2zM12,8C10,4 6,4 7,7zM12,8C14,4 18,4 17,7z" to false),
        "trophy.fill" to (
            "M19,5h-2V3H7v2H5c-1.1,0 -2,0.9 -2,2v1c0,2.55 1.92,4.63 4.39,4.94 0.63,1.5 1.98,2.63 3.61,2.96V19H7v2h10v-2h-4v-3.1" +
                "c1.63,-0.33 2.98,-1.46 3.61,-2.96C19.08,12.63 21,10.55 21,8V7c0,-1.1 -0.9,-2 -2,-2zM5,8V7h2v3.82C5.84,10.4 5,9.3 5,8z" +
                "M19,8c0,1.3 -0.84,2.4 -2,2.82V7h2z" to true
            ),
        "mic.fill" to (
            "M12,14c1.66,0 3,-1.34 3,-3V5c0,-1.66 -1.34,-3 -3,-3S9,3.34 9,5v6c0,1.66" +
                " 1.34,3 3,3zM17.3,11c0,3 -2.54,5.1 -5.3,5.1S6.7,14 6.7,11H5" +
                "c0,3.41 2.72,6.23 6,6.72V21h2v-3.28c3.28,-0.48 6,-3.3 6,-6.72z" to false
            ),
        "gamecontroller.fill" to (
            "M21,6H3c-1.1,0 -2,0.9 -2,2v8c0,1.1 0.9,2 2,2h18c1.1,0 2,-0.9 2,-2V8c0,-1.1 -0.9,-2 -2,-2zM11,13H8v3H6v-3H3v-2h3V8h2v3h3z" +
                "${o(15.5f, 13.5f, 1.5f)}${o(19.5f, 10.5f, 1.5f)}" to true
            ),
        "location.fill" to ("M21,3L3,10.53v0.98l6.84,2.65L12.48,21h0.98z" to false),
        "link" to (
            "M3.9,12c0,-1.71 1.39,-3.1 3.1,-3.1h4V7H7c-2.76,0 -5,2.24 -5,5s2.24,5 5,5h4v-1.9H7c-1.71,0 -3.1,-1.39 -3.1,-3.1zM8,13h8v-2H8z" +
                "M17,7h-4v1.9h4c1.71,0 3.1,1.39 3.1,3.1s-1.39,3.1 -3.1,3.1h-4V17h4c2.76,0 5,-2.24 5,-5s-2.24,-5 -5,-5z" to false
            ),
        "sun.max.fill" to (
            "${o(
                12f,
                12f,
                5f
            )}M11,1h2v3h-2zM11,20h2v3h-2zM1,11h3v2H1zM20,11h3v2h-3zM4.2,5.6l1.4,-1.4 2.1,2.1 -1.4,1.4zM16.3,17.7l1.4,-1.4" +
                " 2.1,2.1 -1.4,1.4zM4.2,18.4l2.1,-2.1 1.4,1.4 -2.1,2.1zM16.3,6.3l2.1,-2.1 1.4,1.4 -2.1,2.1z" to false
            ),
        "cloud.sun.fill" to ("${o(8f, 7f, 4f)}M5,1h1.5v2H5zM0,6h2v1.5H0z$CLOUD" to false),
        "cloud.fill" to (CLOUD to false),
        "cloud.fog.fill" to ("${HIGH_CLOUD}M2,19h20v1.5H2zM4,22h16v1.5H4z" to false),
        "cloud.rain.fill" to (HIGH_CLOUD + DROPS to false),
        "cloud.sun.rain.fill" to ("${o(7f, 5f, 3f)}$HIGH_CLOUD$DROPS" to false),
        "cloud.snow.fill" to ("$HIGH_CLOUD${o(7f, 21f, 1.3f)}${o(12f, 21f, 1.3f)}${o(17f, 21f, 1.3f)}" to false),
        "snowflake" to ("M11,1h2v22h-2zM1,11h22v2H1zM3.9,5.3l1.4,-1.4 14.8,14.8 -1.4,1.4zM18.7,3.9l1.4,1.4 -14.8,14.8 -1.4,-1.4z" to false),
        "cloud.bolt.rain.fill" to ("${HIGH_CLOUD}M11,17h3l-2,3h2l-4,4 1,-3h-2z" to false),
        "thermometer.medium" to ("M10,3a2,2 0,0 1,4 0v10.5a4,4 0,1 1,-4 0z" to false)
    )

    /** Icons the editor offers (same list and order as iOS). */
    val palette = listOf(
        "clock", "record.circle", "eye", "car.fill", "road.lanes", "camera", "music.note", "paperplane", "flame", "stopwatch", "mappin",
        "heart.fill", "banknote", "target", "star.fill", "bolt.fill", "bell.fill", "gift.fill", "trophy.fill", "mic.fill",
        "gamecontroller.fill", "location.fill", "cloud.sun.fill", "link"
    )

    private val cache = HashMap<String, Path?>()

    private fun path(name: String) = synchronized(cache) {
        cache.getOrPut(name) {
            paths[name]?.let { (d, evenOdd) ->
                runCatching { PathParser.createPathFromPathData(d) }.getOrNull()?.apply { if (evenOdd) fillType = Path.FillType.EVEN_ODD }
            }
        }
    }

    private val token = Regex("\\{i:([A-Za-z0-9._-]+)\\}")

    /** [text] with each well-formed {i:name} token drawn as its icon; malformed tokens stay text, unknown names draw nothing. */
    fun spans(text: String): CharSequence {
        if ("{i:" !in text) return text
        val out = SpannableStringBuilder()
        var at = 0
        for (m in token.findAll(text)) {
            out.append(text, at, m.range.first)
            val start = out.length
            out.append("￼")
            out.setSpan(IconSpan(m.groupValues[1]), start, out.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            at = m.range.last + 1
        }
        return out.append(text, at, text.length)
    }

    /** The icon as plain text gone, for places that can't draw (chat replies). */
    fun strip(text: String) = token.replace(text, "").replace(Regex(" {2,}"), " ").trim()

    /** The emoji old presets and saved scenes used, and the icon each stands for. */
    private val emojiIcons = listOf(
        "🕒" to "clock", "🔴" to "record.circle", "👁" to "eye", "🚗" to "car.fill", "🛣" to "road.lanes", "📷" to "camera",
        "🎵" to "music.note", "✈" to "paperplane", "🔥" to "flame", "⏱" to "stopwatch", "📍" to "mappin", "❤" to "heart.fill",
        "💸" to "banknote", "🎯" to "target"
    )

    /** [text] with those emoji swapped for icon tokens (a variation selector after one goes with it). Idempotent. */
    fun iconized(text: String): String {
        var out = text.replace("️", "")
        for ((emoji, name) in emojiIcons) out = out.replace(emoji, "{i:$name}")
        return out
    }

    private class IconSpan(val name: String) : ReplacementSpan() {
        override fun getSize(paint: Paint, text: CharSequence?, start: Int, end: Int, fm: Paint.FontMetricsInt?): Int {
            fm?.let { paint.getFontMetricsInt(it) }
            return (paint.textSize * 1.05f).toInt()
        }

        override fun draw(c: Canvas, text: CharSequence?, start: Int, end: Int, x: Float, top: Int, y: Int, bottom: Int, paint: Paint) {
            val p = path(name) ?: return
            val size = paint.textSize
            val capMid = y - size * 0.36f // centred on the cap height, like iOS
            val m = Matrix().apply {
                setScale(size / 24f, size / 24f)
                postTranslate(x + size * 0.025f, capMid - size / 2)
            }
            val scaled = Path(p).apply { transform(m) }
            c.drawPath(scaled, Paint(paint).apply { style = Paint.Style.FILL }) // same colour and shadow as the text
        }
    }
}
