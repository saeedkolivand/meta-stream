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
