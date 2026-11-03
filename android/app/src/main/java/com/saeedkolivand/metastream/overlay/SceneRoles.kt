package com.saeedkolivand.metastream.overlay

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.bot.AppBot
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Scene roles (iOS SceneRoles): scenes the app switches to on its own. Starting (a countdown after the first connect), BRB
 * (while the link is too weak) and Ending (held after Stop). Role switches go through [Scenes.apply] so they don't cancel
 * themselves; a manual [Scenes.select] ends the role with no way back ([clear]). Rotation pauses while a role is up.
 */
object SceneRoles {
    const val STARTING = "starting"
    const val BRB = "brb"
    const val ENDING = "ending"

    /** The role whose scene is up; null = none. */
    var active by mutableStateOf<String?>(null)
        private set

    /** Seconds left of the Ending hold, for the Stop button; null when not ending. */
    var endingIn by mutableStateOf<Int?>(null)
        private set

    @Volatile private var countdownEnd: Long? = null
    private var back: String? = null
    private var job: Job? = null
    private var weakTicks = 0
    private var goodTicks = 0
    private var weakNoticed = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** {countdown}: Starting time left as m:ss, empty when no countdown runs. */
    val countdownText: String
        get() = countdownEnd?.let { duration(it - System.currentTimeMillis() + 999) }.orEmpty()

    private fun log(role: String, on: Boolean) {
        applog("overlay", "role $role ${if (on) "on" else "off"} -> ${OverlayStore.scene}")
        AppBot.role(role, on)
    }

    /** Selects the role's scene, remembering where to come back to. False when no scene has that role. */
    private fun select(role: String): Boolean {
        val scene = OverlayStore.scenes.firstOrNull { it.role == role } ?: return false
        active?.takeIf { it != role }?.let { log(it, false) }
        if (active == null) back = OverlayStore.scene
        active = role
        countdownEnd = null
        Scenes.updateRotation() // paused for the duration
        Scenes.apply(scene.name)
        log(role, true)
        return true
    }

    /** Role over: back to the scene from before it, rotation resumes. */
    fun end() {
        val role = active ?: return
        val to = back.orEmpty()
        clear(log = false)
        Scenes.apply(to)
        log(role, false)
    }

    /** Role over without a return (a manual pick). No-op when no role is up. */
    fun clear(log: Boolean = true) {
        val role = active ?: return
        active = null
        back = null
        countdownEnd = null
        endingIn = null
        job?.cancel()
        job = null
        weakTicks = 0
        goodTicks = 0
        Scenes.updateRotation()
        if (log) log(role, false)
    }

    /** First connect of a session: the Starting scene for the countdown, then back. */
    fun startRole() {
        val secs = Prefs.int("startCountdown", 60)
        if (secs <= 0 || !select(STARTING)) return
        countdownEnd = System.currentTimeMillis() + secs * 1000L
        job = scope.launch {
            delay(secs * 1000L)
            end()
        }
    }

    /**
     * From Health's 1 s loop. A dropped link, or over 2 s of video stuck in the uplink queue, for 5 s puts BRB up; connected
     * with under 0.5 s queued for 10 s takes it down. Backlog, not throughput: a still BRB card encodes far below target.
     */
    fun checkBrb(down: Boolean, queueBytes: Long, kbps: Int) {
        if (!Engine.live || (active != null && active != BRB)) {
            weakTicks = 0
            goodTicks = 0
            weakNoticed = false
            return
        }
        val backlog = queueBytes * 8.0 / (maxOf(kbps, 500) * 1000)
        weakTicks = if (down || backlog > 2) weakTicks + 1 else 0
        goodTicks = if (!down && backlog < 0.5) goodTicks + 1 else 0
        when {
            active == null && !weakNoticed && weakTicks >= 5 -> if (!select(BRB)) {
                weakNoticed = true // no BRB scene: the stream stays as it is, only the app bot's notice goes out
                log(BRB, true)
            }
            goodTicks >= 10 && active == BRB -> end()
            goodTicks >= 10 && weakNoticed -> {
                weakNoticed = false
                log(BRB, false)
            }
        }
    }

    /** The Stop button: with an Ending scene, hold it for the Ending hold before stopping; a second tap stops now. */
    fun requestStop() {
        val hold = Prefs.int("endingHold", 10)
        if (active == ENDING) return Engine.stop()
        job?.cancel()
        if (!Engine.live || hold <= 0 || !select(ENDING)) return Engine.stop()
        job = scope.launch {
            for (left in hold downTo 1) {
                endingIn = left
                delay(1000)
            }
            Engine.stop()
        }
    }
}
