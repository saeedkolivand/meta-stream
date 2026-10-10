package com.saeedkolivand.metastream.glasses

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private fun b(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }

// NAL header byte for a given type: (type << 1), second byte 1.
private fun nal(type: Int) = b(type shl 1, 1, 0xAA)

class HevcTest {
    @Test fun splitsThreeByteStartCodes() {
        val d = b(0, 0, 1, 0x40, 1, 9) + b(0, 0, 1, 0x42, 1, 8)
        val n = nalUnits(d)
        assertEquals(2, n.size)
        assertArrayEquals(b(0x40, 1, 9), n[0])
        assertArrayEquals(b(0x42, 1, 8), n[1])
    }

    @Test fun fourByteStartCodeDropsLeadingZero() {
        val n = nalUnits(b(0, 0, 0, 1, 0x40, 1, 9) + b(0, 0, 0, 1, 0x42, 1, 8))
        assertArrayEquals(b(0x40, 1, 9), n[0])
        assertArrayEquals(b(0x42, 1, 8), n[1])
    }

    @Test fun skipsEmptyNals() {
        val n = nalUnits(b(0, 0, 1, 0, 0, 1, 0x40, 1))
        assertEquals(1, n.size)
        assertArrayEquals(b(0x40, 1), n[0])
    }

    @Test fun noStartCodeMeansNoNals() = assertTrue(nalUnits(b(1, 2, 3)).isEmpty())

    @Test fun keyframeDetection() {
        assertTrue(isKeyframe(listOf(nal(19)))) // IDR
        assertTrue(isKeyframe(listOf(nal(1), nal(21)))) // CRA
        assertFalse(isKeyframe(listOf(nal(1), nal(32))))
        assertFalse(isKeyframe(emptyList()))
    }

    @Test fun paramSetsCollectAndPrime() {
        val p = ParamSets()
        assertFalse(p.complete())
        assertNull(p.annexB())
        p.offer(listOf(nal(32), nal(33), nal(1)))
        assertFalse(p.complete())
        p.offer(listOf(nal(34)))
        assertTrue(p.complete())
        val sc = b(0, 0, 0, 1)
        assertArrayEquals(sc + nal(32) + sc + nal(33) + sc + nal(34), p.annexB())
        p.reset()
        assertFalse(p.complete())
    }
}
