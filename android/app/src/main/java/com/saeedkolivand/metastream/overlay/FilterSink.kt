package com.saeedkolivand.metastream.overlay

import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.library.view.GlInterface

/**
 * The overlay layers' view of the GL filter chain. It remembers what it added so a rebuild removes only those filters:
 * clearFilters() would also drop the privacy blur, and RootEncoder applies one filter op per frame, so frames would go out unblurred.
 */
class FilterSink(private val gl: GlInterface) {
    private val mine = mutableListOf<BaseFilterRender>()

    fun addFilter(f: BaseFilterRender) {
        mine += f
        gl.addFilter(f)
    }

    /** Ahead of everything already in the chain (the privacy blur included). */
    fun addFirst(f: BaseFilterRender) {
        gl.addFilter(0, f)
        mine += f
    }

    fun clear() {
        mine.forEach(gl::removeFilter)
        mine.clear()
    }

    /** Removes just [f] (a refresh usually clears everything; targeted syncs touch one filter). */
    fun remove(f: BaseFilterRender) {
        if (mine.remove(f)) gl.removeFilter(f)
    }
}
