package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.streaming.SAMPLE_WINDOW
import com.saeedkolivand.metastream.streaming.Sample
import com.saeedkolivand.metastream.streaming.chartMax
import com.saeedkolivand.metastream.streaming.kbpsText

/** Last two minutes: sent kbps line, dashed step line for the target, orange bands for congestion, red for down. */
@Composable
internal fun NetworkChart(samples: List<Sample>, ceilingKbps: Int) {
    val top = chartMax(maxOf(ceilingKbps, samples.maxOfOrNull { maxOf(it.sentKbps, it.targetKbps) } ?: 0))
    Row(Modifier.fillMaxWidth().height(140.dp), Arrangement.spacedBy(6.dp)) {
        Column(Modifier.fillMaxHeight(), Arrangement.SpaceBetween) {
            listOf(top, top / 2, 0).forEach { Text(kbpsText(it), color = Color.White.copy(alpha = 0.5f), fontSize = 10.sp) }
        }
        Canvas(Modifier.weight(1f).fillMaxHeight()) {
            val slot = size.width / SAMPLE_WINDOW
            val x = { i: Int -> (SAMPLE_WINDOW - samples.size + i + 0.5f) * slot } // newest sample sits at the right edge
            val y = { kbps: Int -> size.height * (1f - kbps.coerceAtMost(top).toFloat() / top) }
            drawLine(Hairline, Offset(0f, size.height), Offset(size.width, size.height))
            drawLine(Hairline, Offset(0f, size.height / 2), Offset(size.width, size.height / 2))
            samples.forEachIndexed { i, s ->
                val band = if (s.down) {
                    Red.copy(alpha = 0.4f)
                } else if (s.congested) {
                    Orange.copy(alpha = 0.3f)
                } else {
                    null
                }
                band?.let { drawRect(it, Offset(x(i) - slot / 2, 0f), Size(slot, size.height)) }
            }
            val target = Path()
            val sent = Path()
            samples.forEachIndexed { i, s ->
                if (i == 0) {
                    sent.moveTo(x(i), y(s.sentKbps))
                    target.moveTo(x(i), y(s.targetKbps))
                } else {
                    sent.lineTo(x(i), y(s.sentKbps))
                    target.lineTo(x(i), y(samples[i - 1].targetKbps)) // hold the old target, then step
                    target.lineTo(x(i), y(s.targetKbps))
                }
            }
            if (samples.any { it.targetKbps > 0 }) {
                drawPath(
                    target,
                    Color.White.copy(alpha = 0.5f),
                    style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 8f)))
                )
            }
            drawPath(sent, Green, style = Stroke(2.dp.toPx()))
        }
    }
}
