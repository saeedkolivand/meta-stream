package com.saeedkolivand.metastream.streaming

import com.saeedkolivand.metastream.streaming.uplink.Bonding
import com.saeedkolivand.metastream.streaming.uplink.SrtlaWire
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS Srtla.demo(), same cases. */
class SrtlaWireTest {
    private fun b(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }

    @Test
    fun parsesPackets() {
        assertEquals(SrtlaWire.REG2, SrtlaWire.kind(b(0x92, 0x01), 2))
        assertEquals(0, SrtlaWire.kind(b(0x90), 1))
        assertEquals(258, SrtlaWire.seq(b(0, 0, 1, 2, 0, 0), 6))
        assertNull(SrtlaWire.seq(b(0x80, 2, 0, 0), 4)) // control packet
        assertNull(SrtlaWire.seq(b(0), 1))
        assertEquals(256L, SrtlaWire.be32(b(0, 0, 0, 0, 0, 0, 1, 0), 4))
        assertEquals(0xFFFFFFFFL, SrtlaWire.be32(b(0xFF, 0xFF, 0xFF, 0xFF), 0))
    }

    @Test
    fun picksMainLinksFirst() {
        val wifi = SrtlaWire.Cand(up = true, window = 20_000, inFlight = 3, backup = false)
        val cell = SrtlaWire.Cand(up = true, window = 20_000, inFlight = 0, backup = true)
        assertEquals(0, SrtlaWire.pick(listOf(wifi, cell), cut = false)) // main wins even with a better-scoring backup
        assertEquals(1, SrtlaWire.pick(listOf(wifi, cell), cut = true)) // bitrate cut: backup helps
        val full = SrtlaWire.Cand(up = true, window = 20_000, inFlight = 20, backup = false)
        assertEquals(1, SrtlaWire.pick(listOf(full, cell), cut = false)) // main window full
        val down = SrtlaWire.Cand(up = false, window = 20_000, inFlight = 3, backup = false)
        assertEquals(1, SrtlaWire.pick(listOf(down, cell), cut = false)) // no main up
        assertNull(SrtlaWire.pick(listOf(down), cut = false))
    }

    @Test
    fun bondingRewritesOnlySchemeHostAndPort() {
        // target() starts a proxy, so only the pass-through branch is checked here.
        assertEquals("srt://h:1?streamid=#!::r=live/x", Bonding.target(android.app.Application(), "srt://h:1?streamid=#!::r=live/x"))
    }
}
