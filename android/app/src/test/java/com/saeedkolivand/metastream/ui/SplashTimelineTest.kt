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
    fun easeOutHitsEndpointsAndLeadsLinear() {
        assertEquals(0f, easeOut(0f), 0f)
        assertEquals(1f, easeOut(1f), 0f)
        assertTrue(eased(50f, 0f, 100f) > 0.5f)
    }

    @Test
    fun easeInOutCubicIsSymmetric() {
        assertEquals(0f, easeInOutCubic(0f), 0f)
        assertEquals(0.5f, easeInOutCubic(0.5f), 1e-6f)
        assertEquals(1f, easeInOutCubic(1f), 1e-6f)
        assertTrue(easeInOutCubic(0.25f) < 0.25f)
    }

    @Test
    fun bloomPeaksThenSettles() {
        assertEquals(0f, bloom(100f), 1e-6f)
        assertEquals(0.9f, bloom(350f), 1e-6f)
        assertEquals(0.65f, bloom(600f), 1e-6f)
        assertEquals(0.65f, bloom(1000f), 1e-6f)
    }
}
