package com.saeedkolivand.metastream.remote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ObsServerTest {
    @Test
    fun authMatchesSpecExampleAndLocalCheck() {
        val a = ObsServer.auth(
            "supersecretpassword",
            "lM1GncleQOaCu9lT1yeUZhFYnqhsLLP1G5lAGo3ixaI=",
            "+IxH4CnCiqpX1rM9scsNynZzbOe4KhDeYcTNS3PDaeY="
        )
        assertEquals("1Ct943GAT+6YQUUX47Ia/ncufilbe6+oD6lY+5kaCu4=", a)
        fun ip(s: String) = java.net.InetAddress.getByName(s)
        assertTrue(WsConn.isLocal(ip("192.168.1.5")) && WsConn.isLocal(ip("10.0.0.2")) && WsConn.isLocal(ip("fd00::1")))
        assertFalse(WsConn.isLocal(ip("8.8.8.8")) || WsConn.isLocal(ip("100.64.1.1")) || WsConn.isLocal(ip("2001:db8::1")))
        assertEquals(12, ObsServer.randomPassword().length)
    }
}
