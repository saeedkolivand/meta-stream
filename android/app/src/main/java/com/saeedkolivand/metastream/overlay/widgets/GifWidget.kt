package com.saeedkolivand.metastream.overlay

import com.pedro.encoder.input.gl.render.filters.`object`.GifFilterRender
import java.io.File
import java.io.FileInputStream

private const val HEADER = 6

/**
 * True for a GIF with more than one frame. Frames are counted as graphic control extensions (21 F9 04) in the bytes.
 * ponytail: a still GIF whose pixel data happens to contain that sequence twice is misread as animated; it then just plays
 * as a one-frame loop. Upgrade path: walk the block structure properly.
 */
private fun isAnimatedGif(f: File): Boolean {
    val bytes = runCatching { f.readBytes() }.getOrNull() ?: return false
    if (bytes.size < HEADER || String(bytes, 0, 4, Charsets.US_ASCII) != "GIF8") return false
    var frames = 0
    for (i in 0 until bytes.size - 2) {
        if (bytes[i] == 0x21.toByte() && bytes[i + 1] == 0xF9.toByte() && bytes[i + 2] == 0x04.toByte() && ++frames > 1) return true
    }
    return false
}

/**
 * Animated GIF layer: RootEncoder decodes and steps the frames itself on the GL thread, so there is no job here.
 * Null when the file is missing or isn't an animated GIF, and the caller falls back to the still image path.
 */
internal fun gifWidget(l: Layer, box: Box, outW: Int, outH: Int): WidgetBuild? {
    val file = OverlayStore.local(l.data["file"].orEmpty())?.takeIf(::isAnimatedGif) ?: return null
    val filter = GifFilterRender()
    // ponytail: the OBS crop is ignored for GIFs; the whole animation is scaled into the box.
    val ok = runCatching { FileInputStream(file).use { filter.setGif(it) } }.isSuccess
    if (!ok) return null
    filter.placeIn(box, outW, outH, l.rotation)
    return WidgetBuild(filter, null)
}
