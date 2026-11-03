package com.saeedkolivand.metastream.streaming

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioMathTest {
    private fun pcm(vararg samples: Int) = ByteArray(samples.size * 2).also { b ->
        samples.forEachIndexed { i, s ->
            b[2 * i] = s.toByte()
            b[2 * i + 1] = (s shr 8).toByte()
        }
    }

    @Test
    fun levels() {
        assertEquals(-120f, AudioMath.dBFS(pcm(0, 0, 0, 0), 8), 0f)
        assertEquals(0f, AudioMath.dBFS(pcm(-32768, -32768), 4), 0.01f) // full scale
        assertEquals(-6.02f, AudioMath.dBFS(pcm(16384, -16384), 4), 0.01f) // half scale
    }

    @Test
    fun deadAirNeedsTwentyQuietSecondsLiveAndUnmuted() {
        val (since, alert) = AudioMath.deadAir(null, -80f, 1_000, live = true, muted = false)
        assertEquals(1_000L, since)
        assertFalse(alert)
        assertTrue(AudioMath.deadAir(since, -80f, 21_000, live = true, muted = false).second)
        assertNull(AudioMath.deadAir(since, -20f, 21_000, live = true, muted = false).first) // loud again resets
        assertFalse(AudioMath.deadAir(since, -80f, 21_000, live = true, muted = true).second) // muted never alerts
        assertFalse(AudioMath.deadAir(since, -80f, 21_000, live = false, muted = false).second)
    }

    @Test
    fun mixingAddsWithGainAndClamps() {
        val buf = pcm(1000, 30000, -30000)
        val used = AudioMath.mixInto(buf, buf.size, shortArrayOf(1000, 10000, -10000, 7), 0, 0.5f)
        assertEquals(3, used) // stops at the end of the buffer, not the sound
        assertEquals(1500, AudioMath.sample(buf, 0))
        assertEquals(32767, AudioMath.sample(buf, 2))
        assertEquals(-32768, AudioMath.sample(buf, 4))
    }

    @Test
    fun chimeIsSixTenthsOfASecondOfStereo() {
        val c = AudioMath.chime()
        assertEquals((0.6 * AudioMath.RATE).toInt() * 2, c.size)
        assertEquals(c[200], c[201]) // both channels carry the same sample
        assertEquals(0, c.last().toInt()) // faded out at the end
    }

    @Test
    fun resamplesMonoToStereo() {
        val out = AudioMath.toStereo(ShortArray(22_050) { 100 }, 22_050, 1, 60)
        assertEquals(AudioMath.RATE * 2, out.size) // one second at 44.1 kHz stereo
        assertEquals(100, out[AudioMath.RATE].toInt())
        assertEquals(AudioMath.RATE * 2, AudioMath.toStereo(ShortArray(88_200), 44_100, 1, 1).size) // capped at 1 s
    }
}
