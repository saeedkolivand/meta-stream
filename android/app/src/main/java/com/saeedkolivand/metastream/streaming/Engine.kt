package com.saeedkolivand.metastream.streaming

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.hardware.usb.UsbManager
import android.view.SurfaceView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.pedro.common.ConnectChecker
import com.pedro.common.StreamingStatsReport
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.pedro.encoder.input.sources.video.Camera2Source
import com.pedro.encoder.input.sources.video.VideoSource
import com.pedro.encoder.utils.gl.AspectRatioMode
import com.pedro.extrasources.CameraUvcSource
import com.pedro.library.generic.GenericStream
import com.saeedkolivand.metastream.camera.Cam
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.core.redactFromLogs
import com.saeedkolivand.metastream.glasses.Glasses
import com.saeedkolivand.metastream.overlay.Overlays
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

enum class Source { Phone, Usb, Glasses }

const val DEFAULT_INGEST_URL = "rtmp://100.124.231.50:1935/live"

private const val USB_VIDEO_CLASS = 14

private val DENY_WEARABLES: suspend (Permission) -> PermissionStatus = { PermissionStatus.Denied }

/**
 * Process-wide owner of the stream; the activity and the car screens are views over it.
 *
 * State is Compose snapshot state with private setters: readers observe, changes go through the intent functions.
 * RootEncoder callbacks arrive on its own threads, so they only hop to [scope] (main) before touching state.
 */
object Engine {
    private lateinit var app: Application
    private lateinit var scope: CoroutineScope
    private lateinit var speak: (String) -> Unit
    private lateinit var alert: (String) -> Unit
    lateinit var glasses: Glasses
        private set

    // ponytail: key in plain SharedPreferences (iOS uses Keychain); upgrade path is Keystore-backed storage.
    var url by mutableStateOf("")
        private set
    var key by mutableStateOf("")
        private set
    var live by mutableStateOf(false)
        private set
    var muted by mutableStateOf(false)
        private set

    /** Sends black video while the audio keeps going. */
    var cameraOff by mutableStateOf(false)
        private set
    var status by mutableStateOf("idle")
        private set
    var source by mutableStateOf(Source.Phone)
        private set

    /** Epoch ms of the session's first successful connect; null until then and after stop. */
    var liveSince by mutableStateOf<Long?>(null)
        private set

    /** False while (re)connecting; lets the notification tell "LIVE" from "RECONNECTING". */
    var connected by mutableStateOf(false)
        private set

    private var askWearables: suspend (Permission) -> PermissionStatus = DENY_WEARABLES

    @Volatile private var stream: GenericStream? = null

    /** [speak] and [alert] announce stream events to the user (TTS, car notification). */
    fun init(application: Application, scope: CoroutineScope, speak: (String) -> Unit, alert: (String) -> Unit) {
        app = application
        this.scope = scope
        this.speak = speak
        this.alert = alert
        url = Prefs.string("url", DEFAULT_INGEST_URL)
        key = Prefs.string("key")
        glasses = Glasses(app, scope, checker)
        Cam.init(app)
    }

    fun updateUrl(value: String) {
        url = value
    }

    fun updateKey(value: String) {
        key = value
    }

    /** The activity supplies the Meta AI permission flow; null (activity gone) answers Denied. */
    fun setWearablesAsker(ask: (suspend (Permission) -> PermissionStatus)?) {
        askWearables = ask ?: DENY_WEARABLES
    }

    private fun video(s: Source): VideoSource = if (s == Source.Usb) CameraUvcSource() else Camera2Source(app)

    /** Creates the stream on first use (needs CAMERA + RECORD_AUDIO); callable without any activity. */
    private fun ensure(): GenericStream? {
        stream?.let { return it }
        val permitted = arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
            .all { ContextCompat.checkSelfPermission(app, it) == PackageManager.PERMISSION_GRANTED }
        if (!permitted) {
            status = "camera/mic permission needed"
            return null
        }
        val s = GenericStream(app, checker, video(source), MicrophoneSource())
        s.getGlInterface().autoHandleOrientation = true // output follows device rotation
        s.getGlInterface().setAspectRatioMode(AspectRatioMode.Fill) // the preview crops to fill the screen like iOS
        s.getStreamClient().setReTries(10) // RootEncoder's built-in reconnect, driven from onConnectionFailed
        // ponytail: 720p30 requested of every source; CameraUvcSource has no size API, so UVCAndroid picks its default
        // preview size and the GL pipeline scales it. Upgrade path: own VideoSource wrapping ICameraHelper.setPreviewSize.
        if (!prepare(s)) return null
        stream = s
        return s
    }

    private var preview: SurfaceView? = null
    private var preparedPortrait: Boolean? = null

    private fun portrait() = app.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT

    /** Upright phone = 720x1280 out (rotation 90, as RootEncoder's sample), else 1280x720. */
    private fun prepare(s: GenericStream): Boolean {
        val vertical = portrait()
        val ok = try {
            s.prepareVideo(1280, 720, 4_000_000, fps = 30, rotation = if (vertical) 90 else 0) &&
                s.prepareAudio(44100, true, 128_000)
        } catch (e: IllegalArgumentException) {
            false
        }
        if (ok) applyCameraOff(s)
        if (ok) Cam.attach(s)
        if (ok) Overlays.bind(s.getGlInterface(), if (vertical) 720 else 1280, if (vertical) 1280 else 720)
        if (ok) preparedPortrait = vertical else status = "camera/mic setup failed"
        return ok
    }

    // ponytail: orientation is fixed when going live (like iOS); turning the phone mid-stream letterboxes via
    // autoHandleOrientation instead of re-encoding. Re-preparing needs a released stream, so the preview restarts.
    private fun matchOrientation(s: GenericStream): Boolean {
        if (portrait() == preparedPortrait) return true
        Overlays.unbind() // the re-prepare drops the GL filters; prepare() binds again and goLive refreshes
        s.release()
        val ok = prepare(s)
        preview?.let { if (ok) s.startPreview(it, true) }
        return ok
    }

    /** Preview is optional: it follows the SurfaceView, and streaming continues when it goes away. */
    fun attach(view: SurfaceView) {
        preview = view
        ensure()?.let {
            it.startPreview(view, true)
            applyCameraOff(it)
            Overlays.refresh()
        }
    }

    private fun applyCameraOff(s: GenericStream) = s.getGlInterface().let { if (cameraOff) it.muteVideo() else it.unMuteVideo() }

    fun toggleCameraOff() {
        cameraOff = !cameraOff
        stream?.let(::applyCameraOff)
    }

    fun detach() {
        preview = null
        stream?.let { if (it.isOnPreview) it.stopPreview(true) }
    }

    private fun usbCameraPresent() = app.getSystemService(UsbManager::class.java).deviceList.values.any { d ->
        (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == USB_VIDEO_CLASS }
    }

    fun pick(next: Source) {
        if (next == source) return
        if (live && (next == Source.Glasses || source == Source.Glasses)) {
            status = "stop the stream to switch to or from glasses"
            return
        }
        if (next == Source.Usb && !usbCameraPresent()) {
            status = "no USB camera attached"
            return
        }
        val s = stream
        if (s != null && next != Source.Glasses && (next == Source.Usb) != (s.videoSource is CameraUvcSource)) {
            try {
                s.changeVideoSource(video(next))
                Cam.attach(s)
            } catch (e: IllegalArgumentException) {
                status = "source unsupported: ${e.message}"
                return
            }
        }
        source = next
        Overlays.refresh()
    }

    fun goLive() {
        if (live) return
        if (source == Source.Usb && !usbCameraPresent()) {
            status = "no USB camera attached"
            return
        }
        val s = if (source == Source.Glasses) null else ensure() ?: return
        if (s != null && !matchOrientation(s)) return
        redactFromLogs(key)
        Prefs.put("url", url)
        Prefs.put("key", key)
        applog("stream", "connecting to $url")
        // Reuses the idle service when the activity/car already started it; otherwise Android may refuse from the background.
        if (!StreamingService.hold(app, "live")) {
            status = "open the app on the phone once, then retry"
            return
        }
        val full = url.trimEnd('/') + "/" + key
        if (s == null) glasses.start(full, askWearables) else s.startStream(full)
        Overlays.refresh()
        live = true
    }

    fun stop(reason: String = "idle") {
        if (source == Source.Glasses) glasses.stop() else stream?.stopStream()
        live = false
        connected = false
        liveSince = null
        cameraOff = false
        stream?.let(::applyCameraOff)
        status = reason
        StreamingService.release(app, "live")
        alert("Stream stopped")
        applog("stream", "stopped: $reason")
        speak("stream stopped")
    }

    fun switchCamera() {
        (stream?.videoSource as? Camera2Source)?.switchCamera()
    }

    fun toggleMute() {
        val mic = stream?.audioSource as? MicrophoneSource ?: return
        muted = !muted
        if (muted) mic.mute() else mic.unMute()
    }

    // Callbacks run on RootEncoder threads: decide there, then mutate state on the main scope.
    private val checker = object : ConnectChecker {
        override fun onConnectionStarted(url: String) {
            scope.launch { status = "connecting" }
        }

        override fun onConnectionSuccess() {
            glasses.onRtmpUp()
            applog("stream", "connected")
            scope.launch {
                if (live) {
                    connected = true
                    if (liveSince == null) liveSince = System.currentTimeMillis()
                }
                status = "connected"
                speak("stream connected")
                alert("Back live")
            }
        }

        override fun onConnectionFailed(reason: String) {
            applog("stream", "failed: $reason")
            glasses.onRtmpDown()
            val retrying = if (source == Source.Glasses) glasses.retry(reason) else stream?.getStreamClient()?.reTry(5000, reason) == true
            scope.launch {
                connected = false
                if (retrying) {
                    status = "retrying: $reason"
                    speak("connection lost, retrying")
                    alert("Stream dropped, retrying")
                } else {
                    stop("failed: $reason")
                }
            }
        }

        override fun onDisconnect() {
            glasses.onRtmpDown()
            applog("stream", "disconnected")
            scope.launch { connected = false }
        }

        override fun onAuthError() {
            scope.launch { stop("auth error") }
        }

        override fun onAuthSuccess() {}

        override fun onStreamingStats(report: StreamingStatsReport) {
            scope.launch {
                if (live) status = "%s · %.1f Mb/s".format(status.substringBefore(" ·"), report.smoothedBitrate / 1e6)
            }
        }
    }
}
