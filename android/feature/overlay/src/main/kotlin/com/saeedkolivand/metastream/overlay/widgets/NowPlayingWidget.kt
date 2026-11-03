package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.platforms.NowPlayingTrack
import com.saeedkolivand.metastream.platforms.Spotify
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val ART_WAIT_MS = 1200L

/**
 * The Now playing (Spotify) widget on the GPU (iOS NowPlayingPlayer / NowPlayingArt). A song change plays the old card
 * out and the new one in as one moving scene with each design's own motion (NowPlayingMotion, ported from iOS); between
 * changes the card is still, except the designs with bouncing bars or a spinning disc, which keep a moving scene. A still
 * card is re-shown only when the second, the bar's pixel width or the cover changes.
 */
fun nowPlayingWidget(l: Layer, box: Box, scope: CoroutineScope): WidgetBuild? {
    val style = NowPlayingStyle.from(l.data)
    if (box.w < 1f || box.h < 1f) return null
    val scale = box.w / style.natural.first
    val filter = SpriteFilter().place(box, l.rotation)
    val job = scope.launch {
        Spotify.retain()
        try {
            var shown: Pair<NowPlayingTrack, Bitmap?>? = null
            var openedAt = 0L
            var hidden = false
            var waiting: Long? = null
            var sig = ""
            val d = style.design
            val (w, h) = style.natural
            fun art(t: NowPlayingTrack, a: Bitmap?) = NowPlayingArt(style, t, a, scale)

            // One transition as a moving scene; the steady clock keeps the spin and the bars in phase across scenes.
            suspend fun play(old: NowPlayingArt?, new: NowPlayingArt?, seconds: Double, pose: (Double) -> NpPose) {
                val epoch = System.nanoTime()
                filter.show(
                    GpuScene(w, h, true, epoch) { t ->
                        val p = pose(t.toDouble())
                        (if (p.useNew) new ?: old else old ?: new)!!.items(p, epoch / 1e9 + t)
                    }
                )
                delay((seconds * 1000).toLong())
            }
            fun settled(a: NowPlayingArt) {
                val epoch = System.nanoTime()
                filter.show(GpuScene(w, h, NowPlayingMotion.continuous(d), epoch) { t -> a.items(NpPose(), epoch / 1e9 + t) })
            }
            while (isActive) {
                val now = System.currentTimeMillis()
                val live = Spotify.track
                val cur = shown
                if (live == null && cur != null) {
                    if (!hidden) {
                        art(cur.first, cur.second).let {
                            play(it, null, NowPlayingMotion.exitTotal(d)) { t -> NowPlayingMotion.exit(d, t) }
                        }
                    }
                    filter.show(null)
                    shown = null
                    hidden = false
                    sig = ""
                } else if (live != null && live.id != cur?.first?.id) {
                    waiting = waiting ?: now
                    if (Spotify.art != null || now - waiting > ART_WAIT_MS) {
                        waiting = null
                        val next = art(live, Spotify.art)
                        applog("overlay", "now playing widget: $d ${live.title}")
                        if (cur != null && !hidden) {
                            play(art(cur.first, cur.second), next, NowPlayingMotion.total(d)) { t -> NowPlayingMotion.change(d, t) }
                        } else {
                            play(null, next, NowPlayingMotion.enterTotal(d)) { t -> NowPlayingMotion.enter(d, t) }
                        }
                        shown = live to Spotify.art
                        openedAt = now
                        hidden = false
                        sig = ""
                    }
                } else if (live != null && cur != null) {
                    if (cur.second == null && Spotify.art != null) sig = ""
                    shown = live to (cur.second ?: Spotify.art)
                    if (style.design == "popup" && !hidden && now - openedAt > style.popupSeconds * 1000L) {
                        play(art(live, shown.second), null, NowPlayingMotion.exitTotal(d)) { t -> NowPlayingMotion.exit(d, t) }
                        filter.show(null)
                        hidden = true
                    }
                    val next =
                        "${live.id}|${shown.second != null}|${if (style.design == "slab" || style.design == "disc") {
                            live.elapsedMs(
                                now
                            ) / 1000
                        } else {
                            0
                        }}|" +
                            (live.progress(now) * box.w).toInt()
                    if (!hidden && next != sig) {
                        sig = next
                        settled(art(live, shown.second))
                    }
                }
                delay(250)
            }
        } finally {
            Spotify.release()
        }
    }
    return WidgetBuild(filter, job)
}
