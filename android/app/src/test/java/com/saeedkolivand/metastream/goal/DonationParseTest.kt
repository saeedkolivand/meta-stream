package com.saeedkolivand.metastream.goal

import com.saeedkolivand.metastream.core.model.Money
import java.math.BigDecimal
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DonationParseTest {
    @Test
    fun parsesSiteShapes() {
        val r = DonationParse.parse(
            JSONObject("""{"_id":"a1","price":"1,500,000","type":"toman","donator":"Ali","text":"hi","status":"paid"}"""),
            Shape.reymit
        )!!
        assertEquals("a1", r.id)
        assertEquals(Money(BigDecimal("1500000"), "IRT"), r.money)
        assertEquals("Ali", r.name)
        assertEquals(Parsed.State.Paid, r.state)
        assertNull(DonationParse.parse(JSONObject("""{"id":"x","amount":0}"""), Shape.donofa))
        val se = DonationParse.parseStreamElements(
            JSONObject(
                """{"_id":"s1","status":"refunded","createdAt":"2026-10-20T10:00:00.000Z","donation":{"user":{"username":"bob"},"amount":5.5,"currency":"EUR"}}"""
            )
        )!!
        assertEquals(Parsed.State.Refunded, se.state)
        assertEquals(BigDecimal("5.5"), se.money.amount)
        assertEquals(1_792_490_400_000L, se.date)
        assertEquals(2, DonationParse.items(JSONObject("""{"data":{"donates":[{"id":1},{"id":2}]}}""")).size)
        assertEquals(1_000_000_000_000L, DonationParse.date(1_000_000_000))
        assertEquals(Parsed.State.Pending, DonationParse.state(2))
    }
}
