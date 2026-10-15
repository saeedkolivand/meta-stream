package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.Kind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertTimingTest {
    private fun ev(kind: Kind, cents: Int = 0, count: Int = 0) =
        ChatEvent("twitch", "u", "", kind = kind, amountCents = cents, count = count)

    @Test
    fun formatsAmounts() {
        assertEquals("\$25", alertAmount(ev(Kind.Tip, 2500)))
        assertEquals("\$12.50", alertAmount(ev(Kind.Tip, 1250)))
        assertEquals("120 viewers", alertAmount(ev(Kind.Raid, count = 120)))
        assertEquals("300 bits", alertAmount(ev(Kind.Cheer, count = 300)))
        assertEquals("", alertAmount(ev(Kind.Follow)))
    }

    @Test
    fun bigTier() {
        assertTrue(alertIsBig(ev(Kind.Tip, 1000)))
        assertTrue(alertIsBig(ev(Kind.Raid, count = 50)))
        assertFalse(alertIsBig(ev(Kind.Tip, 999)))
        assertFalse(alertIsBig(ev(Kind.Cheer, count = 5000)))
    }

    @Test
    fun opensBetweenDotAndFull() {
        assertEquals(0f, alertFrame(0f, 5f).open, 0.001f)
        assertEquals(1f, alertFrame(ALERT_OPENED, 5f).open, 0.001f)
        assertEquals(0f, alertFrame(0f, 5f).drop, 0.001f)
        assertEquals(1f, alertFrame(0.28f, 5f).drop, 0.001f)
    }

    @Test
    fun countUpEndsAtFinalAndFlashFades() {
        val e = ev(Kind.Tip, 2500)
        assertEquals(alertAmount(e), alertAmount(e, alertFrame(2f, 5f).amount))
        assertEquals("\$0", alertAmount(e, alertFrame(0f, 5f).amount))
        assertEquals(0.9f, alertFrame(ALERT_OPENED, 5f).flash, 0.001f)
        assertEquals(0f, alertFrame(2f, 5f).flash, 0.001f)
    }

    @Test
    fun exitFinishesAfterHalfSecond() {
        val exit = alertExitAt(5f)
        assertFalse(alertFrame(exit + 0.4f, 5f).done)
        assertEquals(0f, alertFrame(exit + 0.3f, 5f).contentAlpha, 0.001f)
        assertTrue(alertFrame(exit + 0.5f, 5f).done)
    }
}
