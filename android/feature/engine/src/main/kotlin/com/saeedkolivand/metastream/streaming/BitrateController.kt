package com.saeedkolivand.metastream.streaming

const val BITRATE_FLOOR_KBPS = 500
private const val COOLDOWN_MS = 3000L
private const val CLEAN_TICKS_FOR_UP = 15

/** iOS steppedBitrate: 20% down (floors at [floorKbps]), 10% up (ceilings at [ceilingKbps]). */
fun steppedBitrate(current: Int, up: Boolean, ceilingKbps: Int, floorKbps: Int): Int {
    val next = if (up) current + current / 10 else current - current / 5
    return next.coerceIn(floorKbps, ceilingKbps.coerceAtLeast(floorKbps))
}

/**
 * iOS cleanSecondsBeforeUp: climb back in 5 s steps while well below where the link last failed (a stall that collapses
 * the bitrate otherwise takes minutes of 15 s steps to undo); near or above it, probe slowly again.
 */
fun cleanSecondsBeforeUp(current: Int, failedAt: Int) = if (current < failedAt * 4 / 5) 5 else CLEAN_TICKS_FOR_UP

/** Why the controller moved the bitrate, in the words the NETWORK panel shows. */
enum class Why(val text: String) {
    Congested("network backed up"),
    Slow("upload slower than target"),
    Stable("stable, raising"),
    Hot("phone hot")
}

/**
 * Port of iOS adaptBitrate/stepBitrate: an AIMD loop ticked once a second. No I/O; [tick] and [thermal] return the new
 * bitrate to apply, or null when nothing changes. [ceilingKbps] is the configured bitrate.
 */
class BitrateController(private val ceilingKbps: Int, private val floorKbps: Int = BITRATE_FLOOR_KBPS) {
    var currentKbps = ceilingKbps
        private set

    /** Reason for the most recent non-null result of [tick] or [thermal]. */
    var why = Why.Congested
        private set
    private var cleanTicks = 0
    private var falling = false
    private var failedAtKbps = ceilingKbps
    private var lastAdjustMs: Long? = null
    private var thermalCeiling: Int? = null

    fun tick(nowMs: Long, congested: Boolean, throughputKbps: Long): Int? {
        if (congested) {
            cleanTicks = 0
            markFalling()
            why = Why.Congested
            return step(nowMs, false)
        }
        // Short of target by 30%+ (iOS rule); 0 means no sample yet, not a stall.
        if (throughputKbps in 1 until currentKbps * 7L / 10) {
            cleanTicks = 0
            markFalling()
            why = Why.Slow
            return step(nowMs, false)
        }
        if (++cleanTicks >= cleanSecondsBeforeUp(currentKbps, failedAtKbps)) {
            cleanTicks = 0
            falling = false
            why = Why.Stable
            return step(nowMs, true)
        }
        return null
    }

    /** The first down-step of a run remembers where the link gave out; the rest of the run keeps it. */
    private fun markFalling() {
        if (!falling) failedAtKbps = currentKbps
        falling = true
    }

    /** Serious heat forces one step down and caps the ceiling there until it clears (edge-triggered like iOS). */
    fun thermal(nowMs: Long, serious: Boolean): Int? {
        if (!serious) {
            thermalCeiling = null
            return null
        }
        if (thermalCeiling != null) return null
        thermalCeiling = currentKbps
        why = Why.Hot
        val next = step(nowMs, false)
        thermalCeiling = currentKbps
        return next
    }

    private fun step(nowMs: Long, up: Boolean): Int? {
        if (lastAdjustMs?.let { nowMs - it < COOLDOWN_MS } == true) return null
        val ceiling = minOf(thermalCeiling ?: ceilingKbps, ceilingKbps)
        val next = steppedBitrate(currentKbps, up, ceiling, floorKbps)
        if (next == currentKbps) return null
        currentKbps = next
        lastAdjustMs = nowMs
        return next
    }
}
