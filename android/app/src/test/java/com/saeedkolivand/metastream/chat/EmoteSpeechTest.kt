package com.saeedkolivand.metastream.chat

import com.saeedkolivand.metastream.speech.SpeechOptions
import com.saeedkolivand.metastream.speech.eventSummary
import com.saeedkolivand.metastream.speech.spokenAmount
import com.saeedkolivand.metastream.speech.spokenText
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EmoteSpeechTest {
    private val names = mapOf("Kappa" to "https://e/kappa", "catJAM" to "https://e/catjam")

    @Test fun kickTokensBecomeCdnEmotes() {
        val runs = tokenize("gg [emote:12345:wow] nice", emptyMap())
        assertEquals(
            listOf(Run.Text("gg "), Run.Emote("https://files.kick.com/emotes/12345/fullsize", "wow"), Run.Text(" nice")),
            runs
        )
    }

    @Test fun thirdPartyEmotesMatchWholeWordsCaseSensitively() {
        assertEquals(
            listOf(Run.Text("hi "), Run.Emote("https://e/kappa", "Kappa"), Run.Text(" there")),
            tokenize("hi Kappa there", names)
        )
        assertEquals(listOf(Run.Text("kappa Kappas")), tokenize("kappa Kappas", names))
        assertEquals(
            listOf(Run.Emote("https://e/kappa", "Kappa"), Run.Emote("https://e/catjam", "catJAM")),
            tokenize("Kappa catJAM", names).filterNot {
                it is Run.Text
            }
        )
    }

    @Test fun sevenTvPicksStaticOrAnimatedFile() {
        val json = JSONArray(
            """[{"name":"catJAM","data":{"host":{"url":"//cdn.7tv.app/emote/abc","files":[
                {"name":"1x.webp","static_name":"1x_static.webp"},{"name":"2x.webp","static_name":"2x_static.webp"}]}}},
                {"name":"broken"}]"""
        )
        assertEquals(mapOf("catJAM" to "https://cdn.7tv.app/emote/abc/2x_static.webp"), sevenTvEmotes(json))
        val animated = JSONArray(json.toString().replace("\"data\":{", "\"data\":{\"animated\":true,"))
        assertEquals(mapOf("catJAM" to "https://cdn.7tv.app/emote/abc/2x.webp"), sevenTvEmotes(animated))
    }

    @Test fun bttvAndFfz() {
        val bttv = bttvEmotes(listOf(JSONObject("""{"id":"55","code":"OMEGALUL"}"""), JSONObject("""{"id":"x"}""")))
        assertEquals(mapOf("OMEGALUL" to "https://cdn.betterttv.net/emote/55/2x"), bttv)
        val ffz = JSONObject(
            """{"sets":{"3":{"emoticons":[{"name":"ZrehplaR","urls":{"1":"//cdn.frankerfacez.com/a/1","2":"//cdn.frankerfacez.com/a/2"}}]}}}"""
        )
        assertEquals(mapOf("ZrehplaR" to "https://cdn.frankerfacez.com/a/2"), ffzEmotes(ffz, listOf(3)))
        assertEquals(emptyMap<String, String>(), ffzEmotes(ffz, listOf(9)))
    }

    private fun tip(cents: Int, note: String = "") = ChatEvent("youtube", "Fan", note, kind = Kind.Tip, amountCents = cents)

    @Test fun tipsRespectTheFloorAndToggle() {
        val o = SpeechOptions(minTipCents = 500)
        assertNull(spokenText(tip(499), o))
        assertEquals("Fan tipped 5 dollars: love it", spokenText(tip(500, "love it"), o))
        assertNull(spokenText(tip(500), o.copy(tips = false)))
        assertEquals("Fan tipped 12.50 dollars", spokenText(tip(1250), SpeechOptions()))
        assertEquals("money", spokenAmount(0))
        assertEquals("1 dollar", spokenAmount(100))
    }

    @Test fun alertKindsFollowTheirOwnToggles() {
        val all = SpeechOptions()
        val cheer = ChatEvent("twitch", "Whale", "bits!", kind = Kind.Cheer, count = 100)
        assertEquals("Whale cheered 100 bits: bits!", spokenText(cheer, all))
        assertNull(spokenText(cheer, all.copy(tips = false))) // bits are money: same gate as tips
        assertEquals("A followed", spokenText(ChatEvent("twitch", "A", "", kind = Kind.Follow), all))
        assertNull(spokenText(ChatEvent("twitch", "A", "", kind = Kind.Follow), all.copy(follows = false)))
        assertEquals("A subscribed", spokenText(ChatEvent("twitch", "A", "", kind = Kind.Subscribe), all))
        assertEquals("A gifted a sub", spokenText(ChatEvent("twitch", "A", "", kind = Kind.Subscribe, count = 1), all))
        assertEquals("A gifted 5 subs", eventSummary(ChatEvent("twitch", "A", "", kind = Kind.Subscribe, count = 5)))
        assertEquals("A raided with 9 viewers", spokenText(ChatEvent("twitch", "A", "", kind = Kind.Raid, count = 9), all))
        assertNull(spokenText(ChatEvent("twitch", "A", "", kind = Kind.Raid, count = 9), all.copy(raids = false)))
    }

    @Test fun messagesAreSanitizedAndGated() {
        val m = ChatEvent("kick", "Bob", "look https://x.y [emote:1:wow] @streamer")
        assertEquals("Bob says look streamer", spokenText(m, SpeechOptions()))
        assertNull(spokenText(m, SpeechOptions(messages = false)))
        assertNull(spokenText(ChatEvent("kick", "Bob", "https://only.a/link"), SpeechOptions()))
    }

    @Test fun compactSummaries() {
        assertEquals("Fan tipped $5.00 — thanks", eventSummary(tip(500, "thanks")))
        assertEquals("A raided with 9 viewers", eventSummary(ChatEvent("twitch", "A", "", kind = Kind.Raid, count = 9)))
    }
}
