package com.saeedkolivand.metastream.car

import com.saeedkolivand.metastream.streaming.Source

/** The first row of the car screen; while live, [status] is "<state> · <bitrate>" and only the bitrate part is shown. */
internal fun carStatusText(live: Boolean, status: String, source: Source): String = when {
    live -> "LIVE · ${status.substringAfter(" · ", status)} · ${source.name}"
    status == "idle" -> "Offline"
    else -> "Offline · $status"
}
