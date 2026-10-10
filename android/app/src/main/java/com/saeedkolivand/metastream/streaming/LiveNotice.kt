package com.saeedkolivand.metastream.streaming

/** What the live notification shows; [chip] is the status-bar text, [chronometerSince] (epoch ms) the counting-up chip instead. */
internal data class LiveNotice(val title: String, val text: String, val chip: String?, val chronometerSince: Long?, val muteLabel: String)

/** [status] is "<state> · <bitrate>" while streaming, so the bitrate is its tail; drops aren't tracked, so they're omitted. */
internal fun liveNotice(source: Source, status: String, connected: Boolean, liveSince: Long?, muted: Boolean) = LiveNotice(
    // liveSince is set on the first successful connect, so "down and never up" is the initial connect, not a retry.
    title = when {
        connected -> "LIVE"
        liveSince == null -> "CONNECTING"
        else -> "RECONNECTING"
    } + " · ${source.name}",
    text = status.substringAfter(" · ", status),
    chip = if (connected || liveSince == null) null else "RETRY",
    chronometerSince = if (connected) liveSince else null,
    muteLabel = if (muted) "Unmute" else "Mute"
)
