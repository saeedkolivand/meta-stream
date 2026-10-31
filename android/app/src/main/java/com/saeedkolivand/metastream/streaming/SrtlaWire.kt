package com.saeedkolivand.metastream.streaming

/** Constants and pure logic of the SRTLA sender (BELABOX srtla_send.c + common.h, via iOS Srtla.swift); names are its identifiers. */
internal object SrtlaWire {
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
