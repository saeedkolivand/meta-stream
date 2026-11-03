package com.saeedkolivand.metastream.core.model

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale

/**
 * Donations as money (adr/0006): an amount in the currency it was given in. BigDecimal throughout: currency in floating
 * point is a rounding bug waiting to happen. Currency: "IRT" (toman), "USD", "EUR", or a crypto symbol ("USDT", "BTC").
 */
data class Money(val amount: BigDecimal, val currency: String) {
    /** Rial is counted as toman (1 toman = 10 rial). */
    val inToman get() = if (currency == "IRR") Money(amount.divide(BigDecimal.TEN), "IRT") else this

    /** "₮1,000,000", "€9.26", "$10", "0.002 BTC". */
    val display: String
        get() {
            val m = inToman
            val fiat = isFiat(m.currency)
            val maxFrac = if (m.currency == "IRT") {
                0
            } else if (fiat) {
                2
            } else {
                8
            }
            val whole = m.amount.stripTrailingZeros().scale() <= 0
            val minFrac = if (fiat && m.currency != "IRT" && !whole) 2 else 0
            val f = DecimalFormat("#,##0", DecimalFormatSymbols(Locale.US)).apply {
                maximumFractionDigits = maxFrac
                minimumFractionDigits = minFrac
                roundingMode = RoundingMode.HALF_UP
            }
            val n = f.format(m.amount)
            return when (m.currency) {
                "IRT" -> "₮$n"
                "USD" -> "$$n"
                "EUR" -> "€$n"
                else -> "$n ${m.currency}"
            }
        }

    companion object {
        /** Codes as the app keeps them: Persian and symbol spellings mapped; anything not 2-6 letters/digits is "XXX". */
        fun of(amount: BigDecimal, raw: String) = Money(amount, normalize(raw))

        fun normalize(raw: String): String = when (val c = raw.trim().uppercase()) {
            "TOMAN", "TOMANS", "TMN", "IRT", "تومان" -> "IRT"
            "RIAL", "IRR", "RLS", "ریال" -> "IRR"
            "$", "US$", "DOLLAR" -> "USD"
            "€", "EURO" -> "EUR"
            "" -> "USD"
            // Codes come from donation sites and end up in the bot's chat posts: real ones are 2-6 letters or digits.
            else -> if (c.length in 2..6 && c.all { it in 'A'..'Z' || it in '0'..'9' }) c else "XXX"
        }

        fun isFiat(c: String) = c in setOf("IRT", "IRR", "USD", "EUR")

        /** Typed text ("9,99" or "9.99") as an exact amount; null when it isn't a number. */
        fun parse(s: String) = s.trim().replace(',', '.').toBigDecimalOrNull()
    }
}
