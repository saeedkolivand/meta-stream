package com.saeedkolivand.metastream.overlay.widgets.alert

import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.offensive
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import com.saeedkolivand.metastream.overlay.AlertStyle
import com.saeedkolivand.metastream.overlay.Box
import com.saeedkolivand.metastream.overlay.Layer
import com.saeedkolivand.metastream.overlay.SpriteFilter
import com.saeedkolivand.metastream.overlay.WidgetBuild
import com.saeedkolivand.metastream.overlay.donationScene
import com.saeedkolivand.metastream.overlay.donationSeconds
import com.saeedkolivand.metastream.streaming.audio.AudioMix
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val QUEUE_CAP = 20
private const val GAP_MS = 300L

/**
 * Queues follow/sub/raid/tip/cheer events and shows each in turn. Starts from the newest id so a scene switch never replays
 * old follows. The alert's bitmaps are baked once; the GPU runs the motion, the CPU wakes three times per alert.
 */
fun alertWidget(l: Layer, box: Box, outW: Int, outH: Int, scope: CoroutineScope): WidgetBuild? {
    val style = AlertStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val scale = box.w / BOX_W
    val hold = style.holdSeconds.toFloat()
    val exitAt = alertExitAt(hold)
    val filter = SpriteFilter().place(box, l.rotation)
    val job = scope.launch {
        var seen = ChatFeed.chat.value.lastOrNull()?.id ?: 0L
        val queue = ArrayDeque<ChatEvent>()
        while (isActive) {
            val fresh = ChatFeed.chat.value.filter { it.id > seen }
            if (fresh.isNotEmpty()) seen = fresh.last().id
            queue += fresh.filter { style.shows(it.kind) && !it.offensive }
            while (queue.size > QUEUE_CAP) queue.removeFirst() // a raid train shouldn't queue minutes of banners
            val next = queue.removeFirstOrNull()
            if (next == null) {
                ChatFeed.chat.first { (it.lastOrNull()?.id ?: 0L) > seen }
                continue
            }
            if (next.kind == Kind.Tip || next.kind == Kind.Cheer) {
                donationScene(next, style, outW, outH, box)?.let {
                    AudioMix.playAlert()
                    filter.show(it) // one moving scene over the whole picture for the board's loop
                    delay((donationSeconds(style) * 1000).toLong())
                    filter.show(null)
                    delay(GAP_MS)
                    continue
                }
            }
            val art = alertGpu(next, style, scale, hold)
            AudioMix.playAlert() // into the mix with the banner; ignored unless live
            val start = System.nanoTime()
            val moving = art.scene(start, moving = true)
            // The GPU animates the entry and the exit from one time origin; the CPU only swaps scenes at the phase edges.
            filter.show(moving)
            if (exitAt > ALERT_MOTION_END) {
                delay((ALERT_MOTION_END * 1000).toLong())
                filter.show(art.scene(start, moving = false)) // the hold: one still scene, nothing evaluated per frame
                delay(((exitAt - ALERT_MOTION_END) * 1000).toLong())
                filter.show(moving)
                delay(((ALERT_EXIT + 0.05f) * 1000).toLong())
            } else {
                delay(((exitAt + ALERT_EXIT + 0.05f) * 1000).toLong()) // a hold too short to settle: one moving scene
            }
            filter.show(null)
            delay(GAP_MS)
        }
    }
    return WidgetBuild(filter, job)
}
