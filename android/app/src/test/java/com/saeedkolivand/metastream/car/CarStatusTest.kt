package com.saeedkolivand.metastream.car

import com.saeedkolivand.metastream.streaming.Source
import org.junit.Assert.assertEquals
import org.junit.Test

class CarStatusTest {
    @Test fun liveShowsBitrateAndSource() = assertEquals(
        "LIVE · 4.0 Mb/s · Glasses",
        carStatusText(true, "connected · 4.0 Mb/s", Source.Glasses)
    )

    @Test fun liveWithoutBitrateShowsWholeStatus() = assertEquals(
        "LIVE · connecting · Phone",
        carStatusText(true, "connecting", Source.Phone)
    )

    @Test fun idleIsOffline() = assertEquals("Offline", carStatusText(false, "idle", Source.Phone))

    @Test fun offlineShowsReason() = assertEquals(
        "Offline · no USB camera attached",
        carStatusText(false, "no USB camera attached", Source.Usb)
    )
}
