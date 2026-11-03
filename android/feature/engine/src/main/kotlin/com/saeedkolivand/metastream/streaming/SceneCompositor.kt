package com.saeedkolivand.metastream.streaming

import com.pedro.library.view.GlInterface

/**
 * What the engine needs from the scene layer (iOS SceneCompositor). The overlays implement it and the app wiring sets
 * [compositor], so the engine never depends on the overlays.
 */
interface SceneCompositor {
    fun bind(gl: GlInterface, w: Int, h: Int)

    fun unbind()

    /** Rebuilds the GL filter chain (the GL thread drops every filter when it stops). */
    fun refresh()

    fun syncFaceCam()

    fun syncLook()

    /** The first connect of a session: a Starting role scene goes up. */
    fun sessionStarted()

    /** Live ended: a Starting, BRB or Ending role scene goes back to the scene before it. */
    fun sessionEnded()

    /** Health tick: BRB scene in or out by the uplink state. */
    fun checkBrb(down: Boolean, queueBytes: Long, kbps: Int)
}

/** Set once by the app wiring; null in unit tests. */
var compositor: SceneCompositor? = null
