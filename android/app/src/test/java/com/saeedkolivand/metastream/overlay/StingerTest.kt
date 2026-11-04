package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.overlay.widgets.nowplaying.copy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StingerTest {
    @Test
    fun curvesFollowCssKeyframes() {
        assertEquals(0.5, Curve.linear.track(0.5, 0.0 to 0.0, 1.0 to 1.0), 1e-6)
        assertEquals(5.0, Curve.easeInOut.track(0.0, 0.2 to 5.0, 0.4 to 9.0), 0.0) // holds before the first stop
        assertEquals(9.0, Curve.easeInOut.track(0.9, 0.2 to 5.0, 0.4 to 9.0), 0.0) // and after the last
        assertEquals(0.5, Curve.easeInOut(0.5), 1e-3) // symmetric curve crosses the middle
    }

    @Test
    fun timingMatchesTheBoards() {
        val s = StingerStyle()
        assertEquals((0.65 - 0.245) * 6, StingerKind.Lens.seconds(s), 1e-9)
        assertEquals(StingerKind.Lens.seconds(s) / 2, StingerKind.Lens.seconds(s.copy(speed = 2f)), 1e-9)
        assertEquals(StingerKind.Lens.cut, StingerKind.Lens.q(StingerKind.Lens.cutSeconds(s), s), 1e-9)
        assertEquals(StingerKind.Burn, StingerKind.of("burn"))
    }

    @Test
    fun lensClosesOnItsLensAtTheCutAndIsOffOutside() {
        val f = StingerFrame()
        StingerKind.Lens.frame(StingerKind.Lens.cut, StingerStyle(), 1920f, 1080f, f)
        assertTrue(f.on)
        assertEquals(215f, f.p[0], 0.01f) // the hole sits on the 215 px lens
        assertEquals(1f, f.p[19], 0f) // unit at 1080p
        StingerKind.Lens.frame(0.7, StingerStyle(), 1920f, 1080f, f)
        assertFalse(f.on)
    }

    @Test
    fun everyKindCoversTheFrameAtItsCut() {
        val f = StingerFrame()
        for (k in StingerKind.entries) {
            k.frame(k.cut, StingerStyle(name = "x"), 1280f, 720f, f)
            assertTrue(k.name, f.on)
        }
    }

    @Test
    fun colours() {
        assertEquals(0xFFFFFFFF.toInt(), mixWhite(0xFF000000.toInt(), 1.0))
        assertEquals(0xFFF2F1EC.toInt(), fgOn(0xFF0B0B0C.toInt())) // light text on the dark panel
        assertEquals(0xFF0B0B0C.toInt(), fgOn(0xFFFFFFFF.toInt()))
    }
}
