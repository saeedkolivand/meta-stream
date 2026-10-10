// HevcDecoder - On-device HEVC decode for the live preview
//
// Decodes the compressed HEVC frames delivered by the DAT SDK and renders them directly
// to a Surface via MediaCodec (the GPU handles YUV->RGB). Replicates the SDK's
// VideoDecoder NAL-parsing / enqueue logic: parse NAL units, cache config, activate on
// the first keyframe, then feed each NAL separately.
// Trimmed from Meta's sample: the SDK's carry-over start-code scanner (only needed across split buffers, we always
// get whole frames) is a plain scan, and the public/private enqueue pair is one loop.

package com.saeedkolivand.metastream.glasses

import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue

private const val TAG = "HevcDecoder"
private const val DATA_QUEUE_CAPACITY = 100

// Hardware HEVC decoders that corrupt this stream into fragments/trash; the SDK's own decoder
// skips them too. Prefer a software decoder instead (see createHevcDecoder).
private val BLOCKED_DECODERS = setOf("OMX.Exynos.hevc.dec", "c2.mtk.hevc.decoder")

private class DecoderFrame(
    val data: ByteBuffer,
    val offset: Int,
    val presentationTimeUs: Long,
    val isKeyFrame: Boolean,
    val isConfigFrame: Boolean
) {
    val size: Int = data.remaining() // captured now: submit() consumes the buffer
    val flags: Int
        get() = (if (isKeyFrame) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0) or
            (if (isConfigFrame) MediaCodec.BUFFER_FLAG_CODEC_CONFIG else 0)
}

class HevcDecoder {
    // These references are torn down from stop() on the caller thread while MediaCodec callbacks may
    // still fire on the decoder thread. @Volatile is sufficient: each is a single reference assigned
    // on setup and nulled on teardown — no compound state, only publication visibility.
    @Volatile private var decoder: MediaCodec? = null

    @Volatile private var decoderThread: HandlerThread? = null

    @Volatile private var decoderHandler: Handler? = null
    private val incomingDataQueue = LinkedBlockingQueue<DecoderFrame>(DATA_QUEUE_CAPACITY)

    // Input buffers the codec has offered that no frame has filled yet. Locked because activation
    // and stop() clear it from outside the decoder thread: a codec reset invalidates every index.
    private val availableInputBuffers = ArrayDeque<Int>()
    private val feedRunnable = Runnable { feedInputBuffers() }

    @Volatile private var mediaFormat: MediaFormat? = null

    @Volatile private var cachedVideoCodec: ByteBuffer? = null

    @Volatile private var active = false

    @Volatile private var firstInputFrame = true

    @Volatile private var receivedKeyframe = false

    @Volatile private var outputSurface: Surface? = null

    fun start(width: Int, height: Int, surface: Surface) {
        outputSurface = surface
        mediaFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_HEVC, width, height).also {
            it.setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            it.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            it.setInteger(MediaFormat.KEY_BIT_RATE, 750000)
        }
        try {
            if (decoder == null) decoder = createHevcDecoder()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create HEVC decoder: ${e.message}", e)
        }
    }

    fun decodeFrame(data: ByteArray, presentationTimeUs: Long) {
        if (data.isEmpty()) return
        enqueueNals(ByteBuffer.wrap(data), data, presentationTimeUs)
    }

    fun stop() {
        active = false
        decoderHandler = null
        incomingDataQueue.clear()
        synchronized(availableInputBuffers) { availableInputBuffers.clear() }
        try {
            decoder?.stop()
            decoder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping decoder: ${e.message}", e)
        }
        decoder = null
        decoderThread?.quit()
        decoderThread = null
        firstInputFrame = true
        receivedKeyframe = false
        cachedVideoCodec = null
        outputSurface = null
    }

    /**
     * Mirrors SDK VideoDecoder.enqueue: parse NAL units, cache config, activate on the first keyframe (replaying the cached
     * config first), then queue each NAL with its offset into [buffer].
     */
    private fun enqueueNals(buffer: ByteBuffer, bytes: ByteArray, presentationTimeUs: Long) {
        var index = findNalUnit(bytes, 0)
        while (index < bytes.size) {
            val unitType = nalTypeAt(bytes, index)
            val isKeyFrame = isIrap(unitType)
            val isConfigFrame = isParamSet(unitType)
            if (isConfigFrame) {
                cachedVideoCodec = cloneByteBuffer(buffer)
            } else if (isKeyFrame) {
                if (!active) {
                    active = true
                    cachedVideoCodec?.let { enqueueNals(it, bytesOf(it), 0) }
                }
                receivedKeyframe = true
            }
            enqueueFrame(DecoderFrame(cloneByteBuffer(buffer), index, presentationTimeUs, isKeyFrame, isConfigFrame))
            index = findNalUnit(bytes, index + 1)
        }
    }

    // Mirrors SDK VideoDecoder's private enqueue(VideoFrame)
    private fun enqueueFrame(frame: DecoderFrame) {
        if (!active) return
        if (!frame.isConfigFrame && !receivedKeyframe) return
        if (firstInputFrame) {
            firstInputFrame = false
            activateDecoder()
        }
        if (incomingDataQueue.remainingCapacity() == 0) {
            Log.w(TAG, "Decoder queue full")
            active = false
            return
        }
        if (incomingDataQueue.offer(frame)) {
            // An input buffer may already be waiting for this frame.
            decoderHandler?.post(feedRunnable)
        }
    }

    // Prefer a software HEVC decoder
    private fun createHevcDecoder(): MediaCodec {
        val mime = MediaFormat.MIMETYPE_VIDEO_HEVC
        val softwareName = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
            .firstOrNull { info ->
                !info.isEncoder &&
                    info.isSoftwareOnly &&
                    info.name !in BLOCKED_DECODERS &&
                    info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
            }
            ?.name
        return if (softwareName != null) {
            Log.d(TAG, "Using software HEVC decoder: $softwareName")
            MediaCodec.createByCodecName(softwareName)
        } else {
            Log.w(TAG, "No software HEVC decoder found; using platform default")
            MediaCodec.createDecoderByType(mime)
        }
    }

    private fun activateDecoder() {
        try {
            if (decoder == null) decoder = createHevcDecoder()
            decoder?.let { codec ->
                decoderThread?.quit()
                val thread = HandlerThread("HevcDecoderThread", Process.THREAD_PRIORITY_VIDEO)
                thread.start()
                decoderThread = thread
                synchronized(availableInputBuffers) { availableInputBuffers.clear() }
                val handler = Handler(thread.looper)
                decoderHandler = handler

                codec.reset()
                codec.configure(mediaFormat, outputSurface, null, 0)
                codec.setCallback(
                    object : MediaCodec.Callback() {
                        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
                            synchronized(availableInputBuffers) { availableInputBuffers.addLast(index) }
                            feedInputBuffers()
                        }

                        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                            onOutputBuffer(codec, index, info)
                        }

                        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
                            Log.e(TAG, "Codec error: ${e.message}")
                        }

                        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {}
                    },
                    // Deliver MediaCodec callbacks on our own decoder thread.
                    handler
                )
                codec.start()
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Decoder activation exception: ${e.message}", e)
        }
    }

    /**
     * Pairs queued frames with free input buffers until either runs out, without ever waiting for
     * one. The codec delivers decoded output on this same thread, so blocking here would hold every
     * decoded frame back until the next frame arrived. Mirrors SDK AsyncFrameHandler.
     */
    private fun feedInputBuffers() {
        val codec = decoder ?: return
        while (true) {
            // stop() clears this before releasing the codec, which it does from another thread.
            if (decoderHandler == null) return
            val (index, frame) = synchronized(availableInputBuffers) {
                if (availableInputBuffers.isEmpty()) {
                    null
                } else {
                    incomingDataQueue.poll()?.let { availableInputBuffers.removeFirst() to it }
                }
            } ?: return
            submit(codec, index, frame)
        }
    }

    // Mirrors VideoDecoderBufferHandler.onInputBuffer — feeds ENTIRE buffer with offset
    private fun submit(codec: MediaCodec, index: Int, frame: DecoderFrame) {
        var bufferQueued = false
        try {
            val inputBuffer = codec.getInputBuffer(index)
            if (inputBuffer == null || !active) {
                codec.queueInputBuffer(index, 0, 0, 0, 0)
                bufferQueued = true
                return
            }
            frame.data.rewind()
            inputBuffer.clear()
            inputBuffer.put(frame.data)
            inputBuffer.flip()
            val clampedSize = minOf(frame.size, inputBuffer.limit() - frame.offset)
            codec.queueInputBuffer(index, frame.offset, clampedSize, frame.presentationTimeUs, frame.flags)
            bufferQueued = true
        } catch (e: Throwable) {
            Log.e(TAG, "Input buffer error: ${e.message}", e)
            if (active) active = false
        } finally {
            if (!bufferQueued) {
                try {
                    codec.queueInputBuffer(index, 0, 0, 0, 0)
                } catch (_: Throwable) {
                }
            }
        }
    }

    private fun onOutputBuffer(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
        try {
            // Render directly to the Surface — the GPU handles YUV→RGB conversion.
            codec.releaseOutputBuffer(index, active && info.size != 0)
        } catch (e: Throwable) {
            Log.e(TAG, "Output buffer error: ${e.message}", e)
            try {
                codec.releaseOutputBuffer(index, false)
            } catch (_: Throwable) {
            }
        }
    }
}

/** Index of the next 00 00 01 start code at or after [from], or the array size when there is none (or nothing follows it). */
private fun findNalUnit(data: ByteArray, from: Int): Int {
    var i = from
    while (i + 3 < data.size) {
        if (data[i].toInt() == 0 && data[i + 1].toInt() == 0 && data[i + 2].toInt() == 1) return i
        i++
    }
    return data.size
}

// The NAL header sits right after the 3-byte start code.
private fun nalTypeAt(data: ByteArray, offset: Int): Int = if (offset + 3 >= data.size) -1 else (data[offset + 3].toInt() and 0x7E) shr 1

private fun bytesOf(buffer: ByteBuffer): ByteArray = ByteArray(buffer.limit()).also {
    buffer.rewind()
    buffer.get(it)
    buffer.rewind()
}

private fun cloneByteBuffer(original: ByteBuffer): ByteBuffer {
    val clone = if (original.isDirect) ByteBuffer.allocateDirect(original.capacity()) else ByteBuffer.allocate(original.capacity())
    original.rewind()
    clone.put(original)
    original.rewind()
    clone.flip()
    return clone
}
