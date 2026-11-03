package com.saeedkolivand.metastream.bot

import com.saeedkolivand.metastream.chat.safeName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS AppBot.demo() and BotList.demo(), same cases. */
class BotRulesTest {
    private val t = 1_000_000_000L

    @Test
    fun cooldownAndTimers() {
        assertTrue(BotRules.cooldownOK(null, t, false))
        assertFalse(BotRules.cooldownOK(t, t + 29_000, false))
        assertTrue(BotRules.cooldownOK(t, t + 30_000, false))
        assertTrue(BotRules.cooldownOK(t, t + 1_000, true))
        val later = t + 600_000
        assertTrue(BotRules.timerDue(t, 10, 5, null, later))
        assertFalse(BotRules.timerDue(t, 10, 4, null, later)) // too quiet
        assertFalse(BotRules.timerDue(t, 11, 9, null, later)) // too early
        assertFalse(BotRules.timerDue(t, 1, 9, null, t + 120_000)) // minutes floor at 5
        assertFalse(BotRules.timerDue(t, 10, 9, later - 299_000, later)) // another timer just posted
        assertTrue(BotRules.timerDue(t, 10, 9, later - 300_000, later))
        assertTrue(BotRules.brbNoticeDue(null, t))
        assertFalse(BotRules.brbNoticeDue(t, t + 119_000))
        assertTrue(BotRules.brbNoticeDue(t, t + 120_000))
    }

    @Test
    fun templatesAndKeys() {
        assertEquals("bob: 5 subs", BotRules.fill("{user}: {count} subs", "bob", 5))
        assertEquals("botCmdDonate", BotRules.switchKey("!tip"))
        assertEquals("botCmdGoal", BotRules.switchKey("!goal"))
        assertEquals("giveaway end", safeName("!giveaway end"))
        assertEquals("Someone", safeName("!!!"))
    }

    @Test
    fun bots() {
        assertTrue(BotList.isBot("Nightbot", ""))
        assertTrue(BotList.isBot("BotRix", "botrix"))
        assertFalse(BotList.isBot("botanist", "botrix"))
        val tr = "won, winner"
        assertTrue(BotList.isAnnouncement("StreamElements", "Bob WON the giveaway!", "streamelements", tr))
        assertFalse(BotList.isAnnouncement("bob", "I won", "streamelements", tr))
        assertFalse(BotList.isAnnouncement("nightbot", "wonderful day", "", tr))
        assertFalse(BotList.isAnnouncement("nightbot", "anything", "", " , "))
    }
}
