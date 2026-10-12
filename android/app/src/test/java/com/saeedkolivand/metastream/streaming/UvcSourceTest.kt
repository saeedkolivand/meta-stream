package com.saeedkolivand.metastream.streaming

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UvcSourceTest {
    // What a DJI Osmo Action 6 lists in webcam mode (logged on iPad): 16:9 up to 4K, plus portrait variants.
    private val action6 = listOf(
        Triple(1280, 720, listOf(30, 60)),
        Triple(1920, 1080, listOf(30, 60)),
        Triple(3840, 2160, listOf(30)),
        Triple(1080, 1920, listOf(30))
    )

    @Test fun picksTallestUpToTheStreamHeight() {
        assertEquals(2, pickSize(action6, 2160, 30))
        assertEquals(1, pickSize(action6, 1080, 30))
    }

    @Test fun prefersAFormatOfferingTheWantedFps() {
        // 4K has no 60, so a 4K@60 stream takes 1080p60 rather than dropping frames.
        assertEquals(1, pickSize(action6, 2160, 60))
    }

    @Test fun nothingBelowTheTargetMeansDefault() {
        assertNull(pickSize(action6, 480, 30))
    }
}
