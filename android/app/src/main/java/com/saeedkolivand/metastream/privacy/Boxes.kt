package com.saeedkolivand.metastream.privacy

import kotlin.math.max
import kotlin.math.min

/** Normalized (0..1) rectangle, origin top-left, y down. */
data class Box(val l: Float, val t: Float, val r: Float, val b: Float) {
    val w get() = r - l
    val h get() = b - t
    val area get() = max(0f, w) * max(0f, h)

    /** Grows by [f] of its own size on every side (iOS padFraction), clamped to the frame. */
    fun pad(f: Float) = Box(max(0f, l - w * f), max(0f, t - h * f), min(1f, r + w * f), min(1f, b + h * f))

    fun union(o: Box) = Box(min(l, o.l), min(t, o.t), max(r, o.r), max(b, o.b))

    fun overlap(o: Box) = max(0f, min(r, o.r) - max(l, o.l)) * max(0f, min(b, o.b) - max(t, o.t))
}

/**
 * ML Kit reports boxes in the upright image, i.e. after our bitmap is rotated clockwise by [rotation]; this undoes that rotation
 * so the box lands in the bitmap's own space (the space the blur shader works in).
 */
fun uprightToImage(box: Box, rotation: Int): Box = when (((rotation % 360) + 360) % 360) {
    90 -> Box(box.t, 1 - box.r, box.b, 1 - box.l)
    180 -> Box(1 - box.r, 1 - box.b, 1 - box.l, 1 - box.t)
    270 -> Box(1 - box.b, box.l, 1 - box.t, box.r)
    else -> box
}

/** Pixel rect in an image of [w] x [h] to normalized. */
fun normalize(left: Int, top: Int, right: Int, bottom: Int, w: Int, h: Int) =
    Box(left.toFloat() / w, top.toFloat() / h, right.toFloat() / w, bottom.toFloat() / h)

/** The shader samples with GL's bottom-left origin; our bitmap rows are top-down, so only y flips. */
fun toGl(box: Box) = Box(box.l, 1 - box.b, box.r, 1 - box.t)

/** At most [max] boxes: the largest stay, the rest merge into one so nothing is dropped (dropping would show a face). */
fun cap(boxes: List<Box>, max: Int): List<Box> {
    if (boxes.size <= max) return boxes
    val sorted = boxes.sortedByDescending { it.area }
    return sorted.take(max - 1) + sorted.drop(max - 1).reduce(Box::union)
}

/** Keeps each box for [holdMs] after it was last detected, so blur doesn't blink off for one missed pass. */
class BoxTracker(private val holdMs: Long = HOLD_MS, private val maxBoxes: Int = MAX_BOXES) {
    private class Held(val box: Box, val at: Long)

    private var held = emptyList<Held>()

    /** A fresh box that mostly covers an older one replaces it (the face moved); the rest age out. */
    fun update(fresh: List<Box>, now: Long) {
        val kept = held.filter { h ->
            now - h.at <= holdMs && fresh.none { it.overlap(h.box) >= SUPERSEDED * h.box.area }
        }
        held = kept + fresh.map { Held(it, now) }
    }

    fun active(now: Long): List<Box> = cap(held.filter { now - it.at <= holdMs }.map { it.box }, maxBoxes)

    fun clear() {
        held = emptyList()
    }

    companion object {
        const val HOLD_MS = 600L
        const val MAX_BOXES = 16
        private const val SUPERSEDED = 0.5f
    }
}

/** iOS: detection older than 3 s counts as stalled; until the first result there is nothing to trust, so also blur everything. */
object Stall {
    const val THRESHOLD_MS = 3000L

    /** [lastOk] is the last good detection (0 = none yet), [armedAt] when blur started, so a detector that never answers also stalls. */
    fun stalled(now: Long, lastOk: Long, armedAt: Long) = now - max(lastOk, armedAt) > THRESHOLD_MS

    fun blurAll(now: Long, lastOk: Long, armedAt: Long) = lastOk <= 0 || stalled(now, lastOk, armedAt)
}
