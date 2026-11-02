package com.saeedkolivand.metastream.reach

import java.math.BigDecimal
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReachTest {
    @Test
    fun spikesAnonymityAndText() {
        assertFalse(SessionLog.isSpike(40, listOf(5, 5)))
        assertFalse(SessionLog.isSpike(19, listOf(1, 1, 1)))
        assertTrue(SessionLog.isSpike(20, listOf(1, 1, 1)))
        assertFalse(SessionLog.isSpike(29, listOf(10, 10, 10)))
        assertTrue(SessionLog.isSpike(30, listOf(10, 10, 10)))
        assertTrue(SessionLog.isAnonymous(" anonymous ") && SessionLog.isAnonymous("") && !SessionLog.isAnonymous("Bob"))
        val live = LivePostText.live(LivePostText.Live(title = "IRL", slug = "saeed", viewers = 42, elapsedMs = 8_040_000), "en")
        assertTrue("42 watching" in live && "2h 14m" in live && "kick.com/saeed" in live)
        assertTrue(LivePostText.live(LivePostText.Live(), "en").startsWith("🔴 LIVE\n"))
        val rec = LivePostText.Recap(title = "t", slug = "s", donationCount = 2, total = "€30", topName = "Bob", topAmount = "€25")
        assertTrue("€30 from 2 donations" in LivePostText.recap(rec, "en"))
        val donation = Moment(0, Moment.DONATION, "Bob", "€25")
        assertEquals("💸 Big donation from Bob (€25) — come say thanks\n▶️ kick.com/s", LivePostText.ping(donation, "s", "en"))
        assertEquals("🚀 Raid from Al with 40 viewers", LivePostText.ping(Moment(0, Moment.RAID, "Al", "40"), "", "en"))
        assertEquals(1024, LivePostText.fit("x".repeat(5000), true).length)
    }

    @Test
    fun recordRoundTrip() {
        val r = SessionRecord(1000, "t", "EUR", trackingStarted = true)
        r.samples += SessionSample(1, 10, 3, 4000, 0, 0, 2.5, 1)
        r.moments += Moment(5, Moment.RAID, "Al", "40", 40.0)
        r.donationTotal = BigDecimal("12.34")
        r.donors["Bob"] = BigDecimal("5")
        r.chatterCounts["kick|1"] = 3
        val back = SessionRecord.from(JSONObject(r.toJson().toString()))
        assertEquals(10, back.peakViewers)
        assertEquals(BigDecimal("12.34"), back.donationTotal)
        assertEquals("Al", back.moments[0].user)
        assertEquals(3, back.chatterCounts["kick|1"])
        assertEquals(BigDecimal("5"), back.donors["Bob"])
        assertTrue(back.trackingStarted)
    }
}
