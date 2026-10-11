package com.saeedkolivand.metastream.overlay

import android.app.Application
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
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

private const val MAX_SLIDES = 30

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
        for (l in scene.layers.filter { it.visible }) {
            // Only the layer type reaches the log; exception messages could carry a URL.
            runCatching { add(g, web, l, fit) }.onFailure { applog("overlay", "${l.type} layer failed: ${it.javaClass.simpleName}") }
        }
        // ponytail: browser sources share one view drawn above the image/text/media layers, whatever their OBS order.
        // Upgrade path: one view per run of consecutive browser layers.
        if (!web.isEmpty) g.addFilter(web.filter())
    }

    private fun release() {
        sink?.clear()
        browser?.destroy()
        browser = null
        players.forEach { it.release() }
        players.clear()
        main.removeCallbacksAndMessages(null)
    }

    private fun add(g: FilterSink, web: BrowserOverlay, l: Layer, fit: Fit) {
        when (l.type) {
            LayerType.Browser -> web.add(l, fit)
            LayerType.Image -> OverlayStore.local(l.data["file"].orEmpty())?.let { addImage(g, l, it, fit) }
            LayerType.Media -> OverlayStore.local(l.data["file"].orEmpty())?.let { addMedia(g, l, it, fit) }
            LayerType.Slideshow -> addSlideshow(g, l, fit)
            LayerType.Text -> addText(g, l, fit)
            LayerType.Color -> {
                val w = l.data["width"]?.toFloatOrNull() ?: 1920f
                val h = l.data["height"]?.toFloatOrNull() ?: 1080f
                g.addFilter(imageFilter(colorBitmap(l.data["color"]?.toLongOrNull()?.toInt() ?: -1), place(l, w, h), fit, l))
            }
        }
    }

    /** RootEncoder object filters take position and size as percent of the output, top-left based. */
    private fun <T : BaseObjectFilterRender> T.put(box: Box, fit: Fit, rotation: Float): T {
        val b = fit.apply(box)
        setScale(b.w / outW * 100, b.h / outH * 100)
        setPosition(b.x / outW * 100, b.y / outH * 100)
        // OBS rotates clockwise, the GL sprite counter-clockwise.
        if (rotation != 0f) this.rotation = ((360 - rotation) % 360).toInt()
        return this
    }

    private fun imageFilter(bmp: Bitmap, box: Box, fit: Fit, l: Layer) = ImageFilterRender().also {
        it.setImage(bmp)
        it.put(box, fit, l.rotation)
    }

    private fun addImage(g: FilterSink, l: Layer, f: File, fit: Fit) {
        val (w, h) = imageSize(f) ?: return
        val nw = w - l.crop[0] - l.crop[2]
        val box = place(l, nw.toFloat(), (h - l.crop[1] - l.crop[3]).toFloat())
        val d = decode(f, l.crop, fit.apply(box).w) ?: return
        g.addFilter(imageFilter(d.bitmap, box, fit, l))
    }

    private fun addText(g: FilterSink, l: Layer, fit: Fit) {
        val px = (l.data["size"]?.toFloatOrNull() ?: 36f) * fit.scale
        val color = l.data["color"]?.toLongOrNull()?.toInt() ?: -1
        val bmp = textBitmap(l.data["text"].orEmpty(), l.data["face"].orEmpty(), l.data["bold"] == "true", px, color) ?: return
        // The bitmap is already at output scale, so its canvas size is pixels / scale.
        g.addFilter(imageFilter(bmp, place(l, bmp.width / fit.scale, bmp.height / fit.scale), fit, l))
    }

    // ponytail: the media player is muted and a rotated phone video isn't corrected; sizes come from the container metadata.
    private fun addMedia(g: FilterSink, l: Layer, f: File, fit: Fit) {
        val mmr = MediaMetadataRetriever()
        val (w, h) = try {
            mmr.setDataSource(f.path)
            val w = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toFloatOrNull()
            val h = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toFloatOrNull()
            if (w == null || h == null) return
            w to h
        } finally {
            mmr.release()
        }
        val mp = MediaPlayer()
        players += mp
        mp.setDataSource(f.path)
        mp.isLooping = l.data["loop"] == "true"
        mp.setVolume(0f, 0f)
        g.addFilter(
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
        g.addFilter(filter)
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
