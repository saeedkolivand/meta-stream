package com.saeedkolivand.metastream.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS ChatModerationTests: the decisions that don't need the model. */
class ChatModerationTest {
    @Test fun latinOnly() {
        assertTrue(ChatModeration.isMostlyLatin("you are great"))
        assertTrue(ChatModeration.isMostlyLatin("ça va très bien"))
        assertFalse(ChatModeration.isMostlyLatin("سلام خوبی"))
        assertFalse(ChatModeration.isMostlyLatin("ok")) // under 3 letters
        assertFalse(ChatModeration.isMostlyLatin("12345 !!!"))
    }

    @Test fun floodSkipsReview() {
        assertTrue(ChatModeration.shouldHold(ChatModeration.MAX_WAITING - 1))
        assertFalse(ChatModeration.shouldHold(ChatModeration.MAX_WAITING))
    }

    @Test fun failsOpen() {
        assertTrue(ChatModeration.isUnsafeAnswer("UNSAFE"))
        assertTrue(ChatModeration.isUnsafeAnswer(" unsafe.\n"))
        assertFalse(ChatModeration.isUnsafeAnswer("SAFE"))
        assertFalse(ChatModeration.isUnsafeAnswer(""))
        assertFalse(ChatModeration.isUnsafeAnswer(null))
    }
}
