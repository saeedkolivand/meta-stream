package com.saeedkolivand.metastream.camera

import android.app.Application
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.ColorSpaceTransform
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.pedro.encoder.input.sources.video.Camera2Source
import com.pedro.library.generic.GenericStream
import com.pedro.library.view.GlInterface
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.applog

private const val KEY = "camera"
private const val TRIGGER_MS = 120L

/**
 * Live phone-camera controls over RootEncoder's [Camera2Source].
 *
 * Settings are Compose state, persisted as one JSON blob. Every change rebuilds all managed capture-request keys
 * through Camera2Source.setCustomRequest (it mutates the live repeating request), so nothing depends on which
 * RootEncoder helper touched what. A new capture session (first start, front/back flip, re-prepare) is detected from
 * the per-frame callback and gets the full settings re-applied, because the request builder is recreated each time.
 */
object Cam {
    private lateinit var app: Application
    private val main = Handler(Looper.getMainLooper())

    var settings by mutableStateOf(CameraSettings())
        private set
    var caps by mutableStateOf(CameraCaps())
        private set

    /** Last tap-to-focus point and whether AE/AF are locked on it; null = camera decides. */
    var meter by mutableStateOf<Meter?>(null)
        private set
    var stripOpen by mutableStateOf(false)

    private var src: Camera2Source? = null
    private var gl: GlInterface? = null
    private var session: CameraCaptureSession? = null

    // The HAL's own colour matrix from auto frames: manual white balance reuses it and only swaps the gains.
    @Volatile private var wbMatrix: ColorSpaceTransform? = null

    fun init(application: Application) {
        app = application
        settings = CameraSettings.fromJson(Prefs.string(KEY))
    }

    /** Called whenever the stream's video source may have changed (prepare, source switch). Safe to repeat. */
    fun attach(s: GenericStream) {
        gl = s.getGlInterface()
        val cam = s.videoSource as? Camera2Source
        if (cam !== src) {
            src = cam
            session = null
            cam?.setCustomOnCaptureCompletedCallback(::onFrame)
        }
        if (cam == null) {
            stripOpen = false
            meter = null
        }
        applyMirror()
    }

    private fun onFrame(s: CameraCaptureSession, r: CaptureRequest, result: TotalCaptureResult) {
        if (!settings.wbManual) result.get(CaptureResult.COLOR_CORRECTION_TRANSFORM)?.let { wbMatrix = it }
        if (s === session) return
        session = s
        main.post {
            meter = null
            src?.getCurrentCameraId()?.let { CameraCaps.probe(app, it) }?.let { caps = it }
            apply()
        }
    }

    private fun apply(trigger: Boolean = false) {
        val s = settings
        val c = caps
        val m = meter
        val w = wbMatrix
        try {
            src?.setCustomRequest { it.applyCamera(s, c, m, w, trigger) }
        } catch (e: IllegalStateException) {
            applog("camera", "apply failed: ${e.message}") // session closing under us; the next session re-applies
        } catch (e: CameraAccessException) {
            applog("camera", "apply failed: ${e.message}")
        }
    }

    private fun applyMirror() {
        gl?.setIsStreamHorizontalFlip(settings.mirrored)
        gl?.setIsPreviewHorizontalFlip(settings.mirrored)
    }

    fun update(change: (CameraSettings) -> CameraSettings) {
        val before = settings
        settings = change(before)
        Prefs.put(KEY, settings.toJson())
        if (settings.mirrored != before.mirrored) applyMirror()
        apply()
    }

    /** Pulses AF_TRIGGER_START for one capture; AUTO focus only searches when triggered. */
    private fun pulse() {
        apply(trigger = true)
        main.postDelayed({ apply() }, TRIGGER_MS)
    }

    fun setZoom(z: Float) = update { it.copy(zoom = clamp(z, caps.zoomMin, caps.zoomMax)) }

    fun pinch(scale: Float) = setZoom(settings.zoom * scale)

    /** [nx], [ny]: tap normalised to the preview; [displayRotation] is 0/90/180/270. */
    fun tapFocus(nx: Float, ny: Float, displayRotation: Int) {
        val (sx, sy) = viewToSensor(nx, ny, caps.sensorOrientation - displayRotation, settings.mirrored)
        meter = Meter(sx, sy, false)
        apply()
        if (settings.focusMode == "auto") pulse()
    }

    fun toggleLock() {
        val m = meter
        if (m?.locked == true) {
            meter = null
            apply()
        } else {
            meter = Meter(m?.x ?: 0.5f, m?.y ?: 0.5f, true)
            pulse()
        }
    }

    fun toggleStrip() {
        stripOpen = !stripOpen
    }
}
