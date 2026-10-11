package com.saeedkolivand.metastream.ui

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.em
import kotlin.math.hypot
import kotlin.math.min

private val Launch = Color(0xFF1D0A5D) // identical to the native splash background: no flash
private val Cyan = Color(0xFF3DE8FF)
private val Magenta = Color(0xFFC84BFF)
private val Violet = Color(0xFF6D3BFF)
private val Pink = Color(0xFFFF1F5A)
private val DotOrange = Color(0xFFFF7A3D)
private const val HALF_SWEEP = 42f
private const val STATIC_T = 1100f // reduce motion: final mark, no pulse, no zoom

/** Animated "live broadcast" mark, once per cold launch. Draws over the already-running app. */
@Composable
fun Splash(onDone: () -> Unit) {
    val ctx = LocalContext.current
    val reduce =
        remember {
            Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }
    val clock = remember { Animatable(0f) }
    val measurer = rememberTextMeasurer()
    LaunchedEffect(Unit) {
        val end = if (reduce) 850f else 1950f
        clock.animateTo(end, tween(end.toInt(), easing = LinearEasing))
        onDone()
    }
    Canvas(
        Modifier
            .fillMaxSize()
            .graphicsLayer {
                val t = clock.value
                alpha = if (reduce) 1f - segment(t, 600f, 250f) else 1f - segment(t, 1650f, 300f)
            }
            // Swallow touches so nothing underneath (GO LIVE) is hit while visible.
            .pointerInput(Unit) {
                awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } }
            }
    ) { drawSplash(if (reduce) STATIC_T else clock.value, !reduce, measurer) }
}

private fun DrawScope.drawSplash(t: Float, animated: Boolean, measurer: TextMeasurer) {
    val u = 0.62f * min(size.width, size.height) / 55f
    val c = center
    drawRect(Launch)
    drawRect(
        Brush.linearGradient(listOf(Color(0xFF340E9E), Color(0xFF06051C)), Offset.Zero, Offset(size.width, size.height)),
        alpha = eased(t, 0f, 350f)
    )
    val zoom = if (animated) 1f + 8f * eased(t, 1500f, 450f, ::easeIn) else 1f
    withTransform({ scale(zoom, zoom, c) }) { drawMark(t, u, c, animated) }
    if (animated) drawRings(t, u, c)
    drawWordmark(t, u, c, measurer)
}

private fun glow(color: Color, peak: Float, c: Offset, r: Float) = Brush.radialGradient(
    0f to color.copy(alpha = peak),
    0.5f to color.copy(alpha = peak * 0.25f),
    1f to color.copy(alpha = 0f),
    center = c,
    radius = r
)

private fun DrawScope.drawMark(t: Float, u: Float, c: Offset, animated: Boolean) {
    val glowIn = eased(t, 0f, 500f)
    val violetR = 42f * u * (0.6f + 0.4f * glowIn)
    drawCircle(glow(Violet, 0.65f * glowIn, c, violetR), violetR, c)
    val dotIn = segment(t, 150f, 450f)
    drawCircle(glow(Pink, 0.6f * easeOut(dotIn), c, 16f * u), 16f * u, c)

    val inner = eased(t, 350f, 300f)
    drawArcs(13f * u, u, c, inner * HALF_SWEEP, SolidColor(Color.White), inner)
    val outer = eased(t, 550f, 300f)
    drawArcs(23f * u, u, c, outer * HALF_SWEEP, outlineBrush(u, c), outer)

    var s = pop(dotIn)
    if (animated) s *= beat(t, 900f, 250f) * beat(t, 1150f, 250f)
    val r = 7.5f * u * s
    drawCircle(Brush.verticalGradient(listOf(DotOrange, Pink), c.y - r, c.y + r), r, c)
    drawCircle(Color.White, 2.4f * u * s, c - Offset(2.6f * u, 2.6f * u) * s, alpha = 0.35f * dotIn)
}

private fun outlineBrush(u: Float, c: Offset) = Brush.verticalGradient(listOf(Cyan, Magenta), c.y - 25.5f * u, c.y + 25.5f * u)

/** A right and a left arc growing outward from their midpoints (0 and 180 degrees). */
private fun DrawScope.drawArcs(radius: Float, u: Float, c: Offset, sweep: Float, brush: Brush, alpha: Float) {
    if (sweep <= 0f) return
    val tl = c - Offset(radius, radius)
    val box = Size(radius * 2, radius * 2)
    val stroke = Stroke(5f * u, cap = StrokeCap.Round)
    drawArc(brush, -sweep, 2 * sweep, false, tl, box, alpha, stroke)
    drawArc(brush, 180f - sweep, 2 * sweep, false, tl, box, alpha, stroke)
}

private fun DrawScope.drawRings(t: Float, u: Float, c: Offset) {
    val grad = outlineBrush(u, c)
    val maxR = 0.75f * hypot(size.width, size.height)
    for (start in listOf(900f, 1150f)) {
        val p = segment(t, start, 700f)
        if (p <= 0f || p >= 1f) continue
        val e = easeOut(p)
        drawCircle(grad, 8f * u + (maxR - 8f * u) * e, c, alpha = 0.7f * (1f - e), style = Stroke(1.2f * u))
    }
}

private fun DrawScope.drawWordmark(t: Float, u: Float, c: Offset, measurer: TextMeasurer) {
    val fadeIn = eased(t, 700f, 400f)
    val alpha = fadeIn * (1f - segment(t, 1500f, 150f))
    if (alpha <= 0f) return
    val style =
        TextStyle(
            color = Color.White.copy(alpha = alpha),
            fontSize = (9f * u).toSp(),
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (0.35f - 0.27f * fadeIn).em
        )
    val layout = measurer.measure("MetaStream", style)
    val y = c.y + 40f * u - layout.size.height / 2f + 6f * u * (1f - fadeIn)
    drawText(layout, topLeft = Offset(c.x - layout.size.width / 2f, y))
}
