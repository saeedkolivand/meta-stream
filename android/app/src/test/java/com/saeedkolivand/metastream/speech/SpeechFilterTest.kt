package com.saeedkolivand.metastream.speech

import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.Kind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SpeechFilterTest {
    @Test fun noise() {
        assertTrue(isNoise("Nightbot", "hi", ""))
        assertTrue(isNoise("BotRix", "hi", ""))
        assertTrue(isNoise("bob", " !discord", ""))
        assertTrue(isNoise("Spammer", "hi", "alice, @spammer"))
        assertFalse(isNoise("bob", "nice drive!", "alice"))
        assertFalse(isNoise("botanist", "hi", ""))
    }

    @Test fun blocked() {
        for (bad in listOf("you N1GG3R", "niiiiggers lol", "n i g g e r", "just kys", "F@G")) assertTrue(bad, isBlocked(bad, ""))
        for (ok in listOf("spicy food", "nice fagioli", "skyscraper", "good drive!")) assertFalse(ok, isBlocked(ok, ""))
        assertTrue(isBlocked("what a jerkface", "foo, jerkface"))
        assertTrue(isBlocked("کصافت", "کصافت"))
    }

    @Test fun spokenTextFilters() {
        val o = SpeechOptions()
        assertNull(spokenText(ChatEvent("kick", "Nightbot", "follow us"), o))
        assertNull(spokenText(ChatEvent("kick", "bob", "kys"), o))
        assertEquals("bob says hello", spokenText(ChatEvent("kick", "bob", "hello"), o))
        assertEquals("hello", spokenText(ChatEvent("kick", "bob", "hello"), o, sameSpeaker = true))
        assertEquals("someone followed", spokenText(ChatEvent("kick", "n1gg3r_lord", "", kind = Kind.Follow), o))
        assertEquals("Fan tipped 5 dollars", spokenText(ChatEvent("kick", "Fan", "kys", kind = Kind.Tip, amountCents = 500), o))
    }
}
