package com.saeedkolivand.metastream.overlay

import android.app.Application
import android.graphics.Bitmap
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.view.Surface
import com.pedro.encoder.input.gl.render.filters.`object`.BaseObjectFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.ImageFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.SurfaceFilterRender
import com.pedro.library.view.GlInterface
import com.saeedkolivand.metastream.camera.FaceCam
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.privacy.Privacy
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import java.io.File
import kotlin.math.min
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

private const val MAX_SLIDES = 30

/** Widget layers are placed in output px already, so they go through the OBS paths with no canvas fit. */
private val IDENTITY = Fit(1f, 0f, 0f)

/** A live widget: its filter, plus the coroutine that keeps its bitmap current (null for render-once widgets). */
internal class WidgetBuild(val filter: BaseObjectFilterRender, val job: Job?)

/** RootEncoder object filters take position and size as percent of the output, top-left based. [box] is in output px. */
internal fun <T : BaseObjectFilterRender> T.placeIn(box: Box, outW: Int, outH: Int, rotation: Float = 0f): T {
    setScale(box.w / outW * 100, box.h / outH * 100)
    setPosition(box.x / outW * 100, box.y / outH * 100)
    // OBS rotates clockwise, the GL sprite counter-clockwise.
    if (rotation != 0f) this.rotation = ((360 - rotation) % 360).toInt()
    return this
}

/**
 * Draws the active OBS scene onto the stream with RootEncoder filters (Phone/USB only; glasses HEVC can't be drawn on).
 * All calls are on the main thread. [refresh] rebuilds everything, so it is safe to call whenever the GL pipeline restarts.
 */
object Overlays {
    private lateinit var app: Application
    private val main = Handler(Looper.getMainLooper())
    private var gl: GlInterface? = null
    private var sink: FilterSink? = null
    private var outW = 0
    private var outH = 0
    private var browser: BrowserOverlay? = null
    private val players = mutableListOf<MediaPlayer>()
    private var widgetScope: CoroutineScope? = null
    private val widgetJobs = mutableListOf<Job>()

    fun init(application: Application) {
        app = application
    }

    /** Called when the stream is (re)prepared: the output size is only known then. */
    fun bind(gl: GlInterface, w: Int, h: Int) {
        release()
        Privacy.forget() // a new pipeline starts with an empty chain
        this.gl = gl
        sink = FilterSink(gl)
        outW = w
        outH = h
    }

    fun unbind() {
        release()
        FaceCam.stop()
        Privacy.forget()
        gl = null
        sink = null
    }

    /** Filters survive nothing: the GL thread drops them when it stops, so callers refresh after (re)starting it. */
    fun refresh() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post(::refresh)
            return
        }
        release()
        val glNow = gl ?: return
        val g = sink ?: return
        // Chain order is face-cam -> blur -> overlays: the blur must see (and hide faces in) the face-cam window, while
        // alerts stay sharp. Privacy keeps its filter across refreshes; the face-cam goes back in at index 0, ahead of it.
        Privacy.install(glNow)
        FaceCam.install(g, outW, outH)
        val pack = OverlayStore.pack
        val scene = OverlayStore.active()?.takeIf { pack != null && Engine.source != Source.Glasses }
        if (scene == null || pack == null) return
        val fit = fit(pack.canvasW, pack.canvasH, outW, outH)
        val web = BrowserOverlay(app, outW, outH)
        browser = web
        // Fresh per refresh: cancelling it in release() stops every widget's re-render loop with the filters.
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { widgetScope = it }
        for (l in scene.layers.filter { it.visible }) {
            // Only the layer type reaches the log; exception messages could carry a URL.
            runCatching { add(g, web, l, fit, scope) }.onFailure {
                applog("overlay", "${l.type} layer failed: ${it.javaClass.simpleName}")
            }
        }
        // ponytail: browser sources share one view drawn above the image/text/media layers, whatever their OBS order.
        // Upgrade path: one view per run of consecutive browser layers.
        if (!web.isEmpty) g.addLayer(web.filter())
    }

    /** Scene-transition opacity for everything the scene drew (not the privacy blur or face-cam). */
    fun setAlpha(a: Float) {
        sink?.setAlpha(a)
    }

    /**
     * The privacy-blur and face-cam toggles touch only their own filters, so they re-sync just that part of the chain.
     * A full [refresh] would destroy the browser view (reloading its page) and restart media players for a blur toggle.
     */
    fun syncPrivacy() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post(::syncPrivacy)
            return
        }
        val glNow = gl ?: return
        // In a live chain the face-cam window sits at 0, so the blur slots in at 1; without it, at 0, like a fresh rebuild.
        Privacy.install(glNow, if (FaceCam.inChain) 1 else 0)
    }

    fun syncFaceCam() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post(::syncFaceCam)
            return
        }
        val g = sink ?: return
        FaceCam.remove(g) // re-installs below with a fresh filter; overlay layers keep their place
        FaceCam.install(g, outW, outH)
    }

    private fun release() {
        sink?.clear()
        browser?.destroy()
        browser = null
        players.forEach { it.release() }
        players.clear()
        widgetJobs.forEach { it.cancel() }
        widgetJobs.clear()
        widgetScope?.cancel()
        widgetScope = null
        main.removeCallbacksAndMessages(null)
    }

    private fun add(g: FilterSink, web: BrowserOverlay, l: Layer, fit: Fit, scope: CoroutineScope) {
        val lay = l.layout
        if (lay == null) addObs(g, web, l, fit) else addWidget(g, web, l, lay, scope)
    }

    /** Frame-relative layers: box in output px from [widgetBox], then a native widget or, failing that, the OBS paths. */
    private fun addWidget(g: FilterSink, web: BrowserOverlay, l: Layer, lay: WidgetLayout, scope: CoroutineScope) {
        val ow = outW.toFloat()
        val oh = outH.toFloat()
        val text = TextStyle.from(l.data)
        if (l.type == LayerType.Text && "{" !in text.text) {
            // Rendered at output scale, so the still is pixel-exact; natural size = pixels / scale.
            val s = lay.scale * min(ow, oh) / 1080f
            val bmp = inAppTextBitmap(text, s) ?: return
            val box = widgetBox(lay, bmp.width / s, bmp.height / s, ow, oh)
            g.addLayer(ImageFilterRender().also { it.setImage(bmp) }.placeIn(box, outW, outH))
            return
        }
        val (nw, nh) = OverlayStore.naturalSize(l) ?: return
        val box = widgetBox(lay, nw, nh, ow, oh)
        val built = when (l.type) {
            LayerType.Chat -> chatWidget(l, box, outW, outH, scope)
            LayerType.Alerts -> alertWidget(l, box, outW, outH, scope)
            LayerType.Events -> eventListWidget(l, box, outW, outH, scope)
            LayerType.Qr -> qrWidget(l, box, outW, outH)
            LayerType.Text -> liveTextWidget(l, box, outW, outH, scope)
            LayerType.Image -> gifWidget(l, box, outW, outH)
            else -> null
        }
        if (built != null) {
            g.addLayer(built.filter)
            built.job?.let { widgetJobs += it }
            return
        }
        // Everything else (still images, web, colour, media...) is the OBS path with the box baked into the transform.
        addObs(g, web, l.copy(x = box.x, y = box.y, sx = box.w / nw, sy = box.h / nh, align = 5, boundsType = 0, layout = null), IDENTITY)
    }

    private fun addObs(g: FilterSink, web: BrowserOverlay, l: Layer, fit: Fit) {
        when (l.type) {
            LayerType.Browser -> web.add(l, fit)
            LayerType.Image -> OverlayStore.local(l.data["file"].orEmpty())?.let { addImage(g, l, it, fit) }
            LayerType.Media -> OverlayStore.local(l.data["file"].orEmpty())?.let { addMedia(g, l, it, fit) }
            LayerType.Slideshow -> addSlideshow(g, l, fit)
            LayerType.Text -> addText(g, l, fit)
            LayerType.Color -> {
                val w = l.data["width"]?.toFloatOrNull() ?: 1920f
                val h = l.data["height"]?.toFloatOrNull() ?: 1080f
                g.addLayer(imageFilter(colorBitmap(l.data["color"]?.toLongOrNull()?.toInt() ?: -1), place(l, w, h), fit, l))
            }
            else -> Unit // in-app widget types only arrive through addWidget
        }
    }

    private fun <T : BaseObjectFilterRender> T.put(box: Box, fit: Fit, rotation: Float): T = placeIn(fit.apply(box), outW, outH, rotation)

    private fun imageFilter(bmp: Bitmap, box: Box, fit: Fit, l: Layer) = ImageFilterRender().also {
        it.setImage(bmp)
        it.put(box, fit, l.rotation)
    }

    private fun addImage(g: FilterSink, l: Layer, f: File, fit: Fit) {
        val (w, h) = imageSize(f) ?: return
        val nw = w - l.crop[0] - l.crop[2]
        val box = place(l, nw.toFloat(), (h - l.crop[1] - l.crop[3]).toFloat())
        val d = decode(f, l.crop, fit.apply(box).w) ?: return
        g.addLayer(imageFilter(d.bitmap, box, fit, l))
    }

    private fun addText(g: FilterSink, l: Layer, fit: Fit) {
        val px = (l.data["size"]?.toFloatOrNull() ?: 36f) * fit.scale
        val color = l.data["color"]?.toLongOrNull()?.toInt() ?: -1
        val bmp = textBitmap(l.data["text"].orEmpty(), l.data["face"].orEmpty(), l.data["bold"] == "true", px, color) ?: return
        // The bitmap is already at output scale, so its canvas size is pixels / scale.
        g.addLayer(imageFilter(bmp, place(l, bmp.width / fit.scale, bmp.height / fit.scale), fit, l))
    }

    // ponytail: the media player is muted and a rotated phone video isn't corrected; sizes come from the container metadata.
    private fun addMedia(g: FilterSink, l: Layer, f: File, fit: Fit) {
        val (w, h) = mediaSize(f) ?: return
        val mp = MediaPlayer()
        players += mp
        mp.setDataSource(f.path)
        mp.isLooping = l.data["loop"] == "true"
        mp.setVolume(0f, 0f)
        g.addLayer(
            SurfaceFilterRender { st ->
                runCatching {
                    mp.setSurface(Surface(st))
                    mp.setOnPreparedListener { it.start() }
                    mp.prepareAsync()
                }
            }.put(place(l, w, h), fit, l.rotation)
        )
    }

    private fun addSlideshow(g: FilterSink, l: Layer, fit: Fit) {
        val files = l.files.mapNotNull(OverlayStore::local).take(MAX_SLIDES)
        val (w, h) = files.firstOrNull()?.let(::imageSize) ?: return
        val box = place(l, w.toFloat(), h.toFloat())
        val target = fit.apply(box)
        val slides = files.mapNotNull { decode(it, listOf(0, 0, 0, 0), target.w)?.bitmap }
        if (slides.isEmpty()) return
        val filter = imageFilter(slides[0], box, fit, l)
        g.addLayer(filter)
        if (slides.size == 1) return
        val delay = l.data["time"]?.toLongOrNull()?.coerceAtLeast(1000) ?: 8000L
        var i = 0
        main.postDelayed(
            object : Runnable {
                override fun run() {
                    i = (i + 1) % slides.size
                    filter.setImage(slides[i])
                    main.postDelayed(this, delay)
                }
            },
            delay
        )
    }
}
