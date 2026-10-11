package com.saeedkolivand.metastream.core

import android.util.Log

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

internal fun scrub(message: String): String = synchronized(secrets) { secrets.fold(message) { m, s -> m.replace(s, "***") } }

/** Same idea as iOS applog: one tag, a category, and secrets never reach the log. */
fun applog(category: String, message: String) {
    Log.i("MetaStream", "[$category] ${scrub(message)}")
}
