package com.saeedkolivand.metastream.overlay

import org.junit.Assert.assertEquals
import org.junit.Test

class EmoteFramesTest {
    @Test fun frameIndexWrapsOverCumulativeEnds() {
        val ends = longArrayOf(100, 300, 400)
        assertEquals(0, frameIndex(ends, 0))
        assertEquals(1, frameIndex(ends, 100))
        assertEquals(1, frameIndex(ends, 299))
        assertEquals(2, frameIndex(ends, 399))
        assertEquals(0, frameIndex(ends, 400))
        assertEquals(1, frameIndex(ends, 950))
        assertEquals(0, frameIndex(longArrayOf(1), 12345))
    }
}
