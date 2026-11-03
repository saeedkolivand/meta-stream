package com.saeedkolivand.metastream.glasses

/** Splits an Annex-B buffer into NAL payloads (no start codes). Empty NALs (the SDK's double VPS start code) are skipped. */
fun nalUnits(d: ByteArray): List<ByteArray> {
    val out = ArrayList<ByteArray>()
    var start = -1
    var i = 0
    while (i + 2 < d.size) {
        if (d[i] == 0.toByte() && d[i + 1] == 0.toByte() && d[i + 2] == 1.toByte()) {
            if (start >= 0) out.add(trim(d, start, i))
            start = i + 3
            i += 3
        } else {
            i++
        }
    }
    if (start >= 0) out.add(trim(d, start, d.size))
    return out.filter { it.isNotEmpty() }
}

// Drops the leading zero of a 4-byte start code that belongs to the next NAL.
private fun trim(d: ByteArray, from: Int, to: Int): ByteArray {
    var end = to
    while (end > from && d[end - 1] == 0.toByte()) end--
    return d.copyOfRange(from, end)
}

fun nalType(nal: ByteArray) = (nal[0].toInt() and 0x7E) shr 1

/** IRAP pictures (BLA 16-18, IDR 19-20, CRA 21) are valid decode/stream start points. */
fun isIrap(type: Int) = type in 16..21

/** VPS/SPS/PPS (types 32..34). */
fun isParamSet(type: Int) = type in 32..34

fun isKeyframe(nals: List<ByteArray>) = nals.any { isIrap(nalType(it)) }

/** Remembers the latest VPS/SPS/PPS; the SDK emits them once at stream start, so late consumers need the cache. */
class ParamSets {
    var vps: ByteArray? = null
    var sps: ByteArray? = null
    var pps: ByteArray? = null

    fun offer(nals: List<ByteArray>) {
        for (n in nals) {
            when (nalType(n)) {
                32 -> vps = n
                33 -> sps = n
                34 -> pps = n
            }
        }
    }

    fun complete() = vps != null && sps != null && pps != null

    /** Start-code-prefixed VPS+SPS+PPS, for priming the preview decoder. */
    fun annexB(): ByteArray? {
        val v = vps ?: return null
        val s = sps ?: return null
        val p = pps ?: return null
        val sc = byteArrayOf(0, 0, 0, 1)
        return sc + v + sc + s + sc + p
    }

    fun reset() {
        vps = null
        sps = null
        pps = null
    }
}
