package com.saeedkolivand.metastream.core

enum class Lock { Auto, Portrait, Landscape }

/** Ingest options with the iOS defaults (720p, 30 fps, 4000 kbps, SRT buffer 2000 ms); H.264 is iOS's "Auto" for Kick/Twitch. */
data class IngestConfig(
    val height: Int = 720,
    val fps: Int = 30,
    val bitrateKbps: Int = 4000,
    val h265: Boolean = false,
    val lock: Lock = Lock.Auto,
    val srtLatencyMs: Int = 2000
)

/** What RootEncoder's prepareVideo needs; [width] x [height] is the landscape size, rotation 90 flips it to portrait output. */
data class VideoParams(val width: Int, val height: Int, val rotation: Int, val bitrate: Int, val fps: Int, val portrait: Boolean) {
    val outW get() = if (portrait) height else width
    val outH get() = if (portrait) width else height
}

val RESOLUTIONS = listOf(480, 720, 1080)
val FPS_CHOICES = listOf(24, 30, 60)
const val MIN_KBPS = 1000
const val MAX_KBPS = 9000
const val KBPS_STEP = 250

private fun longSide(height: Int) = when (height) {
    480 -> 854
    1080 -> 1920
    else -> 1280
}

/** The lock wins; Auto follows how the phone is held when going live (the existing behaviour). */
fun IngestConfig.toVideoParams(devicePortrait: Boolean): VideoParams {
    val portrait = when (lock) {
        Lock.Portrait -> true
        Lock.Landscape -> false
        Lock.Auto -> devicePortrait
    }
    return VideoParams(longSide(height), height, if (portrait) 90 else 0, bitrateKbps * 1000, fps, portrait)
}

/** Snaps a slider value to the step grid and the allowed range. */
fun snapKbps(v: Int) = (v / KBPS_STEP * KBPS_STEP).coerceIn(MIN_KBPS, MAX_KBPS)
