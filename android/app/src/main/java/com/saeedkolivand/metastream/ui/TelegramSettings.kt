package com.saeedkolivand.metastream.ui

import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.platforms.TokenStore
import com.saeedkolivand.metastream.reach.InstagramStory
import com.saeedkolivand.metastream.reach.LivePost
import com.saeedkolivand.metastream.reach.Telegram
import com.saeedkolivand.metastream.streaming.Engine
import kotlinx.coroutines.launch

/** Settings › Telegram (iOS TelegramSettingsView): the bot and channel behind the Live post, and what it may show. */
@Composable
internal fun TelegramPage() {
    val scope = rememberCoroutineScope()
    var token by remember { mutableStateOf("") }
    var hasToken by remember { mutableStateOf(TokenStore.get("telegramToken") != null) }
    var status by remember { mutableStateOf("") }
    var checking by remember { mutableStateOf(false) }
    Section("Telegram") {
        PrefSwitch("Live post", "telegramOn", false)
        // Never loaded back into the field: the saved token stays encrypted, the field only takes a new one.
        Field(if (hasToken) "Bot token (saved, type to replace)" else "Bot token", token, { token = it })
        Button({
            TokenStore.set("telegramToken", token.trim())
            token = ""
            hasToken = true
        }, enabled = token.isNotBlank()) { Text("Save token") }
        PrefField("Channel (@yourchannel)", "telegramChannel", "")
        OutlinedButton({
            checking = true
            scope.launch {
                status = Telegram.check()
                checking = false
            }
        }, enabled = !checking) { Text(if (checking) "Checking…" else "Check bot") }
        if (status.isNotEmpty()) Note(status)
        Footnote(
            "1. Message @BotFather, send /newbot, paste the token above.\n2. Add the bot as an admin of your channel with only Post, Edit and Delete messages.\n3. Enter the channel and tap Check bot."
        )
    }
    Section("Announce") {
        when (LivePost.phase) {
            "announced" -> OutlinedButton({ LivePost.cancelAnnouncement() }) { Text("Cancel announcement") }
            null -> Button({ LivePost.announce() }, enabled = LivePost.enabled && !Engine.live) { Text("Announce: going live soon") }
            else -> Note("The live post is running")
        }
        Footnote("Posts \"going live soon\" now; GO LIVE turns it into the live post. Not live within an hour, it's edited to cancelled.")
    }
    Section("Post") {
        var lang by remember { mutableStateOf(Prefs.string("telegramLang", "fa")) }
        Choice("Language", listOf("fa" to "فارسی", "en" to "English"), lang) {
            lang = it
            Prefs.put("telegramLang", it)
        }
        PrefSwitch("Show donation total in recap", "telegramShowTotal", true)
        PrefField("Big donation moment (€)", "momentDonationEUR", "20")
        PrefSwitch("Moment pings", "telegramPings", true)
        Footnote(
            "A short reply to the live post when chat spikes, a big donation lands or a raid comes in; at most one per 15 min and 4 per stream, deleted when the stream ends. The language only changes the labels."
        )
        PrefSwitch("Show city", "telegramShowCity", false)
        Footnote("The post stays in the channel after the stream, so the city does too.")
    }
    Section("Instagram story") {
        val ctx = LocalContext.current
        val ready = remember { InstagramStory.available(ctx) }
        var tpl by remember { mutableStateOf(InstagramStory.template) }
        Choice("Card", InstagramStory.Template.entries.map { it to it.title }, tpl) {
            tpl = it
            Prefs.put("igStoryTemplate", it.name)
        }
        Button({
            scope.launch { InstagramStory.share(ctx) }
        }, enabled = ready) { Text(if (Engine.live) "Share to Instagram story" else "Share \"live soon\" story") }
        OutlinedButton({ scope.launch { InstagramStory.share(ctx, test = true) } }, enabled = ready) { Text("Test share") }
        Footnote(
            if (ready) {
                "Opens Instagram's story editor with the card (a frame of the stream while live). Add the Link sticker in the empty lower part."
            } else {
                "Needs Instagram installed and the Meta app ID in the build."
            }
        )
    }
}
