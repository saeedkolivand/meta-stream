package com.saeedkolivand.metastream.overlay

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatBurstTest {
    @Test
    fun threeMessagesInOneSecondIsABurst() {
        assertTrue(isBurst(listOf(9_100, 9_500, 10_000), 10_000))
    }

    @Test
    fun twoMessagesOrOldOnesAreNot() {
        assertFalse(isBurst(listOf(9_500, 10_000), 10_000))
        assertFalse(isBurst(listOf(8_000, 9_000, 9_500, 10_000), 10_900 + 200))
    }
}
