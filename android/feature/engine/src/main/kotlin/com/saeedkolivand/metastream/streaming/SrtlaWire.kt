package com.saeedkolivand.metastream.streaming

/** Constants and pure logic of the SRTLA sender (BELABOX srtla_send.c + common.h, via iOS Srtla.swift); names are its identifiers. */
object SrtlaWire {
    // common.h
    const val NGP = 0x9211
    const val REG1 = 0x9200
    const val REG2 = 0x9201
    const val REG3 = 0x9202
    const val KEEPALIVE = 0x9000
    const val ACK = 0x9100
    const val REG_ERR = 0x9210
    const val REG_NAK = 0x9212
    const val SRT_ACK = 0x8002
    const val SRT_NAK = 0x8003
    const val SRT_HANDSHAKE = 0x8000
    const val ID_LEN = 256

    // srtla_send.c: PKT_LOG_SZ, CONN_TIMEOUT, REG2/3_TIMEOUT, IDLE_TIME (seconds), WINDOW_* x WINDOW_MULT(1000)
    const val LOG_SIZE = 256
    const val CONN_TIMEOUT = 4L
    const val REG_TIMEOUT = 4L
    const val IDLE_TIME = 1L
    const val WIN_MIN = 1000
    const val WIN_DEF = 20_000
    const val WIN_MAX = 60_000
    const val WIN_DECR = 100
    const val WIN_INCR = 30

    /** get_srt_type */
    fun kind(d: ByteArray, n: Int) = if (n < 2) 0 else (d[0].toInt() and 0xFF shl 8) or (d[1].toInt() and 0xFF)

    fun be32(d: ByteArray, at: Int): Long = (0..3).fold(0L) { v, i -> (v shl 8) or (d[at + i].toLong() and 0xFF) }

    /** get_srt_sn: 31-bit sequence number of an SRT data packet (first bit 0), null for control packets. */
    fun seq(d: ByteArray, n: Int): Int? = if (n < 4 || d[0].toInt() and 0x80 != 0) null else be32(d, 0).toInt()

    class Cand(val up: Boolean, val window: Int, val inFlight: Int, val backup: Boolean)

    /**
     * select_conn(): best window / (in_flight + 1). Main links first; backups only when no main link is up, every main
     * window is full, or the bitrate has been cut.
     */
    fun pick(c: List<Cand>, cut: Boolean): Int? {
        val mains = c.indices.filter { c[it].up && !c[it].backup }
        val room = mains.any { c[it].inFlight * 1000 < c[it].window }
        val pool = if (room && !cut) mains else c.indices.filter { c[it].up }
        return pool.maxByOrNull { c[it].window / (c[it].inFlight + 1) }
    }
}

/** conn_t: one bonding link's socket and congestion state (srtla thread only). */
class SrtlaLink(val network: android.net.Network, val label: String, val backup: Boolean, val ch: java.nio.channels.DatagramChannel) {
    var lastRcvd = 0L
    var lastSent = 0L
    var window = SrtlaWire.WIN_DEF
    var inFlight = 0
    var idx = 0
    var sent = 0
    var share = 0
    val log = IntArray(SrtlaWire.LOG_SIZE) { -1 }
    fun up(now: Long) = lastRcvd + SrtlaWire.CONN_TIMEOUT >= now // !conn_timed_out
}

fun List<SrtlaLink>.ack(a: Int) { // register_srt_ack: everything below is delivered
    for (c in this) {
        var n = 0
        for (i in c.log.indices) if (c.log[i] < a) c.log[i] = -1 else n++
        c.inFlight = n
    }
}

/** A NAK range checks each link's 256-entry log instead of walking it: a broken receiver could name two billion numbers. */
fun List<SrtlaLink>.nak(b: ByteArray, n: Int) {
    var i = 16
    while (i + 4 <= n) {
        val v = SrtlaWire.be32(b, i)
        i += 4
        var first = v
        var last = v
        if (v and 0x80000000L != 0L && i + 4 <= n) { // a range: the first has the high bit, the next is the last lost
            first = v and 0x7FFFFFFF
            last = SrtlaWire.be32(b, i)
            i += 4
        }
        for (c in this) {
            for (j in c.log.indices) {
                if (c.log[j] >= 0 && c.log[j] >= first && c.log[j] <= last) { // register_nak: shrink the carrier's window
                    c.log[j] = -1
                    c.window = maxOf(c.window - SrtlaWire.WIN_DECR, SrtlaWire.WIN_MIN)
                }
            }
        }
    }
}

fun List<SrtlaLink>.srtlaAck(s: Int) { // register_srtla_ack
    var found = false
    for (c in this) {
        val i = if (found) -1 else c.log.indexOf(s)
        if (i >= 0) {
            found = true
            c.log[i] = -1
            if (c.inFlight > 0) c.inFlight--
            if (c.inFlight * 1000 > c.window) c.window += SrtlaWire.WIN_INCR - 1
        }
        if (c.lastRcvd != 0L) c.window = minOf(c.window + 1, SrtlaWire.WIN_MAX)
    }
}
