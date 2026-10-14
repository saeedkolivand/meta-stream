package com.saeedkolivand.metastream.chat

import org.json.JSONObject
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

    private val rules = JSONObject(DEFAULT_KICK_RULES)

    private fun kickAlert(name: String, data: String, r: JSONObject = rules) = parseKickRule(r, """App\Events\$name""", data)

    @Test fun kickSubGiftHostFollowKicks() {
        val sub = kickAlert("SubscriptionEvent", """{"username":"s","months":3}""")!!
        assertEquals(Kind.Subscribe, sub.kind)
        assertEquals(0, sub.count)
        assertEquals(3, kickAlert("GiftedSubscriptionsEvent", """{"gifter_username":"g","gifted_usernames":["a","b","c"]}""")!!.count)
        val q = kickAlert("GiftedSubscriptionsEvent", """{"username":"g","quantity":5}""")!!
        assertEquals(5, q.count)
        assertEquals("g", q.user)
        assertEquals(1, kickAlert("GiftedSubscriptionsEvent", """{"username":"g"}""")!!.count)
        val host = kickAlert("StreamHostEvent", """{"host_username":"h","number_viewers":12}""")!!
        assertEquals(Kind.Raid, host.kind)
        assertEquals(12, host.count)
        assertEquals(Kind.Follow, kickAlert("FollowersUpdated", """{"followed":true,"username":"f"}""")!!.kind)
        assertNull(kickAlert("FollowersUpdated", """{"followed":false,"username":"f"}"""))
        val kicks = kickAlert("KicksGifted", """{"sender":{"username":"k"},"gift":{"amount":300},"message":"yo"}""")!!
        assertEquals(Kind.Tip, kicks.kind)
        assertEquals(300, kicks.amountCents)
        assertEquals("yo", kicks.text)
        assertNull(kickAlert("Other", """{"username":"x"}"""))
    }

    @Test fun modifiedKickRulesAreHonoured() {
        val renamed = JSONObject(
            """{"version":1,"events":{"App\\Events\\NewFollow":{"kind":"follow","user":["who.name"]}}}"""
        )
        assertEquals("zed", kickAlert("NewFollow", """{"who":{"name":"zed"}}""", renamed)!!.user)
        assertNull(kickAlert("FollowersUpdated", """{"followed":true,"username":"f"}""", renamed))
    }

    @Test fun kickChannelsSkipUnknownPlaceholders() {
        assertEquals(listOf("chatrooms.1.v2", "channel.2"), kickChannels(rules, 1, 2))
        assertEquals(emptyList<String>(), kickChannels(JSONObject("""{"channels":["x.{nope}"]}"""), 1, 2))
    }
}
