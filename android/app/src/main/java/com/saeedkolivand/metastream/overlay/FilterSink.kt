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

    fun clear() {
        mine.forEach(gl::removeFilter)
        mine.clear()
    }
}
