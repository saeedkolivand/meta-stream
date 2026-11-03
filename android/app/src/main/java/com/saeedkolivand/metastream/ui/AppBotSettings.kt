package com.saeedkolivand.metastream.ui

import android.annotation.SuppressLint
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.saeedkolivand.metastream.bot.AppBot
import com.saeedkolivand.metastream.bot.BotCommand
import com.saeedkolivand.metastream.bot.BotList
import com.saeedkolivand.metastream.bot.BotRules
import com.saeedkolivand.metastream.bot.BotTimer
import com.saeedkolivand.metastream.bot.TwitchBot
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.ActionRow
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.NavRow
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SwitchRow
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.KickWeb
import com.saeedkolivand.metastream.platforms.Twitch
import kotlinx.coroutines.launch

/** A Prefs-backed switch. */
@Composable
internal fun PrefSwitch(label: String, key: String, default: Boolean, enabled: Boolean = true) {
    var on by remember(key) { mutableStateOf(Prefs.bool(key, default)) }
    SwitchRow(label, on, enabled) {
        on = it
        Prefs.put(key, it)
    }
}

/** A Prefs-backed text field; an emptied template saves "" and so posts nothing. */
@Composable
internal fun PrefField(label: String, key: String, default: String) {
    var text by remember(key) { mutableStateOf(Prefs.string(key, default)) }
    Field(label, text, {
        text = it
        Prefs.put(key, it)
    })
}

/** iOS AppBotSettingsView: the app's own chat account, never posting as the streamer. Messages and Timers are their own pages. */
@Composable
internal fun AppBotPage(openMessages: () -> Unit, openTimers: () -> Unit) {
    Section(
        null,
        "Posts only while you are live, never as you. Test mode lets it answer you and your mods (no one else) and post " +
            "notices while offline; turn it off when done."
    ) {
        PrefSwitch("App bot on Kick", "botKick", false, Kick.connected)
        PrefSwitch("App bot on Twitch", "botTwitch", false, Twitch.connected)
        PrefSwitch("Test mode", "botTestMode", false)
        if (AppBot.status.isNotEmpty()) Text(AppBot.status, color = Secondary, fontSize = 13.sp)
    }
    Section(
        "Twitch bot account",
        "Kick: the bot posts as Kick's app bot on your channel once Kick is connected. Twitch: connect a second account here " +
            "(make it a mod of your channel)."
    ) {
        if (TwitchBot.name.isEmpty()) {
            ActionRow("Connect bot account", Twitch.connected, onClick = TwitchBot::connect)
        } else {
            Text("Connected as ${TwitchBot.name}", fontSize = 17.sp)
            ActionRow("Disconnect", destructive = true, onClick = TwitchBot::disconnect)
        }
    }
    Section(
        "Viewer commands",
        "Once per 30 s per command and platform; mods and you skip that. !location says region and country only. !song posts " +
            "the Spotify song with its link (Settings › Spotify). The !donate answer is in Messages."
    ) {
        for (cmd in AppBot.commands - BotRules.donateAliases.toSet()) PrefSwitch(cmd, BotRules.switchKey(cmd), true)
        PrefSwitch("Hide location", "botHideLocation", false)
    }
    Section(null, "What the bot posts for scene changes, donate questions and thank-yous, and repeating timers.") {
        val messages = listOf("botNotices", "botThanks").count { Prefs.bool(it, true) }
        NavRow("Messages", value = if (messages == 0) "Off" else "$messages on", onClick = openMessages)
        val timers = BotTimer.stored().size
        NavRow("Timers", value = if (Prefs.bool("botTimersOn", false) && timers > 0) "$timers" else "Off", onClick = openTimers)
    }
}

@Composable
private fun Tpl(label: String, key: String) = PrefField(label, key, AppBot.defaults.getValue(key))

/** iOS AppBotMessagesView: scene notices, the !donate answer and thank-yous. An emptied template posts nothing. */
@Composable
internal fun AppBotMessagesPage() {
    Section(
        null,
        "Empty = don't post. With no scene set to the BRB role, a weak connection only posts the BRB lines and the stream " +
            "stays on camera. The BRB line goes out at most once per 2 min."
    ) {
        PrefSwitch("Scene notices", "botNotices", true)
        Tpl("BRB starts", "botTplBrbOn")
        Tpl("BRB ends", "botTplBrbOff")
        Tpl("Starting scene", "botTplStartingOn")
        Tpl("Starting ends (live)", "botTplStartingOff")
        Tpl("Ending scene", "botTplEndingOn")
    }
    Section(
        "Viewer commands",
        "!donate (also !tip, !support, !donation) answers with this: {title}, {total}, {target}, {percent} and {url}."
    ) {
        Tpl("Donate answer", "botTplDonate")
    }
    Section(null, "{user} and {count}. Empty = don't post.") {
        PrefSwitch("Thank-yous", "botThanks", true)
        Tpl("Follow", "botTplFollow")
        Tpl("Sub", "botTplSub")
        Tpl("Gifted subs", "botTplGift")
        Tpl("Raid", "botTplRaid")
    }
}

/** iOS AppBotTimersView: repeating messages while live. */
@Composable
internal fun AppBotTimersPage() {
    Section(
        null,
        "A timer posts when its interval has passed and at least 5 viewers chatted since its last post; timers wait 5 min " +
            "after each other."
    ) {
        PrefSwitch("Timers", "botTimersOn", false)
        TimersEditor()
    }
}

/** The kick.com session the unofficial Kick commands run through (iOS KickSessionSection, adr/0005). */
@Composable
private fun KickSessionSection() {
    var signingIn by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { KickWeb.refresh() }
    Section(
        "kick.com session (unofficial)",
        "Used for /poll, /raid, /clear, /clip, /mod, /vip and chat modes, which Kick's API doesn't offer. Unofficial: Kick can " +
            "change it any time."
    ) {
        Text(if (KickWeb.signedIn) "Signed in as ${KickWeb.user}" else "Not signed in", fontSize = 17.sp)
        ActionRow("Sign in to kick.com") { signingIn = true }
        if (KickWeb.signedIn) ActionRow("Sign out", destructive = true, onClick = KickWeb::signOut)
    }
    if (signingIn) {
        val scope = rememberCoroutineScope()
        val close = {
            signingIn = false
            scope.launch { KickWeb.refresh() }
            Unit
        }
        Dialog(close, DialogProperties(usePlatformDefaultWidth = false)) {
            Column(Modifier.fillMaxSize().background(Color.Black)) {
                Row(Modifier.fillMaxWidth().padding(8.dp), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                    Text("kick.com", color = Color.White, fontWeight = FontWeight.Bold)
                    TextButton(close) { Text("Done", fontWeight = FontWeight.Bold) }
                }
                // The user signs in themselves; the cookies land in the app's shared WebView store, where KickWeb reads them.
                AndroidView({ c ->
                    WebView(c).apply {
                        @SuppressLint("SetJavaScriptEnabled")
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        webViewClient = WebViewClient()
                        loadUrl("https://kick.com/login")
                    }
                }, Modifier.fillMaxSize())
            }
        }
    }
}

/** Settings › Commands (iOS CommandsSettingsView): saved commands, the notification button and the kick.com session. */
@Composable
internal fun CommandsPage() {
    Section(
        null,
        "Sent as your own account, so bots that obey only the broadcaster accept them. A command starting with / (like /clear) " +
            "runs as a moderator command instead of being posted. These are examples; check your bot's dashboard for its exact commands."
    ) { CommandsEditor() }
    // Android's live notification holds one command button (iOS: up to 3 Lock Screen buttons on the live card).
    Section(null, "Shows that command as a button on the live notification and Lock Screen. A tap in your pocket could fire it.") {
        var pick by remember { mutableStateOf(Prefs.string("notifyCommand")) }
        Choice("Notification button", listOf("" to "None") + BotCommand.stored().map { it.text to it.text }, pick) {
            pick = it
            Prefs.put("notifyCommand", it)
        }
    }
    KickSessionSection()
}

/** Settings › Known bots (iOS BotsSettingsView): who counts as a bot and which bot lines are announcements. */
@Composable
internal fun KnownBotsPage() {
    Section(
        "Bots",
        "Comma-separated. Names ending in “bot” always count. Bots are hidden from stream chat widgets when Hide bots is on."
    ) { PrefField("Bot names", "botNames", BotList.DEFAULT_NAMES) }
    Section(
        "Announcements",
        "A bot message with a trigger word (whole word, comma-separated) is an announcement: it buzzes your phone and is " +
            "highlighted in chat, whatever the read setting."
    ) {
        var mode by remember { mutableStateOf(Prefs.string("botReadMode", "triggers")) }
        Choice("Read bot messages", listOf("off" to "Never", "triggers" to "Announcements only", "all" to "All"), mode) {
            mode = it
            Prefs.put("botReadMode", it)
        }
        PrefField("Trigger words", "botTriggers", BotList.DEFAULT_TRIGGERS)
    }
}
