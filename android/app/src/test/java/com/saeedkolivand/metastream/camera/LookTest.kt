package com.saeedkolivand.metastream.camera

import com.saeedkolivand.metastream.streaming.Look
import com.saeedkolivand.metastream.streaming.parseCube
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS Look.demo(), same cases. */
class LookTest {
    private fun fails(text: String) = runCatching { parseCube(text) }.isFailure

    @Test
    fun neutral() {
        assertTrue(Look().neutral)
        assertFalse(Look(warmth = 0.1f).neutral)
        assertFalse(Look(lut = "a.cube").neutral)
    }

    @Test
    fun parsesCubes() {
        val c = parseCube("# c\nTITLE \"t\"\nDOMAIN_MIN 0 0 0\nLUT_3D_SIZE 2\n\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n")
        assertEquals(2, c.size)
        assertEquals(8 * 3, c.rgb.size)
        assertEquals(1f, c.rgb[3], 0f) // second entry is red: red index runs fastest
        assertTrue(fails("LUT_1D_SIZE 4\n0 0 0")) // 1D rejected
        assertTrue(fails("LUT_3D_SIZE 65")) // oversize rejected
        assertTrue(fails("LUT_3D_SIZE 2\n0 0 0")) // short cube rejected
        assertTrue(fails("LUT_3D_SIZE 2\n" + "0 0 0\n".repeat(9))) // too many entries rejected
        assertTrue(fails("0 0 0\n")) // entries before the size
    }
}
