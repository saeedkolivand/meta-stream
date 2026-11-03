package com.saeedkolivand.metastream.ui

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.platforms.TokenStore
import com.saeedkolivand.metastream.reach.Telegram
import kotlinx.coroutines.launch

/** Settings › Telegram (iOS TelegramSettingsView): the bot and channel behind the Live post, and what it may show. */
@Composable
internal fun TelegramPage() {
    val scope = rememberCoroutineScope()
    var token by remember { mutableStateOf("") }
    var hasToken by remember { mutableStateOf(TokenStore.get("telegramToken") != null) }
    var status by remember { mutableStateOf("") }
    var checking by remember { mutableStateOf(false) }
    Section(
        "Telegram",
        "1. Message @BotFather, send /newbot, paste the token above.\n2. Add the bot as an admin of your channel with only Post, " +
            "Edit and Delete messages.\n3. Enter the channel and tap Check bot."
    ) {
        PrefSwitch("Live post", "telegramOn", false)
        // Never loaded back into the field: the saved token stays encrypted, the field only takes a new one.
        TextRow(if (hasToken) "Key saved (enter a new one to replace)" else "Bot token", token, { token = it }, secure = true)
        ActionRow("Save", token.isNotBlank()) {
            TokenStore.set("telegramToken", token.trim())
            token = ""
            hasToken = true
        }
        PrefField("@yourchannel", "telegramChannel", "")
        ActionRow(if (checking) "Checking…" else "Check bot", !checking) {
            checking = true
            scope.launch {
                status = Telegram.check()
                checking = false
            }
        }
        if (status.isNotEmpty()) Text(status, color = Secondary, fontSize = 13.sp)
    }
    Section("Post", "The language only changes the labels; titles and names stay as you typed them.") {
        var lang by remember { mutableStateOf(Prefs.string("telegramLang", "fa")) }
        Choice("Language", listOf("fa" to "فارسی", "en" to "English"), lang) {
            lang = it
            Prefs.put("telegramLang", it)
        }
        PrefSwitch("Show donation total in recap", "telegramShowTotal", true)
        var big by remember { mutableStateOf(Prefs.string("momentDonationEUR", "20").toDoubleOrNull()?.toInt() ?: 20) }
        Stepper("Big donation moment (€$big)", big, 1..1000, 5) {
            big = it
            Prefs.put("momentDonationEUR", "$it")
        }
    }
    Section(
        null,
        "A short reply to the live post when chat spikes, a big donation lands or a raid comes in; at most one per 15 min and " +
            "4 per stream, deleted when the stream ends."
    ) { PrefSwitch("Moment pings", "telegramPings", true) }
    Section(null, "Adds your city to the live post. The post stays in the channel after the stream, so the city does too.") {
        PrefSwitch("Show city", "telegramShowCity", false)
    }
}
