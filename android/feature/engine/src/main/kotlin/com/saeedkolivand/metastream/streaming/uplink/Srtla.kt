package com.saeedkolivand.metastream.streaming.uplink

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.SystemClock
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.streaming.uplink.SrtlaWire as W
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.SocketAddress
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.nio.channels.SelectionKey
import java.nio.channels.Selector
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.random.Random

private const val PEER_QUIET_MS = 2000L

/**
 * Bonding (iOS Srtla): RootEncoder's SRT client talks to a loopback UDP socket; this proxy sends those packets to the SRTLA
 * receiver over one UDP socket per network (Wi-Fi, cellular, Ethernet; requested so cellular stays up beside Wi-Fi) and
 * merges the replies back. All link state lives on the "srtla" thread; network callbacks post onto it.
 */
class Srtla(private val host: String, private val port: Int, context: Context, private val onStats: (List<LinkStat>) -> Unit) {
    private val cm = context.getSystemService(ConnectivityManager::class.java)
    private val selector = Selector.open()
    private val local = DatagramChannel.open().apply {
        bind(InetSocketAddress(InetAddress.getLoopbackAddress(), 0)) // loopback only: nothing off the phone can reach it
        configureBlocking(false)
    }
    val localPort = (local.localAddress as InetSocketAddress).port

    // Other apps share loopback, so the peer is pinned: a new sender takes over only with an SRT handshake after the
    // current one has been quiet for PEER_QUIET_MS (libsrt reconnecting from a fresh socket). Anything else is dropped.
    // ponytail: an app that races libsrt's reconnect handshake could still win that one window; an in-process transport
    // would close it, but RootEncoder's SRT client only speaks UDP.
    private var peer: SocketAddress? = null
    private var peerAt = 0L
    private val tasks = ConcurrentLinkedQueue<() -> Unit>()
    private val callbacks = mutableListOf<ConnectivityManager.NetworkCallback>()
    private val links = mutableListOf<SrtlaLink>()
    private val buf = ByteBuffer.allocate(2048)
    private var id = Random.nextBytes(W.ID_LEN) // srtla_id
    private var pending: SrtlaLink? = null // pending_reg2_conn
    private var pendingUntil = 0L
    private var active = 0
    private var ticks = 0

    @Volatile private var running = true

    @Volatile var cut = false // bitrate cut below 70% of target: backups may carry data too

    fun start() {
        local.register(selector, SelectionKey.OP_READ)
        Thread(::loop, "srtla").start()
        for ((transport, key, label, def) in BONDING_TRANSPORTS) {
            val role = Prefs.string(key, def)
            if (role == "off") continue
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    val addr = runCatching { network.getByName(host) }.getOrNull() ?: return // DNS on that network, off our thread
                    post { add(network, label, role == "backup", addr) }
                }

                override fun onLost(network: Network) = post { remove(network) }
            }
            val req = NetworkRequest.Builder().addTransportType(
                transport
            ).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build()
            runCatching { cm.requestNetwork(req, cb) }.onSuccess { callbacks += cb }
        }
    }

    fun stop() {
        callbacks.forEach { runCatching { cm.unregisterNetworkCallback(it) } }
        callbacks.clear()
        running = false
        selector.wakeup()
    }

    private fun post(task: () -> Unit) {
        tasks += task
        selector.wakeup()
    }

    private fun now() = SystemClock.elapsedRealtime() / 1000

    private fun loop() {
        var lastTick = 0L
        try {
            while (running) {
                selector.select(250)
                while (true) tasks.poll()?.invoke() ?: break
                val keys = selector.selectedKeys().iterator()
                while (keys.hasNext()) {
                    val k = keys.next()
                    keys.remove()
                    val l = k.attachment() as SrtlaLink?
                    if (l == null) readLocal() else readLink(l)
                }
                val t = SystemClock.elapsedRealtime()
                if (t - lastTick >= 1000) {
                    lastTick = t
                    housekeeping()
                }
            }
        } catch (e: IOException) {
            applog("stream", "srtla stopped: ${e.message}")
        } finally {
            links.forEach { runCatching { it.ch.close() } }
            links.clear()
            runCatching { local.close() }
            runCatching { selector.close() }
        }
    }

    private fun add(network: Network, label: String, backup: Boolean, addr: InetAddress) {
        if (links.any { it.network == network }) return
        try {
            val ch = DatagramChannel.open()
            network.bindSocket(ch.socket())
            ch.configureBlocking(false)
            ch.connect(InetSocketAddress(addr, port))
            val l = SrtlaLink(network, label, backup, ch)
            ch.register(selector, SelectionKey.OP_READ, l)
            links += l
            applog("stream", "srtla: $label link added (${if (backup) "backup" else "main"})")
        } catch (e: IOException) {
            applog("stream", "srtla: $label link failed: ${e.message}")
        }
    }

    private fun remove(network: Network) {
        val l = links.firstOrNull { it.network == network } ?: return
        runCatching { l.ch.close() }
        links -= l
        if (pending === l) pending = null
        applog("stream", "srtla: ${l.label} link removed")
    }

    private fun send(l: SrtlaLink, b: ByteBuffer) {
        try {
            l.ch.write(b)
        } catch (e: IOException) {
            l.lastRcvd = 1 // sendto() failed: the link is down until it registers again
        }
    }

    private fun sendReg(l: SrtlaLink, type: Int) = send(
        l,
        ByteBuffer.allocate(2 + W.ID_LEN).putShort(type.toShort()).put(id).also {
            it.flip()
        }
    )

    private fun housekeeping() { // connection_housekeeping()
        val t = now()
        active = 0
        if (pending != null && t > pendingUntil) pending = null
        for (l in links) {
            if (!l.up(t)) {
                if (l.lastRcvd > 0) {
                    applog("stream", "srtla: ${l.label} link down, re-registering")
                    l.lastRcvd = 0
                    l.lastSent = 0
                    l.window = W.WIN_MIN
                    l.inFlight = 0
                    l.log.fill(-1)
                }
                if (pending == null) {
                    sendReg(l, W.REG2)
                } else if (pending === l) {
                    sendReg(l, W.REG1)
                }
                continue
            }
            active++
            if (l.lastSent + W.IDLE_TIME < t) send(l, ByteBuffer.wrap(byteArrayOf(0x90.toByte(), 0))) // send_keepalive
        }
        if (++ticks % 10 == 0) {
            val total = links.sumOf { it.sent }.coerceAtLeast(1)
            links.forEach {
                it.share = it.sent * 100 / total
                it.sent = 0
            }
            applog("stream", "srtla: " + links.joinToString { "${it.label} ${if (it.up(t)) "up" else "down"} ${it.share}%" })
        }
        onStats(links.map { LinkStat(it.label, it.backup, it.up(t), it.share) })
    }

    private fun readLocal() { // handle_srt_data
        while (true) {
            buf.clear()
            val from = local.receive(buf) ?: return
            buf.flip()
            val ms = SystemClock.elapsedRealtime()
            if (from != peer) {
                val quiet = peer == null || ms - peerAt > PEER_QUIET_MS
                if (!quiet || W.kind(buf.array(), buf.limit()) != W.SRT_HANDSHAKE) continue
                peer = from
            }
            peerAt = ms
            val t = now()
            val i = W.pick(links.map { W.Cand(it.up(t), it.window, it.inFlight, it.backup) }, cut) ?: continue // none up: SRT retransmits
            val l = links[i]
            l.lastSent = t
            l.sent++
            val sn = W.seq(buf.array(), buf.limit())
            send(l, buf)
            if (sn != null) { // reg_pkt
                l.log[l.idx] = sn
                l.idx = (l.idx + 1) % W.LOG_SIZE
                l.inFlight++
            }
        }
    }

    private fun readLink(l: SrtlaLink) { // handle_srtla_data
        while (true) {
            buf.clear()
            val n = try {
                l.ch.read(buf)
            } catch (e: IOException) {
                return // ICMP unreachable and the like: the timeout takes the link down
            }
            if (n <= 0) return
            buf.flip()
            if (fromReceiver(l, buf.array(), n)) peer?.let { runCatching { local.send(buf, it) } }
        }
    }

    /** True when the packet goes on to libsrt. */
    private fun fromReceiver(l: SrtlaLink, b: ByteArray, n: Int): Boolean {
        val t = now()
        when (val k = W.kind(b, n)) {
            W.NGP -> { // the receiver doesn't know our group: REG1 on this link, only when nothing else is going on
                if (active == 0 && pending == null && t > pendingUntil) {
                    sendReg(l, W.REG1)
                    pending = l
                    pendingUntil = t + W.REG_TIMEOUT
                }
                return false
            }
            W.REG2 -> {
                val half = W.ID_LEN / 2
                if (pending === l && n >= 2 + W.ID_LEN && (0 until half).all { b[2 + it] == id[it] }) { // first half must be ours
                    id = b.copyOfRange(2, 2 + W.ID_LEN)
                    links.forEach { sendReg(it, W.REG2) }
                    pending = null
                    pendingUntil = t + W.REG_TIMEOUT
                    applog("stream", "srtla: group registered via ${l.label}")
                }
                return false
            }
            W.REG_ERR, W.REG_NAK -> { // ponytail: the reference forwards these to libsrt; they are noise there
                applog("stream", "srtla: ${l.label} registration refused (0x${k.toString(16)})")
                return false
            }
        }
        l.lastRcvd = t
        when (W.kind(b, n)) {
            W.SRT_ACK -> if (n >= 20) links.ack(W.be32(b, 16).toInt())
            W.SRT_NAK -> links.nak(b, n)
            W.ACK -> { // SRTLA ACK: a list of acknowledged sequence numbers
                var i = 4
                while (i + 4 <= n) {
                    links.srtlaAck(W.be32(b, i).toInt())
                    i += 4
                }
                return false
            }
            W.KEEPALIVE -> return false
            W.REG3 -> {
                active++
                applog("stream", "srtla: ${l.label} link registered")
                return false
            }
        }
        return true
    }
}
