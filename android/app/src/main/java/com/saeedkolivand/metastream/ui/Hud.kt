package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import kotlinx.coroutines.delay

private fun elapsed(ms: Long): String {
    val s = (ms / 1000).coerceAtLeast(0)
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%02d:%02d".format(s / 60, s % 60)
}

/** Amber while down: the timer measures the session, so it shows degraded time instead of counting dead air as healthy. */
@Composable
private fun TimerPill() {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1000)
            now = System.currentTimeMillis()
        }
    }
    val t = elapsed(Engine.liveSince?.let { now - it } ?: 0)
    if (Engine.connected) Pill(R.drawable.ic_record, t, Red) else Pill(R.drawable.ic_warning, "down $t", Orange)
}

private fun glassesColor(status: String) = when {
    status.contains("streaming") -> Green
    status.isEmpty() -> Color.Gray
    else -> Orange
}

/** Top status strip; scrolls sideways so a long run of pills never wraps over the preview. */
@Composable
internal fun Hud() {
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(top = 4.dp), Arrangement.spacedBy(8.dp)) {
        if (Engine.live) {
            TimerPill()
            // status is "<state> · <bitrate>" while streaming
            Pill(R.drawable.ic_antenna, Engine.status.substringAfter(" · ", Engine.status), Color.White)
        } else {
            Pill(R.drawable.ic_antenna, Engine.status, Color.Gray)
        }
        val (icon, name) = when (Engine.source) {
            Source.Phone -> R.drawable.ic_phone to "Phone"
            Source.Usb -> R.drawable.ic_usb to "USB"
            Source.Glasses -> R.drawable.ic_glasses to "Glasses"
        }
        Pill(icon, name, Color.White)
        ScenePill()
        if (Engine.source == Source.Glasses) {
            val g = Engine.glasses.status
            Pill(R.drawable.ic_glasses, g.ifEmpty { "idle" }, glassesColor(g))
        }
        val on = Speaker.readAloud
        Pill(
            if (on) R.drawable.ic_speaker else R.drawable.ic_speaker_off,
            if (on) "tts" else "tts off",
            if (on) Color.White else Orange
        ) { Speaker.updateReadAloud(!on) }
    }
}
