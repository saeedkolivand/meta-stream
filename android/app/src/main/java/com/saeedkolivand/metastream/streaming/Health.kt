package com.saeedkolivand.metastream.streaming

import android.app.Application
import android.os.BatteryManager
import android.os.PowerManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.pedro.library.util.streamclient.StreamBaseClient
import com.saeedkolivand.metastream.core.applog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val LOW_BATTERY = 15

/** Battery percentage moves slowly; refreshing the HUD every ~30 s is plenty and skips a systems-server wake per tick. */
private const val BATTERY_MS = 30_000L

/** True when a battery refresh is due; the first tick after go-live always refreshes (last is 0). */
internal fun batteryDue(now: Long, last: Long) = last == 0L || now - last >= BATTERY_MS

/** iOS HUD wording: fair -> warm, serious -> hot, critical -> overheating; null while nominal (Android NONE/LIGHT). */
fun thermalLabel(status: Int): String? = when {
    status >= PowerManager.THERMAL_STATUS_CRITICAL -> "overheating"
    status == PowerManager.THERMAL_STATUS_SEVERE -> "hot"
    status == PowerManager.THERMAL_STATUS_MODERATE -> "warm"
    else -> null
}

fun thermalSerious(status: Int) = status >= PowerManager.THERMAL_STATUS_SEVERE

/** Seconds of downtime at which iOS nudges again: Speaker's own repeat (30/60) plus the 2 and 5 minute escalations. */
fun escalation(downSec: Long, last: Long): String? = when {
    downSec >= 300 && last < 300 -> "stream still down after 5 minutes, may need a manual restart"
    downSec >= 120 && last < 120 -> "stream still down after 2 minutes"
    downSec >= 60 && last < 60 -> "stream dropped"
    downSec >= 30 && last < 30 -> "stream dropped"
    else -> null
}

/**
 * Stream health while live: fps/kbps, phone battery and heat for the HUD, adaptive bitrate, and the spoken/notified
 * alerts of iOS HealthMonitor. One 1 s loop (like iOS's stats tick) runs only between [start] and [stop].
 */
object Health {
    private lateinit var app: Application
    private lateinit var scope: CoroutineScope
    private lateinit var speak: (String) -> Unit
    private lateinit var alert: (String) -> Unit

    var fps by mutableIntStateOf(0)
        private set
    var kbps by mutableIntStateOf(0)
        private set

    /** Smoothed outgoing bitrate for the {bitrate} text token; 0 while not streaming. */
    var bitrateKbps by mutableIntStateOf(0)
        private set
    var battery by mutableStateOf<Int?>(null)
        private set
    var thermal by mutableIntStateOf(PowerManager.THERMAL_STATUS_NONE)
        private set

    /** Current adaptive bitrate; HUD shows the "cap" pill when it is below [ceilingKbps]. 0 = not adapting. */
    var capKbps by mutableIntStateOf(0)
        private set
    var ceilingKbps by mutableIntStateOf(0)
        private set

    @Volatile private var outKbps = 0L
    private var job: Job? = null
    private var listening = false
    private var downSince: Long? = null
    private var lastEscalation = 0L
    private var warnedBattery = false
    private var warnedThermal = false
    private val thermalListener = PowerManager.OnThermalStatusChangedListener { thermal = it }

    fun init(application: Application, scope: CoroutineScope, speak: (String) -> Unit, alert: (String) -> Unit) {
        app = application
        this.scope = scope
        this.speak = speak
        this.alert = alert
    }

    /** Feeds the loop from RootEncoder's stats callback (its own thread). */
    fun onStats(bytesOutPerSecond: Long, smoothedBitrate: Long) {
        outKbps = bytesOutPerSecond * 8 / 1000
        kbps = (smoothedBitrate / 1000).toInt()
        bitrateKbps = kbps
    }

    /** [client] is null for glasses passthrough (no encoder knob, so no adaptation); [apply] sets the encoder bitrate. */
    fun start(ceiling: Int, client: StreamBaseClient?, apply: (Int) -> Unit) {
        stop()
        ceilingKbps = ceiling
        capKbps = if (client == null) 0 else ceiling
        val controller = client?.let { BitrateController(ceiling) }
        val power = app.getSystemService(PowerManager::class.java)
        thermal = power.currentThermalStatus
        power.addThermalStatusListener(ContextCompat.getMainExecutor(app), thermalListener)
        listening = true
        job = scope.launch {
            var lastFrames = client?.getSentVideoFrames() ?: 0
            var lastBattery = 0L
            warnedBattery = false
            warnedThermal = false
            while (true) {
                delay(1000)
                val now = System.currentTimeMillis()
                client?.let {
                    fps = (it.getSentVideoFrames() - lastFrames).toInt()
                    lastFrames = it.getSentVideoFrames()
                }
                if (batteryDue(now, lastBattery)) {
                    lastBattery = now
                    updateBattery()
                }
                if (controller != null && client != null) {
                    val change = controller.thermal(now, thermalSerious(thermal))
                        ?: if (downSince == null) controller.tick(now, client.hasCongestion(), outKbps) else null
                    if (change != null) {
                        apply(change)
                        capKbps = change
                        applog("stream", "bitrate -> $change kbps")
                    }
                }
                if (thermalSerious(thermal) && !warnedThermal) {
                    warnedThermal = true
                    speak("phone getting hot")
                }
                escalate(now)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        // remove throws when the listener was never added (first start() calls stop() too)
        if (listening) app.getSystemService(PowerManager::class.java).removeThermalStatusListener(thermalListener)
        listening = false
        fps = 0
        kbps = 0
        bitrateKbps = 0
        battery = null
        capKbps = 0
        downSince = null
        lastEscalation = 0
        outKbps = 0
    }

    private fun updateBattery() {
        val pct = app.getSystemService(BatteryManager::class.java).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        battery = pct.takeIf { it in 0..100 }
        if (pct in 0 until LOW_BATTERY && !warnedBattery) {
            warnedBattery = true
            speak("phone battery fifteen percent")
        }
    }

    /** First sign a live connection is down: start the downtime clock, speak and notify once. */
    fun markDown() {
        if (downSince != null) return
        downSince = System.currentTimeMillis()
        lastEscalation = 0
        applog("stream", "connection dropped, retrying")
        speak("connection lost, retrying")
        alert("Stream dropped, retrying")
    }

    fun markUp() {
        downSince = null
        lastEscalation = 0
    }

    private fun escalate(now: Long) {
        val since = downSince ?: return
        val sec = (now - since) / 1000
        escalation(sec, lastEscalation)?.let {
            lastEscalation = sec
            speak(it)
            alert(it)
        }
    }
}
