package com.saeedkolivand.metastream.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ModerationTest {
    @Test
    fun kickEvents() {
        assertEquals(
            Moderation.Remove(msgId = "m1"),
            parseKickModeration("""App\Events\MessageDeletedEvent""", """{"message":{"id":"m1"}}""")
        )
        assertEquals(
            Moderation.Remove(userId = "98", login = "bob"),
            parseKickModeration("""App\Events\UserBannedEvent""", """{"user":{"id":98,"username":"bob"}}""")
        )
        assertEquals(Moderation.Clear, parseKickModeration("""App\Events\ChatroomClearEvent""", "{}"))
        assertNull(parseKickModeration("""App\Events\ChatMessageEvent""", "{}"))
    }
}
