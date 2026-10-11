package com.saeedkolivand.metastream.privacy

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.pedro.library.view.GlInterface
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.overlay.Overlays
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

private const val PAD = 0.3f // iOS padFraction: motion between detections is the risk, not one frame of under-blur
private const val EVERY_MS = 110L // ~9 detections a second, so the encoder keeps its frame budget
private const val LOST_MS = 1000L // a capture that never answered is retried instead of wedging blur
private const val WATCH_MS = 500L

enum class BlurState { Off, Protecting, Pending }

/**
 * Privacy blur: faces, text (so licence plates) and QR/barcodes are pixelated before the encoder sees them, Phone and USB only.
 * Fails closed like iOS: if detection hasn't completed for 3 s the whole frame is pixelated and [stalled] drives the HUD pill.
 * Unlike iOS (which hides the camera) we pixelate rather than go black, and we also hide everything until the first result.
 */
object Privacy : BlurFeed {
    private lateinit var speak: (String) -> Unit
    private val main = Handler(Looper.getMainLooper())
    private val tracker = BoxTracker()
    private val detector by lazy { Detector(ROTATION) }
    private var filter: RegionBlurFilter? = null
    private var owner: GlInterface? = null // the pipeline [filter] lives in

    var on by mutableStateOf(false)
        private set
    var faces by mutableStateOf(true)
        private set
    var text by mutableStateOf(true)
        private set
    var barcodes by mutableStateOf(true)
        private set
    var stalled by mutableStateOf(false)
        private set
    var installed by mutableStateOf(false)
        private set

    @Volatile private var lastOk = 0L

    @Volatile private var armedAt = 0L

    @Volatile private var lastCapture = 0L

    @Volatile private var inFlightSince = 0L

    /** Glasses passthrough is HEVC straight from the glasses; there are no frames here to alter. */
    val applicable get() = Engine.source != Source.Glasses
    val wanted get() = on && applicable

    val state
        get() = when {
            !on -> BlurState.Off
            Engine.live && !installed -> BlurState.Pending
            else -> BlurState.Protecting
        }

    fun init(speak: (String) -> Unit) {
        this.speak = speak
        on = Prefs.bool("blurOn")
        faces = Prefs.bool("blurFaces", true)
        text = Prefs.bool("blurText", true)
        barcodes = Prefs.bool("blurBarcodes", true)
    }

    fun updateOn(v: Boolean) {
        on = v
        Prefs.put("blurOn", v)
        Overlays.refresh() // installs or removes the filter and re-picks the preview aspect mode
    }

    fun updateFaces(v: Boolean) {
        faces = v
        Prefs.put("blurFaces", v)
    }

    fun updateText(v: Boolean) {
        text = v
        Prefs.put("blurText", v)
    }

    fun updateBarcodes(v: Boolean) {
        barcodes = v
        Prefs.put("blurBarcodes", v)
    }

    /**
     * Makes the chain match the setting; the filter goes first so overlays stay sharp. It outlives Overlays' own rebuilds
     * (those remove only their filters), because a clear would leave frames unblurred until the next filter op, one per frame.
     */
    fun install(g: GlInterface) {
        if (owner !== g) forget() // fail closed: a filter in a replaced pipeline protects nothing, so never trust it
        val f = filter
        if (wanted && f == null) {
            detector.warm()
            synchronized(tracker) { tracker.clear() }
            lastOk = 0
            armedAt = SystemClock.elapsedRealtime()
            filter = RegionBlurFilter(this).also { g.addFilter(0, it) }
            owner = g
            installed = true
            main.removeCallbacks(watch)
            main.post(watch)
        } else if (!wanted && f != null) {
            g.removeFilter(f)
            forget()
        }
    }

    /** The GL pipeline was replaced, so the old filter is already gone. */
    fun forget() {
        filter = null
        owner = null
        installed = false
        main.removeCallbacks(watch)
        markStalled(false)
    }

    private val watch = object : Runnable {
        override fun run() {
            markStalled(Stall.stalled(SystemClock.elapsedRealtime(), lastOk, armedAt))
            main.postDelayed(this, WATCH_MS)
        }
    }

    private fun markStalled(v: Boolean) {
        if (v == stalled) return
        stalled = v
        applog("privacy", if (v) "detection stalled, hiding the whole frame" else "detection recovered")
        speak(if (v) "blur stopped working, frame hidden" else "blur working, frame back")
    }

    // GL thread from here down.

    override fun rects(now: Long): FloatArray? {
        if (Stall.blurAll(now, lastOk, armedAt)) return null
        val boxes = synchronized(tracker) { tracker.active(now) }
        return FloatArray(boxes.size * 4).also { out ->
            boxes.forEachIndexed { i, b ->
                val g = toGl(b)
                floatArrayOf(g.l, g.t, g.r, g.b).copyInto(out, i * 4)
            }
        }
    }

    override fun wantFrame(now: Long): Boolean {
        val busy = inFlightSince != 0L && now - inFlightSince < LOST_MS
        if (busy || now - lastCapture < EVERY_MS) return false
        lastCapture = now
        inFlightSince = now
        return true
    }

    override fun onFrame(frame: Bitmap) {
        val want = Targets(faces, text, barcodes)
        main.post {
            detector.detect(frame, want) { found ->
                inFlightSince = 0
                if (found != null) {
                    val now = SystemClock.elapsedRealtime()
                    synchronized(tracker) { tracker.update(found.map { it.pad(PAD) }, now) }
                    lastOk = now
                } else {
                    applog("privacy", "detection pass failed")
                }
            }
        }
    }

    // How the captured bitmap must turn to be upright for ML Kit; matches the filter chain's orientation.
    private const val ROTATION = 0
}
