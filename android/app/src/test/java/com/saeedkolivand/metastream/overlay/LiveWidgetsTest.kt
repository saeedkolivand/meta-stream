package com.saeedkolivand.metastream.overlay

import org.junit.Assert.assertEquals
import org.junit.Test

class LiveWidgetsTest {
    @Test
    fun weatherEmojiMapsCodes() {
        assertEquals("☀️", weatherEmoji(0))
        assertEquals("🌤️", weatherEmoji(2))
        assertEquals("☁️", weatherEmoji(3))
        assertEquals("🌧️", weatherEmoji(61))
        assertEquals("❄️", weatherEmoji(75))
        assertEquals("🌦️", weatherEmoji(81))
        assertEquals("⛈️", weatherEmoji(95))
        assertEquals("🌡️", weatherEmoji(1000))
    }

    @Test
    fun rotatingLineCyclesEveryInterval() {
        val t = "a\nb\nc"
        assertEquals("a", rotatingLine(t, 5, 0))
        assertEquals("b", rotatingLine(t, 5, 5_000))
        assertEquals("c", rotatingLine(t, 5, 14_999))
        assertEquals("a", rotatingLine(t, 5, 15_000))
    }

    @Test
    fun rotatingLineSkipsBlankLines() {
        assertEquals("b", rotatingLine("a\n\n  \nb", 5, 5_000))
        assertEquals("", rotatingLine("", 5, 5_000))
    }
}
