package com.saeedkolivand.metastream.streaming

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import com.saeedkolivand.metastream.core.logging.applog
import java.io.File
import java.nio.ByteOrder

private const val TIMEOUT_US = 10_000L

/**
 * The first audio track of [file] decoded to the stream's 44.1 kHz stereo 16-bit PCM, at most [maxSeconds] (iOS SoundMix.load:
 * read whole, truncated). Null for an unreadable file or one without audio. Blocking: call it off the main thread.
 * ponytail: assumes the decoder's default 16-bit output (Android's default); a float-PCM decoder would need a branch here.
 */
internal fun decodeAudio(file: File, maxSeconds: Int): ShortArray? {
    val ex = MediaExtractor()
    var codec: MediaCodec? = null
    return try {
        ex.setDataSource(file.path)
        val track = (0 until ex.trackCount).firstOrNull {
            ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: return null
        ex.selectTrack(track)
        val format = ex.getTrackFormat(track)
        var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val c = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec = c
        c.configure(format, null, null, 0)
        c.start()
        val chunks = mutableListOf<ShortArray>()
        var total = 0L
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        while (!outputDone && total < maxSeconds.toLong() * rate * channels) {
            if (!inputDone) {
                val i = c.dequeueInputBuffer(TIMEOUT_US)
                if (i >= 0) {
                    val n = ex.readSampleData(c.getInputBuffer(i)!!, 0)
                    if (n < 0) {
                        c.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        c.queueInputBuffer(i, 0, n, ex.sampleTime, 0)
                        ex.advance()
                    }
                }
            }
            val o = c.dequeueOutputBuffer(info, TIMEOUT_US)
            if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                rate = c.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = c.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } else if (o >= 0) {
                val buf = c.getOutputBuffer(o)!!
                buf.position(info.offset)
                buf.limit(info.offset + info.size)
                val shorts = buf.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                val chunk = ShortArray(shorts.remaining())
                shorts.get(chunk)
                chunks += chunk
                total += chunk.size
                c.releaseOutputBuffer(o, false)
                outputDone = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            }
        }
        val all = ShortArray(total.toInt())
        var at = 0
        for (ch in chunks) {
            ch.copyInto(all, at)
            at += ch.size
        }
        AudioMath.toStereo(all, rate, channels, maxSeconds).takeIf { it.isNotEmpty() }
    } catch (e: Exception) {
        applog("audio", "can't decode ${file.name}: ${e.message}")
        null
    } finally {
        runCatching { codec?.stop() }
        codec?.release()
        ex.release()
    }
}
