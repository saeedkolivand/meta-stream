package com.saeedkolivand.metastream.streaming

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BitrateControllerTest {
    @Test fun stepsDownTwentyPercentAndFloors() {
        assertEquals(3200, steppedBitrate(4000, false, 4000, 500))
        assertEquals(500, steppedBitrate(550, false, 4000, 500))
    }

    @Test fun stepsUpTenPercentAndCeilings() {
        assertEquals(4400, steppedBitrate(4000, true, 8000, 500))
        assertEquals(4100, steppedBitrate(4000, true, 4100, 500))
        assertEquals(4000, steppedBitrate(4000, true, 4000, 500))
    }

    @Test fun congestionStepsDownThenCooldownBlocksNext() {
        val c = BitrateController(4000)
        assertEquals(3200, c.tick(10_000, true, 4000))
        assertNull(c.tick(11_000, true, 4000))
        assertEquals(2560, c.tick(13_000, true, 4000))
    }

    @Test fun lowThroughputStepsDownButZeroSampleDoesNot() {
        val c = BitrateController(4000)
        assertNull(c.tick(0, false, 0))
        assertEquals(3200, c.tick(5_000, false, 2000))
    }

    @Test fun fifteenCleanTicksStepUpToCeilingOnly() {
        val c = BitrateController(4000)
        c.tick(0, true, 4000) // 3200
        var out: Int? = null
        for (i in 1..15) out = c.tick(10_000L + i * 1000, false, 3200)
        assertEquals(3520, out)
        repeat(15 * 10) { i -> c.tick(100_000L + i * 1000, false, c.currentKbps.toLong()) }
        assertEquals(4000, c.currentKbps)
    }

    @Test fun thermalStepsDownOnceAndCapsUntilCleared() {
        val c = BitrateController(4000)
        assertEquals(3200, c.thermal(0, true))
        assertNull(c.thermal(10_000, true))
        repeat(15 * 5) { i -> c.tick(20_000L + i * 1000, false, c.currentKbps.toLong()) }
        assertEquals(3200, c.currentKbps) // held under the thermal ceiling
        c.thermal(200_000, false)
        repeat(15) { i -> c.tick(300_000L + i * 1000, false, c.currentKbps.toLong()) }
        assertEquals(3520, c.currentKbps)
    }
}
