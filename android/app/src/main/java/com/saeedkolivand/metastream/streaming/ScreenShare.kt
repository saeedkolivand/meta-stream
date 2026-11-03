package com.saeedkolivand.metastream.streaming

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.snapshotFlow
import com.pedro.encoder.input.sources.audio.MixAudioSource
import com.pedro.encoder.input.sources.video.Camera2Source
import com.pedro.encoder.input.sources.video.NoVideoSource
import com.pedro.encoder.input.sources.video.ScreenSource
import com.pedro.encoder.input.sources.video.VideoSource
import com.saeedkolivand.metastream.core.applog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * The Screen source (iOS ScreenSource): the phone's screen through MediaProjection, with the mic as its audio. Android
 * wants the consent first, then the foreground service promoted to the media-projection type, then the projection, so the
 * consent result travels to [StreamingService], which calls [granted]. Leaving the source ends the share.
 * ponytail: one capture per consent (Android 14+ allows one virtual display per projection), so a re-prepare while
 * sharing (a resolution change) needs the share started again. App audio rides along with the mic (Engine.syncAudio).
 */
object ScreenShare {
    private var projection: MediaProjection? = null
    val sharing get() = projection != null
    private var watch: Job? = null
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun consentIntent(context: Context): Intent = context.getSystemService(MediaProjectionManager::class.java).createScreenCaptureIntent()

    /** The consent dialog said yes: the service promotes itself, then hands back to [granted]. */
    fun consent(context: Context, code: Int, data: Intent) {
        context.startService(
            Intent(context, StreamingService::class.java).setAction(StreamingService.ACTION_SCREEN)
                .putExtra(StreamingService.EXTRA_CODE, code).putExtra(StreamingService.EXTRA_DATA, data)
        )
    }

    /** Called by the service once it runs as a media-projection foreground service. */
    internal fun granted(context: Context, code: Int, data: Intent) {
        val p = runCatching { context.getSystemService(MediaProjectionManager::class.java).getMediaProjection(code, data) }
            .onFailure { applog("screen", "no projection: ${it.message}") }.getOrNull() ?: return
        stop()
        projection = p
        p.registerCallback(
            object : MediaProjection.Callback() {
                override fun onStop() { // the system's "stop sharing", or the screen locked
                    main.post {
                        projection = null
                        if (Engine.source == Source.Screen) Engine.pick(Source.Phone)
                    }
                }
            },
            main
        )
        Engine.pick(Source.Screen)
        if (Engine.source != Source.Screen) return stop() // refused (glasses while live, say)
        applog("screen", "sharing")
        watch = scope.launch {
            snapshotFlow { Engine.source }.first { it != Source.Screen }
            stop()
        }
    }

    /**
     * Engine's video source for Screen. Without a projection (a fresh stream after a restart) it's a blank frame, never
     * the camera: the user chose to show their screen, so falling back to the camera would film them unannounced.
     */
    internal fun source(context: Context): VideoSource = projection?.let { ScreenSource(context, it) } ?: NoVideoSource().also {
        applog("screen", "no projection, sending a blank frame; pick Screen again to share")
    }

    /** The apps' audio mixed with the mic, from the current projection; null without one. */
    internal fun appAudio(): MixAudioSource? = projection?.let { MixAudioSource(it, object : MediaProjection.Callback() {}) }

    fun stop() {
        watch?.cancel()
        watch = null
        projection?.let {
            projection = null
            it.stop()
            applog("screen", "stopped")
        }
    }
}

/** The RootEncoder source class [s] runs on, so Engine.pick swaps only when it changes. */
internal fun sourceClass(s: Source): Class<out VideoSource> = when (s) {
    Source.Usb -> UvcSource::class.java
    Source.Screen -> ScreenSource::class.java
    else -> Camera2Source::class.java
}

internal fun videoSource(context: Context, s: Source): VideoSource = when (s) {
    Source.Usb -> UvcSource()
    Source.Screen -> ScreenShare.source(context)
    else -> Camera2Source(context)
}
