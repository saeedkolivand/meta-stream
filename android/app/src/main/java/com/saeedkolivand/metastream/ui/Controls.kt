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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.camera.FaceCam
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

private fun sourceIcon(s: Source) = when (s) {
    Source.Phone -> R.drawable.ic_phone
    Source.Usb -> R.drawable.ic_usb
    Source.Glasses -> R.drawable.ic_glasses
}

// The glasses mic and HEVC passthrough video can't be muted or blanked here, so Glasses gets no quick tiles.
@Composable
private fun QuickControls(granted: Boolean) {
    if (Engine.source == Source.Glasses) return
    Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), Arrangement.spacedBy(12.dp)) {
        QuickTile(
            if (Engine.muted) R.drawable.ic_car_mic_off else R.drawable.ic_car_mic,
            if (Engine.muted) "Muted" else "Mic",
            if (Engine.muted) Red else Green,
            granted,
            Engine::toggleMute
        )
        QuickTile(
            if (Engine.cameraOff) R.drawable.ic_videocam_off else R.drawable.ic_videocam,
            if (Engine.cameraOff) "Hidden" else "Camera",
            if (Engine.cameraOff) Red else Green,
            granted,
            Engine::toggleCameraOff
        )
        if (Engine.source == Source.Phone) {
            QuickTile(R.drawable.ic_flip_camera, "Flip", null, granted, Engine::switchCamera)
        }
    }
}

@Composable
private fun SourcePicker() {
    var open by remember { mutableStateOf(false) }
    Box {
        RoundButton(sourceIcon(Engine.source), false) { open = true }
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
private fun GoLive(enabled: Boolean) {
    val haptic = rememberHaptic()
    val color by animateColorAsState(if (Engine.live) Red else Green)
    Box(
        Modifier.size(84.dp).alpha(if (enabled) 1f else 0.4f)
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
            fontSize = 15.sp,
            fontWeight = FontWeight.ExtraBold,
            textAlign = TextAlign.Center
        )
    }
}

/** Fixed bottom controls: the ones you need in the second something goes wrong. */
@Composable
internal fun Controls(granted: Boolean, chatOpen: Boolean, onChat: () -> Unit, onSettings: () -> Unit) {
    Column(Modifier.padding(bottom = 12.dp)) {
        QuickControls(granted)
        // iOS tightens the spacing to fit the extra eye button.
        Row(
            Modifier.fillMaxWidth(),
            Arrangement.spacedBy(if (FaceCam.active) 8.dp else 18.dp, Alignment.CenterHorizontally),
            Alignment.CenterVertically
        ) {
            SourcePicker()
            // granted is required even for glasses: the camera|microphone foreground service throws without it.
            GoLive(granted)
            if (FaceCam.active) {
                RoundButton(if (FaceCam.hidden) R.drawable.ic_eye_off else R.drawable.ic_eye, FaceCam.hidden) {
                    FaceCam.hide(!FaceCam.hidden)
                }
            }
            RoundButton(R.drawable.ic_chat, chatOpen, onChat)
            RoundButton(R.drawable.ic_settings, false, onSettings)
        }
    }
}
