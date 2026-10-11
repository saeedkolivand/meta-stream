package com.saeedkolivand.metastream.ui

import kotlin.math.pow

/** Linear 0..1 progress of the segment [start, start + dur] at time [t] (ms), clamped. */
internal fun segment(t: Float, start: Float, dur: Float): Float = ((t - start) / dur).coerceIn(0f, 1f)

internal fun easeOut(x: Float): Float = 1f - (1f - x).pow(3)

internal fun easeInOutCubic(x: Float): Float = if (x < 0.5f) 4f * x * x * x else 1f - (-2f * x + 2f).pow(3) / 2f

/** Ease-out progress of a segment. */
internal fun eased(t: Float, start: Float, dur: Float): Float = easeOut(segment(t, start, dur))

/** LED bloom alpha: rises to 0.9 by 350 ms, then settles to 0.65 by 600 ms. */
internal fun bloom(t: Float): Float = 0.9f * eased(t, 100f, 250f) - 0.25f * eased(t, 350f, 250f)
