package com.saeedkolivand.metastream.core

import android.util.Log

@Volatile
private var secret = ""

/** The stream key to scrub from every later log line. */
fun redactFromLogs(value: String) {
    secret = value
}

/** Same idea as iOS applog: one tag, a category, and the stream key never reaches the log. */
fun applog(category: String, message: String) {
    val s = secret
    val safe = if (s.isEmpty()) message else message.replace(s, "***")
    Log.i("MetaStream", "[$category] $safe")
}
