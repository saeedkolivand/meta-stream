package com.saeedkolivand.metastream.core

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
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

internal fun scrub(message: String): String = synchronized(secrets) { secrets.fold(message) { m, s -> m.replace(s, "***") } }

/** Same idea as iOS applog: one tag, a category, and secrets never reach the log (nor the shareable Logs screen). */
fun applog(category: String, message: String) {
    val safe = scrub(message)
    Log.i("MetaStream", "[$category] $safe")
    LogBuffer.add("${SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())} [$category] $safe")
}
