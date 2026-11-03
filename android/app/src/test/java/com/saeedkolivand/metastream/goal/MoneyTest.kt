package com.saeedkolivand.metastream.goal

import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Test

class MoneyTest {
    @Test
    fun normalizesAndDisplays() {
        assertEquals("IRT", Money.normalize("تومان"))
        assertEquals("IRR", Money.normalize("rial"))
        assertEquals("USD", Money.normalize(""))
        assertEquals("XXX", Money.normalize("<script>"))
        assertEquals("₮1,000,000", Money(BigDecimal(10_000_000), "IRR").display) // rial counted as toman
        assertEquals("€9.26", Money(BigDecimal("9.255"), "EUR").display)
        assertEquals("$10", Money(BigDecimal(10), "USD").display)
        assertEquals("€9.50", Money(BigDecimal("9.5"), "EUR").display)
        assertEquals("0.002 BTC", Money(BigDecimal("0.002"), "BTC").display)
        assertEquals(BigDecimal("9.99"), Money.parse("9,99"))
    }
}
