package com.saeedkolivand.metastream.core

import android.content.Context
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import java.io.File
import java.io.FileOutputStream
import java.io.Writer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Stream key plus every OAuth token seen this process; insertion-ordered so the oldest can be dropped at the cap.
private val secrets = LinkedHashSet<String>()

/** A value (stream key, access/refresh token) to scrub from every later log line. */
fun redactFromLogs(value: String) {
    if (value.length < 6) return // too short to be a secret, and replacing it would mangle ordinary words
    synchronized(secrets) {
        secrets.add(value)
        if (secrets.size > 64) secrets.remove(secrets.first()) // tokens refresh hourly; never grows without bound
    }
}

/** Fixed-size ring of log lines; the oldest drop first. Thread-safe. */
class LogRing(private val capacity: Int) {
    private val lines = ArrayDeque<String>()

    @Synchronized
    fun add(line: String) {
        if (lines.size == capacity) lines.removeFirst()
        lines.addLast(line)
    }

    @Synchronized
    fun snapshot(): List<String> = lines.toList()
}

/** In-app copy of the applog lines (already redacted) for the Logs screen. [version] bumps so Compose can re-read. */
object LogBuffer {
    private val ring = LogRing(500)
    var version by mutableIntStateOf(0)
        private set

    fun add(line: String) {
        ring.add(line)
        version++
    }

    fun lines() = ring.snapshot()
}

private const val LOG_FILE_MAX = 5_000_000L

/**
 * applog lines appended to <external files>/metastream.log, so a day's log survives restarts. Past 5 MB at launch it
 * moves to metastream.1.log (one previous file kept). Pull over USB:
 * `adb pull /sdcard/Android/data/com.saeedkolivand.metastream/files/metastream.log`
 */
object LogFile {
    private var out: Writer? = null

    @Synchronized
    fun start(context: Context) {
        if (out != null) return
        out = runCatching {
            val dir = context.getExternalFilesDir(null) ?: context.filesDir
            val f = File(dir, "metastream.log")
            if (f.length() > LOG_FILE_MAX) f.renameTo(File(dir, "metastream.1.log"))
            FileOutputStream(f, true).bufferedWriter().apply {
                write("=== launch ${Date()} ===\n")
                flush()
            }
        }.getOrNull()
    }

    @Synchronized
    fun add(line: String) {
        runCatching {
            out?.run {
                write(line)
                write("\n")
                flush()
            }
        }
    }
}

internal fun scrub(message: String): String = synchronized(secrets) { secrets.fold(message) { m, s -> m.replace(s, "***") } }

/** Same idea as iOS applog: one tag, a category, and secrets never reach the log (nor the shareable Logs screen). */
fun applog(category: String, message: String) {
    val safe = scrub(message)
    Log.i("MetaStream", "[$category] $safe")
    val line = "${SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())} [$category] $safe"
    LogBuffer.add(line)
    LogFile.add(line)
}
