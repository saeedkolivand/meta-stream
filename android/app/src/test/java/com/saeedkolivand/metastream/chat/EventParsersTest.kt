package com.saeedkolivand.metastream.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EventParsersTest {
    private fun frame(type: String, subType: String, event: String) =
        """{"metadata":{"message_type":"$type","subscription_type":"$subType"},"payload":{"event":$event}}"""

    private fun notification(subType: String, event: String) =
        (parseEventSubFrame(frame("notification", subType, event)) as EventSubFrame.Notification).event

    @Test fun welcomeCarriesTheSessionId() {
        val f = parseEventSubFrame("""{"metadata":{"message_type":"session_welcome"},"payload":{"session":{"id":"abc123"}}}""")
        assertEquals(EventSubFrame.Welcome("abc123"), f)
    }

    @Test fun reconnectCarriesTheNewUrl() {
        val f = parseEventSubFrame(
            """{"metadata":{"message_type":"session_reconnect"},"payload":{"session":{"reconnect_url":"wss://x.example/ws?c=1"}}}"""
        )
        assertEquals(EventSubFrame.Reconnect("wss://x.example/ws?c=1"), f)
    }

    @Test fun keepaliveAndGarbageAreIgnored() {
        assertEquals(EventSubFrame.Ignored, parseEventSubFrame("""{"metadata":{"message_type":"session_keepalive"},"payload":{}}"""))
        assertEquals(EventSubFrame.Ignored, parseEventSubFrame("not json"))
        assertEquals(EventSubFrame.Ignored, parseEventSubFrame(frame("notification", "channel.unknown.thing", "{}")))
    }

    @Test fun chatMessageWithBadgesAndColor() {
        val e = notification(
            "channel.chat.message",
            """{"chatter_user_name":"Viewer","color":"#1e90ff","message":{"text":"gg well played"},
               "badges":[{"set_id":"subscriber","id":"6","info":"7"},{"set_id":"moderator","id":"1","info":""},{"set_id":"bits","id":"100","info":""}]}"""
        )
        assertEquals("twitch", e.platform)
        assertEquals(Kind.Message, e.kind)
        assertEquals("Viewer", e.user)
        assertEquals("gg well played", e.text)
        assertEquals("#1E90FF", e.color)
        assertEquals(listOf("moderator", "subscriber"), e.badges) // display order; unknown "bits" dropped
    }

    @Test fun badColorIsDropped() {
        val e = notification("channel.chat.message", """{"chatter_user_name":"V","color":"","message":{"text":"x"}}""")
        assertNull(e.color)
    }

    @Test fun followSubscribeRaid() {
        assertEquals(Kind.Follow, notification("channel.follow", """{"user_name":"Fan"}""").kind)
        assertEquals("Fan", notification("channel.subscribe", """{"user_name":"Fan"}""").user)
        val raid = notification("channel.raid", """{"from_broadcaster_user_name":"Big","viewers":42}""")
        assertEquals(Kind.Raid, raid.kind)
        assertEquals("Big", raid.user)
        assertEquals(42, raid.count)
    }

    @Test fun twitchGiftAndResub() {
        val gift = notification("channel.subscription.gift", """{"user_name":"G","total":5,"is_anonymous":false}""")
        assertEquals("G", gift.user)
        assertEquals(5, gift.count)
        assertEquals("Anonymous", notification("channel.subscription.gift", """{"user_name":null,"total":1,"is_anonymous":true}""").user)
        val resub = notification("channel.subscription.message", """{"user_name":"R","message":{"text":"hi"}}""")
        assertEquals(0, resub.count)
        assertEquals("hi", resub.text)
    }

    @Test fun youtubeMembershipEvents() {
        fun item(type: String, count: String = "") = JSONObject(
            """{"snippet":{"type":"$type","membershipGiftingDetails":{"giftMembershipsCount":$count}},"authorDetails":{"displayName":"M"}}"""
        )
        assertEquals(Kind.Subscribe, parseYouTubeItem(item("newSponsorEvent", "0"))!!.kind)
        assertEquals(7, parseYouTubeItem(item("membershipGiftingEvent", "7"))!!.count)
        assertEquals(3, parseYouTubeItem(item("membershipGiftingEvent", "\"3\""))!!.count)
        assertNull(parseYouTubeItem(item("giftMembershipReceivedEvent", "0")))
    }

    @Test fun cheerAndAnonymousCheer() {
        val c = notification("channel.cheer", """{"user_name":"Whale","message":"take my bits","bits":500}""")
        assertEquals(Kind.Cheer, c.kind)
        assertEquals(500, c.count)
        assertEquals("take my bits", c.text)
        assertEquals("an anonymous cheerer", notification("channel.cheer", """{"is_anonymous":true,"bits":1}""").user)
    }

    @Test fun eventWithoutAUserIsDropped() {
        assertNull(parseEventSubEvent("channel.follow", JSONObject("{}")))
        assertNull(parseEventSubEvent("channel.chat.message", JSONObject("""{"chatter_user_name":"V"}""")))
    }

    @Test fun youtubeTextMessageWithRoles() {
        val e = parseYouTubeItem(
            JSONObject(
                """{"snippet":{"type":"textMessageEvent","textMessageDetails":{"messageText":"hello"}},
                    "authorDetails":{"displayName":"Yt User","isChatModerator":true,"isChatSponsor":true,"isChatOwner":false}}"""
            )
        )!!
        assertEquals("youtube", e.platform)
        assertEquals("Yt User", e.user)
        assertEquals("hello", e.text)
        assertEquals(listOf("moderator", "subscriber"), e.badges)
    }

    @Test fun youtubeSuperChatBecomesATipInCents() {
        val e = parseYouTubeItem(
            JSONObject(
                """{"snippet":{"type":"superChatEvent","superChatDetails":{"amountMicros":"5000000","currency":"USD","userComment":"love the stream"}},
                    "authorDetails":{"displayName":"GenerousViewer"}}"""
            )
        )!!
        assertEquals(Kind.Tip, e.kind)
        assertEquals(500, e.amountCents)
        assertEquals("love the stream", e.text)
    }

    @Test fun youtubeSuperStickerAndOtherTypes() {
        val sticker = parseYouTubeItem(
            JSONObject(
                """{"snippet":{"type":"superStickerEvent","superStickerDetails":{"amountMicros":"1990000"}},"authorDetails":{"displayName":"S"}}"""
            )
        )!!
        assertEquals(199, sticker.amountCents)
        assertNull(parseYouTubeItem(JSONObject("""{"snippet":{"type":"membershipEvent"},"authorDetails":{"displayName":"x"}}""")))
        assertNull(parseYouTubeItem(JSONObject("""{"snippet":{"type":"textMessageEvent"}}""")))
        assertTrue(parseYouTubeItem(JSONObject("{}")) == null)
    }
}
