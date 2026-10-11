package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.camera.Cam
import com.saeedkolivand.metastream.camera.CameraSettings
import com.saeedkolivand.metastream.camera.FaceCam
import com.saeedkolivand.metastream.camera.shutterLabel

private val Dim = Color.White.copy(alpha = 0.6f)

@Composable
private fun Group(title: String, note: String? = null, content: @Composable () -> Unit) {
    Text(title.uppercase(), Modifier.padding(top = 12.dp), color = Dim, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    content()
    if (note != null) Text(note, color = Dim, fontSize = 11.sp)
}

@Composable
private fun Toggle(label: String, on: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.4f), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text(label)
        Switch(on, onChange, enabled = enabled)
    }
}

@Composable
private fun Value(
    label: String,
    text: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    enabled: Boolean = true,
    onChange: (Float) -> Unit
) {
    Column(Modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.4f)) {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
            Text(label)
            Text(text, color = Dim)
        }
        Slider(value.coerceIn(range), onChange, enabled = enabled && range.endInclusive > range.start, valueRange = range)
    }
}

/** Chips for a small fixed choice; [enabled] decides per option so unsupported ones show greyed, not missing. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Choice(
    options: List<Pair<String, String>>,
    selected: String,
    enabled: (String) -> Boolean = { true },
    onPick: (String) -> Unit
) {
    FlowRow(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp)) {
        options.forEach { (key, label) -> FilterChip(selected == key, { onPick(key) }, { Text(label) }, enabled = enabled(key)) }
    }
}

private fun edit(change: CameraSettings.() -> CameraSettings) = Cam.update { it.change() }

@Composable
private fun FocusGroup(s: CameraSettings) {
    val c = Cam.caps
    Group("Focus", "Smooth autofocus trades speed for less visible hunting: better for video. 0 is closest for manual lens position.") {
        Choice(
            listOf("continuous" to "Continuous", "auto" to "Auto (single-shot)", "manual" to "Manual"),
            s.focusMode,
            { it != "manual" || c.manualFocus }
        ) { edit { copy(focusMode = it) } }
        if (s.focusMode == "manual") {
            Value("Lens position", "%.2f".format(s.lensPosition), s.lensPosition, 0f..1f) { edit { copy(lensPosition = it) } }
        }
        Toggle("Smooth autofocus", s.smoothAf) { edit { copy(smoothAf = it) } }
        Toggle("Face-driven autofocus", s.faceAf, c.faceDetect) { edit { copy(faceAf = it) } }
    }
}

@Composable
private fun ExposureGroup(s: CameraSettings) {
    val c = Cam.caps
    Group(
        "Exposure",
        "Manual exposure fixes ISO and shutter instead of tracking the scene. Set it before you walk somewhere known. Shutter is capped at 1/30s so it never stalls the stream."
    ) {
        Toggle("Manual exposure", s.exposureManual, c.manualSensor) { edit { copy(exposureManual = it) } }
        if (s.exposureManual && c.manualSensor) {
            Value("ISO", "%.0f".format(s.iso), s.iso, c.isoMin..c.isoMax) { edit { copy(iso = it) } }
            // Slider is in milliseconds; the label reads like a shutter speed.
            Value("Shutter", shutterLabel(s.shutterMs), s.shutterMs, c.shutterMinMs..c.shutterMaxMs) { edit { copy(shutterMs = it) } }
        } else {
            Value("Exposure bias", "%.1f EV".format(s.biasEv), s.biasEv, c.evMin..c.evMax, c.evMax > c.evMin) { edit { copy(biasEv = it) } }
        }
        Toggle("Low-light boost", s.lowLight, c.lowLight) { edit { copy(lowLight = it) } }
    }
}

@Composable
private fun WhiteBalanceGroup(s: CameraSettings) {
    val c = Cam.caps
    Group(
        "White balance",
        "Locks colour instead of letting it drift. Temperature is an approximation, not calibrated Kelvin. The strip's lock button freezes auto white balance instead."
    ) {
        Toggle("Manual white balance", s.wbManual, c.manualWb) { edit { copy(wbManual = it) } }
        if (s.wbManual && c.manualWb) {
            Value("Temperature", "%.0fK".format(s.wbKelvin), s.wbKelvin, 2500f..10000f) { edit { copy(wbKelvin = it) } }
            Value("Tint", "%.0f".format(s.wbTint), s.wbTint, -150f..150f) { edit { copy(wbTint = it) } }
        }
    }
}

@Composable
private fun ImageGroup(s: CameraSettings) {
    val c = Cam.caps
    Group(
        "Image",
        "Distortion correction straightens the ultra-wide lens. Torch is a fill light for the whole session and drains the battery."
    ) {
        Choice(listOf("auto" to "HDR auto", "on" to "HDR on", "off" to "HDR off"), s.hdr, {
            it == "auto" || it == "off" || c.hdr
        }) { edit { copy(hdr = it) } }
        Toggle("Mirror", s.mirrored) { edit { copy(mirrored = it) } }
        Toggle("Geometric distortion correction", s.distortion, c.distortion.isNotEmpty()) { edit { copy(distortion = it) } }
        Value("Torch", if (s.torch <= 0f) "Off" else "%.0f%%".format(s.torch * 100), s.torch, 0f..1f, c.torch) { edit { copy(torch = it) } }
        Text("Stabilisation", color = Dim, fontSize = 12.sp)
        Choice(
            listOf("off" to "Off", "standard" to "Standard", "ois" to "OIS"),
            s.stabilization,
            { it in c.stabilizationModes }
        ) { edit { copy(stabilization = it) } }
    }
}

@Composable
private fun FaceCamGroup() {
    val o = FaceCam.options
    val why = FaceCam.unsupported
    Group(
        "Face cam (dual camera)",
        why ?: "The back camera fills the stream, the front camera shows in a corner window; the eye button hides it. " +
            "It turns off while the main camera is flipped to the front, and when the phone overheats."
    ) {
        Toggle("Dual camera", FaceCam.enabled && why == null, why == null) { FaceCam.enable(it) }
        if (FaceCam.enabled && why == null) {
            Choice(
                listOf("topLeft" to "Top left", "topRight" to "Top right", "bottomLeft" to "Bottom left", "bottomRight" to "Bottom right"),
                o.corner
            ) { FaceCam.pick(o.copy(corner = it)) }
            Choice(listOf("s" to "Small", "m" to "Medium", "l" to "Large"), o.size) { FaceCam.pick(o.copy(size = it)) }
            Choice(listOf("rounded" to "Rounded", "circle" to "Circle"), o.shape) { FaceCam.pick(o.copy(shape = it)) }
        }
    }
}

/**
 * The whole Camera settings page as one self-contained column (iOS CameraSettingsView). Phone camera only; host it
 * in a "Camera" sub-page or section, it brings its own headers and needs no state from the host.
 */
@Composable
fun CameraSettingsContent() {
    val s = Cam.settings
    val c = Cam.caps
    Column(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp)) {
        Group("Live control strip", "Choose which controls the cam button shows over the preview, and their order.") { CamCustomize() }
        Group("Lens & zoom") {
            if (c.lenses.isNotEmpty()) {
                Choice(
                    c.lenses.map {
                        it.label to "${it.label}x"
                    },
                    c.lenses.firstOrNull { kotlin.math.abs(it.zoom - s.zoom) < 0.05f }?.label.orEmpty()
                ) { label ->
                    c.lenses.firstOrNull { it.label == label }?.let { Cam.setZoom(it.zoom) }
                }
            }
            Value("Zoom", "%.2fx".format(s.zoom), s.zoom, c.zoomMin..c.zoomMax, c.zoomable) { Cam.setZoom(it) }
        }
        FocusGroup(s)
        ExposureGroup(s)
        WhiteBalanceGroup(s)
        ImageGroup(s)
        FaceCamGroup()
        Group("Viewfinder overlays", "Grid and level only draw over the preview; they never reach the stream.") {
            Toggle("Rule-of-thirds grid", s.grid) { edit { copy(grid = it) } }
            Toggle("Level", s.level) { edit { copy(level = it) } }
        }
        Text("Open the camera once (Phone source) so unsupported controls can grey out for this device.", color = Dim, fontSize = 11.sp)
    }
}
