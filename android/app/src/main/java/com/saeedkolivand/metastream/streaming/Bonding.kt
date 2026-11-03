package com.saeedkolivand.metastream.streaming

import android.content.Context
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.applog

/** One bonding link for the network sheet: up or down, and its share of the last 10 s of packets. */
data class LinkStat(val label: String, val backup: Boolean, val up: Boolean, val share: Int)

/** A network the proxy bonds over: its Settings key ("main" | "backup" | "off"), label and default role, like iOS. */
internal data class Transport(val type: Int, val key: String, val label: String, val def: String)

internal val BONDING_TRANSPORTS = listOf(
    Transport(NetworkCapabilities.TRANSPORT_WIFI, "srtlaWifi", "Wi-Fi", "main"),
    Transport(NetworkCapabilities.TRANSPORT_ETHERNET, "srtlaEthernet", "Ethernet", "main"),
    Transport(NetworkCapabilities.TRANSPORT_CELLULAR, "srtlaCellular", "Cellular", "backup")
)

/** srtla:// ingests: the [Srtla] proxy for a live session, and its links for the network sheet. */
object Bonding {
    var links by mutableStateOf(listOf<LinkStat>())
        private set

    private var proxy: Srtla? = null
    private val main = Handler(Looper.getMainLooper())

    /**
     * For srtla://host:port/rest starts the proxy and returns srt://127.0.0.1:localport/rest; any other URL comes back as
     * is. Only scheme, host and port are swapped, as text: a streamid like "#!::r=live/x" must not be parsed as a URL.
     */
    fun target(context: Context, full: String): String {
        stop()
        if (!full.lowercase().startsWith("srtla://")) return full
        val rest = full.substring("srtla://".length)
        val end = rest.indexOfAny(charArrayOf('/', '?')).let { if (it < 0) rest.length else it }
        val authority = rest.substring(0, end)
        val host = authority.substringBeforeLast(':').trim('[', ']') // ponytail: IPv6 only in brackets, with a port
        val port = authority.substringAfterLast(':', "").toIntOrNull() ?: 5000 // srtla_rec's usual port
        val s = Srtla(host, port, context) { stats -> main.post { if (proxy != null) links = stats } }
        proxy = s
        s.start()
        applog("stream", "bonding proxy on 127.0.0.1:${s.localPort}")
        return "srt://127.0.0.1:${s.localPort}" + rest.substring(end)
    }

    fun stop() {
        proxy?.stop()
        proxy = null
        links = emptyList()
    }

    /** The bitrate controller cut below 70% of target: backup links may carry data too. */
    fun setCut(cut: Boolean) {
        proxy?.cut = cut
    }
}
