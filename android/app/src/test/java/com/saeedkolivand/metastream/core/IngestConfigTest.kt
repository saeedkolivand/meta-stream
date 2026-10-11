package com.saeedkolivand.metastream.core

import org.junit.Assert.assertEquals
import org.junit.Test

class IngestConfigTest {
    @Test fun defaultsMatchIos() {
        val c = IngestConfig()
        assertEquals(720, c.height)
        assertEquals(30, c.fps)
        assertEquals(4000, c.bitrateKbps)
        assertEquals(2000, c.srtLatencyMs)
    }

    @Test fun autoFollowsThePhoneAndSwapsOutputSize() {
        val up = IngestConfig().toVideoParams(devicePortrait = true)
        assertEquals(VideoParams(1280, 720, 90, 4_000_000, 30, true), up)
        assertEquals(720 to 1280, up.outW to up.outH)
        val flat = IngestConfig().toVideoParams(devicePortrait = false)
        assertEquals(0, flat.rotation)
        assertEquals(1280 to 720, flat.outW to flat.outH)
    }

    @Test fun lockOverridesThePhone() {
        assertEquals(true, IngestConfig(lock = Lock.Portrait).toVideoParams(false).portrait)
        assertEquals(false, IngestConfig(lock = Lock.Landscape).toVideoParams(true).portrait)
    }

    @Test fun resolutionFpsBitrateReachThePrepareParameters() {
        val p = IngestConfig(height = 1080, fps = 60, bitrateKbps = 8000).toVideoParams(false)
        assertEquals(1920, p.width)
        assertEquals(1080, p.height)
        assertEquals(60, p.fps)
        assertEquals(8_000_000, p.bitrate)
        assertEquals(854, IngestConfig(height = 480).toVideoParams(false).width)
    }

    @Test fun snapKbpsSnapsAndClamps() {
        assertEquals(4250, snapKbps(4310))
        assertEquals(MIN_KBPS, snapKbps(10))
        assertEquals(MAX_KBPS, snapKbps(99_999))
    }
}
