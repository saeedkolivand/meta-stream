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
 * Port of iOS adaptBitrate/stepBitrate: an AIMD loop ticked once a second. No I/O; [tick] and [thermal] return the new
 * bitrate to apply, or null when nothing changes. [ceilingKbps] is the configured bitrate.
 */
class BitrateController(private val ceilingKbps: Int, private val floorKbps: Int = BITRATE_FLOOR_KBPS) {
    var currentKbps = ceilingKbps
        private set
    private var cleanTicks = 0
    private var lastAdjustMs: Long? = null
    private var thermalCeiling: Int? = null

    fun tick(nowMs: Long, congested: Boolean, throughputKbps: Long): Int? {
        if (congested) {
            cleanTicks = 0
            return step(nowMs, false)
        }
        // Short of target by 30%+ (iOS rule); 0 means no sample yet, not a stall.
        if (throughputKbps in 1 until currentKbps * 7L / 10) {
            cleanTicks = 0
            return step(nowMs, false)
        }
        if (++cleanTicks >= CLEAN_TICKS_FOR_UP) {
            cleanTicks = 0
            return step(nowMs, true)
        }
        return null
    }

    /** Serious heat forces one step down and caps the ceiling there until it clears (edge-triggered like iOS). */
    fun thermal(nowMs: Long, serious: Boolean): Int? {
        if (!serious) {
            thermalCeiling = null
            return null
        }
        if (thermalCeiling != null) return null
        thermalCeiling = currentKbps
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
