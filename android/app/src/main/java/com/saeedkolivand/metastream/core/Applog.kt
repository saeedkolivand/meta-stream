package com.saeedkolivand.metastream.core

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Volatile
private var secret = ""

/** The stream key to scrub from every later log line. */
fun redactFromLogs(value: String) {
    secret = value
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

/** Same idea as iOS applog: one tag, a category, and the stream key never reaches the log. */
fun applog(category: String, message: String) {
    val s = secret
    val safe = if (s.isEmpty()) message else message.replace(s, "***")
    Log.i("MetaStream", "[$category] $safe")
    LogBuffer.add("${SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())} [$category] $safe")
}
