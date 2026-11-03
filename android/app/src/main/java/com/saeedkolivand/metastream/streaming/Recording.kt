package com.saeedkolivand.metastream.streaming

import android.content.ContentValues
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.pedro.library.base.recording.RecordController
import com.pedro.library.generic.GenericStream
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.speech.Speaker
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Local recording, independent of going live: it writes whatever the encoder is producing (composited picture + mic)
 * to app storage, then moves the finished file into the gallery on stop.
 */
object Recording {
    var since by mutableStateOf<Long?>(null)
        private set

    private var stream: GenericStream? = null
    private var path: File? = null

    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val main = Handler(Looper.getMainLooper())

    fun toggle() {
        if (since == null) start() else stop()
    }

    fun start() {
        if (since != null) return
        if (Engine.source == Source.Glasses) {
            // ponytail: glasses HEVC passthrough bypasses the encoder, so a recording would have no video.
            applog("stream", "recording refused: glasses passthrough has no video")
            Speaker.speakSystem("Recording needs the phone camera")
            return
        }
        val s = Engine.recorder()
        if (s == null) {
            applog("stream", "recording refused: stream not ready")
            return
        }
        // Holds the camera+mic foreground service so the recording survives the app going to the background (not live).
        if (!StreamingService.hold(Engine.appContext, "record")) {
            applog("stream", "recording refused: foreground service not allowed")
            return
        }
        // filesDir, not cacheDir: a failed gallery save keeps the file, and Android may purge the cache.
        val dir = File(Engine.appContext.filesDir, "recordings").apply { mkdirs() }
        val file = File(dir, "MetaStream-${SimpleDateFormat("yyyy-MM-dd-HHmmss", Locale.US).format(Date())}.mp4")
        stream = s
        path = file
        try {
            s.startRecord(
                file.absolutePath,
                listener = object : RecordController.Listener {
                    override fun onStatusChange(status: RecordController.Status) {}

                    override fun onError(e: Exception?) {
                        applog("stream", "recording error: $e")
                        main.post { if (stream === s) stop() } // the muxer thread must not stop itself
                    }
                }
            )
            since = System.currentTimeMillis()
            applog("stream", "recording started ${file.name}")
        } catch (e: Exception) {
            stream = null
            path = null
            file.delete()
            StreamingService.release(Engine.appContext, "record")
            applog("stream", "recording start failed: $e")
        }
    }

    fun stop() {
        val s = stream ?: return
        val file = path
        var wasRecording = false
        try {
            wasRecording = s.isRecording
            if (wasRecording) s.stopRecord() // finalises the file before it is copied
        } catch (e: Exception) {
            applog("stream", "recording stop failed: $e")
        }
        stream = null
        path = null
        since = null
        StreamingService.release(Engine.appContext, "record")
        if (wasRecording && file != null) {
            applog("stream", "recording stopped ${file.name}")
            io.launch {
                if (save(file)) main.post { Speaker.speakSystem("Recording saved") }
            }
        }
    }

    /** Called when the source changes to Glasses: passthrough leaves the file without video, so end it here. */
    fun checkSource() {
        if (since == null || Engine.source != Source.Glasses) return
        Speaker.speakSystem("Recording stopped: glasses passthrough can't be recorded")
        stop()
    }

    /** Copies [file] into Movies/MetaStream and drops the cache copy; a failure keeps the file where it is. */
    private fun save(file: File): Boolean {
        val resolver = Engine.appContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/MetaStream")
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        return try {
            val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                ?: error("MediaStore insert failed")
            resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                ?: error("MediaStore open failed")
            resolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
            file.delete()
            applog("stream", "recording saved ${file.name}")
            true
        } catch (e: Exception) {
            applog("stream", "recording save failed, file kept at ${file.absolutePath}: $e")
            false
        }
    }
}
