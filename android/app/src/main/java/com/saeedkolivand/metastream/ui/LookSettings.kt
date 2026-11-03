package com.saeedkolivand.metastream.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.saeedkolivand.metastream.core.ui.ActionRow
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.Footnote
import com.saeedkolivand.metastream.core.ui.Red
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SliderRow
import com.saeedkolivand.metastream.overlay.Overlays
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Look
import com.saeedkolivand.metastream.streaming.Looks

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
    Section("Look ($key)", "Graded on the GPU before the widgets, so overlays keep their colours. Each camera keeps its own look.") {
        SliderRow("Brightness", "%+.2f".format(look.brightness), look.brightness, -0.5f..0.5f) { edit(look.copy(brightness = it)) }
        SliderRow("Contrast", "%.2f".format(look.contrast), look.contrast, 0.5f..1.5f) { edit(look.copy(contrast = it)) }
        SliderRow("Saturation", "%.2f".format(look.saturation), look.saturation, 0f..2f) { edit(look.copy(saturation = it)) }
        SliderRow("Warmth", "%+.2f".format(look.warmth), look.warmth, -1f..1f) { edit(look.copy(warmth = it)) }
        Choice(
            "LUT",
            listOf<String?>(null).plus(luts).map {
                it to (it?.removeSuffix(".cube") ?: "None")
            },
            look.lut
        ) { edit(look.copy(lut = it)) }
        ActionRow("Import .cube…") { pick.launch(arrayOf("*/*")) } // .cube has no registered MIME type
        look.lut?.let { name ->
            ActionRow("Remove ${name.removeSuffix(".cube")}", destructive = true) {
                Looks.delete(name)
                luts = Looks.files()
                edit(look.copy(lut = null))
            }
        }
        ActionRow("Reset", enabled = !look.neutral) { edit(Look()) }
        error?.let { Text(it, color = Red) }
    }
}
