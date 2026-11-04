package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.overlay.widgets.text.InlineIcons
import com.saeedkolivand.metastream.overlay.widgets.text.rotatingLine
import org.junit.Assert.assertEquals
import org.junit.Test

class LiveWidgetsTest {
    @Test
    fun weatherIconsAndEmojiMigration() {
        assertEquals("sun.max.fill", weatherSymbol(0))
        assertEquals("cloud.sun.fill", weatherSymbol(2))
        assertEquals("cloud.rain.fill", weatherSymbol(61))
        assertEquals("thermometer.medium", weatherSymbol(1000))
        assertEquals("partly cloudy", weatherWords(1))
        // emoji become icon tokens once; running it again changes nothing
        assertEquals("{i:clock} {time}  {i:heart.fill} {i:record.circle}", InlineIcons.iconized("🕒 {time}  ❤️ 🔴"))
        assertEquals("{i:clock}", InlineIcons.iconized("{i:clock}"))
        assertEquals("17°", InlineIcons.strip("{i:sun.max.fill} 17°"))
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
