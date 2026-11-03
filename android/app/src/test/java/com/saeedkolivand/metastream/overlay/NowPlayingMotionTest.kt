package com.saeedkolivand.metastream.overlay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS NowPlayingMotion.demo(), ported. */
class NowPlayingMotionTest {
    private val designs = listOf("slab", "island", "disc", "ticker", "text", "twoLine", "cover", "popup")

    @Test
    fun everyDesignStartsSwitchesAndSettles() {
        for (d in designs) {
            val sw = NowPlayingMotion.timing(d).first
            val start = NowPlayingMotion.change(d, 0.0)
            assertFalse(d, start.useNew)
            assertEquals("$d change start", NpPose(), start.copy(useNew = true))
            assertFalse("$d switch", NowPlayingMotion.change(d, sw - 0.001).useNew)
            assertTrue("$d switch", NowPlayingMotion.change(d, sw).useNew)
            assertEquals("$d change end", NpPose(), NowPlayingMotion.change(d, NowPlayingMotion.total(d) + 0.001))
            assertEquals("$d change end", NpPose(), NowPlayingMotion.change(d, NowPlayingMotion.total(d) + 5))
            assertNotEquals("$d enter", NpPose(), NowPlayingMotion.enter(d, 0.0))
            assertEquals("$d enter", NpPose(), NowPlayingMotion.enter(d, NowPlayingMotion.enterTotal(d) + 0.001))
            assertEquals("$d exit", NpPose(), NowPlayingMotion.exit(d, 0.0))
            assertEquals("$d exit", 0f, NowPlayingMotion.exit(d, NowPlayingMotion.exitTotal(d)).alpha)
        }
        assertEquals(0f, NowPlayingMotion.exit("popup", NowPlayingMotion.exitTotal("popup")).reveal)
    }

    @Test
    fun curvesAndDecorations() {
        assertEquals(0.0, Cubic.standard.at(0.0), 0.0)
        assertEquals(1.0, Cubic.standard.at(1.0), 0.0)
        assertTrue(Cubic.spring.at(0.5) > 1)
        assertEquals(0.5, Cubic.easeInOut.at(0.5), 0.001)
        assertEquals(0.35f, NowPlayingMotion.eq(0.0, 0.9, 0.0, 0.35f), 0f)
        assertEquals(1f, NowPlayingMotion.eq(0.45, 0.9, 0.0, 0.35f), 0.001f)
        assertEquals(180f, NowPlayingMotion.spin(2.5), 0.001f)
    }
}
