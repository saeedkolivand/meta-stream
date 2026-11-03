package com.saeedkolivand.metastream.remote

import java.io.DataInputStream
import java.net.Inet6Address
import java.net.InetAddress
import java.net.Socket
import java.security.MessageDigest
import java.util.Base64

/**
 * The server side of one RFC 6455 WebSocket, just enough for obs-websocket: the HTTP upgrade, masked client text frames up
 * to 64 KB, ping/pong and close. ponytail: no fragmented messages and no extensions (obs-websocket clients send neither);
 * a fragment closes the connection. Blocking; one IO coroutine per connection.
 */
class WsConn(private val sock: Socket) {
    private val input = DataInputStream(sock.getInputStream().buffered())
    private val out = sock.getOutputStream()
    val peer: InetAddress = sock.inetAddress

    /** Reads the upgrade request (8 KB of headers at most) and answers 101; false when it isn't a WebSocket upgrade. */
    fun handshake(subprotocol: String): Boolean {
        val headers = HashMap<String, String>()
        var total = 0
        while (true) {
            val line = readLine() ?: return false
            total += line.length
            if (total > 8192) return false
            if (line.isEmpty()) break
            line.indexOf(':').takeIf { it > 0 }?.let { headers[line.substring(0, it).trim().lowercase()] = line.substring(it + 1).trim() }
        }
        val key = headers["sec-websocket-key"] ?: return false
        val accept = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest((key + GUID).toByteArray()))
        val proto = headers["sec-websocket-protocol"]?.split(',')?.map { it.trim() }?.contains(subprotocol) == true
        val reply = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: $accept\r\n" +
            (if (proto) "Sec-WebSocket-Protocol: $subprotocol\r\n" else "") + "\r\n"
        synchronized(this) {
            out.write(reply.toByteArray())
            out.flush()
        }
        return true
    }

    /** The next text message; null once the peer closes, breaks the rules or the socket fails. Pings are answered here. */
    fun read(): String? = runCatching {
        while (true) {
            val b0 = input.readUnsignedByte()
            val b1 = input.readUnsignedByte()
            var len = (b1 and 0x7F).toLong()
            if (len == 126L) len = input.readUnsignedShort().toLong()
            if (len == 127L) len = input.readLong()
            // Clients must mask; no fragments; a frame over 64 KB is an attack, not a controller.
            if (b0 and 0x80 == 0 || b1 and 0x80 == 0 || len !in 0..MAX_FRAME) return@runCatching null
            val mask = ByteArray(4).also(input::readFully)
            val data = ByteArray(len.toInt()).also(input::readFully)
            for (i in data.indices) data[i] = (data[i].toInt() xor mask[i % 4].toInt()).toByte()
            when (b0 and 0x0F) {
                1 -> return@runCatching String(data, Charsets.UTF_8)
                9 -> send(10, data)
                10 -> Unit
                else -> return@runCatching null // close (8), binary, continuation
            }
        }
        @Suppress("UNREACHABLE_CODE")
        null
    }.getOrNull()

    fun text(s: String) = runCatching { send(1, s.toByteArray()) }.isSuccess

    /** A close frame with [code] (obs-websocket uses 4000+), then the socket. */
    fun close(code: Int = 1000) {
        runCatching { send(8, byteArrayOf((code shr 8).toByte(), code.toByte())) }
        runCatching { sock.close() }
    }

    private fun send(op: Int, data: ByteArray) = synchronized(this) {
        val head = when {
            data.size < 126 -> byteArrayOf((0x80 or op).toByte(), data.size.toByte())
            data.size < 65536 -> byteArrayOf((0x80 or op).toByte(), 126, (data.size shr 8).toByte(), data.size.toByte())
            else -> byteArrayOf((0x80 or op).toByte(), 127) + ByteArray(8) { (data.size.toLong() shr (56 - 8 * it)).toByte() }
        }
        out.write(head + data)
        out.flush()
    }

    private fun readLine(): String? {
        val sb = StringBuilder()
        while (true) {
            val c = runCatching { input.readUnsignedByte() }.getOrNull() ?: return null
            if (c == '\n'.code) return sb.toString().trimEnd('\r')
            sb.append(c.toChar())
            if (sb.length > 4096) return null
        }
    }

    companion object {
        private const val GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        private const val MAX_FRAME = 64L * 1024

        /** Private IPv4 ranges, link-local, unique-local IPv6 and loopback: the hotspot and home Wi-Fi, never the internet. */
        fun isLocal(a: InetAddress) = a.isLoopbackAddress ||
            a.isSiteLocalAddress ||
            a.isLinkLocalAddress ||
            (a is Inet6Address && a.address[0].toInt() and 0xFE == 0xFC)
    }
}
