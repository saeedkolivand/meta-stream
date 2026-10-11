package com.saeedkolivand.metastream.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatParsersTest {
    private val kickFrame = """{"event":"App\\Events\\ChatMessageEvent","data":"{\"content\":\"hey\",\"sender\":{\"username\":\"bob\"}}"}"""

    @Test fun kickMessage() {
        val e = parseKickFrame(kickFrame)!!
        assertEquals("kick", e.platform)
        assertEquals("bob", e.user)
        assertEquals("hey", e.text)
    }

    @Test fun kickIgnoresOtherEventsAndGarbage() {
        assertNull(parseKickFrame("""{"event":"pusher:connection_established","data":"{}"}"""))
        assertNull(parseKickFrame("not json"))
        assertNull(parseKickFrame("""{"event":"App\\Events\\ChatMessageEvent","data":"{}"}"""))
    }

    @Test fun kickPing() {
        assertTrue(isKickPing("""{"event":"pusher:ping","data":"{}"}"""))
        assertFalse(isKickPing(kickFrame))
        assertFalse(isKickPing("not json"))
    }

    @Test fun twitchUsesDisplayNameTag() {
        val e = parseTwitchLine("@badges=;display-name=BobTheBuilder;id=1 :bob!bob@bob.tmi.twitch.tv PRIVMSG #chan :hello world")!!
        assertEquals("twitch", e.platform)
        assertEquals("BobTheBuilder", e.user)
        assertEquals("hello world", e.text)
    }

    @Test fun twitchFallsBackToLogin() {
        val e = parseTwitchLine("@badges=;display-name=;id=1 :bob!bob@bob.tmi.twitch.tv PRIVMSG #chan :yo")!!
        assertEquals("bob", e.user)
        assertEquals("bob", parseTwitchLine("@id=1 :bob!bob@bob.tmi.twitch.tv PRIVMSG #chan :yo")!!.user)
    }

    @Test fun twitchIgnoresNonPrivmsgAndPing() {
        assertNull(parseTwitchLine(":tmi.twitch.tv 001 justinfan1 :Welcome"))
        assertNull(parseTwitchLine("PING :tmi.twitch.tv"))
        assertTrue(isTwitchPing("PING :tmi.twitch.tv"))
        assertFalse(isTwitchPing("@id=1 :bob!bob@bob.tmi.twitch.tv PRIVMSG #chan :PING"))
    }

    @Test fun displayTextShowsKickEmoteNames() {
        assertEquals("another EZ  5k", displayText("another [emote:5756668:EZ]  5k"))
        assertEquals("collectiblesModTime", displayText("[emote:5748074:collectiblesModTime]"))
        assertEquals("plain text", displayText("plain text"))
    }

    @Test fun twitchBadgesAndColor() {
        val line = "@badge-info=subscriber/14;badges=moderator/1,subscriber/12,premium/1,bits/100;color=#FF4500;display-name=Mod;id=1 " +
            ":mod!mod@mod.tmi.twitch.tv PRIVMSG #chan :hi"
        val e = parseTwitchLine(line)!!
        assertEquals(listOf("moderator", "subscriber"), e.badges)
        assertEquals("#FF4500", e.color)
        val owner = parseTwitchLine(line.replace("moderator/1,subscriber/12", "partner/1,broadcaster/1"))!!
        assertEquals(listOf("broadcaster", "verified"), owner.badges)
    }

    @Test fun twitchNoBadgesNoColor() {
        val e = parseTwitchLine("@badges=;color=;display-name=Bob;id=1 :bob!bob@bob.tmi.twitch.tv PRIVMSG #chan :hi")!!
        assertEquals(emptyList<String>(), e.badges)
        assertNull(e.color)
    }

    @Test fun kickBadgesAndColor() {
        val data = """{\"content\":\"gg\",\"sender\":{\"username\":\"xqc\",\"identity\":{\"color\":\"#E9113C\",""" +
            """\"badges\":[{\"type\":\"og\",\"text\":\"OG\"},{\"type\":\"subscriber\",\"text\":\"Subscriber\",\"count\":7},""" +
            """{\"type\":\"sub_gifter\",\"text\":\"Sub Gifter\",\"count\":5},{\"type\":\"moderator\",\"text\":\"Moderator\"}]}}}"""
        val e = parseKickFrame("""{"event":"App\\Events\\ChatMessageEvent","data":"$data"}""")!!
        assertEquals("#E9113C", e.color)
        assertEquals(listOf("moderator", "subscriber", "og"), e.badges)
    }

    @Test fun kickWithoutIdentity() {
        val e = parseKickFrame(kickFrame)!!
        assertEquals(emptyList<String>(), e.badges)
        assertNull(e.color)
    }
}
