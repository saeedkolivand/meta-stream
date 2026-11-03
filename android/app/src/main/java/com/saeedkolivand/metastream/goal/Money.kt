package com.saeedkolivand.metastream.goal

import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import com.saeedkolivand.metastream.core.model.Money
import java.math.BigDecimal

/**
 * What a sub, a Bit or a KICK is worth: face value, what the viewer paid (adr/0006), editable in Settings › Goal.
 * Stored as dollar strings so "4.99" stays exact.
 */
object DonationPrices {
    val defaults = linkedMapOf(
        "kickSub" to "4.99",
        "twitchTier1" to "4.99",
        "twitchTier2" to "9.99",
        "twitchTier3" to "24.99",
        "youtubeMember" to "4.99",
        "bit" to "0.01",
        "kick" to "0.01"
    )

    fun price(key: String) = Prefs.string("goalPrice.$key", defaults[key].orEmpty()).toBigDecimalOrNull() ?: BigDecimal.ZERO

    fun set(key: String, value: BigDecimal) = Prefs.put("goalPrice.$key", value.toPlainString())

    /** The money an event carries, in its own currency; null for messages, follows, raids. A gift of n subs is n subs. */
    fun money(e: ChatEvent): Money? = when (e.kind) {
        Kind.Tip -> e.money ?: if (e.amountCents > 0) Money(BigDecimal(e.amountCents).movePointLeft(2), "USD") else null
        Kind.Cheer -> if (e.count > 0) Money(BigDecimal(e.count) * price(if (e.platform == "kick") "kick" else "bit"), "USD") else null
        Kind.Subscribe -> {
            val each = when (e.platform) {
                "twitch" -> price("twitchTier${e.tier.coerceIn(1, 3)}")
                "youtube" -> price("youtubeMember")
                else -> price("kickSub")
            }
            Money(each * BigDecimal(maxOf(e.count, 1)), "USD")
        }
        else -> null
    }
}

/**
 * A tip's worth in US cents, for thresholds (big alert, minimum spoken tip): a site's tip in its own currency at today's
 * rate, else the platform's cents; 0 when no rate.
 */
val ChatEvent.tipCents: Int
    get() = money?.let { m -> Rates.convert(m, "USD")?.movePointRight(2)?.toInt() ?: 0 } ?: amountCents
