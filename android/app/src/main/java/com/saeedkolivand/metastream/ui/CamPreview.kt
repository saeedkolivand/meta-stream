package com.saeedkolivand.metastream.ui

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.camera.Cam
import com.saeedkolivand.metastream.camera.isLevel
import com.saeedkolivand.metastream.camera.rollDegrees
import kotlinx.coroutines.delay

private val Yellow = Color(0xFFFFD60A)
private const val SMOOTHING = 0.2f

@Composable
private fun rememberDisplayRotation(): () -> Int {
    val view = LocalView.current
    return { (view.display?.rotation ?: 0) * 90 }
}

/** Accelerometer horizon, low-passed. Registered only while the level overlay is on so it costs nothing off. */
@Composable
private fun rememberRoll(on: Boolean, rotation: () -> Int): Float {
    val context = LocalContext.current
    var roll by remember { mutableFloatStateOf(0f) }
    DisposableEffect(on) {
        val sm = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val listener = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val r = rollDegrees(e.values[0], e.values[1], rotation())
                roll += (r - roll) * SMOOTHING
            }

            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        if (on && sensor != null) sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
        onDispose { sm.unregisterListener(listener) }
    }
    return roll
}

@Composable
private fun Grid() = Canvas(Modifier.fillMaxSize()) {
    val line = Color.White.copy(alpha = 0.5f)
    for (i in 1..2) {
        drawLine(line, Offset(size.width * i / 3, 0f), Offset(size.width * i / 3, size.height), 0.75.dp.toPx())
        drawLine(line, Offset(0f, size.height * i / 3), Offset(size.width, size.height * i / 3), 0.75.dp.toPx())
    }
}

/** Horizon line; green within ~1.5 degrees of level. Viewfinder only, never in the encoded video. */
@Composable
private fun Level(rotation: () -> Int) {
    val roll = rememberRoll(true, rotation)
    Canvas(Modifier.fillMaxSize()) {
        rotate(-roll, center) {
            val half = size.width * 0.3f
            drawLine(
                if (isLevel(roll)) Green else Color.White,
                Offset(center.x - half, center.y),
                Offset(center.x + half, center.y),
                1.5.dp.toPx()
            )
        }
    }
}

@Composable
private fun FocusRing(at: Offset, id: Int) {
    val scale = remember { Animatable(1.4f) }
    val alpha = remember { Animatable(1f) }
    LaunchedEffect(id) {
        alpha.snapTo(1f)
        scale.snapTo(1.4f)
        scale.animateTo(1f)
        delay(800)
        alpha.animateTo(0f)
    }
    Canvas(Modifier.fillMaxSize()) {
        val side = 70.dp.toPx() * scale.value
        drawRoundRect(
            Yellow.copy(alpha = alpha.value),
            Offset(at.x - side / 2, at.y - side / 2),
            Size(side, side),
            CornerRadius(4.dp.toPx()),
            Stroke(1.5.dp.toPx())
        )
    }
}

/**
 * Everything drawn over and listened to on the Phone preview: tap to focus, long-press AE/AF lock, pinch zoom,
 * and the grid/level viewfinder guides. Sits above the SurfaceView, below the HUD and controls.
 */
@Composable
internal fun CamPreviewLayer() {
    val rotation = rememberDisplayRotation()
    val haptic = rememberHaptic()
    var ping by remember { mutableStateOf<Offset?>(null) }
    var pingId by remember { mutableIntStateOf(0) }
    Box(
        Modifier.fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = {
                        ping = it
                        pingId++
                        Cam.tapFocus(it.x / size.width, it.y / size.height, rotation())
                    },
                    onLongPress = {
                        haptic(true)
                        Cam.toggleLock()
                    }
                )
            }
            .pointerInput(Unit) { detectTransformGestures { _, _, zoom, _ -> if (zoom != 1f) Cam.pinch(zoom) } }
    ) {
        if (Cam.settings.grid) Grid()
        if (Cam.settings.level) Level(rotation)
        ping?.let { FocusRing(it, pingId) }
        if (Cam.meter?.locked == true) {
            Text(
                "AE/AF LOCK",
                Modifier.align(Alignment.TopCenter).safeDrawingPadding().padding(top = 54.dp).clip(CircleShape).background(Scrim)
                    .padding(horizontal = 10.dp, vertical = 5.dp),
                color = Yellow,
                fontSize = 11.sp,
                fontWeight = FontWeight.ExtraBold
            )
        }
    }
}
