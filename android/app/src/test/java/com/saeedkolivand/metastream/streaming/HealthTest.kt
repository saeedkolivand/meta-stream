package com.saeedkolivand.metastream.streaming

import android.os.PowerManager
import com.saeedkolivand.metastream.core.LogRing
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthTest {
    @Test fun thermalLabelsMatchIos() {
        assertNull(thermalLabel(PowerManager.THERMAL_STATUS_NONE))
        assertNull(thermalLabel(PowerManager.THERMAL_STATUS_LIGHT))
        assertEquals("warm", thermalLabel(PowerManager.THERMAL_STATUS_MODERATE))
        assertEquals("hot", thermalLabel(PowerManager.THERMAL_STATUS_SEVERE))
        assertEquals("overheating", thermalLabel(PowerManager.THERMAL_STATUS_CRITICAL))
        assertEquals("overheating", thermalLabel(PowerManager.THERMAL_STATUS_SHUTDOWN))
        assertFalse(thermalSerious(PowerManager.THERMAL_STATUS_MODERATE))
        assertTrue(thermalSerious(PowerManager.THERMAL_STATUS_SEVERE))
    }

    @Test fun escalationFiresOncePerThreshold() {
        assertNull(escalation(10, 0))
        assertEquals("stream dropped", escalation(30, 0))
        assertNull(escalation(31, 30))
        assertEquals("stream still down after 2 minutes", escalation(120, 90))
        assertEquals("stream still down after 5 minutes, may need a manual restart", escalation(301, 120))
        assertNull(escalation(400, 301))
    }

    @Test fun logRingDropsOldest() {
        val r = LogRing(3)
        listOf("a", "b", "c", "d").forEach(r::add)
        assertEquals(listOf("b", "c", "d"), r.snapshot())
    }
}
