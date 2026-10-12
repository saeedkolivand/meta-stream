package com.saeedkolivand.metastream.overlay

import kotlin.math.min

private const val LEFT = 1
private const val RIGHT = 2
private const val TOP = 4
private const val BOTTOM = 8

/** Left/top/width/height. */
data class Box(val x: Float, val y: Float, val w: Float, val h: Float)

/** Where the canvas sits in the output: uniform scale, centered. */
data class Fit(val scale: Float, val offX: Float, val offY: Float) {
    fun apply(b: Box) = Box(offX + b.x * scale, offY + b.y * scale, b.w * scale, b.h * scale)
}

fun fit(canvasW: Int, canvasH: Int, outW: Int, outH: Int): Fit {
    val s = min(outW.toFloat() / canvasW, outH.toFloat() / canvasH)
    return Fit(s, (outW - canvasW * s) / 2, (outH - canvasH * s) / 2)
}

private fun anchor(pos: Float, size: Float, align: Int, lo: Int, hi: Int) = when {
    align and lo != 0 -> pos
    align and hi != 0 -> pos - size
    else -> pos - size / 2
}

private fun inside(start: Float, outer: Float, inner: Float, align: Int, lo: Int, hi: Int) = when {
    align and lo != 0 -> start
    align and hi != 0 -> start + outer - inner
    else -> start + (outer - inner) / 2
}

/** The item's rectangle in canvas px for a source of natural size nw x nh (already cropped), per OBS transform rules. */
fun place(l: Layer, nw: Float, nh: Float): Box {
    var w = nw * l.sx
    var h = nh * l.sy
    if (l.boundsType == 0 || l.bw <= 0 || l.bh <= 0) {
        return Box(anchor(l.x, w, l.align, LEFT, RIGHT), anchor(l.y, h, l.align, TOP, BOTTOM), w, h)
    }
    val rx = l.bw / nw
    val ry = l.bh / nh
    // OBS bounds types: 1 stretch, 2 scale inner, 3 scale outer, 4 to width, 5 to height, 6 max only.
    // ponytail: "outer" (cover) is drawn as inner, since object filters can't clip to the bounds.
    val (fx, fy) = when (l.boundsType) {
        1 -> rx to ry
        2, 3 -> min(rx, ry).let { it to it }
        4 -> rx to rx
        5 -> ry to ry
        else -> min(1f, min(rx, ry)).let { it to it }
    }
    w = nw * fx
    h = nh * fy
    val bx = anchor(l.x, l.bw, l.align, LEFT, RIGHT)
    val by = anchor(l.y, l.bh, l.align, TOP, BOTTOM)
    return Box(inside(bx, l.bw, w, l.boundsAlign, LEFT, RIGHT), inside(by, l.bh, h, l.boundsAlign, TOP, BOTTOM), w, h)
}

private fun widgetScale(layout: WidgetLayout, outW: Float, outH: Float) = layout.scale * min(outW, outH) / 1080f

/**
 * An in-app widget's rectangle in output px. Its size is the natural size times [WidgetLayout.scale] at a 1080 px
 * short side; the anchor point on the frame (and the same point on the widget) are pinned together, then offset by dx/dy.
 */
fun widgetBox(layout: WidgetLayout, nw: Float, nh: Float, outW: Float, outH: Float): Box {
    val s = widgetScale(layout, outW, outH)
    val w = nw * s
    val h = nh * s
    val col = layout.anchor % 3
    val row = layout.anchor / 3
    return Box(col * outW / 2 - col * w / 2 + layout.dx * outW, row * outH / 2 - row * h / 2 + layout.dy * outH, w, h)
}

private fun third(c: Float, size: Float) = (c / size * 3).toInt().coerceIn(0, 2)

/** Inverse of [widgetBox]: the anchor nearest the box centre (by thirds), with dx/dy so the box is reproduced at [scale]. */
fun widgetLayoutFor(box: Box, nw: Float, nh: Float, outW: Float, outH: Float, scale: Float): WidgetLayout {
    val col = third(box.x + box.w / 2, outW)
    val row = third(box.y + box.h / 2, outH)
    val s = widgetScale(WidgetLayout(scale = scale), outW, outH)
    val dx = (box.x - (col * outW / 2 - col * nw * s / 2)) / outW
    val dy = (box.y - (row * outH / 2 - row * nh * s / 2)) / outH
    return WidgetLayout(row * 3 + col, dx, dy, scale)
}
