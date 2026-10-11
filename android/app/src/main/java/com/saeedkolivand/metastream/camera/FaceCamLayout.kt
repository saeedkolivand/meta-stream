package com.saeedkolivand.metastream.camera

import kotlin.math.min

private val CORNERS = setOf("topLeft", "topRight", "bottomLeft", "bottomRight")
private val SIZES = setOf("s", "m", "l")
private val SHAPES = setOf("rounded", "circle")

/** Window options; the strings and defaults are iOS's dualCam* values so both apps describe the same layout. */
data class FaceCamOptions(val corner: String = "topRight", val size: String = "m", val shape: String = "rounded") {
    companion object {
        /** Unknown or missing values fall back to the defaults instead of failing. */
        fun parse(corner: String?, size: String?, shape: String?) = FaceCamOptions(
            corner?.takeIf { it in CORNERS } ?: "topRight",
            size?.takeIf { it in SIZES } ?: "m",
            shape?.takeIf { it in SHAPES } ?: "rounded"
        )
    }
}

/** A window in output pixels, top-left origin. */
data class FaceRect(val x: Float, val y: Float, val w: Float, val h: Float) {
    fun contains(px: Float, py: Float) = px >= x && px <= x + w && py >= y && py <= y + h
}

/**
 * iOS pipRect: the window is a fraction of the output's short side (S .22 / M .30 / L .40) inset by 4%. Rounded is 16:9 in
 * the output's own orientation, circle is square.
 */
fun faceRect(outW: Int, outH: Int, o: FaceCamOptions): FaceRect {
    val short = min(outW, outH).toFloat()
    val f = when (o.size) {
        "s" -> 0.22f
        "l" -> 0.40f
        else -> 0.30f
    }
    val m = short * 0.04f
    val (w, h) = when {
        o.shape == "circle" -> short * f to short * f
        outH >= outW -> short * f to short * f * 16 / 9
        else -> short * f * 16 / 9 to short * f
    }
    val x = if (o.corner.endsWith("Left")) m else outW - w - m
    val y = if (o.corner.startsWith("top")) m else outH - h - m
    return FaceRect(x, y, w, h)
}

/** iOS pipCornerRadius, in output pixels. */
fun faceRadius(r: FaceRect, shape: String) = if (shape == "circle") r.w / 2 else min(r.w, r.h) * 0.12f

/**
 * The first set of cameras that may run together holding [backId] and a front camera, or any back+front pair when
 * [backId] is null. Pure so the pairing rule is testable without a device.
 */
fun frontPartner(sets: Set<Set<String>>, backId: String?, isFront: (String) -> Boolean, isBack: (String) -> Boolean): String? =
    sets.firstNotNullOfOrNull { s ->
        if (backId != null && backId !in s) return@firstNotNullOfOrNull null
        if (backId == null && s.none(isBack)) return@firstNotNullOfOrNull null
        s.firstOrNull(isFront)
    }
