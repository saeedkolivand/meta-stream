package com.saeedkolivand.metastream.ui

import android.Manifest
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.meta.wearable.dat.core.types.RegistrationState
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import com.saeedkolivand.metastream.streaming.StreamingService

private val required = arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
private val bluetooth = arrayOf(Manifest.permission.BLUETOOTH, Manifest.permission.BLUETOOTH_CONNECT)

@Composable
internal fun MainScreen() {
    val activity = requireNotNull(LocalActivity.current)
    var granted by remember { mutableStateOf(false) }
    var chatOpen by remember { mutableStateOf(false) }
    val ask = rememberLauncherForActivityResult(RequestMultiplePermissions()) { r ->
        granted = required.all { r[it] == true }
        if (granted) StreamingService.hold(activity, "app") // onStart ran before the permission existed
        // The DAT SDK must be initialized after the Bluetooth permissions are granted.
        if (bluetooth.all { r[it] == true }) Engine.glasses.init(activity)
    }
    LaunchedEffect(Unit) {
        // POST_NOTIFICATIONS only decides whether the live notification shows, so it isn't required.
        // Android 17: LAN ingests (OBS/relay on the LAN) need ACCESS_LOCAL_NETWORK; it shares the NEARBY_DEVICES group
        // with BLUETOOTH_CONNECT, so users see no extra prompt. Not required: public ingests work without it.
        val all = required + bluetooth + Manifest.permission.ACCESS_LOCAL_NETWORK
        ask.launch(all + Manifest.permission.POST_NOTIFICATIONS)
    }

    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Source:", Modifier.padding(top = 8.dp))
            FilterChip(Engine.source == Source.Phone, { Engine.pick(Source.Phone) }, { Text("Phone") })
            FilterChip(Engine.source == Source.Usb, { Engine.pick(Source.Usb) }, { Text("USB camera") })
            FilterChip(Engine.source == Source.Glasses, { Engine.pick(Source.Glasses) }, { Text("Glasses") })
        }
        if (Engine.source == Source.Glasses) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val registered = Engine.glasses.registration == RegistrationState.REGISTERED
                OutlinedButton({ if (registered) Engine.glasses.unregister(activity) else Engine.glasses.register(activity) }) {
                    Text(if (registered) "Unregister" else "Register with Meta AI")
                }
                Text("Mock glasses", Modifier.padding(top = 12.dp))
                Switch(Engine.glasses.mock, Engine.glasses::enableMock)
            }
            AndroidView(
                factory = { ctx ->
                    SurfaceView(ctx).apply {
                        holder.addCallback(object : SurfaceHolder.Callback {
                            override fun surfaceCreated(h: SurfaceHolder) = Engine.glasses.setSurface(h.surface)
                            override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, ht: Int) {}
                            override fun surfaceDestroyed(h: SurfaceHolder) = Engine.glasses.setSurface(null)
                        })
                    }
                },
                modifier = Modifier.weight(1f).fillMaxWidth()
            )
        } else if (granted) {
            AndroidView(
                factory = { SurfaceView(it).also(Engine::attach) },
                onRelease = { Engine.detach() },
                modifier = Modifier.weight(1f).fillMaxWidth()
            )
        } else {
            Text("Camera and microphone permission are required.", Modifier.weight(1f))
        }
        OutlinedTextField(Engine.url, Engine::updateUrl, Modifier.fillMaxWidth(), label = {
            Text("RTMP / SRT URL")
        }, singleLine = true, enabled = !Engine.live)
        OutlinedTextField(
            Engine.key,
            Engine::updateKey,
            Modifier.fillMaxWidth(),
            label = { Text("Stream key") },
            singleLine = true,
            enabled = !Engine.live,
            visualTransformation = PasswordVisualTransformation()
        )
        Text(if (Engine.source == Source.Glasses) "${Engine.glasses.status} | ${Engine.status}" else Engine.status)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            // granted is required even for glasses: the camera|microphone foreground service throws without it.
            Button({
                if (Engine.live) Engine.stop() else Engine.goLive()
            }, enabled = granted) { Text(if (Engine.live) "Stop" else "Go Live") }
            OutlinedButton(Engine::switchCamera, enabled = granted && Engine.source == Source.Phone) { Text("Flip") }
            OutlinedButton(Engine::toggleMute, enabled = granted && Engine.source != Source.Glasses) {
                Text(if (Engine.muted) "Unmute" else "Mute")
            }
            OutlinedButton({ chatOpen = !chatOpen }) { Text(if (chatOpen) "Hide chat" else "Chat") }
        }
        if (chatOpen) ChatPanel(Modifier.weight(1f))
    }
}
