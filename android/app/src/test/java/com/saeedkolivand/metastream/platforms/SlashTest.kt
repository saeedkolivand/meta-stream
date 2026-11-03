package com.saeedkolivand.metastream.platforms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS SlashCommand.demo(), same cases. */
class SlashTest {
    @Test
    fun parses() {
        assertEquals("ban" to listOf("bob", "spam"), Slash.parse("/ban bob spam"))
        assertEquals("clear" to emptyList<String>(), Slash.parse("/CLEAR"))
        assertNull(Slash.parse("hello"))
        assertNull(Slash.parse("/"))
        assertNull(Slash.parse("/  "))
    }

    @Test
    fun durations() {
        assertEquals(600, Slash.seconds("600"))
        assertEquals(600, Slash.seconds("10m"))
        assertEquals(3600, Slash.seconds("1h"))
        assertEquals(86400, Slash.seconds("1d"))
        assertNull(Slash.seconds("spam"))
        assertNull(Slash.seconds("0"))
        assertNull(Slash.seconds("m"))
        assertEquals("10 min", Slash.pretty(600))
        assertEquals("1 d", Slash.pretty(86400))
    }
}
