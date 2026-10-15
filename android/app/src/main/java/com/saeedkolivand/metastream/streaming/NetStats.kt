package com.saeedkolivand.metastream.streaming

import android.app.Application
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

const val SAMPLE_WINDOW = 120
private const val MAX_CHANGES = 12
private const val RECENT_SECONDS = 5
private const val SLOW_PERCENT = 70

/** One second of the stream: bytes actually sent, the adaptive target, the controller's congestion signal, link down. */
data class Sample(val sentKbps: Int, val targetKbps: Int, val congested: Boolean, val down: Boolean)

/** One bitrate step the controller made. */
data class Change(val atMs: Long, val kbps: Int, val up: Boolean, val why: Why)

enum class Level { Ok, Warn, Bad }

/** Keeps the newest [capacity] samples, oldest first. */
class Ring(private val capacity: Int = SAMPLE_WINDOW) {
    private val items = ArrayDeque<Sample>()

    fun add(s: Sample) {
        if (items.size == capacity) items.removeFirst()
        items.addLast(s)
    }

    fun toList(): List<Sample> = items.toList()

    fun clear() = items.clear()
}

/** m:ss, or h:mm:ss from an hour up. */
fun duration(ms: Long): String {
    val s = (ms / 1000).coerceAtLeast(0)
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
}

/** "just now", "42 s ago", "3 min ago", "2 h ago". */
fun relative(ms: Long): String {
    val s = (ms / 1000).coerceAtLeast(0)
    return when {
        s < 5 -> "just now"
        s < 60 -> "$s s ago"
        s < 3600 -> "${s / 60} min ago"
        else -> "${s / 3600} h ago"
    }
}

/** 2640 -> "2,640", fixed to US digits so a Persian locale doesn't change the figures. */
fun kbpsText(kbps: Int) = "%,d".format(Locale.US, kbps)

/** Chart top: the peak rounded up to the next 500 kbps, at least 500. */
fun chartMax(peak: Int) = ((peak + 499) / 500 * 500).coerceAtLeast(500)

/** Red when down now; orange when any of the last 5 s was congested or the newest second sent under 70% of target. */
fun level(samples: List<Sample>): Level {
    val last = samples.lastOrNull() ?: return Level.Ok
    if (last.down) return Level.Bad
    val slow = last.targetKbps > 0 && last.sentKbps * 100 < last.targetKbps * SLOW_PERCENT
    return if (slow || samples.takeLast(RECENT_SECONDS).any { it.congested }) Level.Warn else Level.Ok
}

/** A Wi-Fi link that Android marks metered is almost always a phone hotspot. */
fun pathLabel(wifi: Boolean, cellular: Boolean, ethernet: Boolean, metered: Boolean) = when {
    wifi && metered -> "Wi-Fi (phone hotspot)"
    wifi -> "Wi-Fi"
    cellular -> "Cellular"
    ethernet -> "Ethernet"
    else -> "No network"
}

/**
 * What the in-app NETWORK panel shows: per-second samples, drops, downtime, bitrate changes and the network path.
 * Fed by the [Health] stats loop (no timers of its own); the path comes from a default-network callback.
 */
object NetStats {
    private val ring = Ring()
    private var active = false
    private var closedDownMs = 0L
    private var cm: ConnectivityManager? = null

    var samples by mutableStateOf<List<Sample>>(emptyList())
        private set
    var changes by mutableStateOf<List<Change>>(emptyList())
        private set
    var drops by mutableIntStateOf(0)
        private set
    var lastDropAt by mutableStateOf<Long?>(null)
        private set
    var connectedSince by mutableStateOf<Long?>(null)
        private set

    /** Start of the outage in progress, null while connected. */
    var downStart by mutableStateOf<Long?>(null)
        private set
    var path by mutableStateOf("No network")
        private set
    var metered by mutableStateOf(false)
        private set
    var dataSaver by mutableStateOf(false)
        private set

    /** Total time down this session including an outage still in progress. */
    fun downtimeMs(now: Long) = closedDownMs + (downStart?.let { now - it } ?: 0)

    /** A new session: forget the last one. */
    fun begin() {
        ring.clear()
        samples = emptyList()
        changes = emptyList()
        drops = 0
        lastDropAt = null
        closedDownMs = 0
        downStart = null
        connectedSince = null
        active = true
    }

    fun end() {
        active = false
    }

    fun record(s: Sample) {
        ring.add(s)
        samples = ring.toList()
    }

    fun change(now: Long, kbps: Int, up: Boolean, why: Why) {
        changes = (listOf(Change(now, kbps, up, why)) + changes).take(MAX_CHANGES)
    }

    fun drop(now: Long) {
        if (!active || downStart != null) return
        downStart = now
        lastDropAt = now
        connectedSince = null
        drops++
    }

    fun up(now: Long) {
        if (!active) return
        downStart?.let { closedDownMs += now - it }
        downStart = null
        if (connectedSince == null) connectedSince = now
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            path = pathLabel(
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                metered
            )
            dataSaver = cm?.restrictBackgroundStatus != ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED
        }

        override fun onLost(network: Network) {
            path = "No network"
            metered = false
        }
    }

    fun init(app: Application) {
        val m = app.getSystemService(ConnectivityManager::class.java)
        cm = m
        // ponytail: callbacks on the main looper so state is only touched from main; needs ACCESS_NETWORK_STATE.
        m.registerDefaultNetworkCallback(callback, Handler(Looper.getMainLooper()))
    }
}
