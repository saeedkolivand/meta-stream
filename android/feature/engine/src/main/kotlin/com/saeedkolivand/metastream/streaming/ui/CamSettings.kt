package com.saeedkolivand.metastream.ui

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import com.saeedkolivand.metastream.camera.Cam
import com.saeedkolivand.metastream.camera.CameraSettings
import com.saeedkolivand.metastream.camera.shutterLabel
import com.saeedkolivand.metastream.core.storage.AppSettings
import com.saeedkolivand.metastream.core.storage.FPS_CHOICES
import com.saeedkolivand.metastream.core.storage.Lock
import com.saeedkolivand.metastream.core.storage.RESOLUTIONS
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.NavRow
import com.saeedkolivand.metastream.core.ui.Orange
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.Segmented
import com.saeedkolivand.metastream.core.ui.SliderRow
import com.saeedkolivand.metastream.core.ui.SwitchRow
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.FaceCam
import com.saeedkolivand.metastream.streaming.Source
import com.saeedkolivand.metastream.streaming.level

private fun edit(change: CameraSettings.() -> CameraSettings) = Cam.update { it.change() }

/**
 * iOS CameraSettingsView: live strip, camera and lens, zoom, resolution, stabilisation, mirror, face cam, then Pro controls on
 * their own page.
 */
@Composable
fun CameraSettingsContent(openStrip: () -> Unit = {}, openPro: () -> Unit = {}) {
    val s = Cam.settings
    val c = Cam.caps
    val ingest = AppSettings.ingest
    val idle = !Engine.live
    if (c.lenses.isEmpty() && !c.zoomable) {
        Section(null) { Text("Open the camera once (Phone source) so this device's lenses and controls show here.", color = Orange) }
    }
    Section(null, "Choose which controls appear over the preview while streaming, and in what order.") {
        NavRow("Customise live control strip", onClick = openStrip)
    }
    Section(
        "Lens",
        "Sets the starting zoom for that lens (also the fallback camera while the glasses are disconnected); a lens this phone lacks is skipped."
    ) {
        val back = Cam.facingBack()
        Segmented(listOf(true to "Back", false to "Front"), back, Engine.source == Source.Phone) { if (it != back) Engine.switchCamera() }
        Choice(
            "Lens",
            c.lenses.map { it.label to "${it.label}x" },
            c.lenses.firstOrNull { kotlin.math.abs(it.zoom - s.zoom) < 0.05f }?.label.orEmpty(),
            c.lenses.isNotEmpty()
        ) { label -> c.lenses.firstOrNull { it.label == label }?.let { Cam.setZoom(it.zoom) } }
    }
    Section("Zoom") {
        SliderRow("Zoom", "%.2fx".format(s.zoom), s.zoom, c.zoomMin..c.zoomMax, c.zoomable) { Cam.setZoom(it) }
    }
    Section(
        "Resolution",
        "Only formats this camera supports are offered. Fixed for the whole stream: set before going live. With the dual camera " +
            "or a USB webcam the frame rate is capped at 30."
    ) {
        Choice("Resolution", RESOLUTIONS.map { it to "${it}p" }, ingest.height, idle) { AppSettings.updateIngest(ingest.copy(height = it)) }
        Choice(
            "Aspect",
            listOf(Lock.Auto to "Follow the phone", Lock.Portrait to "Portrait 9:16", Lock.Landscape to "Landscape 16:9"),
            ingest.lock,
            idle
        ) { AppSettings.updateIngest(ingest.copy(lock = it)) }
        Choice("Frame rate", FPS_CHOICES.map { it to "$it" }, ingest.fps, idle) { AppSettings.updateIngest(ingest.copy(fps = it)) }
    }
    Section(
        null,
        "Crops the picture and the stronger modes add latency. Standard is the safe pick for a live stream; OIS is the lens's own " +
            "stabiliser where the phone has one."
    ) {
        Choice(
            "Stabilisation",
            listOf("off" to "Off", "standard" to "Standard", "ois" to "OIS").filter {
                it.first == "off" || it.first in c.stabilizationModes
            },
            s.stabilization
        ) { edit { copy(stabilization = it) } }
    }
    Section(null) { SwitchRow("Mirror", s.mirrored) { edit { copy(mirrored = it) } } }
    FaceCamSection()
    Section(null, "Focus, exposure, white balance, HDR, torch, look (LUT) and viewfinder overlays.") {
        NavRow("Pro controls", value = if (s.exposureManual) "Manual exposure" else "Auto", onClick = openPro)
    }
}

@Composable
private fun FaceCamSection() {
    val o = FaceCam.options
    val unsupported = FaceCam.unsupported?.let { "$it " }.orEmpty()
    val basics = "Streams one camera full-frame with the other as a small window. Tap the window to swap which is big."
    val more = " The eye button on the main screen hides it. The window is hidden while blur is on, also shows over screen share, " +
        "and turns off while the phone overheats."
    Section("Face cam (dual camera)", unsupported + basics + if (FaceCam.enabled) more else "") {
        SwitchRow("Dual camera", FaceCam.enabled) { FaceCam.enable(it) }
        if (FaceCam.enabled) {
            Choice(
                "Corner",
                listOf("topLeft" to "Top left", "topRight" to "Top right", "bottomLeft" to "Bottom left", "bottomRight" to "Bottom right"),
                o.corner
            ) { FaceCam.pick(o.copy(corner = it)) }
            Choice("Size", listOf("s" to "Small", "m" to "Medium", "l" to "Large"), o.size) { FaceCam.pick(o.copy(size = it)) }
            Choice("Shape", listOf("rounded" to "Rounded", "circle" to "Circle"), o.shape) { FaceCam.pick(o.copy(shape = it)) }
        }
    }
}

/** iOS CameraProControlsView: focus, exposure, white balance, image, look and viewfinder overlays. */
@Composable
internal fun CameraProPage() {
    val s = Cam.settings
    val c = Cam.caps
    Section(
        "Focus",
        "Smooth autofocus trades focus speed for less visible hunting: worth leaving on for anything handheld or walking. " +
            "0 is closest, 1 is furthest for manual lens position."
    ) {
        Choice(
            "Mode",
            listOf("continuous" to "Continuous", "auto" to "Auto (single-shot)", "manual" to "Manual").filter {
                it.first != "manual" ||
                    c.manualFocus
            },
            s.focusMode
        ) { edit { copy(focusMode = it) } }
        if (s.focusMode ==
            "manual"
        ) {
            SliderRow("Lens position", "%.2f".format(s.lensPosition), s.lensPosition, 0f..1f) { edit { copy(lensPosition = it) } }
        }
        SwitchRow("Smooth autofocus", s.smoothAf) { edit { copy(smoothAf = it) } }
        SwitchRow("Face-driven autofocus", s.faceAf, c.faceDetect) { edit { copy(faceAf = it) } }
    }
    Section(
        "Exposure",
        "Manual exposure fixes ISO and shutter speed instead of letting the camera track the scene: set it walking into a place " +
            "you know is dark or bright, not mid-stream. Off, the exposure bias slider still nudges auto exposure."
    ) {
        SwitchRow("Manual exposure", s.exposureManual, c.manualSensor) { edit { copy(exposureManual = it) } }
        if (s.exposureManual && c.manualSensor) {
            SliderRow("ISO", "%.0f".format(s.iso), s.iso, c.isoMin..c.isoMax) { edit { copy(iso = it) } }
            SliderRow("Shutter", shutterLabel(s.shutterMs), s.shutterMs, c.shutterMinMs..c.shutterMaxMs) { edit { copy(shutterMs = it) } }
        } else {
            SliderRow("Exposure bias", "%.1f EV".format(s.biasEv), s.biasEv, c.evMin..c.evMax, c.evMax > c.evMin) {
                edit { copy(biasEv = it) }
            }
        }
        SwitchRow("Low-light boost", s.lowLight, c.lowLight) { edit { copy(lowLight = it) } }
    }
    Section(
        "White balance",
        "Locks color instead of letting it drift as lighting changes across a walk: mainly useful going indoor↔outdoor repeatedly " +
            "and wanting one consistent look."
    ) {
        SwitchRow("Manual white balance", s.wbManual, c.manualWb) { edit { copy(wbManual = it) } }
        if (s.wbManual && c.manualWb) {
            SliderRow("Temperature", "%.0fK".format(s.wbKelvin), s.wbKelvin, 2500f..10000f) { edit { copy(wbKelvin = it) } }
            SliderRow("Tint", "%.0f".format(s.wbTint), s.wbTint, -150f..150f) { edit { copy(wbTint = it) } }
        }
    }
    Section(
        "Image",
        "Geometric distortion correction straightens the ultra-wide lens's fisheye look; matters most on that lens. Torch is a " +
            "fill light for the whole session, not a camera flash: it drains battery fast at high levels."
    ) {
        Choice(
            "HDR",
            listOf("auto" to "Auto", "on" to "On", "off" to "Off").filter {
                it.first == "auto" || c.hdr
            },
            s.hdr
        ) { edit { copy(hdr = it) } }
        SwitchRow("Geometric distortion correction", s.distortion, c.distortion.isNotEmpty()) { edit { copy(distortion = it) } }
        SliderRow(
            "Torch",
            if (s.torch <=
                0f
            ) {
                "Off"
            } else {
                "%.0f%%".format(s.torch * 100)
            },
            s.torch,
            0f..1f,
            c.torch
        ) { edit { copy(torch = it) } }
    }
    LookSection()
    Section("Viewfinder overlays", "Grid and level only draw over the preview here — they never reach the recorded or streamed video.") {
        SwitchRow("Rule-of-thirds grid", s.grid) { edit { copy(grid = it) } }
        SwitchRow("Level", s.level) { edit { copy(level = it) } }
    }
}
