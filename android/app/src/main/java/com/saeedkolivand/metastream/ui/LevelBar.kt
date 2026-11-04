package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.core.ui.Green
import com.saeedkolivand.metastream.core.ui.Orange
import com.saeedkolivand.metastream.core.ui.Red
import com.saeedkolivand.metastream.streaming.audio.AudioMath
import com.saeedkolivand.metastream.streaming.audio.AudioMix
import kotlinx.coroutines.delay

private const val METER_MS = 125L

/** iOS LevelBar: thin flat bar for the mix (-60...0 dBFS), orange when near silent, red near clipping. Polled at 8 Hz. */
@Composable
internal fun RowScope.LevelBar() {
    var db by remember { mutableFloatStateOf(AudioMath.SILENCE_DB) }
    LaunchedEffect(Unit) {
        while (true) {
            db = AudioMix.level()
            delay(METER_MS)
        }
    }
    val color = when {
        db > -6f -> Red
        db < AudioMath.DEAD_AIR_DB -> Orange
        else -> Green
    }
    Box(
        Modifier.align(Alignment.CenterVertically).size(44.dp, 6.dp).clip(RoundedCornerShape(3.dp))
            .background(Color.White.copy(alpha = 0.2f)).semantics { contentDescription = "Audio level" }
    ) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(((db + 60f) / 60f).coerceIn(0f, 1f)).background(color))
    }
}
