package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.bot.AppBot
import com.saeedkolivand.metastream.bot.BotCommand
import com.saeedkolivand.metastream.bot.BotList
import com.saeedkolivand.metastream.bot.BotRules
import com.saeedkolivand.metastream.bot.TwitchBot
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.Twitch

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

/** iOS AppBotSettingsView: the app's own chat account, never posting as the streamer. */
@Composable
internal fun AppBotPage() {
    if (AppBot.status.isNotEmpty()) Note(AppBot.status)
    Section("Accounts") {
        PrefSwitch("Kick (the app's bot account)", "botKick", false, Kick.connected)
        if (!Kick.connected) Footnote("Connect Kick in Stream Manager first; the bot posts as Kick's app bot on your channel.")
        PrefSwitch("Twitch", "botTwitch", false, Twitch.connected)
        Row {
            if (TwitchBot.name.isEmpty()) {
                Button(TwitchBot::connect, enabled = Twitch.connected) { Text("Connect Twitch bot account") }
            } else {
                OutlinedButton(TwitchBot::disconnect) { Text("Disconnect ${TwitchBot.name}") }
            }
        }
        Footnote("Twitch needs a second account for the bot: sign in to it on the activate page (a private tab helps).")
        PrefSwitch("Test mode (works while offline)", "botTestMode", false)
        Footnote("Offline, only you and your mods get answers. Timers stay live-only.")
    }
    Section("Scene notices") {
        PrefSwitch("Post scene notices", "botNotices", true)
        for ((key, label) in listOf(
            "botTplStartingOn" to "Starting scene up",
            "botTplStartingOff" to "Starting scene over",
            "botTplBrbOn" to "Weak connection (BRB)",
            "botTplBrbOff" to "Back from BRB",
            "botTplEndingOn" to "Ending scene"
        )) {
            PrefField(label, key, AppBot.defaults.getValue(key))
        }
    }
    Section("Thank-yous") {
        PrefSwitch("Thank followers, subs, gifts and raids", "botThanks", true)
        for ((key, label) in listOf(
            "botTplFollow" to "Follow",
            "botTplSub" to "Sub",
            "botTplGift" to "Gifted subs",
            "botTplRaid" to "Raid"
        )) {
            PrefField(label, key, AppBot.defaults.getValue(key))
        }
        Footnote("{user} is the name, {count} the gifts or raiders.")
    }
    Section("Viewer commands") {
        for (cmd in AppBot.commands - BotRules.donateAliases.toSet()) PrefSwitch(cmd, BotRules.switchKey(cmd), true)
        PrefSwitch("Hide location (!location says it's private)", "botHideLocation", false)
        PrefField("!donate reply ({title} {total} {target} {percent} {url})", "botTplDonate", AppBot.defaults.getValue("botTplDonate"))
        Footnote(
            "!tip, !support and !donation answer like !donate. Each command answers once per 30 s per platform; you and your mods skip the wait."
        )
    }
    Section("Timers") {
        PrefSwitch("Repeat timers while live", "botTimersOn", false)
        TimersEditor()
        Footnote("A timer waits for its interval (5 min at least) and 5 chat messages, and 5 min after any other timer.")
    }
    Section("Saved commands") {
        CommandsEditor()
        var pick by remember { mutableStateOf(Prefs.string("notifyCommand")) }
        Choice("Notification button", listOf("" to "None") + BotCommand.stored().map { it.text to it.text }, pick) {
            pick = it
            Prefs.put("notifyCommand", it)
        }
        Footnote("Shows that command as a button on the live notification and Lock Screen. A tap in your pocket could fire it.")
    }
    Section("Other bots") {
        PrefField("Bot names", "botNames", BotList.DEFAULT_NAMES)
        PrefField("Trigger words", "botTriggers", BotList.DEFAULT_TRIGGERS)
        var mode by remember { mutableStateOf(Prefs.string("botReadMode", "triggers")) }
        Choice("Read bots aloud", listOf("off" to "Never", "triggers" to "Trigger words", "all" to "Always"), mode) {
            mode = it
            Prefs.put("botReadMode", it)
        }
        Footnote("Names ending in \"bot\" always count. A bot line with a trigger word (\"won\") is read aloud.")
    }
}
