package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.Kind
import java.util.Locale
import kotlin.math.pow
import kotlin.math.roundToInt

// Seconds from the start of an alert; the same numbers drive the iOS banner.
internal const val ALERT_ENTER_END = 0.77f
internal const val ALERT_EXIT = 0.5f
internal const val ALERT_OPENED = 0.62f // the capsule is fully open; the big-tier flash starts here
private const val FLASH_SECONDS = 1.1f
private const val FLASH_ALPHA = 0.9f
private const val AMOUNT_START = 0.45f
private const val AMOUNT_END = 1.55f
private const val RISE_UNITS = 16f

/** Past this the picture is static until the exit (flash and count-up are done, with room for a slow thermal frame). */
internal const val ALERT_MOTION_END = 1.85f

/** Everything the banner draws at one instant. [done] is true once the exit has finished. */
internal data class AlertFrame(
    val drop: Float, // 0 = above the box, 1 = at rest
    val open: Float, // 0 = dot, 1 = full width, a little above 1 while it overshoots
    val contentAlpha: Float,
    val rise: Float, // units the content still has to climb
    val amount: Float, // count-up progress 0..1
    val flash: Float, // opacity of the event-colour flash, 0..0.9
    val away: Float, // 0..1 progress of the dot rising off the top
    val alpha: Float, // whole-banner opacity, below 1 only while the dot fades away
    val done: Boolean
)

private fun clamp01(x: Float) = x.coerceIn(0f, 1f)
private fun span(t: Float, from: Float, to: Float) = clamp01((t - from) / (to - from))
private fun easeOut(x: Float) = 1f - (1f - x).pow(3)
private fun easeInOut(x: Float) = x * x * (3f - 2f * x)
private fun easeOutBack(x: Float): Float {
    val c = 1.2f
    return 1f + (c + 1f) * (x - 1f).pow(3) + c * (x - 1f).pow(2)
}

/** Seconds at which the exit starts for an alert held [hold] seconds. */
internal fun alertExitAt(hold: Float) = ALERT_ENTER_END + hold

internal fun alertFrame(t: Float, hold: Float): AlertFrame {
    val u = t - alertExitAt(hold)
    val enter = easeOutBack(span(t, 0.28f, ALERT_OPENED))
    val content = easeOut(span(t, 0.42f, ALERT_ENTER_END))
    val away = easeOut(span(u, 0.28f, ALERT_EXIT))
    return AlertFrame(
        drop = easeOut(span(t, 0f, 0.28f)),
        open = if (u > 0f) 1f - easeInOut(span(u, 0f, 0.28f)) else enter,
        contentAlpha = if (u > 0f) 1f - span(u, 0f, 0.15f) else content,
        rise = RISE_UNITS * (1f - content),
        amount = easeOut(span(t, AMOUNT_START, AMOUNT_END)),
        flash = FLASH_ALPHA * (1f - span(t, ALERT_OPENED, ALERT_OPENED + FLASH_SECONDS)) * (if (t < ALERT_OPENED) 0f else 1f),
        away = away,
        alpha = 1f - span(u, 0.28f, ALERT_EXIT),
        done = u >= ALERT_EXIT
    )
}

internal fun alertColor(e: ChatEvent, accent: Int): Int = when (e.kind) {
    Kind.Follow -> 0xFFD9D9E3.toInt()
    Kind.Subscribe -> accent
    Kind.Tip -> 0xFF20C56C.toInt()
    Kind.Cheer -> 0xFFFF4FA3.toInt()
    Kind.Raid -> 0xFFFF7A2F.toInt()
    Kind.Message -> accent
}

internal fun alertLabel(e: ChatEvent) = when (e.kind) {
    Kind.Follow -> "NEW FOLLOWER"
    Kind.Subscribe -> "NEW SUBSCRIBER"
    Kind.Tip -> "TIP"
    Kind.Cheer -> "BITS"
    Kind.Raid -> "RAID"
    Kind.Message -> ""
}

internal fun alertIsBig(e: ChatEvent) = (e.kind == Kind.Tip && e.amountCents >= 1000) || (e.kind == Kind.Raid && e.count >= 50)

/** The right-hand amount at count-up [progress] (1 = final); empty for follows and subs. */
internal fun alertAmount(e: ChatEvent, progress: Float = 1f): String = when (e.kind) {
    Kind.Tip -> (e.amountCents * progress).roundToInt().let {
        if (it % 100 == 0) "$${it / 100}" else "$" + String.format(Locale.US, "%.2f", it / 100.0)
    }
    Kind.Cheer -> "${(e.count * progress).roundToInt()} bits"
    Kind.Raid -> "${(e.count * progress).roundToInt()} viewers"
    else -> ""
}
