package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.Kind
import org.junit.Assert.assertEquals
import org.junit.Test

class ChatPlacementsTest {
    private fun ev(id: Long) = ChatEvent("twitch", "u$id", "hi", kind = Kind.Message, id = id, time = 10_000)

    @Test
    fun newestSitsAtTheBottomAndSpacingPushesOlderUp() {
        val rows = listOf(ev(1), ev(2))
        val p = chatPlacements(rows, listOf(10f, 10f), ChatStyle(height = 100f, fontSize = 20f), 10_000, burst = true)
        assertEquals(2, p.size)
        assertEquals(82f, p[0].y, 0.001f)
        assertEquals(65.6f, p[1].y, 0.001f)
        assertEquals(1f, p[0].alpha, 0.001f)
    }

    @Test
    fun stopsOnceTheStackLeavesTheBox() {
        val rows = listOf(ev(1), ev(2), ev(3))
        val p = chatPlacements(rows, listOf(30f, 30f, 30f), ChatStyle(height = 60f, fontSize = 20f), 10_000, burst = true)
        assertEquals(2, p.size)
    }
}
