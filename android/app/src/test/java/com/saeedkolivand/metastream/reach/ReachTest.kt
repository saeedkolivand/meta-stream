package com.saeedkolivand.metastream.reach

import com.saeedkolivand.metastream.platforms.KickWeb
import com.saeedkolivand.metastream.platforms.Spotify
import com.saeedkolivand.metastream.streaming.uplink.cleanSecondsBeforeUp
import java.math.BigDecimal
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReachTest {
    @Test
    fun spikesAnonymityAndText() {
        assertFalse(SessionLog.isSpike(40, listOf(5, 5)))
        assertFalse(SessionLog.isSpike(19, listOf(1, 1, 1)))
        assertTrue(SessionLog.isSpike(20, listOf(1, 1, 1)))
        assertFalse(SessionLog.isSpike(29, listOf(10, 10, 10)))
        assertTrue(SessionLog.isSpike(30, listOf(10, 10, 10)))
        assertTrue(SessionLog.isAnonymous(" anonymous ") && SessionLog.isAnonymous("") && !SessionLog.isAnonymous("Bob"))
        val live = LivePostText.live(LivePostText.Live(title = "IRL", slug = "saeed", viewers = 42, elapsedMs = 8_040_000), "en")
        assertTrue("42 watching" in live && "2h 14m" in live && "kick.com/saeed" in live)
        assertTrue(LivePostText.live(LivePostText.Live(), "en").startsWith("🔴 LIVE\n"))
        val rec = LivePostText.Recap(title = "t", slug = "s", donationCount = 2, total = "€30", topName = "Bob", topAmount = "€25")
        assertTrue("€30 from 2 donations" in LivePostText.recap(rec, "en"))
        val donation = Moment(0, Moment.DONATION, "Bob", "€25")
        assertEquals("💸 Big donation from Bob (€25) — come say thanks\n▶️ kick.com/s", LivePostText.ping(donation, "s", "en"))
        assertEquals("🚀 Raid from Al with 40 viewers", LivePostText.ping(Moment(0, Moment.RAID, "Al", "40"), "", "en"))
        assertEquals(1024, LivePostText.fit("x".repeat(5000), true).length)
    }

    @Test
    fun postTemplates() {
        val v = mapOf("title" to "IRL", "city" to "", "n" to "3")
        assertEquals("A · IRL\nn=3", LivePostText.render("A[ · {title}]\n📍 {city}\nn={n}", v))
        assertEquals("A\n{typo}", LivePostText.render("A[ · {city}]\n{typo}", v))
        assertEquals("", LivePostText.render("[{city}]", v))
        // the built-in templates still give the old posts
        val p = LivePostText.Live(title = "IRL", slug = "saeed", viewers = 42, elapsedMs = 8_040_000)
        assertTrue(LivePostText.live(p, "en").startsWith("🔴 LIVE · IRL\n👁 42 watching · ⏱ 2h 14m\n▶️ kick.com/saeed\nupdated "))
        val down = LivePostText.live(LivePostText.Live(reconnecting = true), "en")
        assertTrue(down.startsWith("🔴 LIVE\n📡 reconnecting…\nupdated ") && "watching" !in down)
        val rec = LivePostText.Recap(title = "t", slug = "s", durationMs = 3_600_000, showTotal = false, topName = "Bob", topAmount = "€25")
        assertEquals("✅ Stream ended · t\n⏱ 1h 0m · 👁 peak 0 · avg 0\n💸 top: Bob €25\n▶️ kick.com/s", LivePostText.recap(rec, "en"))
        assertEquals("📣 به‌زودی لایو\n▶️ kick.com/s", LivePostText.announce("", "s", "fa"))
        // a custom template wins; one that renders to nothing falls back to the built-in post
        val mine: (LivePostText.Kind) -> String? = { "Live now: {title} ({viewers})" }
        assertEquals("Live now: IRL (42)", LivePostText.live(p, "en", mine))
        assertEquals("📣 Going live soon\n▶️ kick.com/s", LivePostText.announce("", "s", "en") { "[{title}]" })
    }

    @Test
    fun recordRoundTrip() {
        val r = SessionRecord(1000, "t", "EUR", trackingStarted = true)
        r.samples += SessionSample(1, 10, 3, 4000, 0, 0, 2.5, 1)
        r.moments += Moment(5, Moment.RAID, "Al", "40", 40.0)
        r.donationTotal = BigDecimal("12.34")
        r.donors["Bob"] = BigDecimal("5")
        r.chatterCounts["kick|1"] = 3
        val back = SessionRecord.from(JSONObject(r.toJson().toString()))
        assertEquals(10, back.peakViewers)
        assertEquals(BigDecimal("12.34"), back.donationTotal)
        assertEquals("Al", back.moments[0].user)
        assertEquals(3, back.chatterCounts["kick|1"])
        assertEquals(BigDecimal("5"), back.donors["Bob"])
        assertTrue(back.trackingStarted)
    }
}

class HeatmapTest {
    @Test
    fun bucketsByWeekdayHour() {
        val utc = java.util.TimeZone.getTimeZone("UTC")
        val monday10 = 1_704_067_200_000L + 10 * 3_600_000L // Monday 2024-01-01 10:00 UTC
        fun rec(start: Long, vararg v: Int) = SessionRecord(start, "", "EUR").apply {
            v.forEachIndexed { i, x -> samples += SessionSample(i + 1, x, 0, 0, 0, 0, x.toDouble(), 0) }
        }
        val recs = listOf(rec(monday10, 10, 20), rec(monday10 + 7 * 86_400_000L, 30, 0))
        val avg = Heatmap.cells(recs, Heatmap.Metric.Viewers, utc).single()
        assertEquals(0, avg.weekday)
        assertEquals(10, avg.hour)
        assertEquals(20.0, avg.value, 1e-9)
        assertTrue(avg.enough)
        assertEquals(900.0, Heatmap.cells(recs, Heatmap.Metric.Donations, utc).single().value, 1e-9) // 60 over 4 samples, per hour
    }
}

class WrappedTest {
    @Test
    fun buildsMonth() {
        val utc = java.util.TimeZone.getTimeZone("UTC")
        val base = 1_704_067_200_000L // 2024-01-01 00:00 UTC
        val first = SessionRecord(base, "a", "EUR").apply {
            end = base + 3_600_000
            chatterCounts += mapOf("k|1" to 5, "k|2" to 3, "k|3" to 9)
            chatterNames += mapOf("k|1" to "Ann", "k|2" to "Bob", "k|3" to "")
        }
        val second = SessionRecord(base + 86_400_000, "b", "EUR").apply {
            end = start + 7_200_000
            chatterCounts["k|1"] = 4
            chatterNames["k|1"] = "Annie"
        }
        val other = SessionRecord(base + 40 * 86_400_000L, "c", "EUR").apply { end = start }
        assertEquals(null, WrappedBuilder.build("2023-12", listOf(first), "en", utc))
        val d = WrappedBuilder.build("2024-01", listOf(second, first, other), "en", utc)!!
        assertEquals(2, d.streams)
        assertEquals(3.0, d.hours, 1e-9)
        assertEquals(null, d.km)
        assertEquals(listOf("Annie" to 9, "Bob" to 3), d.topChatters)
        val json = d.toJson()
        assertEquals(13, json.length())
        assertTrue(json.isNull("km") && json.isNull("donations") && json.isNull("bestMoment"))
        second.distanceMeters = 1234.0
        assertEquals(1.2, WrappedBuilder.build("2024-01", listOf(second, first), "en", utc)!!.km!!, 1e-9)
    }
}

class SpotifyParseTest {
    @Test
    fun parsesPlayingTrackOnly() {
        val json = """{"is_playing":true,"currently_playing_type":"track","progress_ms":1000,"item":{"id":"x","name":"Song",
            "duration_ms":10000,"artists":[{"name":"A"},{"name":"B"}],
            "album":{"images":[{"url":"big","width":640},{"url":"mid","width":300},{"url":"small","width":64}]}}}"""
        val t = Spotify.parse(JSONObject(json), 1_000_000)!!
        assertEquals("A, B", t.artist)
        assertEquals("mid", t.artURL)
        assertEquals(3000, t.elapsedMs(1_002_000))
        assertEquals(10000, t.elapsedMs(1_060_000))
        assertEquals(null, Spotify.parse(JSONObject(json.replace("true", "false")), 0))
        assertEquals(null, Spotify.parse(JSONObject(json.replace("\"track\"", "\"ad\"")), 0))
    }
}

class BitrateRecoveryTest {
    @Test
    fun climbsFastWellBelowWhereItFailed() {
        assertEquals(5, cleanSecondsBeforeUp(2000, 4000))
        assertEquals(15, cleanSecondsBeforeUp(3500, 4000))
    }
}

class ReportInsightsTest {
    @Test
    fun ordinalsAndPercent() {
        assertEquals("2nd", ReportInsights.ordinal(2))
        assertEquals("11th", ReportInsights.ordinal(11))
        assertEquals("23rd", ReportInsights.ordinal(23))
        assertEquals(50, ReportInsights.percent(15.0, listOf(10.0, 10.0)))
        assertEquals(null, ReportInsights.percent(5.0, emptyList()))
    }
}

class KickWebTest {
    @Test
    fun modeBodiesPollsAndNames() {
        val k = KickWeb
        assertEquals("""{"slow_mode":{"enabled":true,"duration_seconds":5}}""", k.modeBody("slow", listOf("on")))
        assertEquals("""{"slow_mode":{"enabled":true,"duration_seconds":30}}""", k.modeBody("slow", listOf("30")))
        assertEquals("""{"slow_mode":{"enabled":false,"duration_seconds":1}}""", k.modeBody("slow", listOf("off")))
        assertEquals("""{"emotes_only_mode":{"enabled":true}}""", k.modeBody("emoteonly", emptyList()))
        assertEquals("""{"followers_only_mode":{"enabled":true,"duration_seconds":600}}""", k.modeBody("followonly", listOf("on", "10")))
        assertEquals(null, k.modeBody("subscribers", emptyList()))
        assertEquals("Best?" to listOf("Cats", "Dogs"), k.poll(listOf("Best?", "|", "Cats", "|", "Dogs")))
        assertEquals(null, k.poll(listOf("Q?", "|", "a", "|", "bb")))
        assertEquals(null, k.poll(listOf("|", "aa", "|", "bb")))
        assertEquals("saeed", k.person("@Saeed"))
        assertEquals(null, k.person("@"))
    }
}
