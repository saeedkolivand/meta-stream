package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.camera.Cam
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

private const val FADE_STEPS = 3
private const val FADE_STEP_MS = 60L
private const val MIN_ROTATE_SECONDS = 5

/** Scene changes as the viewer sees them: fade, optional camera switch, auto-rotation. The HUD, settings and rotation all go through here. */
object Scenes {
    private lateinit var scope: CoroutineScope
    private var rotation: Job? = null

    // Switches queue instead of overlapping, so two fades never fight over the alpha.
    private val switching = Mutex()

    fun init(scope: CoroutineScope) {
        this.scope = scope
    }

    /** A manual pick outside the rotation list turns rotation off (otherwise it would yank the viewer back in a minute). */
    fun select(name: String) {
        if (OverlayStore.rotateOn && name !in OverlayStore.rotateScenes) {
            OverlayStore.setRotateOn(false)
            updateRotation()
        }
        switchTo(name)
    }

    private fun switchTo(name: String) {
        scope.launch {
            switching.withLock {
                val fade = OverlayStore.transition == "fade" && name != OverlayStore.scene
                try {
                    if (fade) ramp(1f, 0f)
                    OverlayStore.select(name)
                    applyCamera(name)
                } finally {
                    // Fades in even if cancelled, so a failed switch can't leave the stream blank.
                    if (fade) withContext(NonCancellable) { ramp(0f, 1f) }
                    Overlays.setAlpha(1f)
                }
            }
        }
    }

    private suspend fun ramp(from: Float, to: Float) {
        for (i in 1..FADE_STEPS) {
            Overlays.setAlpha(from + (to - from) * i / FADE_STEPS)
            delay(FADE_STEP_MS)
        }
    }

    // Engine.pick refuses unavailable or unsafe switches (no USB camera, glasses while live), so a refused one just keeps the current camera.
    // ponytail: the flip is judged right after pick(), so a Usb->Phone change may flip against the old camera's facing; fine for a manual retry.
    private fun applyCamera(sceneName: String) {
        when (val cam = OverlayStore.scenes.firstOrNull { it.name == sceneName }?.camera) {
            "back", "front" -> {
                Engine.pick(Source.Phone)
                if (Engine.source == Source.Phone && Cam.facingBack() != (cam == "back")) Engine.switchCamera()
            }
            "external" -> Engine.pick(Source.Usb)
            "glasses" -> Engine.pick(Source.Glasses)
        }
    }

    /** Restarts or stops the rotation loop to match [OverlayStore]'s settings: needs two existing scenes, at least 5 s apart. */
    fun updateRotation() {
        rotation?.cancel()
        rotation = null
        if (!OverlayStore.rotateOn || validRotation().size < 2) return
        val every = maxOf(MIN_ROTATE_SECONDS, OverlayStore.rotateSeconds) * 1000L
        rotation = scope.launch {
            while (true) {
                delay(every)
                // Re-read each tick: scenes can be renamed or deleted while it runs.
                val list = validRotation()
                if (list.size >= 2) switchTo(list[(list.indexOf(OverlayStore.scene) + 1) % list.size])
            }
        }
    }

    private fun validRotation() = OverlayStore.rotateScenes.filter { n -> OverlayStore.scenes.any { it.name == n } }
}
