package com.saeedkolivand.metastream.streaming

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LiveNoticeTest {
    @Test fun connectedCountsUpFromLiveSince() {
        val n = liveNotice(Source.Phone, "connected · 4.0 Mb/s", true, 1000L, false)
        assertEquals("LIVE · Phone", n.title)
        assertEquals("4.0 Mb/s", n.text)
        assertEquals(1000L, n.chronometerSince)
        assertNull(n.chip)
        assertEquals("Mute", n.muteLabel)
    }

    @Test fun reconnectingShowsRetryChipAndNoChronometer() {
        val n = liveNotice(Source.Usb, "retrying: timeout", false, 1000L, true)
        assertEquals("RECONNECTING · Usb", n.title)
        assertEquals("retrying: timeout", n.text)
        assertEquals("RETRY", n.chip)
        assertNull(n.chronometerSince)
        assertEquals("Unmute", n.muteLabel)
    }

    @Test fun firstConnectIsConnectingNotRetry() {
        val n = liveNotice(Source.Phone, "connecting", false, null, false)
        assertEquals("CONNECTING · Phone", n.title)
        assertNull(n.chip)
        assertNull(n.chronometerSince)
    }
}
