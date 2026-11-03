package com.saeedkolivand.metastream.overlay

import org.junit.Assert.assertEquals
import org.junit.Test

class DonationArtTest {
    @Test
    fun keyframesWrapAndBoard() {
        assertEquals(0f, track(0f, ::dLinear, 0.1f to 0f, 0.2f to 10f), 0f)
        assertEquals(5f, track(0.15f, ::dLinear, 0.1f to 0f, 0.2f to 10f), 1e-4f)
        assertEquals(10f, track(0.9f, ::dLinear, 0.1f to 0f, 0.2f to 10f), 0f)
        assertEquals(listOf("hello", "world"), wrap("hello world", 8, 4))
        assertEquals(listOf("abcd", "efgh"), wrap("abcdefgh", 4, 4))
        assertEquals(listOf("a b", "c …"), wrap("a b c d e f", 3, 2))
        val plain = Board.of(1920f, 1080f, DonationKind.CoinBurst.focus, null)
        assertEquals(1.5f, plain.s, 0f)
        assertEquals(960f, plain.x(640f), 0f)
        // a full-size Alerts widget (900 units at 1080p) keeps the plain scale; the focus centres on the box
        val b = Board.of(1920f, 1080f, DonationKind.CoinBurst.focus, Box(500f, 300f, 900f, 240f))
        assertEquals(1.5f, b.s, 1e-4f)
        assertEquals(950f, b.x(640f), 1e-3f)
    }
}
