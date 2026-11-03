package com.saeedkolivand.metastream.goal

import java.math.BigDecimal
import java.time.Instant
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DonatePageTest {
    @Test
    fun bodyAndHost() {
        val j = JSONObject(DonatePage.body("Cam", BigDecimal("1234567.6"), BigDecimal("5000000"), "IRT", true, Instant.EPOCH))
        assertEquals(1234568.0, j.getDouble("total"), 0.0)
        assertEquals(true, j.getBoolean("live"))
        assertEquals(
            12.35,
            JSONObject(DonatePage.body("x", BigDecimal("12.345"), BigDecimal.TEN, "EUR", false, Instant.EPOCH)).getDouble("total"),
            0.0
        )
        assertEquals("donate.iamsaeed.dev", DonatePage.host("https://Donate.iamsaeed.dev/"))
        assertNull(DonatePage.host("not a url"))
    }
}
