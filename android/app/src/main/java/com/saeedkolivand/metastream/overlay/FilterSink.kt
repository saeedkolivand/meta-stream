package com.saeedkolivand.metastream.overlay

import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.BaseObjectFilterRender
import com.pedro.library.view.GlInterface

/**
 * The overlay layers' view of the GL filter chain. It remembers what it added so a rebuild removes only those filters:
 * clearFilters() would also drop the privacy blur, and RootEncoder applies one filter op per frame, so frames would go out unblurred.
 */
class FilterSink(private val gl: GlInterface) {
    private val mine = mutableListOf<BaseFilterRender>()
    private val fading = mutableListOf<BaseObjectFilterRender>()

    /** Scene-wide opacity for the scene transition; kept so filters built mid-fade start at the same level. */
    var alpha = 1f
        private set

    fun addFilter(f: BaseFilterRender) {
        mine += f
        gl.addFilter(f)
    }

    /** A scene layer: like [addFilter], but it follows [setAlpha] (the face-cam and privacy blur must not fade). */
    fun addLayer(f: BaseObjectFilterRender) {
        fading += f
        f.alpha = alpha
        addFilter(f)
    }

    // ponytail: overwrites a widget's own alpha (alert fade) for the ~360 ms of a scene switch; blending needs a second multiplier.
    fun setAlpha(a: Float) {
        alpha = a
        fading.forEach { it.alpha = a }
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
