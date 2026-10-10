package com.saeedkolivand.metastream.glasses

import android.app.Activity
import android.app.Application
import android.media.MediaCodec
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meta.wearable.dat.camera.Camera
import com.meta.wearable.dat.camera.addCamera
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.VideoFrame
import com.meta.wearable.dat.camera.types.VideoQuality
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.AutoDeviceSelector
import com.meta.wearable.dat.core.session.DeviceSession
import com.meta.wearable.dat.core.session.DeviceSessionState
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.meta.wearable.dat.core.types.RegistrationState
import com.meta.wearable.dat.mockdevice.MockDeviceKit
import com.meta.wearable.dat.mockdevice.api.GlassesModel
import com.meta.wearable.dat.mockdevice.api.MockGlasses
import com.meta.wearable.dat.mockdevice.api.camera.CameraFacing
import com.pedro.common.ConnectChecker
import com.pedro.common.VideoCodec
import com.pedro.rtmp.rtmp.RtmpClient
import com.saeedkolivand.metastream.core.applog
import java.nio.ByteBuffer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Ray-Ban Meta glasses source: DAT registration, session/stream lifecycle, an HEVC preview decoder, and
 * HEVC passthrough to RTMP through RootEncoder's low-level [RtmpClient] (no re-encode, like iOS).
 */
class Glasses(private val app: Application, private val scope: CoroutineScope, checker: ConnectChecker) {
    var registration by mutableStateOf(RegistrationState.UNAVAILABLE)
        private set
    var mock by mutableStateOf(false)
        private set
    var status by mutableStateOf("")
        private set

    private val selector = AutoDeviceSelector()
    private val kit = MockDeviceKit.getInstance(app)
    private var mockGlasses: MockGlasses? = null
    private var initialized = false

    private var session: DeviceSession? = null
    private var camera: Camera? = null
    private var job: Job? = null

    private val rtmp = RtmpClient(checker)
    private val params = ParamSets()
    private val lock = Any()
    private var surface: Surface? = null
    private var decoder: HevcDecoder? = null

    // RTMP hookup state: written by the frame collector thread, and reset from main (stop) and RootEncoder callback threads
    // (onRtmpUp/Down), so every field is volatile.
    @Volatile private var url = ""

    @Volatile private var rtmpStarted = false

    @Volatile private var basePts = -1L

    @Volatile private var connected = false

    @Volatile private var sending = false

    /** Call once permissions are granted; SDK init is required before any Wearables API. */
    fun init(activity: Activity) {
        if (initialized) return
        initialized = true
        Wearables.initialize(activity)
        scope.launch { Wearables.registrationState.collect { registration = it } }
    }

    fun register(activity: Activity) = Wearables.startRegistration(activity)
    fun unregister(activity: Activity) = Wearables.startUnregistration(activity)

    fun enableMock(on: Boolean) {
        mock = on
        if (on) {
            kit.enable()
            scope.launch {
                kit.pairGlasses(GlassesModel.RAYBAN_META).fold(
                    onSuccess = { g ->
                        mockGlasses = g
                        g.powerOn()
                        g.don()
                        scope.launch { g.services.camera.setCameraFeed(CameraFacing.BACK) } // phone camera stands in for the glasses
                    },
                    onFailure = { e, _ -> status = "mock pairing failed: ${e.description}" }
                )
            }
        } else {
            mockGlasses?.let { g -> scope.launch { kit.unpairDevice(g) } }
            mockGlasses = null
            kit.disable()
        }
    }

    fun setSurface(s: Surface?) = synchronized(lock) {
        surface = s
        if (s == null) {
            decoder?.stop()
            decoder = null
        }
    }

    /** Session (retry up to 3x on "Device unavailable", as iOS) -> camera stream -> frames to preview and RTMP. */
    fun start(rtmpUrl: String, askCamera: suspend (Permission) -> PermissionStatus) {
        url = rtmpUrl
        job = scope.launch {
            val perm = Wearables.checkPermissionStatus(Permission.CAMERA).fold({ it }, { _, _ -> PermissionStatus.Denied })
            if (perm != PermissionStatus.Granted && askCamera(Permission.CAMERA) != PermissionStatus.Granted) {
                status = "glasses camera permission denied"
                return@launch
            }
            var started: DeviceSession? = null
            for (attempt in 1..3) {
                status = "starting session ($attempt/3)"
                val created = Wearables.createSession(selector).fold({ it }, { e, _ ->
                    status = "session: ${e.description}"
                    null
                }) ?: break
                scope.launch { created.errors.collect { applog("glasses", "session error: ${it.description}") } }
                created.start()
                val end = withTimeoutOrNull(30_000) {
                    created.state.first {
                        it == DeviceSessionState.STARTED ||
                            it == DeviceSessionState.STOPPED
                    }
                }
                if (end == DeviceSessionState.STARTED) {
                    started = created
                    break
                }
                created.stop()
                delay(2000)
            }
            val s = started ?: return@launch
            session = s
            val cam = s.addCamera(StreamConfiguration(videoQuality = VideoQuality.HIGH, frameRate = 30, compressVideo = true))
                .fold({ it }, { e, _ ->
                    status = "camera: ${e.description}"
                    null
                }) ?: return@launch
            camera = cam
            val stream = cam.stream
            launch { stream.state.collect { status = "stream ${it.name.lowercase()}" } }
            launch { stream.errorStream.collect { applog("glasses", "stream error: ${it.description}") } }
            launch(Dispatchers.Default.limitedParallelism(1)) { stream.videoStream.collect(::onFrame) }
            stream.start().onFailure { e, _ -> status = "stream start: ${e.description}" }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        if (rtmpStarted) rtmp.disconnect()
        synchronized(lock) {
            decoder?.stop()
            decoder = null
        }
        camera?.close()
        camera = null // closing the camera stops its stream; STOPPED sessions are not reusable
        session?.stop()
        session = null
        params.reset()
        rtmpStarted = false
        connected = false
        sending = false
        basePts = -1
        status = ""
    }

    fun onRtmpUp() {
        connected = true
    }

    fun onRtmpDown() {
        connected = false
        sending = false
    }

    fun retry(reason: String): Boolean {
        if (!rtmp.shouldRetry(reason)) return false
        rtmp.reConnect(5000)
        return true
    }

    private fun onFrame(f: VideoFrame) {
        if (!f.isCompressed) return
        val data = ByteArray(f.buffer.remaining()).also { f.buffer.duplicate().get(it) }
        val nals = nalUnits(data)
        params.offer(nals)

        synchronized(lock) {
            val s = surface
            if (decoder == null && s != null) {
                decoder = HevcDecoder().also { d ->
                    d.start(f.width, f.height, s)
                    params.annexB()?.let { d.decodeFrame(it, 0) }
                }
            }
            decoder?.decodeFrame(data, f.presentationTimeUs)
        }
        if (f.isCodecConfig) return

        // Warm-up like iOS: video is already flowing (decoder fed) before RTMP connects, and sending starts on a keyframe.
        val key = isKeyframe(nals)
        if (!rtmpStarted) {
            if (!key || !params.complete()) return
            rtmpStarted = true
            rtmp.setVideoCodec(VideoCodec.H265)
            rtmp.setOnlyVideo(true) // audio is a later phase
            rtmp.setVideoResolution(f.width, f.height)
            rtmp.setFps(30)
            rtmp.setReTries(10)
            rtmp.setVideoInfo(ByteBuffer.wrap(params.sps!!), ByteBuffer.wrap(params.pps!!), ByteBuffer.wrap(params.vps!!))
            rtmp.connect(url)
            return
        }
        if (!connected) return
        // ponytail: after (re)connect we wait for the glasses' next keyframe instead of caching one; fine unless their GOP is long.
        if (!sending) {
            if (!key) return
            sending = true
        }
        if (basePts < 0) basePts = f.presentationTimeUs
        val info = MediaCodec.BufferInfo().apply {
            set(0, data.size, f.presentationTimeUs - basePts, if (key) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
        }
        rtmp.sendVideo(ByteBuffer.wrap(data), info)
    }
}
