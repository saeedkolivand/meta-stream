package com.saeedkolivand.metastream.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SplashTimelineTest {
    @Test
    fun segmentClampsOutsideRange() {
        assertEquals(0f, segment(100f, 350f, 300f), 0f)
        assertEquals(0.5f, segment(500f, 350f, 300f), 1e-6f)
        assertEquals(1f, segment(900f, 350f, 300f), 0f)
    }

    @Test
    fun easedHitsEndpointsAndLeadsLinear() {
        assertEquals(0f, eased(0f, 0f, 100f), 0f)
        assertEquals(1f, eased(100f, 0f, 100f), 0f)
        assertTrue(eased(50f, 0f, 100f) > 0.5f)
        assertTrue(eased(50f, 0f, 100f, ::easeIn) < 0.5f)
    }

    @Test
    fun popOvershootsThenSettles() {
        assertEquals(0f, pop(0f), 1e-6f)
        assertEquals(1f, pop(1f), 1e-6f)
        assertTrue((1..99).maxOf { pop(it / 100f) } > 1.1f)
    }

    @Test
    fun beatReturnsToOne() {
        assertEquals(1f, beat(0f, 0f, 250f), 1e-6f)
        assertEquals(1.12f, beat(125f, 0f, 250f), 1e-5f)
        assertEquals(1f, beat(300f, 0f, 250f), 1e-5f)
    }
}
