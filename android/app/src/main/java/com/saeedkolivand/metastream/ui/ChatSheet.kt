package com.saeedkolivand.metastream.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlinx.coroutines.launch

internal enum class Detent { Hidden, Partial, Expanded }

internal data class SheetArgs(
    val detent: Detent,
    val onDetent: (Detent) -> Unit,
    val totalPx: Float,
    val topInsetPx: Float,
    val restPx: Float,
    val modifier: Modifier = Modifier
)

/**
 * Non-modal bottom sheet (iOS .fraction(0.45)/.large with background interaction): only its own area takes touches,
 * so the preview, HUD and controls stay usable. [restPx] is the room kept below it while partial (the controls).
 */
@Composable
internal fun ChatSheet(args: SheetArgs, header: @Composable () -> Unit, content: @Composable () -> Unit) {
    val (detent, onDetent, totalPx, topInsetPx, restPx, modifier) = args
    val partialPx = totalPx * 0.5f
    val fullPx = totalPx - topInsetPx
    fun target(d: Detent) = when (d) {
        Detent.Hidden -> 0f
        Detent.Partial -> partialPx
        Detent.Expanded -> fullPx
    }
    val h = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(detent, totalPx, topInsetPx) { h.animateTo(target(detent)) }
    val drag = rememberDraggableState { dy -> scope.launch { h.snapTo((h.value - dy).coerceIn(0f, fullPx)) } }
    fun settle(velocity: Float) {
        val projected = h.value - velocity * 0.15f
        val next = Detent.entries.minBy { abs(target(it) - projected) }
        // Same detent: the effect above won't rerun, so spring back here.
        if (next == detent) scope.launch { h.animateTo(target(next)) } else onDetent(next)
    }
    if (h.value < 1f && detent == Detent.Hidden) return
    // Sits above the controls while partial, flush with the screen bottom once expanded.
    val expandedness = ((h.value - partialPx) / (fullPx - partialPx)).coerceIn(0f, 1f)
    val dp = LocalDensity.current
    val corner = if (expandedness >= 1f) 0.dp else 20.dp
    Column(
        modifier
            .offset(y = with(dp) { (-restPx * (1f - expandedness)).toDp() })
            .height(with(dp) { h.value.toDp() })
            .clip(RoundedCornerShape(topStart = corner, topEnd = corner))
            .background(Color.Black.copy(alpha = 0.7f + 0.24f * expandedness))
    ) {
        Column(Modifier.fillMaxWidth().draggable(drag, Orientation.Vertical, onDragStopped = { settle(it) })) {
            Box(Modifier.fillMaxWidth().padding(top = 8.dp), Alignment.Center) {
                Box(Modifier.width(40.dp).height(5.dp).clip(RoundedCornerShape(3.dp)).background(Color.White.copy(alpha = 0.4f)))
            }
            header()
        }
        content()
    }
}
