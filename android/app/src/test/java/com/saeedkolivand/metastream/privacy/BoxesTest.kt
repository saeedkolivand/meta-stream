package com.saeedkolivand.metastream.privacy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BoxesTest {
    private fun assertBox(e: Box, a: Box) {
        assertEquals(e.l, a.l, 1e-4f)
        assertEquals(e.t, a.t, 1e-4f)
        assertEquals(e.r, a.r, 1e-4f)
        assertEquals(e.b, a.b, 1e-4f)
    }

    @Test fun padGrowsByItsOwnSizeAndClamps() {
        assertBox(Box(0.35f, 0.35f, 0.65f, 0.65f), Box(0.4f, 0.4f, 0.6f, 0.6f).pad(0.25f))
        assertBox(Box(0f, 0f, 0.3f, 0.3f), Box(0f, 0f, 0.2f, 0.2f).pad(0.5f))
    }

    @Test fun uprightMappingUndoesBitmapRotation() {
        // A box in the top-left of the upright image.
        val up = Box(0f, 0f, 0.2f, 0.1f)
        assertBox(up, uprightToImage(up, 0))
        // Bitmap was rotated 90 clockwise to be upright, so upright top-left was the bitmap's bottom-left.
        assertBox(Box(0f, 0.8f, 0.1f, 1f), uprightToImage(up, 90))
        assertBox(Box(0.8f, 0.9f, 1f, 1f), uprightToImage(up, 180))
        assertBox(Box(0.9f, 0f, 1f, 0.2f), uprightToImage(up, 270))
    }

    @Test fun rotationRoundTrips() {
        val b = Box(0.1f, 0.3f, 0.4f, 0.5f)

        // Rotating the box clockwise by r and undoing it must give the box back.
        fun cw(x: Box) = Box(1 - x.b, x.l, 1 - x.t, x.r)
        assertBox(b, uprightToImage(cw(b), 90))
        assertBox(b, uprightToImage(cw(cw(b)), 180))
        assertBox(b, uprightToImage(cw(cw(cw(b))), 270))
        assertBox(uprightToImage(b, 90), uprightToImage(b, 450))
    }

    @Test fun glSpaceFlipsOnlyY() {
        assertBox(Box(0.1f, 0.6f, 0.3f, 0.9f), toGl(Box(0.1f, 0.1f, 0.3f, 0.4f)))
    }

    @Test fun capMergesTheOverflowInsteadOfDroppingIt() {
        val small = List(5) { Box(it * 0.1f, 0f, it * 0.1f + 0.01f, 0.01f) }
        val capped = cap(small + Box(0.5f, 0.5f, 0.9f, 0.9f), 3)
        assertEquals(3, capped.size)
        // every original box is still covered by some capped box
        for (s in small) assertTrue(capped.any { it.l <= s.l && it.t <= s.t && it.r >= s.r && it.b >= s.b })
    }

    @Test fun trackerHoldsThenExpires() {
        val t = BoxTracker(holdMs = 600)
        val face = Box(0.4f, 0.4f, 0.6f, 0.6f)
        t.update(listOf(face), 1000)
        assertEquals(listOf(face), t.active(1500))
        assertTrue(t.active(1601).isEmpty())
    }

    @Test fun movedBoxReplacesTheOldOneButADifferentOneStays() {
        val t = BoxTracker(holdMs = 600)
        t.update(listOf(Box(0.4f, 0.4f, 0.6f, 0.6f), Box(0.1f, 0.1f, 0.2f, 0.2f)), 0)
        t.update(listOf(Box(0.42f, 0.4f, 0.62f, 0.6f)), 100)
        val now = t.active(150)
        assertEquals(2, now.size)
        assertTrue(now.contains(Box(0.1f, 0.1f, 0.2f, 0.2f)))
        assertFalse(now.contains(Box(0.4f, 0.4f, 0.6f, 0.6f)))
    }

    @Test fun trackerNeverExceedsItsLimit() {
        val t = BoxTracker(holdMs = 600, maxBoxes = 4)
        t.update(List(10) { Box(it * 0.09f, 0f, it * 0.09f + 0.05f, 0.05f) }, 0)
        assertEquals(4, t.active(10).size)
    }

    @Test fun stallComesAfterThreeSecondsWithoutAResult() {
        assertFalse(Stall.stalled(now = 4000, lastOk = 2000, armedAt = 0))
        assertTrue(Stall.stalled(now = 5001, lastOk = 2000, armedAt = 0))
    }

    @Test fun neverAnsweringDetectorStallsFromArming() {
        assertFalse(Stall.stalled(now = 3000, lastOk = 0, armedAt = 100))
        assertTrue(Stall.stalled(now = 3101, lastOk = 0, armedAt = 100))
    }

    @Test fun wholeFrameIsHiddenUntilTheFirstResultAndOnceStalled() {
        assertTrue(Stall.blurAll(now = 500, lastOk = 0, armedAt = 100)) // nothing trusted yet
        assertFalse(Stall.blurAll(now = 500, lastOk = 400, armedAt = 100))
        assertTrue(Stall.blurAll(now = 4000, lastOk = 400, armedAt = 100))
    }
}
