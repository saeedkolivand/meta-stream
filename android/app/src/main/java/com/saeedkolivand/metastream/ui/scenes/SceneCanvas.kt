package com.saeedkolivand.metastream.ui.scenes

import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.overlay.Box
import com.saeedkolivand.metastream.overlay.Layer
import com.saeedkolivand.metastream.overlay.LayerType
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.overlay.fit
import com.saeedkolivand.metastream.overlay.place
import com.saeedkolivand.metastream.overlay.previewBitmap
import com.saeedkolivand.metastream.overlay.widgetBox
import com.saeedkolivand.metastream.overlay.widgetLayoutFor
import com.saeedkolivand.metastream.ui.SystemBlue
import com.saeedkolivand.metastream.ui.rememberHaptic
import kotlin.math.abs
import kotlin.math.roundToInt

private val GuideColor = Color(0xFFFFD60A)
private const val INSET_X = 0.025f
private const val INSET_Y = 0.04f

/** An in-flight drag/pinch in canvas view px; nothing is written to the store until it ends. */
private class Gesture(val index: Int, val drag: Offset, val zoom: Float)

private class Live(val rect: Rect, val gx: List<Float>, val gy: List<Float>)

/** Same fallback the editor and the compositor share, so the box matches what's drawn. */
private fun natural(l: Layer): Pair<Float, Float> = OverlayStore.naturalSize(l) ?: (400f to 200f)

/** The layer's rectangle in output px: widgets by their frame-relative layout, OBS layers through fit + place. */
private fun layerBox(l: Layer, outW: Int, outH: Int): Box? {
    val (nw, nh) = natural(l)
    l.layout?.let { return widgetBox(it, nw, nh, outW.toFloat(), outH.toFloat()) }
    val pack = OverlayStore.pack ?: return null
    return fit(pack.canvasW, pack.canvasH, outW, outH).apply(place(l, nw, nh))
}

/** Pinch factor actually applied: a widget's scale is clamped, so the factor is whatever lands inside the limits. */
private fun multiplier(l: Layer, zoom: Float): Float {
    val s = l.layout?.scale?.takeIf { it > 0f } ?: return zoom.coerceIn(0.1f, 8f)
    return (s * zoom).coerceIn(0.05f, 4f) / s
}

private fun snapAxis(edges: List<Float>, targets: List<Float>, tol: Float): Pair<Float, List<Float>> {
    var best: Pair<Float, Float>? = null
    for (e in edges) {
        for (t in targets) {
            if (abs(t - e) <= tol && abs(t - e) < abs(best?.first ?: Float.MAX_VALUE)) best = (t - e) to t
        }
    }
    return best?.let { it.first to listOf(it.second) } ?: (0f to emptyList())
}

/** Edges and centre against the canvas edges, the safe inset and the centre lines; nearest within [tol]. */
private fun snap(r: Rect, w: Float, h: Float, tol: Float): Live {
    val (dx, gx) = snapAxis(listOf(r.left, r.center.x, r.right), listOf(0f, w * INSET_X, w / 2, w * (1 - INSET_X), w), tol)
    val (dy, gy) = snapAxis(listOf(r.top, r.center.y, r.bottom), listOf(0f, h * INSET_Y, h / 2, h * (1 - INSET_Y), h), tol)
    return Live(r.translate(dx, dy), gx, gy)
}

private fun live(l: Layer, b: Box, g: Gesture?, k: Float, outW: Int, outH: Int, tol: Float): Live {
    val r = Rect(b.x * k, b.y * k, (b.x + b.w) * k, (b.y + b.h) * k)
    if (g == null) return Live(r, emptyList(), emptyList())
    val m = multiplier(l, g.zoom)
    val scaled = Rect(r.center - Offset(r.width * m / 2, r.height * m / 2), Size(r.width * m, r.height * m))
    return snap(scaled.translate(g.drag), outW * k, outH * k, tol)
}

/** The layer after a finished gesture: a widget through widgetLayoutFor (exact); OBS layers move by their centre. */
private fun committed(l: Layer, b: Box, out: Box, zoom: Float, outW: Int, outH: Int): Layer {
    val m = multiplier(l, zoom)
    l.layout?.let {
        val (nw, nh) = natural(l)
        return l.copy(layout = widgetLayoutFor(out, nw, nh, outW.toFloat(), outH.toFloat(), it.scale * m))
    }
    val pack = OverlayStore.pack ?: return l
    val f = fit(pack.canvasW, pack.canvasH, outW, outH).scale
    // ponytail: OBS layers scale about their own anchor, so corner-anchored ones land a few px off; widgets are exact.
    val moved = l.copy(x = l.x + (out.x + out.w / 2 - b.x - b.w / 2) / f, y = l.y + (out.y + out.h / 2 - b.y - b.h / 2) / f)
    return if (l.boundsType != 0) moved.copy(bw = l.bw * m, bh = l.bh * m) else moved.copy(sx = l.sx * m, sy = l.sy * m)
}

private data class PreviewKey(val type: LayerType, val data: Map<String, String>, val files: List<String>, val scale: Int)

/** Bitmaps by layer content, so dragging and selecting never re-render a chat; quantised scale keeps pinches from thrashing it. */
private class PreviewCache {
    private val map = HashMap<PreviewKey, android.graphics.Bitmap?>()

    fun get(l: Layer, scale: Float): android.graphics.Bitmap? {
        val q = (scale * 100).roundToInt().coerceAtLeast(1)
        if (map.size > 48) map.clear()
        // ponytail: rendered on the main thread at draw time; a sample chat is a few ms. Upgrade path: render off-thread.
        return map.getOrPut(PreviewKey(l.type, l.data, l.files, q)) { previewBitmap(l, q / 100f) }
    }
}

@Composable
internal fun SceneCanvas(
    layers: List<Layer>,
    outW: Int,
    outH: Int,
    selected: Int?,
    onSelect: (Int?) -> Unit,
    onCommit: (Int, Layer) -> Unit
) {
    val haptic = rememberHaptic()
    val measurer = rememberTextMeasurer()
    val cache = remember { PreviewCache() }
    var width by remember { mutableStateOf(0f) }
    var gesture by remember { mutableStateOf<Gesture?>(null) }
    val k = if (width > 0f) width / outW else 0f
    val boxes = remember(layers, outW, outH) { layers.map { layerBox(it, outW, outH) } }
    val images = remember(layers, boxes, k) {
        layers.mapIndexed { i, l ->
            val b = boxes[i]
            if (!l.visible || b == null || k == 0f) null else cache.get(l, b.w * k / natural(l).first.coerceAtLeast(1f))?.asImageBitmap()
        }
    }
    val tol = with(androidx.compose.ui.platform.LocalDensity.current) { 12.dp.toPx() }
    val grab = tol * 2 / 3
    val layersNow by rememberUpdatedState(layers)
    val boxesNow by rememberUpdatedState(boxes)
    val kNow by rememberUpdatedState(k)
    val selectedNow by rememberUpdatedState(selected)
    val select by rememberUpdatedState(onSelect)
    val commit by rememberUpdatedState(onCommit)

    fun liveOf(i: Int, g: Gesture?): Live? =
        boxesNow[i]?.let { live(layersNow[i], it, g?.takeIf { x -> x.index == i }, kNow, outW, outH, tol) }

    /** Topmost visible layer under the point; the selected one wins ties so overlapping widgets stay grabbable. */
    fun hit(p: Offset): Int? {
        fun at(i: Int) = layersNow[i].visible && liveOf(i, null)?.rect?.inflate(grab)?.contains(p) == true
        return selectedNow?.takeIf { it in layersNow.indices && at(it) } ?: layersNow.indices.reversed().firstOrNull(::at)
    }

    Canvas(
        Modifier.fillMaxSize().onSizeChanged { width = it.width.toFloat() }.semantics { contentDescription = "Scene canvas" }
            .pointerInput(outW, outH) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val i = hit(down.position)
                    select(i)
                    if (i == null) {
                        waitForUpOrCancellation()
                        return@awaitEachGesture
                    }
                    var drag = Offset.Zero
                    var zoom = 1f
                    var lastGuides = ""
                    do {
                        val ev = awaitPointerEvent()
                        zoom *= ev.calculateZoom()
                        drag += ev.calculatePan()
                        val g = Gesture(i, drag, zoom)
                        gesture = g
                        val guides = liveOf(i, g)?.let { it.gx.toString() + it.gy.toString() }.orEmpty()
                        if (guides != lastGuides && guides != "[][]") haptic(false)
                        lastGuides = guides
                        ev.changes.forEach { it.consume() }
                    } while (ev.changes.any { it.pressed })
                    gesture = null
                    val moved = drag.getDistance() > grab / 2 || abs(zoom - 1f) > 0.01f
                    val b = boxesNow[i]
                    val r = liveOf(i, Gesture(i, drag, zoom))?.rect
                    if (moved && b != null && r != null) {
                        val kk = kNow
                        val out = Box(r.left / kk, r.top / kk, r.width / kk, r.height / kk)
                        commit(i, committed(layersNow[i], b, out, zoom, outW, outH))
                    }
                }
            }
    ) {
        drawRect(Color(0xFF141416))
        for (f in listOf(1f / 3, 2f / 3)) {
            drawLine(Color.White.copy(alpha = 0.07f), Offset(size.width * f, 0f), Offset(size.width * f, size.height))
            drawLine(Color.White.copy(alpha = 0.07f), Offset(0f, size.height * f), Offset(size.width, size.height * f))
        }
        val g = gesture
        layers.forEachIndexed { i, l ->
            val r = (if (l.visible) liveOf(i, g)?.rect else null) ?: return@forEachIndexed
            val img = images.getOrNull(i)
            if (img != null) {
                drawImage(
                    img,
                    dstOffset = IntOffset(r.left.roundToInt(), r.top.roundToInt()),
                    dstSize = IntSize(r.width.roundToInt().coerceAtLeast(1), r.height.roundToInt().coerceAtLeast(1))
                )
            } else {
                drawRect(Color.White.copy(alpha = 0.08f), r.topLeft, r.size)
                val dash = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 8f)))
                drawRect(Color.White.copy(alpha = 0.5f), r.topLeft, r.size, style = dash)
                val label = if (l.type == LayerType.Browser) Uri.parse(l.data["url"].orEmpty()).host ?: l.name else l.name
                drawText(measurer, label, r.topLeft + Offset(6.dp.toPx(), 4.dp.toPx()), TextStyle(Color.White, 11.sp))
            }
        }
        val sel = selected?.takeIf { it in layers.indices && layers[it].visible }?.let { liveOf(it, g)?.rect }
        if (sel != null) {
            drawRect(SystemBlue, sel.topLeft, sel.size, style = Stroke(1.5.dp.toPx()))
            for (c in listOf(sel.topLeft, sel.topRight, sel.bottomLeft, sel.bottomRight)) drawCircle(SystemBlue, 4.dp.toPx(), c)
        }
        g?.let { liveOf(it.index, it) }?.let { lv ->
            for (x in lv.gx) drawLine(GuideColor, Offset(x, 0f), Offset(x, size.height), 1.dp.toPx())
            for (y in lv.gy) drawLine(GuideColor, Offset(0f, y), Offset(size.width, y), 1.dp.toPx())
        }
    }
}
