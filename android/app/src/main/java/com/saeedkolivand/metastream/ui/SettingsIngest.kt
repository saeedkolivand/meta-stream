package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.saeedkolivand.metastream.core.AppSettings
import com.saeedkolivand.metastream.core.FPS_CHOICES
import com.saeedkolivand.metastream.core.KBPS_STEP
import com.saeedkolivand.metastream.core.Lock
import com.saeedkolivand.metastream.core.MAX_KBPS
import com.saeedkolivand.metastream.core.MIN_KBPS
import com.saeedkolivand.metastream.core.RESOLUTIONS
import com.saeedkolivand.metastream.core.snapKbps
import com.saeedkolivand.metastream.streaming.Engine

/** iOS IngestSettingsView: the destination plus resolution, fps, codec, bitrate, orientation lock and SRT buffer. */
@Composable
internal fun IngestPage() {
    val c = AppSettings.ingest
    val idle = !Engine.live // the encoder is configured at Go Live, so editing while live would do nothing
    Section("Ingest") {
        OutlinedTextField(Engine.url, Engine::updateUrl, Modifier.fillMaxWidth(), label = {
            Text("RTMP / SRT URL")
        }, singleLine = true, enabled = idle)
        OutlinedTextField(
            Engine.key,
            Engine::updateKey,
            Modifier.fillMaxWidth(),
            label = { Text("Stream key") },
            singleLine = true,
            enabled = idle,
            visualTransformation = PasswordVisualTransformation()
        )
        Choice("Resolution", RESOLUTIONS.map { it to "${it}p" }, c.height, idle) { AppSettings.updateIngest(c.copy(height = it)) }
        Choice("Frame rate", FPS_CHOICES.map { it to "$it fps" }, c.fps, idle) { AppSettings.updateIngest(c.copy(fps = it)) }
        Choice("Video codec", listOf(false to "H.264", true to "H.265 (HEVC)"), c.h265, idle) {
            AppSettings.updateIngest(c.copy(h265 = it))
        }
        Choice("Orientation", Lock.entries.map { it to it.name }, c.lock, idle) { AppSettings.updateIngest(c.copy(lock = it)) }
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
            Text("Bitrate")
            Text("${c.bitrateKbps} kbps")
        }
        Slider(
            c.bitrateKbps.toFloat(),
            { AppSettings.updateIngest(c.copy(bitrateKbps = snapKbps(it.toInt()))) },
            enabled = idle,
            valueRange = MIN_KBPS.toFloat()..MAX_KBPS.toFloat(),
            steps = (MAX_KBPS - MIN_KBPS) / KBPS_STEP - 1
        )
        if (Engine.url.lowercase().startsWith("srt://")) {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
                Text("SRT buffer")
                Text("${c.srtLatencyMs} ms")
            }
            Slider(
                c.srtLatencyMs.toFloat(),
                { AppSettings.updateIngest(c.copy(srtLatencyMs = (it.toInt() / 200 * 200))) },
                enabled = idle,
                valueRange = 200f..8000f,
                steps = 38
            )
        }
        Footnote(
            "Applied when you go live. Adaptive bitrate lowers the encoder bitrate on congestion or heat and never goes above " +
                "the bitrate set here. Paste an srt:// URL to publish over SRT, with the key in its streamid."
        )
        OutlinedButton({ AppSettings.restoreIngestDefaults() }, enabled = idle) { Text("Restore defaults") }
    }
}
