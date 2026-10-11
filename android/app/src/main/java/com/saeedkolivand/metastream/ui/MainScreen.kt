package com.saeedkolivand.metastream.ui

import android.Manifest
import android.content.Intent
import android.provider.Settings
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.net.toUri
import com.meta.wearable.dat.core.types.RegistrationState
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import com.saeedkolivand.metastream.streaming.StreamingService

private val required = arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
private val bluetooth = arrayOf(Manifest.permission.BLUETOOTH, Manifest.permission.BLUETOOTH_CONNECT)

// POST_NOTIFICATIONS only decides whether the live notification shows, so it isn't required.
// Android 17: LAN ingests (OBS/relay on the LAN) need ACCESS_LOCAL_NETWORK; it shares the NEARBY_DEVICES group
// with BLUETOOTH_CONNECT, so users see no extra prompt. Not required: public ingests work without it.
private val everything = required + bluetooth + Manifest.permission.ACCESS_LOCAL_NETWORK + Manifest.permission.POST_NOTIFICATIONS

@Composable
private fun GlassesPreview() = AndroidView(
    factory = { ctx ->
        SurfaceView(ctx).apply {
            holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(h: SurfaceHolder) = Engine.glasses.setSurface(h.surface)
                override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, ht: Int) {}
                override fun surfaceDestroyed(h: SurfaceHolder) = Engine.glasses.setSurface(null)
            })
        }
    },
    modifier = Modifier.fillMaxSize()
)

@Composable
internal fun MainScreen() {
    val activity = requireNotNull(LocalActivity.current)
    val density = LocalDensity.current.density
    var granted by remember { mutableStateOf(false) }
    var detent by remember { mutableStateOf(Detent.Hidden) }
    var totalPx by remember { mutableFloatStateOf(0f) }
    var restPx by remember { mutableFloatStateOf(0f) }
    var settingsOpen by remember { mutableStateOf(false) }
    val ask = rememberLauncherForActivityResult(RequestMultiplePermissions()) { r ->
        granted = required.all { r[it] == true }
        if (granted) StreamingService.hold(activity, "app") // onStart ran before the permission existed
        // The DAT SDK must be initialized after the Bluetooth permissions are granted.
        if (bluetooth.all { r[it] == true }) Engine.glasses.init(activity)
    }
    LaunchedEffect(Unit) { ask.launch(everything) }

    Box(
        Modifier.fillMaxSize().background(Color.Black).onSizeChanged { totalPx = it.height.toFloat() }
    ) {
        if (Engine.source == Source.Glasses) {
            GlassesPreview()
        } else if (granted) {
            AndroidView(
                factory = { SurfaceView(it).also(Engine::attach) },
                onRelease = { Engine.detach() },
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Box(Modifier.fillMaxSize(), Alignment.Center) {
                PermissionCard {
                    // After a second denial Android stops showing the dialog (no rationale left), so send them to Settings.
                    if (required.any(activity::shouldShowRequestPermissionRationale)) {
                        ask.launch(everything)
                    } else {
                        activity.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${activity.packageName}".toUri())
                        )
                    }
                }
            }
        }
        val unregistered = Engine.source == Source.Glasses && Engine.glasses.registration != RegistrationState.REGISTERED
        if (unregistered) {
            Box(Modifier.fillMaxSize(), Alignment.Center) {
                RegisterCard(Engine.glasses.registration.name.lowercase()) { Engine.glasses.register(activity) }
            }
        }
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 16.dp)) {
            Hud()
            Spacer(Modifier.weight(1f))
            Box(Modifier.onGloballyPositioned { restPx = totalPx - it.positionInRoot().y + 8 * density }) {
                val open = detent != Detent.Hidden
                Controls(granted, open, { detent = if (open) Detent.Hidden else Detent.Partial }, { settingsOpen = true })
            }
        }
        val args = SheetArgs(
            detent,
            { detent = it },
            totalPx,
            WindowInsets.safeDrawing.getTop(LocalDensity.current).toFloat(),
            restPx,
            Modifier.align(Alignment.BottomCenter)
        )
        ChatPanel(args) { settingsOpen = true }
    }
    if (settingsOpen) SettingsSheet { settingsOpen = false }
}
