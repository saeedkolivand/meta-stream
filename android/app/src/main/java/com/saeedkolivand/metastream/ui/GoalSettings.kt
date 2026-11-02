package com.saeedkolivand.metastream.ui

import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.Kind
import com.saeedkolivand.metastream.goal.DonatePage
import com.saeedkolivand.metastream.goal.DonationPrices
import com.saeedkolivand.metastream.goal.EntryState
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.goal.Money
import com.saeedkolivand.metastream.goal.Rates
import java.math.BigDecimal
import java.text.DateFormat
import java.util.Date

private val CURRENCIES = listOf("IRT" to "Toman", "EUR" to "Euro", "USD" to "US dollar")

/** iOS GoalSettingsView + GoalSubScreens: the goal, manual and test donations, rates and prices, the donation list. */
@Composable
internal fun GoalPage() {
    val c = GoalStore.config
    var title by remember { mutableStateOf(c.title) }
    var target by remember { mutableStateOf(c.target.toPlainString()) }
    var start by remember { mutableStateOf(c.start.toPlainString()) }
    var currency by remember { mutableStateOf(c.currency) }
    val t = Money.parse(target)
    val s = Money.parse(start)
    Section("Goal") {
        Field("Title", title, { title = it })
        Field("Target", target, { target = it })
        Field("Already raised", start, { start = it })
        Choice("Currency", CURRENCIES, currency) { currency = it }
        if (currency == c.currency) {
            Button({ GoalStore.update(title, t!!, s!!) }, enabled = t != null && s != null) { Text("Save") }
        } else {
            Button({
                GoalStore.reset(title, t!!, currency, s!!)
            }, enabled = t != null && s != null) { Text("Start a new goal in ${CURRENCIES.toMap()[currency]}") }
        }
        OutlinedButton({ GoalStore.reset(title, t ?: c.target, c.currency, s ?: BigDecimal.ZERO) }) { Text("Reset goal") }
        Footnote(
            "Donations are counted in the goal's currency when they arrive and keep that value. Another currency starts a new goal; reset clears the list."
        )
    }
    Section("Status") {
        Text("Raised ${GoalStore.money(GoalStore.total)} / ${GoalStore.money(c.target)} (${(GoalStore.progress * 100).toInt()}%)")
        if (GoalStore.pendingCount > 0) Note("${GoalStore.pendingCount} waiting for a rate")
    }
    AddAndTest()
    RatesAndPrices()
    Section("Recent donations (${GoalStore.entries.size})") {
        for (e in GoalStore.entries.take(30)) {
            val state = when (e.state) {
                EntryState.Pending -> " · waiting for a rate"
                EntryState.Refunded -> " · refunded"
                EntryState.Test -> " · test"
                EntryState.Counted -> if (e.missed) " · found later" else ""
            }
            Text("${e.original.display}${e.value?.let { " = ${GoalStore.money(it)}" }.orEmpty()} · ${e.source}$state")
            Note(
                listOf(e.note, DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(e.at))).filter {
                    it.isNotEmpty()
                }.joinToString(" · ")
            )
        }
    }
}

/** The page URL and its key; the key is never loaded back into the field (iOS does the same). */
@Composable
internal fun DonatePagePage() {
    var url by remember { mutableStateOf(DonatePage.pageURL) }
    var key by remember { mutableStateOf("") }
    var hasKey by remember { mutableStateOf(DonatePage.hasToken) }
    Section("Donate page") {
        Field("Page address", url, { url = it })
        OutlinedButton({ DonatePage.setURL(url) }, enabled = url.trim() != DonatePage.pageURL) { Text("Save address") }
        Field(if (hasKey) "Page key (saved, type to replace)" else "Page key", key, { key = it })
        Button({
            DonatePage.setToken(key)
            key = ""
            hasKey = DonatePage.hasToken
        }, enabled = key.isNotBlank()) { Text("Save key") }
        if (hasKey) {
            OutlinedButton({
                DonatePage.setToken("")
                hasKey = false
            }) { Text("Remove key") }
        }
        Note(DonatePage.status)
        Footnote(
            "The page shows the goal and LIVE while you stream. The key is only sent over https, to the address it was saved for: change the address and enter the key again."
        )
    }
}

@Composable
private fun AddAndTest() {
    var amount by remember { mutableStateOf("") }
    var cur by remember { mutableStateOf(GoalStore.config.currency) }
    var note by remember { mutableStateOf("") }
    Section("Add amount") {
        Field("Amount", amount, { amount = it })
        Choice("Currency", CURRENCIES, cur) { cur = it }
        Field("Note", note, { note = it })
        val d = Money.parse(amount)
        Button({
            GoalStore.addManual(Money(d!!, cur), note)
            amount = ""
            note = ""
        }, enabled = d != null && d.signum() != 0) { Text("Add") }
        Footnote("Cash or a bank transfer. A negative amount corrects a mistake.")
    }
    var test by remember { mutableStateOf("10") }
    var testCur by remember { mutableStateOf("EUR") }
    Section("Test donation") {
        Field("Amount", test, { test = it })
        Choice("Currency", CURRENCIES + ("BITS" to "Bits"), testCur) { testCur = it }
        Button({
            if (testCur == "BITS") {
                ChatFeed.onChat(ChatEvent("test-donation", "Test", "Test donation", kind = Kind.Cheer, count = 100))
                GoalStore.test(Money(BigDecimal(100) * DonationPrices.price("bit"), "USD"))
            } else {
                Money.parse(test)?.takeIf { it.signum() > 0 }?.let { Money(it, testCur) }?.let { m ->
                    GoalStore.test(m)
                    ChatFeed.onChat(ChatEvent("test-donation", "Test", "Test donation", kind = Kind.Tip, money = m))
                }
            }
        }) { Text("Send test donation") }
        Footnote("Moves the bar for 10 seconds and shows the alert. Bits sends 100 Bits. Not counted.")
    }
}

@Composable
private fun RatesAndPrices() {
    Section("Rates") {
        Text("Toman per euro: ${Rates.tomanPerEuro?.let { Money(it, "IRT").display } ?: "—"}")
        Note(Rates.tomanSource)
        PrefField("Your toman per euro (empty = market)", "goalManualTomanPerEUR", "")
        Footnote(
            "The free-market rate (Nobitex's toman per USDT, the ECB's euro), never the official rial rate. A donation with no rate under a day old waits."
        )
    }
    Section("What subs, Bits and KICKs are worth (USD)") {
        val labels = mapOf(
            "kickSub" to "Kick sub",
            "twitchTier1" to "Twitch tier 1",
            "twitchTier2" to "Twitch tier 2",
            "twitchTier3" to "Twitch tier 3",
            "youtubeMember" to "YouTube member",
            "bit" to "One Bit",
            "kick" to "One KICK"
        )
        for ((key, label) in labels) {
            var v by remember { mutableStateOf(DonationPrices.price(key).toPlainString()) }
            Field(label, v, {
                v = it
                Money.parse(it)?.takeIf { d -> d.signum() >= 0 }?.let { d -> DonationPrices.set(key, d) }
            })
        }
        Footnote("Face value: what the viewer paid, not the streamer's share.")
    }
}
