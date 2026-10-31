package com.saeedkolivand.metastream.overlay

import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.BaseObjectFilterRender
import com.pedro.library.view.GlInterface
import com.saeedkolivand.metastream.privacy.Privacy

/**
 * The overlay layers' view of the GL filter chain. It remembers what it added so a rebuild removes only those filters:
 * clearFilters() would also drop the privacy blur, and RootEncoder applies one filter op per frame, so frames would go out unblurred.
 */
class FilterSink(private val gl: GlInterface) {
    private val mine = mutableListOf<BaseFilterRender>()
    private val fading = mutableListOf<BaseFilterRender>()

    /** Scene-wide opacity for the scene transition; kept so filters built mid-fade start at the same level. */
    var alpha = 1f
        private set

    /** On top of everything the scene draws (the stinger); layers added while it's up go in just below it. */
    private var tail: BaseFilterRender? = null

    // Chain order is face-cam, privacy blur, layers, tail. Ops apply in order, one a frame, so counting what's queued ahead
    // gives the slot right under the tail. ponytail: a blur toggle mid-stinger can shift that slot by one for that one scene.
    fun addFilter(f: BaseFilterRender) {
        val below = (if (Privacy.inChain) 1 else 0) + mine.size
        mine += f
        if (tail == null) gl.addFilter(f) else gl.addFilter(below, f)
    }

    /** Puts [f] above the scene until the next call (null takes it away). A refresh's [clear] leaves it in place. */
    fun setTail(f: BaseFilterRender?) {
        tail?.let(gl::removeFilter)
        tail = f
        f?.let(gl::addFilter)
    }

    /** A scene layer: like [addFilter], but it follows [setAlpha] (the face-cam and privacy blur must not fade). */
    fun addLayer(f: BaseFilterRender) {
        fading += f
        fade(f, alpha)
        addFilter(f)
    }

    // ponytail: overwrites a widget's own alpha (alert fade) for the ~360 ms of a scene switch; blending needs a second multiplier.
    fun setAlpha(a: Float) {
        alpha = a
        fading.forEach { fade(it, a) }
    }

    private fun fade(f: BaseFilterRender, a: Float) {
        when (f) {
            is BaseObjectFilterRender -> f.alpha = a
            is SpriteFilter -> f.setAlpha(a)
        }
    }

    /** Ahead of everything already in the chain (the privacy blur included). */
    fun addFirst(f: BaseFilterRender) {
        gl.addFilter(0, f)
        mine += f
    }

    fun clear() {
        mine.forEach(gl::removeFilter)
        mine.clear()
        fading.clear()
    }

    /** Removes just [f] (a refresh usually clears everything; targeted syncs touch one filter). */
    fun remove(f: BaseFilterRender) {
        if (mine.remove(f)) gl.removeFilter(f)
        fading.removeAll { it === f }
    }
}
