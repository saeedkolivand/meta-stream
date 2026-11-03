package com.saeedkolivand.metastream.streaming

import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** The mix's loudness, the dead-air rule, mixing and the chime: pure (tested), same numbers as iOS AudioMath/SoundMix. */
internal object AudioMath {
    const val DEAD_AIR_DB = -50f
    const val DEAD_AIR_MS = 20_000L
    const val SILENCE_DB = -120f

    /** The stream's audio format (Engine.prepareAudio): 44.1 kHz, stereo, 16-bit little-endian. */
    const val RATE = 44_100

    /** One signed 16-bit little-endian sample at byte [i]. */
    fun sample(pcm: ByteArray, i: Int): Int = (pcm[i].toInt() and 0xFF) or (pcm[i + 1].toInt() shl 8)

    /** RMS level of the first [n] bytes of 16-bit PCM in dBFS (0 = full scale); -120 for silence. */
    fun dBFS(pcm: ByteArray, n: Int): Float {
        var sum = 0.0
        var count = 0
        var i = 0
        while (i + 1 < n) {
            val s = sample(pcm, i) / 32768.0
            sum += s * s
            count++
            i += 2
        }
        if (count == 0 || sum <= 0.0) return SILENCE_DB
        return max(SILENCE_DB, (10 * log10(sum / count)).toFloat())
    }

    /**
     * One dead-air step. [quietSince] is when the level first dropped below -50 dBFS (null while loud); alert = quiet for
     * 20 s while live and unmuted. Muted is silent on purpose, so it never alerts.
     */
    fun deadAir(quietSince: Long?, level: Float, now: Long, live: Boolean, muted: Boolean): Pair<Long?, Boolean> {
        if (!live || muted || level >= DEAD_AIR_DB) return null to false
        val since = quietSince ?: now
        return since to (now - since >= DEAD_AIR_MS)
    }

    /** Adds [src] from sample [pos] into the first [n] bytes of [pcm] at [gain], clamped; returns how many samples it used. */
    fun mixInto(pcm: ByteArray, n: Int, src: ShortArray, pos: Int, gain: Float): Int {
        var i = 0
        var p = pos
        while (i + 1 < n && p < src.size) {
            val v = (sample(pcm, i) + src[p] * gain).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            pcm[i] = v.toByte()
            pcm[i + 1] = (v shr 8).toByte()
            i += 2
            p++
        }
        return p - pos
    }

    /** iOS makeChime: two tones, ~0.6 s, A5 then E6, each a soft attack with an exponential decay, faded out at the end. */
    fun chime(rate: Int = RATE): ShortArray {
        val n = (0.6 * rate).toInt()
        val out = ShortArray(n * 2)
        fun tone(t: Double, start: Double, hz: Double): Double {
            val x = t - start
            return if (x < 0) 0.0 else min(1.0, x / 0.01) * exp(-x * 7) * sin(2 * PI * hz * x)
        }
        for (i in 0 until n) {
            val t = i.toDouble() / rate
            val s = 0.4 * (tone(t, 0.0, 880.0) + tone(t, 0.15, 1318.5)) * min(1.0, (0.6 - t) / 0.05)
            val v = (s * Short.MAX_VALUE).toInt().toShort()
            out[2 * i] = v
            out[2 * i + 1] = v
        }
        return out
    }

    /**
     * Interleaved 16-bit PCM at [rate] Hz with [channels] channels to the stream's 44.1 kHz stereo, at most [maxSeconds].
     * ponytail: linear resampling, mono duplicated, channels past the second dropped; a sinc resampler if anyone hears it.
     */
    fun toStereo(src: ShortArray, rate: Int, channels: Int, maxSeconds: Int): ShortArray {
        if (rate <= 0 || channels <= 0) return ShortArray(0)
        val frames = src.size / channels
        if (frames == 0) return ShortArray(0)
        val outFrames = min(frames.toLong() * RATE / rate, maxSeconds.toLong() * RATE).toInt()
        val out = ShortArray(outFrames * 2)
        for (f in 0 until outFrames) {
            val x = f.toDouble() * rate / RATE
            val a = min(x.toInt(), frames - 1)
            val b = min(a + 1, frames - 1)
            val k = x - a
            for (c in 0..1) {
                val ch = if (channels == 1) 0 else c
                out[2 * f + c] = (src[a * channels + ch] * (1 - k) + src[b * channels + ch] * k).toInt().toShort()
            }
        }
        return out
    }

    /** A Settings volume (0..100) as a gain. */
    fun gain(percent: Int) = percent.coerceIn(0, 100) / 100f
}
