package com.saeedkolivand.metastream.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.streaming.AudioMix
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Mics
import com.saeedkolivand.metastream.streaming.Soundboard

private val AUDIO_TYPES = arrayOf("audio/*")

/** iOS AudioSettingsView: microphone, mute, the mix volumes, the alert sound and the soundboard. */
@Composable
internal fun AudioPage() {
    val context = LocalContext.current
    // Re-read each time the page opens, so a freshly plugged USB or Bluetooth mic shows up (iOS refreshMics onAppear).
    val mics = remember { Mics.available(context).filter { it.isSource } }
    Section("Microphone") {
        RadioRow("Default", Mics.selected.isEmpty()) {
            Mics.select("")
            Engine.refreshMic()
        }
        mics.forEach {
            RadioRow(Mics.label(it), Mics.selected == Mics.key(it)) {
                Mics.select(Mics.key(it))
                Engine.refreshMic()
            }
        }
        SwitchRow("Mute microphone", Engine.muted) { if (it != Engine.muted) Engine.toggleMute() }
        var appAudio by remember { mutableStateOf(Prefs.bool("screenAppAudio", true)) }
        SwitchRow("App audio when sharing the screen", appAudio) {
            appAudio = it
            Prefs.put("screenAppAudio", it)
            Engine.syncAudio()
        }
    }
    Section("Mix volume") {
        Volume("Microphone", "volMic")
        Volume("Alert sounds", "volAlert")
        Volume("Clip audio", "volClip")
        Volume("Sounds", "volSound")
        Footnote(
            "The mix is what viewers hear. Alerts, clips and sounds play on stream only, never through the phone speaker, " +
                "and go quiet while the microphone is muted."
        )
    }
    val pickAlert = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { Soundboard.setAlert(context, it) }
    }
    Section("Alert sound") {
        Text(Soundboard.alertLabel())
        Row {
            TextButton({ pickAlert.launch(AUDIO_TYPES) }) { Text("Choose file…") }
            if (Soundboard.alertSound.isNotEmpty()) TextButton({ Soundboard.setAlert(context, null) }) { Text("Use the chime") }
        }
    }
    SoundboardSection()
}

/** One 0..100 volume, saved when the drag ends (Prefs [key], default 100). */
@Composable
private fun Volume(title: String, key: String) {
    var value by remember { mutableFloatStateOf(Prefs.int(key, 100).toFloat()) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.width(110.dp))
        Slider(
            value,
            { value = it },
            valueRange = 0f..100f,
            onValueChangeFinished = {
                Prefs.put(key, value.toInt())
                AudioMix.applyVolumes()
                if (key == "volMic") Engine.refreshMic() // the mic volume lives on the mic source
            }
        )
    }
}

/** iOS SoundboardView: up to 8 short sounds, renamed in place, played from the live controls. */
@Composable
private fun SoundboardSection() {
    val context = LocalContext.current
    val add = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { Soundboard.add(context, it) }
    }
    Section("Soundboard") {
        Soundboard.sounds.forEachIndexed { i, s ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                var name by remember(s.file) { mutableStateOf(s.name) }
                OutlinedTextField(
                    name,
                    {
                        name = it
                        Soundboard.rename(i, it)
                    },
                    Modifier.weight(1f),
                    singleLine = true
                )
                TextButton({ Soundboard.remove(i) }) { Text("Remove") }
            }
        }
        TextButton({ add.launch(AUDIO_TYPES) }, enabled = Soundboard.sounds.size < Soundboard.MAX) { Text("Add sound…") }
        Footnote(
            "Up to ${Soundboard.MAX} short sounds. While live, a music note button appears in the controls; " +
                "tap a name to play it into the mix. They go quiet while the microphone is muted."
        )
    }
}
