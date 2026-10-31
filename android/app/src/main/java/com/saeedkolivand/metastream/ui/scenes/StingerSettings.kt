package com.saeedkolivand.metastream.ui.scenes

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.overlay.Overlays
import com.saeedkolivand.metastream.overlay.Scenes
import com.saeedkolivand.metastream.overlay.StingerKind
import com.saeedkolivand.metastream.overlay.StingerStyle
import com.saeedkolivand.metastream.ui.Choice
import com.saeedkolivand.metastream.ui.Footnote
import com.saeedkolivand.metastream.ui.RadioRow
import com.saeedkolivand.metastream.ui.Section
import com.saeedkolivand.metastream.ui.SwitchRow

/**
 * iOS StingerSettingsView, built-in stingers only. ponytail: no looping preview in Settings; "Play on preview" runs the real
 * one over the camera preview. No "your video" stinger: Android's decoders drop a clip's alpha, so it would cover in black.
 */
@Composable
internal fun StingerSettings() {
    var kindId by remember { mutableStateOf(Prefs.string("stingerKind", StingerKind.Lens.id)) }
    var style by remember { mutableStateOf(StingerStyle.load()) }
    fun edit(next: StingerStyle) {
        style = next
        next.save()
    }
    val kind = StingerKind.of(kindId) ?: StingerKind.Lens
    Section("Stinger") {
        for (k in StingerKind.entries) {
            RadioRow(k.title, k == kind) {
                kindId = k.id
                Prefs.put("stingerKind", k.id)
            }
        }
        OutlinedButton({ Scenes.previewStinger() }, Modifier.fillMaxWidth(), enabled = Overlays.stingerCanvas() != null) {
            Text("Play on preview")
        }
        Footnote("The scene switches underneath at the moment the screen is fully covered.")
    }
    Section("Motion") {
        Text("Speed: ${"%.1f".format(style.speed)}× · ${"%.1f".format(kind.seconds(style))} s")
        Slider(style.speed, { edit(style.copy(speed = (it * 10).toInt() / 10f)) }, valueRange = 0.4f..2f)
    }
    Section("Look") {
        when (kind) {
            StingerKind.Lens -> SwatchRow("Tally light", style.tally) { edit(style.copy(tally = it)) }
            StingerKind.Burn -> {
                Choice("Tone", listOf("warm" to "Warm", "cool" to "Cool", "accent" to "Accent"), style.tone) {
                    edit(style.copy(tone = it))
                }
                if (style.tone == "accent") SwatchRow("Accent", style.accent) { edit(style.copy(accent = it)) }
            }
            else -> {
                SwatchRow("Accent", style.accent) { edit(style.copy(accent = it)) }
                SwatchRow("Panel", style.ink) { edit(style.copy(ink = it)) }
            }
        }
    }
    Section("Name") {
        SwitchRow("Show name", style.showName) { edit(style.copy(showName = it)) }
        if (style.showName) {
            OutlinedTextField(
                style.name,
                { edit(style.copy(name = it)) },
                Modifier.fillMaxWidth(),
                label = { Text("Channel name") },
                singleLine = true
            )
        }
    }
}
