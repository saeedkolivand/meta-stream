package com.saeedkolivand.metastream.camera

import android.annotation.SuppressLint
import android.app.Application
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.Display
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.overlay.FilterSink
import com.saeedkolivand.metastream.overlay.Overlays
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import com.saeedkolivand.metastream.streaming.thermalSerious

private const val CLOSE_DELAY_MS = 2000L
private const val MAX_PIXELS = 1280 * 720 // concurrent streams are only guaranteed up to 720p each

/**
 * Dual camera (iOS dualCam): the back camera fills the stream and the front camera shows in a corner window.
 *
 * The stream's own camera is RootEncoder's; this opens the second one straight through Camera2 into the SurfaceTexture
 * of a [FaceCamFilter]. Overlays.refresh() recreates the filter (GL drops filters on every clear), so the camera device
 * stays open and only its capture session moves to the new surface. All calls are on the main thread.
 */
object FaceCam {
    private lateinit var app: Application
    private lateinit var manager: CameraManager
    private val main = Handler(Looper.getMainLooper())
    private val closeLater = Runnable { closeDevice() }

    /** The user's toggle; the window only runs when [wanted] also holds. */
    var enabled by mutableStateOf(false)
        private set
    var hidden by mutableStateOf(false)
        private set
    var options by mutableStateOf(FaceCamOptions())
        private set

    /** The window is part of the stream right now (drives the eye button). */
    var active by mutableStateOf(false)
        private set

    /** Null when this phone can run its front and back cameras together, else why not. */
    var unsupported: String? = null
        private set

    private var filter: FaceCamFilter? = null
    private var outW = 0
    private var outH = 0
    private var overheated = false
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var opening = false
    private var readyFilter: FaceCamFilter? = null
    private var readyTex: SurfaceTexture? = null
    private var generation = 0

    fun init(application: Application) {
        app = application
        manager = app.getSystemService(CameraManager::class.java)
        enabled = Prefs.bool("dualCam")
        hidden = Prefs.bool("dualCamHidden")
        options = FaceCamOptions.parse(Prefs.string("dualCamCorner"), Prefs.string("dualCamSize"), Prefs.string("dualCamShape"))
        unsupported = if (partner(null) == null) "This phone can't run its front and back cameras at once." else null
        applog("facecam", "concurrent camera sets ${manager.concurrentCameraIds}, supported=${unsupported == null}")
        // iOS only logs the multicam cost; here severe heat drops the second camera (a whole extra sensor + GPU pass).
        app.getSystemService(PowerManager::class.java).addThermalStatusListener(ContextCompat.getMainExecutor(app)) {
            val hot = thermalSerious(it)
            if (hot != overheated) {
                overheated = hot
                applog("facecam", if (hot) "dropped: phone is overheating" else "restored: phone cooled down")
                Overlays.refresh()
            }
        }
    }

    private fun facing(id: String) = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)

    /** The front camera that may run beside [back] (any back camera when null), per the platform's concurrent sets. */
    private fun partner(back: String?) = frontPartner(
        manager.concurrentCameraIds,
        back,
        { facing(it) == CameraCharacteristics.LENS_FACING_FRONT },
        { facing(it) == CameraCharacteristics.LENS_FACING_BACK }
    )

    /** Phone source with the back camera as the main one; a flipped (front) main camera owns the front sensor. */
    private fun wanted() = enabled && unsupported == null && !overheated && Engine.source == Source.Phone && Cam.facingBack()

    fun enable(on: Boolean) {
        enabled = on
        Prefs.put("dualCam", on)
        Overlays.refresh()
    }

    fun hide(h: Boolean) {
        hidden = h
        Prefs.put("dualCamHidden", h)
        filter?.show = !h
    }

    fun pick(o: FaceCamOptions) {
        options = o
        Prefs.put("dualCamCorner", o.corner)
        Prefs.put("dualCamSize", o.size)
        Prefs.put("dualCamShape", o.shape)
        layout()
    }

    private fun layout() {
        val r = faceRect(outW, outH, options)
        filter?.setWindow(r, faceRadius(r, options.shape), outW, outH)
    }

    /** Called from Overlays.refresh() after it cleared the filters; returns whether a face-cam filter is in the chain. */
    fun install(g: FilterSink, w: Int, h: Int): Boolean {
        outW = w
        outH = h
        filter = null
        if (!wanted()) {
            active = false
            closeAll()
            return false
        }
        val f = FaceCamFilter({ f, st -> main.post { ready(f, st) } }, { f -> main.post { gone(f) } })
        f.show = !hidden
        filter = f
        layout()
        g.addFirst(f) // under the blur, so a face in the window is hidden too
        active = true
        return true
    }

    /** The GL thread's surface exists: point the (possibly already open) front camera at it. */
    private fun ready(f: FaceCamFilter, st: SurfaceTexture) {
        if (f !== filter) return
        readyFilter = f
        readyTex = st
        main.removeCallbacks(closeLater)
        val d = device
        if (d != null) startSession(d, f, st) else open(f, st)
    }

    /** The filter was released (refresh or GL stopped): its surface is dead, and the camera goes if nothing replaces it. */
    private fun gone(f: FaceCamFilter) {
        f.clearFrame()
        closeSession()
        if (readyFilter === f) readyFilter = null
        if (f === filter || filter == null) main.postDelayed(closeLater, CLOSE_DELAY_MS)
    }

    @SuppressLint("MissingPermission") // the stream's own camera permission gate ran before any filter was installed
    private fun open(f: FaceCamFilter, st: SurfaceTexture) {
        if (opening) return
        val back = Cam.mainCameraId()
        val id = partner(back)
        if (id == null) {
            applog("facecam", "no front camera can run beside camera $back")
            return
        }
        opening = true
        val cb = object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                opening = false
                device = camera
                // A refresh may have swapped the filter while the camera was opening: use whatever surface is current.
                val cur = filter
                val tex = readyTex
                if (cur != null && cur === readyFilter && tex != null) {
                    startSession(camera, cur, tex)
                } else if (cur == null) {
                    closeDevice()
                }
            }

            override fun onDisconnected(camera: CameraDevice) {
                applog("facecam", "front camera disconnected; the main stream continues")
                camera.close()
                drop()
            }

            override fun onError(camera: CameraDevice, error: Int) {
                applog("facecam", "front camera error $error; the main stream continues")
                camera.close()
                drop()
            }
        }
        try {
            manager.openCamera(id, ContextCompat.getMainExecutor(app), cb)
        } catch (e: Exception) { // CameraAccessException or SecurityException: either way the main stream must go on
            opening = false
            applog("facecam", "open failed: ${e.javaClass.simpleName}")
        }
    }

    private fun startSession(cam: CameraDevice, f: FaceCamFilter, st: SurfaceTexture) {
        closeSession()
        val ch = manager.getCameraCharacteristics(cam.id)
        val sizes = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)?.getOutputSizes(SurfaceTexture::class.java).orEmpty()
        val size = sizes.filter { it.width * it.height <= MAX_PIXELS }.maxByOrNull { it.width * it.height } ?: return
        st.setDefaultBufferSize(size.width, size.height)
        val sensor = ch.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 270
        f.setCamera(size.width, size.height, (sensor - displayDegrees() + 360) % 360)
        val gen = ++generation
        val surface = Surface(st)
        val cfg = SessionConfiguration(
            SessionConfiguration.SESSION_REGULAR,
            listOf(OutputConfiguration(surface)),
            ContextCompat.getMainExecutor(app),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    if (gen != generation) {
                        s.close()
                        return
                    }
                    session = s
                    f.clearFrame()
                    try {
                        val req = cam.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply { addTarget(surface) }.build()
                        s.setRepeatingRequest(req, null, main)
                    } catch (e: Exception) {
                        applog("facecam", "no frames: ${e.javaClass.simpleName}")
                    }
                }

                override fun onConfigureFailed(s: CameraCaptureSession) {
                    applog("facecam", "session configure failed")
                    s.close()
                }
            }
        )
        try {
            cam.createCaptureSession(cfg)
        } catch (e: Exception) {
            applog("facecam", "session failed: ${e.javaClass.simpleName}")
        }
    }

    private fun displayDegrees() = when (app.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)?.rotation) {
        Surface.ROTATION_90 -> 90
        Surface.ROTATION_180 -> 180
        Surface.ROTATION_270 -> 270
        else -> 0
    }

    private fun closeSession() {
        generation++
        session?.close()
        session = null
    }

    private fun closeDevice() {
        closeSession()
        device?.close()
        device = null
    }

    private fun closeAll() {
        main.removeCallbacks(closeLater)
        closeDevice()
    }

    /** The camera died under us: hide the window and stay down until the next refresh (a new stream or toggle) retries. */
    private fun drop() {
        device = null
        closeSession()
        filter?.clearFrame()
    }

    /** Stream released (settings re-prepare, unbind): nothing will draw, so free the sensor now. */
    fun stop() {
        filter = null
        active = false
        closeAll()
    }

    /** The main camera is about to switch lens; the front sensor can't serve two openers, so let go of it first. */
    fun beforeFlip() = closeAll()

    fun afterFlip() = Overlays.refresh()
}
