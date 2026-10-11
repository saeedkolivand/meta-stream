package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.camera.Cam
import com.saeedkolivand.metastream.camera.LiveControl
import kotlin.math.abs

private val Blue = Color(0xFF0A84FF)
private val Chip = Color.White.copy(alpha = 0.15f)

/** iOS liveSlider: icon + value label over a slider; the picture changes under the finger on every tick. */
@Composable
internal fun StripSlider(
    icon: Int,
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    enabled: Boolean = true,
    onChange: (Float) -> Unit
) {
    Column(Modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.4f)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(painterResource(icon), null, Modifier.size(12.dp), tint = Color.White)
            Text(label, color = Color.White, fontSize = 11.sp, maxLines = 1)
        }
        Slider(
            value.coerceIn(range),
            onChange,
            Modifier.height(28.dp),
            enabled = enabled,
            valueRange = range,
            colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Chip)
        )
    }
}

/** iOS toggle tile: icon over caption, blue when on. */
@Composable
internal fun StripButton(icon: Int, caption: String, on: Boolean, onClick: () -> Unit) {
    val haptic = rememberHaptic()
    Column(
        Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(10.dp)).background(if (on) Blue else Chip)
            .clickable {
                haptic(false)
                onClick()
            },
        Arrangement.Center,
        Alignment.CenterHorizontally
    ) {
        Icon(painterResource(icon), null, Modifier.size(18.dp), tint = Color.White)
        Text(caption, color = Color.White, fontSize = 10.sp)
    }
}

@Composable
private fun LensRow() {
    val lenses = Cam.caps.lenses
    if (lenses.isEmpty()) return
    val zoom = Cam.settings.zoom
    val haptic = rememberHaptic()
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(6.dp)) {
        lenses.forEach { l ->
            val on = abs(zoom - l.zoom) < 0.05f
            Box(
                Modifier.size(30.dp).clip(CircleShape).background(if (on) Color.White else Chip)
                    .clickable {
                        haptic(false)
                        Cam.setZoom(l.zoom)
                    },
                Alignment.Center
            ) { Text(l.label, color = if (on) Color.Black else Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold) }
        }
    }
}

/** Deliberate dropdown rather than a slider you graze: each mode crops differently, so switching should be a tap. */
@Composable
private fun StabilizationButton() {
    var open by remember { mutableStateOf(false) }
    val mode = Cam.settings.stabilization
    val supported = Cam.caps.stabilizationModes
    Box {
        StripButton(R.drawable.ic_stabilize, stabilizationLabel(mode), mode != "off") { open = true }
        DropdownMenu(open, { open = false }) {
            listOf("off", "standard", "ois").forEach { m ->
                DropdownMenuItem(
                    { Text(stabilizationLabel(m)) },
                    {
                        Cam.update { it.copy(stabilization = m) }
                        open = false
                    },
                    enabled = m in supported
                )
            }
        }
    }
}

internal fun stabilizationLabel(mode: String) = when (mode) {
    "standard" -> "Standard"
    "ois" -> "OIS"
    else -> "Off"
}

@Composable
private fun StripRow(control: LiveControl) {
    val s = Cam.settings
    val c = Cam.caps
    when (control) {
        LiveControl.Lens -> LensRow()
        LiveControl.Zoom -> if (c.zoomable) {
            StripSlider(R.drawable.ic_zoom, "%.1fx".format(s.zoom), s.zoom, c.zoomMin..c.zoomMax) { Cam.setZoom(it) }
        }
        LiveControl.Exposure -> if (c.evMax > c.evMin) {
            val manual = s.exposureManual && c.manualSensor
            Column {
                StripSlider(R.drawable.ic_sun, "%.1f EV".format(s.biasEv), s.biasEv, c.evMin..c.evMax, !manual) { v ->
                    Cam.update { it.copy(biasEv = v) }
                }
                // Bias only moves auto exposure; say so instead of silently ignoring the slider.
                if (manual) Text("manual exposure on", color = Orange, fontSize = 9.sp)
            }
        }
        LiveControl.Torch -> if (c.torch) {
            StripSlider(R.drawable.ic_torch, if (s.torch <= 0f) "off" else "%.0f%%".format(s.torch * 100), s.torch, 0f..1f) { v ->
                Cam.update { it.copy(torch = v) }
            }
        }
        LiveControl.WhiteBalanceLock -> if (c.awbLock) {
            StripButton(if (s.wbLock) R.drawable.ic_lock else R.drawable.ic_lock_open, if (s.wbLock) "WB locked" else "Lock WB", s.wbLock) {
                Cam.update { it.copy(wbLock = !it.wbLock) }
            }
        }
        LiveControl.Stabilization -> StabilizationButton()
        LiveControl.Mirror -> StripButton(R.drawable.ic_mirror, if (s.mirrored) "Mirrored" else "Mirror", s.mirrored) {
            Cam.update { it.copy(mirrored = !it.mirrored) }
        }
    }
}

/** The live strip on the trailing edge; contents and order come from [Cam.settings] so Settings can reshape it. */
@Composable
internal fun CamStrip(modifier: Modifier = Modifier) {
    Column(
        modifier.width(156.dp).clip(RoundedCornerShape(18.dp)).background(Scrim).verticalScroll(rememberScrollState()).padding(12.dp),
        Arrangement.spacedBy(14.dp)
    ) {
        Cam.settings.order.forEach { StripRow(it) }
    }
}
