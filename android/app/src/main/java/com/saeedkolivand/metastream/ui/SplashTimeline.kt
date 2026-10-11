package com.saeedkolivand.metastream.ui

import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin

/** Linear 0..1 progress of the segment [start, start + dur] at time [t] (ms), clamped. */
internal fun segment(t: Float, start: Float, dur: Float): Float = ((t - start) / dur).coerceIn(0f, 1f)

internal fun easeOut(x: Float): Float = 1f - (1f - x).pow(3)

internal fun easeIn(x: Float): Float = x * x * x

/** Eased progress of a segment; ease-out by default. */
internal fun eased(t: Float, start: Float, dur: Float, ease: (Float) -> Float = ::easeOut): Float = ease(segment(t, start, dur))

/** Overshooting pop (peaks about 1.15) for the dot. */
internal fun pop(x: Float): Float {
    val c = 2.5f
    return 1f + (c + 1f) * (x - 1f).pow(3) + c * (x - 1f).pow(2)
}

/** Heartbeat scale 1 -> 1.12 -> 1 over [dur] ms starting at [start]. */
internal fun beat(t: Float, start: Float, dur: Float): Float = 1f + 0.12f * sin(PI.toFloat() * segment(t, start, dur))
