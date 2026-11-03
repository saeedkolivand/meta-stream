package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import com.saeedkolivand.metastream.core.model.Money
import com.saeedkolivand.metastream.goal.DonatePage
import com.saeedkolivand.metastream.goal.DonationPrices
import com.saeedkolivand.metastream.goal.EntryState
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.goal.Rates
import java.math.BigDecimal
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.launch

private val CURRENCIES = listOf("IRT" to "Toman", "EUR" to "Euro", "USD" to "US dollar")

/** iOS GoalSettingsView: the goal, status, manual and test donations; rates and the donation list are one level down. */
@Composable
internal fun GoalPage(openRates: () -> Unit, openRecent: () -> Unit) {
    val c = GoalStore.config
    var title by remember { mutableStateOf(c.title) }
    var target by remember { mutableStateOf(c.target.toPlainString()) }
    var start by remember { mutableStateOf(c.start.toPlainString()) }
    var currency by remember { mutableStateOf(c.currency) }
    val t = Money.parse(target)
    val s = Money.parse(start)
    Section(
        "Goal",
        "Donations are counted in the goal's currency when they arrive and keep that value. Another currency starts a new goal; " +
            "reset clears the list."
    ) {
        TextRow("Title", title, { title = it })
        TextRow("Target", target, { target = it }, keyboard = KeyboardType.Decimal)
        TextRow("Already raised", start, { start = it }, keyboard = KeyboardType.Decimal)
        Choice("Currency", CURRENCIES, currency) { currency = it }
        if (currency == c.currency) {
            ActionRow("Save", t != null && s != null) { GoalStore.update(title, t!!, s!!) }
        } else {
            ActionRow("Start a new goal in ${CURRENCIES.toMap()[currency]}", t != null && s != null, destructive = true) {
                GoalStore.reset(title, t!!, currency, s!!)
            }
        }
        ActionRow("Reset goal", destructive = true) {
            GoalStore.reset(title, t ?: c.target, c.currency, s ?: BigDecimal.ZERO)
            currency = GoalStore.config.currency
        }
    }
    Section("Status") {
        ValueRow("Raised", "${GoalStore.money(GoalStore.total)} / ${GoalStore.money(c.target)} (${(GoalStore.progress * 100).toInt()}%)")
        if (GoalStore.pendingCount > 0) ValueRow("Waiting for a rate", "${GoalStore.pendingCount}")
    }
    AddAndTest()
    Section(null, "Exchange rates, what subs and Bits are worth, and the donation list.") {
        NavRow("Rates", value = Rates.tomanPerEuro?.let { Money(it, "IRT").display }.orEmpty(), onClick = openRates)
        NavRow("Recent donations", value = "${GoalStore.entries.size}", onClick = openRecent)
    }
}

@Composable
private fun AddAndTest() {
    var amount by remember { mutableStateOf("") }
    var cur by remember { mutableStateOf("EUR") }
    var note by remember { mutableStateOf("") }
    Section("Add amount", "Cash or a bank transfer. A negative amount corrects a mistake.") {
        TextRow("Amount", amount, { amount = it }, keyboard = KeyboardType.Text)
        Choice("Currency", CURRENCIES, cur) { cur = it }
        TextRow("Note", note, { note = it })
        val d = Money.parse(amount)
        ActionRow("Add", d != null && d.signum() != 0) {
            GoalStore.addManual(Money(d!!, cur), note)
            amount = ""
            note = ""
        }
    }
    var test by remember { mutableStateOf("10") }
    var testCur by remember { mutableStateOf("EUR") }
    Section("Test donation", "Moves the bar for 10 seconds and shows the alert. Bits sends 100 Bits. Not counted.") {
        TextRow("Amount", test, { test = it }, keyboard = KeyboardType.Decimal)
        Choice("Currency", CURRENCIES + ("BITS" to "Bits"), testCur) { testCur = it }
        ActionRow("Send test donation") {
            if (testCur == "BITS") {
                ChatFeed.onChat(ChatEvent("test-donation", "Test", "Test donation", kind = Kind.Cheer, count = 100))
                GoalStore.test(Money(BigDecimal(100) * DonationPrices.price("bit"), "USD"))
            } else {
                Money.parse(test)?.takeIf { it.signum() > 0 }?.let { Money(it, testCur) }?.let { m ->
                    GoalStore.test(m)
                    ChatFeed.onChat(ChatEvent("test-donation", "Test", "Test donation", kind = Kind.Tip, money = m))
                }
            }
        }
    }
}

/** iOS GoalRatesView: the rates behind the goal and what subs and Bits are worth in it. */
@Composable
internal fun GoalRatesPage() {
    val scope = rememberCoroutineScope()
    Section("Rates", "Toman from Nobitex, euro from the ECB. Your rate replaces Nobitex; empty = Nobitex.") {
        ValueRow("Toman rate", Rates.tomanSource)
        ValueRow("₮ per €", Rates.tomanPerEuro?.let { Money(it, "IRT").display } ?: "No rate")
        PrefField("Your rate (₮ per €)", "goalManualTomanPerEUR", "")
        ActionRow("Refresh rates") { scope.launch { Rates.refresh() } }
    }
    Section("Values (US dollars)", "What each counts for in the goal.") {
        val labels = listOf(
            "kickSub" to "Kick sub",
            "twitchTier1" to "Twitch Tier 1 / Prime",
            "twitchTier2" to "Twitch Tier 2",
            "twitchTier3" to "Twitch Tier 3",
            "youtubeMember" to "YouTube membership",
            "bit" to "Bit",
            "kick" to "KICK"
        )
        for ((key, label) in labels) {
            var v by remember { mutableStateOf(DonationPrices.price(key).toPlainString()) }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(label, Modifier.weight(1f), fontSize = 17.sp)
                Row(Modifier.width(110.dp)) {
                    TextRow("0", v, {
                        v = it
                        Money.parse(it)?.takeIf { d -> d.signum() >= 0 }?.let { d -> DonationPrices.set(key, d) }
                    }, keyboard = KeyboardType.Decimal)
                }
            }
        }
    }
}

@Composable
private fun Badge(text: String, color: Color) = Text(
    text,
    Modifier.background(color.copy(alpha = 0.15f), RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 2.dp),
    color = color,
    fontSize = 11.sp,
    fontWeight = FontWeight.SemiBold
)

/** iOS GoalRecentView: the last 50, newest first; Remove takes one out of the total and keeps it listed as refunded. */
@Composable
internal fun GoalRecentPage() {
    Section(null) {
        if (GoalStore.entries.isEmpty()) Text("None yet", color = Secondary, fontSize = 17.sp)
        for (e in GoalStore.entries.take(50)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).padding(vertical = 4.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(e.original.display, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                        val v = e.value
                        if (v != null &&
                            e.original.currency != GoalStore.config.currency
                        ) {
                            Text("= ${GoalStore.money(v)}", color = Secondary)
                        }
                        if (e.state == EntryState.Pending) Badge("pending", Orange)
                        if (e.state == EntryState.Refunded) Badge("refunded", Red)
                        if (e.state == EntryState.Test) Badge("test", SystemBlue)
                        if (e.missed) Badge("missed", Secondary)
                    }
                    if (e.note.isNotEmpty()) Text(e.note, fontSize = 15.sp, maxLines = 2)
                    val at = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(e.at))
                    Text("${e.source.replaceFirstChar(Char::uppercase)} · $at", color = Secondary, fontSize = 13.sp)
                }
                // ponytail: a Remove button instead of iOS's swipe action.
                if (e.state == EntryState.Counted || e.state == EntryState.Pending) {
                    TextButton({ GoalStore.refund(e.id) }) { Text("Remove", color = Red) }
                }
            }
        }
    }
}

/** iOS DonatePageSettingsView. The key is never loaded back into the field, and only goes to the host it was saved for. */
@Composable
internal fun DonatePagePage() {
    var url by remember { mutableStateOf(DonatePage.pageURL) }
    var key by remember { mutableStateOf("") }
    var hasKey by remember { mutableStateOf(DonatePage.hasToken) }
    Section("Donate page", "Your donate page shows this goal live. Set the same key on Cloudflare (GOAL_TOKEN).") {
        TextRow("Page URL", url, {
            url = it
            DonatePage.setURL(it)
        }, keyboard = KeyboardType.Uri)
        TextRow(if (hasKey) "Key saved (enter a new one to replace)" else "Page key", key, { key = it }, secure = true)
        ActionRow("Save", key.isNotBlank()) {
            DonatePage.setToken(key)
            key = ""
            hasKey = DonatePage.hasToken
        }
        if (hasKey) {
            ActionRow("Remove key", destructive = true) {
                DonatePage.setToken("")
                hasKey = false
            }
        }
        Text(DonatePage.status, color = Secondary, fontSize = 13.sp)
    }
}
