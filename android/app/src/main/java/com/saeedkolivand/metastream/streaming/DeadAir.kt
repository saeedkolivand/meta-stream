package com.saeedkolivand.metastream.streaming

import com.saeedkolivand.metastream.core.applog

/** Seconds into a dead-air alert at which it's spoken again (iOS Speaker's startRepeating: 30 s, 60 s, 2 min). */
private val REPEATS = longArrayOf(30, 60, 120)

/**
 * iOS HealthMonitor.checkDeadAir: "No audio on stream" once the mix has been under -50 dBFS for 20 s while live and
 * unmuted. Driven by Health's 1 s loop, not by the level reports, so a mic that delivers no buffers counts as silence.
 */
internal object DeadAir {
    private var quietSince: Long? = null
    private var alertSince: Long? = null
    private var repeat = 0

    fun tick(now: Long, speak: (String) -> Unit) {
        // Glasses passthrough audio never reaches the phone's mic hook, so its level is unknown, not silent.
        val live = Engine.live && Engine.source != Source.Glasses
        val (since, alert) = AudioMath.deadAir(quietSince, AudioMix.level(staleMs = 2000), now, live, Engine.muted)
        quietSince = since
        val started = alertSince
        when {
            alert && started == null -> {
                alertSince = now
                repeat = 0
                applog("stream", "dead air: mix silent for ${AudioMath.DEAD_AIR_MS / 1000} s")
                speak("No audio on stream")
            }
            alert && started != null && repeat < REPEATS.size && (now - started) / 1000 >= REPEATS[repeat] -> {
                repeat++
                speak("No audio on stream")
            }
            !alert && started != null -> {
                alertSince = null
                applog("stream", "dead air cleared")
                if (live && !Engine.muted) speak("Audio is back")
            }
        }
    }

    /** On stop live: forget the quiet stretch without announcing anything. */
    fun reset() {
        quietSince = null
        alertSince = null
    }
}
