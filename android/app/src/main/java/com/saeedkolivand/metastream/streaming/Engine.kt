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
import androidx.core.net.toUri
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.pedro.common.ConnectChecker
import com.pedro.common.StreamingStatsReport
import com.pedro.common.VideoCodec
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.pedro.encoder.input.sources.video.Camera2Source
import com.pedro.encoder.input.sources.video.VideoSource
import com.pedro.encoder.utils.gl.AspectRatioMode
import com.pedro.library.generic.GenericStream
import com.pedro.library.util.streamclient.SrtStreamClient
import com.saeedkolivand.metastream.camera.Cam
import com.saeedkolivand.metastream.camera.FaceCam
import com.saeedkolivand.metastream.core.AppSettings
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.VideoParams
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.core.redactFromLogs
import com.saeedkolivand.metastream.core.toVideoParams
import com.saeedkolivand.metastream.glasses.Glasses
import com.saeedkolivand.metastream.overlay.Overlays
import com.saeedkolivand.metastream.privacy.Privacy
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
        Health.init(app, scope, speak, alert)
        Cam.init(app)
        FaceCam.init(app)
        Privacy.init(speak)
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

    private fun video(s: Source): VideoSource = if (s == Source.Usb) UvcSource() else Camera2Source(app)

    /** Creates the stream on first use (needs CAMERA + RECORD_AUDIO); callable without any activity. */
    private fun ensure(): GenericStream? {
        stream?.let { return it }
        val permitted = arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
            .all { ContextCompat.checkSelfPermission(app, it) == PackageManager.PERMISSION_GRANTED }
        if (!permitted) {
            status = "camera/mic permission needed"
            return null
        }
        val mic = MicrophoneSource().also { Mics.apply(app, it) }
        val s = GenericStream(app, checker, video(source), mic)
        s.getGlInterface().autoHandleOrientation = true // output follows device rotation
        s.getGlInterface().setAspectRatioMode(AspectRatioMode.Fill) // the preview crops to fill the screen like iOS
        s.getStreamClient().setReTries(10) // RootEncoder's built-in reconnect, driven from onConnectionFailed
        if (!prepare(s)) return null
        stream = s
        return s
    }

    private var preview: SurfaceView? = null
    private var prepared: Pair<VideoParams, Boolean>? = null

    private fun portrait() = app.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT

    private fun wanted() = AppSettings.ingest.let { it.toVideoParams(portrait()) to it.h265 }

    /** Applies the saved ingest settings; an upright phone with no lock = 720x1280 out (rotation 90, as RootEncoder's sample). */
    private fun prepare(s: GenericStream): Boolean {
        val want = wanted()
        val (p, h265) = want
        val ok = try {
            s.setVideoCodec(if (h265) VideoCodec.H265 else VideoCodec.H264)
            s.prepareVideo(p.width, p.height, p.bitrate, fps = p.fps, rotation = p.rotation) &&
                s.prepareAudio(44100, true, 128_000)
        } catch (e: IllegalArgumentException) {
            false
        }
        if (ok) applyCameraOff(s)
        if (ok) Overlays.bind(s.getGlInterface(), p.outW, p.outH)
        if (ok) Cam.attach(s)
        if (ok) prepared = want else status = "camera/mic setup failed"
        return ok
    }

    // ponytail: size/orientation/codec are fixed when going live (like iOS); turning the phone mid-stream letterboxes via
    // autoHandleOrientation instead of re-encoding. Re-preparing needs a released stream, so the preview restarts.
    private fun matchSettings(s: GenericStream): Boolean {
        if (wanted() == prepared) return true
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
        if (s != null && next != Source.Glasses && (next == Source.Usb) != (s.videoSource is UvcSource)) {
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
        if (s != null && !matchSettings(s)) return
        redactFromLogs(key)
        Prefs.put("url", url)
        Prefs.put("key", key)
        // Scheme/host/path only: SRT URLs carry passphrase/streamid in the query, RTMP ones can embed user:pass.
        applog("stream", "connecting to ${url.toUri().let { "${it.scheme}://${it.host}:${it.port}${it.path}" }}")
        // Reuses the idle service when the activity/car already started it; otherwise Android may refuse from the background.
        if (!StreamingService.hold(app, "live")) {
            status = "open the app on the phone once, then retry"
            return
        }
        Overlays.refresh() // before the encoder starts, so the privacy blur is already in the chain for the first frame
        val full = url.trimEnd('/') + "/" + key
        if (s == null) glasses.start(full, askWearables) else startStream(s, full)
        // Glasses passthrough has no encoder knob, so Health only watches it.
        Health.start(AppSettings.ingest.bitrateKbps, s?.getStreamClient()) { s?.setVideoBitrateOnFly(it * 1000) }
        live = true
    }

    fun stop(reason: String = "idle") {
        Health.stop()
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

    private fun startStream(s: GenericStream, full: String) {
        if (full.startsWith("srt://")) setSrtLatency(s, AppSettings.ingest.srtLatencyMs)
        s.startStream(full)
    }

    // ponytail: GenericStreamClient hides the SRT client's setLatency (its setDelay is something else); reflection reaches it.
    // Upgrade path: build SrtStream directly when the URL is srt://.
    private fun setSrtLatency(s: GenericStream, ms: Int) {
        try {
            val client = s.getStreamClient()
            val f = client.javaClass.getDeclaredField("srtClient").apply { isAccessible = true }
            (f.get(client) as SrtStreamClient).setLatency(ms)
        } catch (e: ReflectiveOperationException) {
            applog("stream", "SRT latency not applied: ${e.message}")
        }
    }

    fun switchCamera() {
        val cam = stream?.videoSource as? Camera2Source ?: return
        FaceCam.beforeFlip()
        cam.switchCamera()
        FaceCam.afterFlip()
    }

    /** Re-applies the picked microphone to the running source (a new choice from Settings). */
    fun refreshMic() {
        (stream?.audioSource as? MicrophoneSource)?.let { Mics.apply(app, it) }
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
                Health.markUp()
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
                    Health.markDown()
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
            Health.onStats(report.bytesOutPerSecond, report.smoothedBitrate)
            scope.launch {
                if (live) status = "%s · %.1f Mb/s".format(status.substringBefore(" ·"), report.smoothedBitrate / 1e6)
            }
        }
    }
}
