package com.saeedkolivand.metastream.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.camera.FaceCam
import com.saeedkolivand.metastream.privacy.BlurState
import com.saeedkolivand.metastream.privacy.Privacy
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

private fun sourceIcon(s: Source) = when (s) {
    Source.Phone -> R.drawable.ic_phone
    Source.Usb -> R.drawable.ic_usb
    Source.Glasses -> R.drawable.ic_glasses
}

// The glasses mic and HEVC passthrough video can't be muted or blanked here, so Glasses gets no quick buttons.
@Composable
private fun QuickControls(granted: Boolean, size: Dp) {
    if (Engine.source == Source.Glasses) return
    RoundButton(
        if (Engine.muted) R.drawable.ic_car_mic_off else R.drawable.ic_car_mic,
        false,
        size,
        if (Engine.muted) Red else Green,
        if (Engine.muted) "Muted" else "Mic",
        granted,
        Engine::toggleMute
    )
    RoundButton(
        if (Engine.cameraOff) R.drawable.ic_videocam_off else R.drawable.ic_videocam,
        false,
        size,
        if (Engine.cameraOff) Red else Green,
        if (Engine.cameraOff) "Hidden" else "Camera",
        granted,
        Engine::toggleCameraOff
    )
    // iOS: grey off, blue protecting, amber when asked for but not in effect yet.
    val blur = Privacy.state
    RoundButton(
        if (blur == BlurState.Off) R.drawable.ic_eye else R.drawable.ic_eye_off,
        false,
        size,
        when (blur) {
            BlurState.Off -> null
            BlurState.Pending -> Orange
            BlurState.Protecting -> SystemBlue
        },
        when (blur) {
            BlurState.Off -> "Blur off"
            BlurState.Pending -> "Next stream"
            BlurState.Protecting -> "Blur on"
        }
    ) { Privacy.updateOn(!Privacy.on) }
}

@Composable
private fun SourcePicker(size: Dp) {
    var open by remember { mutableStateOf(false) }
    Box {
        RoundButton(sourceIcon(Engine.source), false, size) { open = true }
        DropdownMenu(open, { open = false }) {
            listOf(Source.Phone to "Phone", Source.Usb to "USB camera", Source.Glasses to "Glasses").forEach { (s, name) ->
                DropdownMenuItem(
                    { Text(name) },
                    {
                        Engine.pick(s)
                        open = false
                    },
                    leadingIcon = { Icon(painterResource(sourceIcon(s)), null, Modifier.size(20.dp)) }
                )
            }
        }
    }
}

@Composable
private fun GoLive(enabled: Boolean, size: Dp) {
    val haptic = rememberHaptic()
    val color by animateColorAsState(if (Engine.live) Red else Green)
    Box(
        Modifier.size(size).alpha(if (enabled) 1f else 0.4f)
            .shadow(12.dp, CircleShape, ambientColor = color, spotColor = color)
            .clip(CircleShape).background(color)
            .clickable(enabled) {
                haptic(true)
                if (Engine.live) Engine.stop() else Engine.goLive()
            },
        Alignment.Center
    ) {
        Text(
            if (Engine.live) "END" else "GO\nLIVE",
            color = Color.White,
            fontSize = if (size < 80.dp) 13.sp else 15.sp,
            fontWeight = FontWeight.ExtraBold,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun narrow() = LocalConfiguration.current.screenWidthDp < 600

/** Narrow phones: mic / camera / blur stand in a left-edge rail so the bottom row fits 360dp at 48dp touch targets. */
@Composable
internal fun QuickRail(granted: Boolean, modifier: Modifier) {
    if (narrow()) Column(modifier, Arrangement.spacedBy(10.dp)) { QuickControls(granted, 48.dp) }
}

/** Fixed bottom controls: the ones you need in the second something goes wrong. */
@Composable
internal fun Controls(granted: Boolean, chatOpen: Boolean, onChat: () -> Unit, onSettings: () -> Unit) {
    // 360dp phone worst case: 4x48 round + 72 GO LIVE + 4x8 gaps = 296 <= 328 (360 minus side padding); quick three live in a side rail.
    val compact = narrow()
    val round = if (compact) 48.dp else 52.dp
    val gap = if (FaceCam.active && !compact) 4.dp else 8.dp
    Row(
        Modifier.fillMaxWidth().padding(bottom = 12.dp),
        Arrangement.spacedBy(gap, Alignment.CenterHorizontally),
        Alignment.CenterVertically
    ) {
        if (!compact) QuickControls(granted, 52.dp)
        SourcePicker(round)
        // granted is required even for glasses: the camera|microphone foreground service throws without it.
        GoLive(granted, if (compact) 72.dp else 84.dp)
        if (FaceCam.active) {
            RoundButton(if (FaceCam.hidden) R.drawable.ic_eye_off else R.drawable.ic_eye, FaceCam.hidden, round) {
                FaceCam.hide(!FaceCam.hidden)
            }
        }
        RoundButton(R.drawable.ic_chat, chatOpen, round, onClick = onChat)
        RoundButton(R.drawable.ic_settings, false, round, onClick = onSettings)
    }
}
