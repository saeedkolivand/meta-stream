package com.saeedkolivand.metastream.reach

import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.model.Money
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.storage.TokenStore
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.overlay.Overlays
import com.saeedkolivand.metastream.overlay.SceneRoles
import com.saeedkolivand.metastream.overlay.WidgetLocation
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.platforms.YouTube
import com.saeedkolivand.metastream.privacy.Privacy
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Health
import com.saeedkolivand.metastream.streaming.uplink.NetStats
import java.io.ByteArrayOutputStream
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject

/**
 * The Live post (iOS LivePost): the one Telegram channel message a stream session owns. Announced before the stream
 * (optional), adopted on go-live, refreshed while live (text every 60 s, a frame every 5 min), turned into the recap at the
 * end. Moment pings reply to it (at most 1 per 15 min, 4 per stream) and are deleted at the end. Network jobs run one at a
 * time in order. Main thread.
 */
object LivePost {
    private class State(val messageId: Long, var phase: String, val announcedAt: Long?, var hasPhoto: Boolean, val pings: MutableList<Long>)

    var phase by mutableStateOf<String?>(null) // "announced" | "live"
        private set
    private var state: State? = null
        set(v) {
            field = v
            phase = v?.phase
            Prefs.put(
                "livePost",
                v?.let {
                    JSONObject().put(
                        "id",
                        it.messageId
                    ).put(
                        "phase",
                        it.phase
                    ).put("at", it.announcedAt).put("photo", it.hasPhoto).put("pings", JSONArray(it.pings)).toString()
                }.orEmpty()
            )
        }
    private val jobs = Channel<suspend () -> Unit>(Channel.UNLIMITED)
    private var queued = 0
    private var closing = false
    private var lastEdit = 0L
    private var lastPhoto = 0L
    private var lastPing = 0L
    private var handledMoments = 0
    private lateinit var scope: CoroutineScope

    private val lang get() = if (Prefs.string("telegramLang", "fa") == "en") "en" else "fa"
    val enabled get() = Prefs.bool("telegramOn", false) &&
        Prefs.string("telegramChannel", "").isNotBlank() &&
        TokenStore.get("telegramToken") != null
    private val slug get() = Prefs.string("chatChannel", "").trim().ifEmpty { Kick.user.lowercase() }
    private val viewers get() = Kick.viewers + Twitch.viewers + YouTube.viewers

    /** Once from the App: restores a saved post, then follows go-live / end and ticks every second. */
    fun start(scope: CoroutineScope) {
        this.scope = scope
        state = runCatching {
            val o = JSONObject(Prefs.string("livePost", ""))
            val p = o.optJSONArray("pings") ?: JSONArray()
            State(
                o.getLong("id"),
                o.getString("phase"),
                if (o.isNull("at")) null else o.optLong("at"),
                o.optBoolean("photo"),
                MutableList(p.length()) {
                    p.getLong(it)
                }
            )
        }.getOrNull()
        scope.launch {
            for (job in jobs) {
                runCatching { job() }.onFailure(::fail)
                queued--
            }
        }
        resume()
        scope.launch {
            var wasLive = Engine.live
            snapshotFlow { Engine.live }.collect { live ->
                if (live == wasLive) return@collect
                wasLive = live
                if (live) {
                    SessionLog.begin(Kick.title)
                    sessionStarted()
                } else {
                    sessionEnded(SessionLog.end())
                }
            }
        }
        scope.launch {
            while (true) {
                delay(1000)
                second()
            }
        }
    }

    // before the stream

    fun announce() {
        if (!enabled || state != null || queued > 0) return
        val text = LivePostText.announce(Kick.title, slug, lang, LivePostText::stored)
        enqueue {
            state =
                State(Telegram.sendMessage(LivePostText.fit(text, false)), "announced", System.currentTimeMillis(), false, mutableListOf())
        }
    }

    fun cancelAnnouncement() {
        val st = state?.takeIf { it.phase == "announced" } ?: return
        state = null
        val text = LivePostText.cancelled(lang, LivePostText::stored)
        enqueue { Telegram.editText(st.messageId, text) }
    }

    // during the stream

    private fun sessionStarted() {
        if (!enabled) return
        closing = false
        handledMoments = 0
        lastPing = 0
        val text = LivePostText.live(liveInput(), lang, LivePostText::stored)
        enqueue {
            val st = state
            if (st != null && st.phase == "announced") {
                st.phase = "live"
                state = st
                push(text)
            } else {
                state = State(Telegram.sendMessage(LivePostText.fit(text, false)), "live", null, false, mutableListOf())
            }
            lastEdit = System.currentTimeMillis()
            lastPhoto = lastEdit
            grab()?.let { push(text, it) }
        }
    }

    private fun second() {
        if (!Engine.live) {
            val st = state ?: return
            if (st.phase == "announced" && System.currentTimeMillis() - (st.announcedAt ?: 0) > 3_600_000) cancelAnnouncement()
            return
        }
        val now = System.currentTimeMillis()
        SessionLog.tick(viewers, Health.kbps, NetStats.drops, (NetStats.downtimeMs(now) / 1000).toInt())
        pingNewMoments()
        tick(now)
    }

    /** A Moment found since the last look gets a reply, unless one went out in the last 15 min or 4 already have (dropped, never queued). */
    private fun pingNewMoments() {
        val st = state?.takeIf { it.phase == "live" && !closing } ?: return
        val moments = SessionLog.current?.moments ?: return
        if (moments.size <= handledMoments) return
        val m = moments[handledMoments]
        handledMoments = moments.size
        val now = System.currentTimeMillis()
        if (!Prefs.bool("telegramPings", true) || st.pings.size >= 4 || now - lastPing < 900_000) return
        lastPing = now
        val text = LivePostText.ping(m, slug, lang, LivePostText::stored)
        enqueue {
            val id = Telegram.sendMessage(text, st.messageId)
            if (state?.messageId != st.messageId) runCatching { Telegram.deleteMessage(id) } else state = state?.also { it.pings += id }
        }
    }

    /** Text every 60 s; a frame every 5 min (every 15 s until the first works). While the link is down the last photo stays. */
    private fun tick(now: Long) {
        val st = state?.takeIf { it.phase == "live" && !closing && queued == 0 } ?: return
        val wantPhoto = NetStats.connectedSince != null && now - lastPhoto >= if (st.hasPhoto) 300_000 else 15_000
        val textDue = now - lastEdit >= 60_000
        if (!wantPhoto && !textDue) return
        if (textDue) lastEdit = now
        if (wantPhoto) lastPhoto = now
        val text = LivePostText.live(liveInput(), lang, LivePostText::stored)
        enqueue {
            val jpeg = if (wantPhoto) grab() else null
            if (jpeg != null || textDue) push(text, jpeg)
        }
    }

    /** The post becomes the recap and keeps the last live photo (a fresh grab now could publish an unblurred frame). */
    private fun sessionEnded(rec: SessionRecord?) {
        if (state == null) return
        closing = true
        val text = rec?.let { LivePostText.recap(recapInput(it), lang, LivePostText::stored) } ?: LivePostText.endedBare(lang)
        enqueue {
            val pings = state?.pings.orEmpty().toList()
            try {
                closeOut(pings) { push(text) }
            } finally {
                state = null
            }
        }
    }

    /** At launch: an old announcement is withdrawn; a post still saying live belongs to a session that died with the app. */
    private fun resume() {
        val st = state ?: return
        if (st.phase == "announced") return
        state = null
        val text = LivePostText.endedBare(lang)
        enqueue { closeOut(st.pings) { edit(text, st.messageId, st.hasPhoto) } }
    }

    private suspend fun closeOut(pings: List<Long>, work: suspend () -> Unit) {
        val failure = runCatching { work() }.exceptionOrNull()
        for (id in pings) {
            runCatching {
                Telegram.deleteMessage(id)
            }.onFailure { if (!Telegram.isGone(it)) applog("telegram", "ping delete: ${it.message}") }
        }
        failure?.let { throw it }
    }

    // sending

    private fun enqueue(job: suspend () -> Unit) {
        queued++
        jobs.trySend(job)
    }

    private fun fail(e: Throwable) {
        if (Telegram.isGone(e)) state = null else applog("telegram", "live post: ${e.message}")
    }

    private suspend fun push(text: String, jpeg: ByteArray? = null) {
        val st = state ?: return
        edit(text, st.messageId, st.hasPhoto, jpeg)
        if (jpeg != null && state?.messageId == st.messageId) state = state?.also { it.hasPhoto = true }
    }

    private suspend fun edit(text: String, id: Long, photo: Boolean, jpeg: ByteArray? = null) {
        val body = LivePostText.fit(text, photo || jpeg != null)
        when {
            jpeg != null -> Telegram.editPhoto(id, jpeg, body)
            photo -> Telegram.editCaption(id, body)
            else -> Telegram.editText(id, body)
        }
    }

    /** The output frame (after blur and overlays) as JPEG; null unless still live, not ending and blur isn't stalled. */
    private suspend fun grab(): ByteArray? {
        val bmp = frame() ?: return null
        return withContext(Dispatchers.Default) {
            ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
        }
    }

    /** The output frame after blur and overlays; null unless live, not ending and blur isn't stalled (also the story card's). */
    suspend fun frame(): Bitmap? {
        val bmp =
            withTimeoutOrNull(3000) { suspendCancellableCoroutine<Bitmap?> { c -> if (!Overlays.grab { c.resume(it) }) c.resume(null) } }
                ?: return null
        return bmp.takeIf { Engine.live && !closing && !Privacy.stalled }
    }

    // text inputs

    private fun goalLine() = GoalStore.config.takeIf { it.target.signum() > 0 }?.let {
        LivePostText.GoalLine((GoalStore.progress * 100).toInt(), Money(it.target, it.currency).display, it.title)
    }

    private fun liveInput() = LivePostText.Live(
        title = Kick.title, slug = slug, viewers = viewers,
        elapsedMs = Engine.liveSince?.let { System.currentTimeMillis() - it } ?: 0,
        countdown = SceneRoles.countdownText.takeIf { SceneRoles.active == "starting" && it.isNotEmpty() },
        reconnecting = NetStats.connectedSince == null, goal = goalLine(),
        last = SessionLog.lastDonation?.let { "${it.first} · ${it.second}" },
        city = WidgetLocation.cityText.takeIf { Prefs.bool("telegramShowCity", false) && it != "--" }
    )

    private fun recapInput(r: SessionRecord) = LivePostText.Recap(
        title = r.title.ifEmpty { Kick.title }, slug = slug, durationMs = r.durationMs, peak = r.peakViewers, avg = r.avgViewers,
        donationCount = r.donationCount,
        total = Money(
            r.donationTotal,
            r.currency
        ).display,
        showTotal = Prefs.bool("telegramShowTotal", true),
        topName = r.topDonor, topAmount = r.topDonorDisplay, goal = goalLine(), moments = r.moments,
        chatters = if (r.trackingStarted) r.chatterCounts.size else r.newChatters, trackingStarted = r.trackingStarted
    )
}
