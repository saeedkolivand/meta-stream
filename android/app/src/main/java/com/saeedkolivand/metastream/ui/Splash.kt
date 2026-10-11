package com.saeedkolivand.metastream.ui

import android.provider.Settings
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.em
import kotlin.math.hypot
import kotlin.math.min
import kotlinx.coroutines.flow.first

private val Launch = Color(0xFF121214) // identical to the native splash background: no flash
private val BgTop = Color(0xFF1C1C1F)
private val BgBottom = Color(0xFF0A0A0C)
private val Silver = Color(0xFFC8C8CE)
private val Titanium = Color(0xFF3A3A3E)
private val GlassCenter = Color(0xFF16181E)
private val GlassEdge = Color(0xFF020203)
private val LedTop = Color(0xFFFF5A3C)
private val LedBottom = Color(0xFFE8101E)
private val Bloom = Color(0xFFFF2814)
private const val END_MS = 1750f
private const val REDUCED_END_MS = 850f
private const val STATIC_T = 1000f // reduce motion: finished lens, before the camera wakes

/** "Lens reveal": the icon's lens assembles, then opens onto the already-running app. Once per cold launch. */
@Composable
fun Splash(onDone: () -> Unit) {
    val ctx = LocalContext.current
    val view = LocalView.current
    val reduce =
        remember {
            Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }
    val clock = remember { Animatable(0f) }
    val measurer = rememberTextMeasurer()
    LaunchedEffect(Unit) {
        val end = if (reduce) REDUCED_END_MS else END_MS
        clock.animateTo(end, tween(end.toInt(), easing = LinearEasing))
        onDone()
    }
    LaunchedEffect(Unit) {
        if (reduce) return@LaunchedEffect
        snapshotFlow { clock.value }.first { it >= 1000f }
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }
    Canvas(
        Modifier
            .fillMaxSize()
            .graphicsLayer { alpha = if (reduce) 1f - easeOut(segment(clock.value, 600f, 250f)) else 1f }
            // Swallow touches so nothing underneath (GO LIVE) is hit while visible.
            .pointerInput(Unit) {
                awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } }
            }
    ) { drawSplash(if (reduce) STATIC_T else clock.value, measurer) }
}

private fun DrawScope.drawSplash(t: Float, measurer: TextMeasurer) {
    val m = min(size.width, size.height)
    val c = center
    val reveal = easeInOutCubic(segment(t, 1200f, 550f))
    val maxR = 0.75f * hypot(size.width, size.height) + 0.05f * m
    val rimR = lerp(0.199f * m, maxR, reveal)
    val rimW = lerp(0.022f * m, 0.035f * m, reveal)
    val holeR = rimR - rimW / 2f // inner edge of the rim
    val wake = easeOut(segment(t, 1000f, 200f)) // the camera shows through from here on
    val bg = Brush.verticalGradient(listOf(BgTop, BgBottom), 0f, size.height)
    val bgIn = eased(t, 0f, 300f)

    // Outside the rim the background is always drawn; inside it clears as the camera wakes.
    val outside =
        Path().apply {
            fillType = PathFillType.EvenOdd
            addRect(Rect(Offset.Zero, size))
            addOval(Rect(c, holeR))
        }
    drawPath(outside, Launch)
    drawPath(outside, bg, alpha = bgIn)
    drawCircle(Launch, holeR, c, alpha = 1f - wake)
    drawCircle(bg, holeR, c, alpha = bgIn * (1f - wake))

    drawGlass(t, m, c, 1f - wake)
    drawRim(t, m, c, rimR, rimW)
    drawLed(t, m, c)
    drawWordmark(t, m, c, measurer)
}

private fun DrawScope.drawGlass(t: Float, m: Float, c: Offset, keep: Float) {
    val glassR = 0.188f * m
    val glass = eased(t, 200f, 300f) * keep
    drawCircle(Brush.radialGradient(listOf(GlassCenter, GlassEdge), c, glassR), glassR, c, alpha = glass)
    drawCircle(
        Color.White,
        0.1285f * m,
        c,
        alpha = 0.07f * eased(t, 500f, 300f) * keep,
        style = Stroke(0.0025f * m)
    )
    val reflect = eased(t, 600f, 300f) * keep
    if (reflect <= 0f) return
    val r = 0.169f * m
    val a = Path().apply { addOval(Rect(c + Offset(-0.019f * m, -0.019f * m), r)) }
    val b = Path().apply { addOval(Rect(c + Offset(0f, 0.0125f * m), r)) }
    val crescent = Path.combine(PathOperation.Difference, a, b)
    val lens = Path().apply { addOval(Rect(c, glassR)) }
    // Unblurred, so slightly lower alpha than the 0.16 of the blurred icon.
    clipPath(lens) { drawPath(crescent, Color.White, alpha = 0.12f * reflect) }
}

private fun DrawScope.drawRim(t: Float, m: Float, c: Offset, r: Float, w: Float) {
    val alpha = 1f - segment(t, 1580f, 170f)
    // Trimmed from 12 o'clock clockwise.
    val sweep = 360f * easeInOutCubic(segment(t, 200f, 600f))
    if (sweep <= 0f || alpha <= 0f) return
    val shade = Brush.linearGradient(listOf(Silver, Titanium), c - Offset(0.15f * m, 0.15f * m), c + Offset(0.15f * m, 0.15f * m))
    drawArc(
        shade,
        startAngle = -90f,
        sweepAngle = sweep,
        useCenter = false,
        topLeft = c - Offset(r, r),
        size = Size(2 * r, 2 * r),
        alpha = alpha,
        style = Stroke(w)
    )
}

/** Red tally light: bloom behind, warm gradient disc, glassy highlight. */
private fun DrawScope.drawLed(t: Float, m: Float, c: Offset) {
    val fade = 1f - segment(t, 1000f, 150f)
    val on = eased(t, 100f, 450f) * fade
    if (on <= 0f) return
    val dotR = 0.0389f * m
    val bloomR = lerp(1.4f, 2.2f, eased(t, 100f, 500f)) * dotR
    val glow = bloom(t) * fade
    drawCircle(Brush.radialGradient(listOf(Bloom.copy(alpha = glow), Bloom.copy(alpha = 0f)), c, bloomR), bloomR, c)
    drawCircle(Brush.verticalGradient(listOf(LedTop, LedBottom), c.y - dotR, c.y + dotR), dotR, c, alpha = on)
    val dot = Path().apply { addOval(Rect(c, dotR)) }
    clipPath(dot) { drawCircle(Color.White, 0.72f * dotR, c - Offset(0f, 0.32f * dotR), alpha = 0.28f * on) }
}

private fun DrawScope.drawWordmark(t: Float, m: Float, c: Offset, measurer: TextMeasurer) {
    val e = eased(t, 650f, 350f)
    val alpha = 0.92f * e * (1f - segment(t, 1000f, 150f))
    if (alpha <= 0f) return
    val spacing = lerp(0.32f, 0.20f, e)
    val size = 0.048f * m
    val style =
        TextStyle(
            color = Color.White.copy(alpha = alpha),
            fontSize = size.toSp(),
            fontWeight = FontWeight.Normal,
            letterSpacing = spacing.em
        )
    val layout = measurer.measure("MetaStream", style)
    // Letter spacing also trails the last glyph; shift back by half so the word stays optically centred.
    val x = c.x - layout.size.width / 2f + spacing * size / 2f
    val y = c.y + 0.34f * m - layout.size.height / 2f + 0.015f * m * (1f - e)
    drawText(layout, topLeft = Offset(x, y))
}

private fun lerp(a: Float, b: Float, f: Float) = a + (b - a) * f
