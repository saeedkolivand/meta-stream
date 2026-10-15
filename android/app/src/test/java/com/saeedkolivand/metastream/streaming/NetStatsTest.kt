package com.saeedkolivand.metastream.streaming

import org.junit.Assert.assertEquals
import org.junit.Test

class NetStatsTest {
    private fun s(sent: Int, target: Int = 3000, congested: Boolean = false, down: Boolean = false) = Sample(sent, target, congested, down)

    @Test fun ringKeepsNewestInOrder() {
        val r = Ring(3)
        (1..5).forEach { r.add(s(it)) }
        assertEquals(listOf(3, 4, 5), r.toList().map { it.sentKbps })
        r.clear()
        assertEquals(emptyList<Sample>(), r.toList())
    }

    @Test fun durationFormats() {
        assertEquals("0:12", duration(12_000))
        assertEquals("12:34", duration(754_000))
        assertEquals("1:02:03", duration(3_723_000))
        assertEquals("0:00", duration(-5))
    }

    @Test fun relativeFormats() {
        assertEquals("just now", relative(2_000))
        assertEquals("42 s ago", relative(42_000))
        assertEquals("3 min ago", relative(190_000))
        assertEquals("2 h ago", relative(7_300_000))
    }

    @Test fun kbpsHasThousandsSeparator() = assertEquals("2,640", kbpsText(2640))

    @Test fun chartMaxRoundsUpToFiveHundred() {
        assertEquals(500, chartMax(0))
        assertEquals(3000, chartMax(3000))
        assertEquals(3500, chartMax(3001))
    }

    @Test fun levelFollowsDownCongestionAndSlowSend() {
        assertEquals(Level.Ok, level(listOf(s(2900))))
        assertEquals(Level.Warn, level(listOf(s(1000))))
        assertEquals(Level.Warn, level(listOf(s(2900, congested = true), s(2900), s(2900))))
        assertEquals(Level.Ok, level(listOf(s(2900, congested = true)) + List(5) { s(2900) }))
        assertEquals(Level.Bad, level(listOf(s(0, down = true))))
        assertEquals(Level.Ok, level(listOf(s(500, target = 0))))
    }

    @Test fun pathLabels() {
        assertEquals("Wi-Fi (phone hotspot)", pathLabel(true, false, false, true))
        assertEquals("Wi-Fi", pathLabel(true, false, false, false))
        assertEquals("Cellular", pathLabel(false, true, false, true))
        assertEquals("Ethernet", pathLabel(false, false, true, false))
        assertEquals("No network", pathLabel(false, false, false, false))
    }

    @Test fun controllerReportsWhy() {
        val c = BitrateController(4000)
        c.tick(10_000, true, 4000)
        assertEquals("network backed up", c.why.text)
        c.tick(20_000, false, 1000)
        assertEquals("upload slower than target", c.why.text)
        c.thermal(30_000, true)
        assertEquals("phone hot", c.why.text)
        assertEquals("15 s stable, raising", Why.Stable.text)
    }
}
