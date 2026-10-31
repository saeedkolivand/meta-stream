package com.saeedkolivand.metastream.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.saeedkolivand.metastream.camera.Look
import com.saeedkolivand.metastream.camera.Looks
import com.saeedkolivand.metastream.overlay.Overlays
import com.saeedkolivand.metastream.streaming.Engine

/** iOS CameraProControlsView+Look: the live source's grade, saved per source on every change, applied on the GPU. */
@Composable
internal fun LookSection() {
    val context = LocalContext.current
    val key = Looks.key()
    if (key == "glasses") {
        Footnote("Glasses video goes out as the glasses send it, so it can't take a look.")
        return
    }
    var look by remember(key, Engine.source) { mutableStateOf(Look.load(key)) }
    var luts by remember { mutableStateOf(Looks.files()) }
    var error by remember { mutableStateOf<String?>(null) }
    fun edit(next: Look) {
        look = next
        Look.save(next, key)
        Overlays.syncLook()
    }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        Looks.import(context, uri).onSuccess {
            error = null
            luts = Looks.files()
            edit(look.copy(lut = it))
        }.onFailure { error = it.message ?: "Not a usable .cube file" }
    }
    Section("Look ($key)") {
        Adjust("Brightness", "%+.2f".format(look.brightness), look.brightness, -0.5f..0.5f) { edit(look.copy(brightness = it)) }
        Adjust("Contrast", "%.2f".format(look.contrast), look.contrast, 0.5f..1.5f) { edit(look.copy(contrast = it)) }
        Adjust("Saturation", "%.2f".format(look.saturation), look.saturation, 0f..2f) { edit(look.copy(saturation = it)) }
        Adjust("Warmth", "%+.2f".format(look.warmth), look.warmth, -1f..1f) { edit(look.copy(warmth = it)) }
        RadioRow("No LUT", look.lut == null) { edit(look.copy(lut = null)) }
        for (name in luts) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) { RadioRow(name.removeSuffix(".cube"), look.lut == name) { edit(look.copy(lut = name)) } }
                TextButton({
                    Looks.delete(name)
                    luts = Looks.files()
                    if (look.lut == name) edit(look.copy(lut = null))
                }) { Text("Remove") }
            }
        }
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
            TextButton({ pick.launch(arrayOf("*/*")) }) { Text("Import .cube…") } // .cube has no registered MIME type
            TextButton({ edit(Look()) }, enabled = !look.neutral) { Text("Reset") }
        }
        error?.let { Text(it, color = Red) }
        Footnote("Graded on the GPU before the widgets, so overlays keep their colours. Each camera keeps its own look.")
    }
}

@Composable
private fun Adjust(label: String, text: String, value: Float, range: ClosedFloatingPointRange<Float>, onChange: (Float) -> Unit) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
        Text(label)
        Text(text)
    }
    Slider(value, onChange, valueRange = range)
}
