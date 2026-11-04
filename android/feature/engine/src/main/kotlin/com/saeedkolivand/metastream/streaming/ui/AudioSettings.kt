package com.saeedkolivand.metastream.streaming.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.ActionRow
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.NavRow
import com.saeedkolivand.metastream.core.ui.Red
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SwitchRow
import com.saeedkolivand.metastream.core.ui.SystemBlue
import com.saeedkolivand.metastream.core.ui.TextRow
import com.saeedkolivand.metastream.core.ui.ValueRow
import com.saeedkolivand.metastream.streaming.AudioMix
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Mics
import com.saeedkolivand.metastream.streaming.Soundboard

private val AUDIO_TYPES = arrayOf("audio/*")

/** iOS AudioSettingsView: microphone, mute, the mix volumes, the alert sound and the soundboard (its own page). */
@Composable
fun AudioPage(openSoundboard: () -> Unit) {
    val context = LocalContext.current
    // Re-read each time the page opens, so a freshly plugged USB or Bluetooth mic shows up (iOS refreshMics onAppear).
    val mics = remember { Mics.available(context).filter { it.isSource } }
    Section(null) {
        Choice("Microphone", listOf("" to "Default") + mics.map { Mics.key(it) to Mics.label(it) }, Mics.selected) {
            Mics.select(it)
            Engine.refreshMic()
        }
        SwitchRow("Mute microphone", Engine.muted) { if (it != Engine.muted) Engine.toggleMute() }
    }
    // Android only: screen share can carry other apps' sound.
    Section(null, "Other apps' sound goes into the stream while the screen is shared.") {
        var appAudio by remember { mutableStateOf(Prefs.bool("screenAppAudio", true)) }
        SwitchRow("App audio when sharing the screen", appAudio) {
            appAudio = it
            Prefs.put("screenAppAudio", it)
            Engine.syncAudio()
        }
    }
    Section(
        "Mix volume",
        "The mix is what viewers hear. Alerts, clips and sounds play on stream only, never through the phone speaker, " +
            "and go quiet while the microphone is muted."
    ) {
        Volume("Microphone", "volMic")
        Volume("Alert sounds", "volAlert")
        Volume("Clip audio", "volClip")
        Volume("Sounds", "volSound")
    }
    val pickAlert = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { Soundboard.setAlert(context, it) }
    }
    Section("Alert sound") {
        ValueRow("Alert sound", Soundboard.alertLabel())
        ActionRow("Choose file…") { pickAlert.launch(AUDIO_TYPES) }
        if (Soundboard.alertSound.isNotEmpty()) ActionRow("Use the chime") { Soundboard.setAlert(context, null) }
    }
    Section(null, "Short sounds you can play into the mix while live.") {
        NavRow("Soundboard", value = "${Soundboard.sounds.size}", onClick = openSoundboard)
    }
}

/** One 0..100 volume beside its label (iOS HStack slider), saved when the drag ends (Prefs [key], default 100). */
@Composable
private fun Volume(title: String, key: String) {
    var value by remember { mutableFloatStateOf(Prefs.int(key, 100).toFloat()) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.width(120.dp), fontSize = 17.sp)
        Slider(
            value,
            { value = it },
            valueRange = 0f..100f,
            colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = SystemBlue, inactiveTrackColor = Color(0xFF3A3A3C)),
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
fun SoundboardPage() {
    val context = LocalContext.current
    val add = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { Soundboard.add(context, it) }
    }
    Section(
        null,
        "Up to ${Soundboard.MAX} short sounds. While live, a music note button appears in the controls; " +
            "tap a name to play it into the mix. They go quiet while the microphone is muted."
    ) {
        Soundboard.sounds.forEachIndexed { i, s ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                var name by remember(s.file) { mutableStateOf(s.name) }
                Row(Modifier.weight(1f)) {
                    TextRow("Name", name, {
                        name = it
                        Soundboard.rename(i, it)
                    })
                }
                TextButton({ Soundboard.remove(i) }) { Text("Delete", color = Red) }
            }
        }
        ActionRow("Add sound…", Soundboard.sounds.size < Soundboard.MAX) { add.launch(AUDIO_TYPES) }
    }
}
