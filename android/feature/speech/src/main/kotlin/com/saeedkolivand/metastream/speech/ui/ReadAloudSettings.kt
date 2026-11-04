package com.saeedkolivand.metastream.ui

import android.speech.tts.Voice
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.ChatModerator
import com.saeedkolivand.metastream.chat.ChatSettings
import com.saeedkolivand.metastream.core.storage.BoolPref
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.NavRow
import com.saeedkolivand.metastream.core.ui.Orange
import com.saeedkolivand.metastream.core.ui.RadioRow
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SliderRow
import com.saeedkolivand.metastream.core.ui.Stepper
import com.saeedkolivand.metastream.core.ui.SwitchRow
import com.saeedkolivand.metastream.core.ui.TextRow
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.speech.SpeechSettings

private fun Voice.label() = name + when {
    quality >= Voice.QUALITY_VERY_HIGH -> " (very high)"
    quality >= Voice.QUALITY_HIGH -> " (high)"
    else -> ""
}

@Composable
private fun PrefSwitch(label: String, pref: BoolPref, after: () -> Unit = {}) = SwitchRow(label, pref.value) {
    pref.set(it)
    after()
}

/** iOS ReadAloudSettingsView: chat origin and channel, voice, don't read, then what is read and how. */
@Composable
internal fun ReadAloudSettings(openVoice: () -> Unit, openBlocked: () -> Unit) {
    // The engine is created on demand; opening this page is a demand, so the voice page has voices to show.
    LaunchedEffect(Unit) { Speaker.prepare() }
    Section("Chat") {
        // ponytail: Android keeps a Kick and a Twitch channel; the origin picks which one the channel row edits.
        var origin by remember {
            mutableStateOf(
                Prefs.string(
                    "chatOrigin",
                    if (ChatFeed.kickSlug.isBlank() &&
                        ChatFeed.twitchChannel.isNotBlank()
                    ) {
                        "twitch"
                    } else {
                        "kick"
                    }
                )
            )
        }
        Choice("Chat origin", listOf("kick" to "Kick", "twitch" to "Twitch"), origin) {
            origin = it
            Prefs.put("chatOrigin", it)
        }
        if (origin == "kick") {
            TextRow("Channel name", ChatFeed.kickSlug, ChatFeed::setKick)
        } else {
            TextRow("Channel name", ChatFeed.twitchChannel, ChatFeed::setTwitch)
        }
    }
    Section(
        null,
        "The highest-quality voices sound the most human: add one in system Settings › Text-to-speech output › engine " +
            "settings › Install voice data, then reopen this app."
    ) {
        NavRow(
            "Voice",
            value = Speaker.voices.firstOrNull {
                it.name == SpeechSettings.voice
            }?.label() ?: "Best installed",
            onClick = openVoice
        )
    }
    Section(null, "Blocked names and words.") {
        val count = listOf(SpeechSettings.ignored, ChatSettings.blocked).flatMap { it.split(",") }.count { it.isNotBlank() }
        NavRow("Don't read", value = if (count == 0) "None" else "$count", onClick = openBlocked)
    }
    Section(
        null,
        "Chat is spoken through whatever is playing audio, such as the glasses' speakers. The tts pill on the live screen " +
            "silences chat and alerts; stream warnings always speak. Use the phone microphone if viewers hear an echo."
    ) {
        PrefSwitch("Chat messages", SpeechSettings.messages)
        PrefSwitch("Tips and bits", SpeechSettings.tips)
        PrefSwitch("Follows", SpeechSettings.follows)
        PrefSwitch("Subscriptions", SpeechSettings.subs)
        PrefSwitch("Raids", SpeechSettings.raids)
        SliderRow("Speed", "", SpeechSettings.rate, 0.35f..0.65f) {
            SpeechSettings.pickRate(it)
            Speaker.applyVoice()
        }
        Stepper(
            "Read tips from $${SpeechSettings.minTipCents / 100}",
            SpeechSettings.minTipCents,
            0..5000,
            100,
            onChange = SpeechSettings::pickMinTip
        )
        PrefSwitch("Kick chat", ChatSettings.kickChat) { ChatFeed.restartKick() }
        PrefSwitch("Twitch chat", ChatSettings.twitchChat) { ChatFeed.restartTwitch() }
        PrefSwitch("YouTube chat", ChatSettings.youtubeChat) { ChatFeed.restartYouTube() }
        val missing = Twitch.missingScopeFeatures
        if (Twitch.connected && missing.isNotEmpty()) {
            Text("Reconnect Twitch in Stream Manager to enable ${missing.joinToString(", ")}.", color = Orange, fontSize = 13.sp)
        }
    }
}

/** iOS .pickerStyle(.navigationLink) voice picker: its own page, voices grouped by language, best first. */
@Composable
internal fun VoicePage() {
    LaunchedEffect(Unit) { Speaker.prepare() }
    fun pick(name: String) {
        SpeechSettings.pickVoice(name)
        Speaker.applyVoice()
        if (name.isNotEmpty()) Speaker.preview("This is how chat will sound")
    }
    Section(null) { RadioRow("Best installed", SpeechSettings.voice.isEmpty()) { pick("") } }
    val groups = remember(Speaker.voices) {
        Speaker.voices.groupBy { it.locale.displayName }.toSortedMap().mapValues { (_, v) ->
            v.sortedWith(compareByDescending<Voice> { it.quality }.thenBy { it.name })
        }
    }
    for ((language, voices) in groups) {
        Section(language) { for (v in voices) RadioRow(v.label(), SpeechSettings.voice == v.name) { pick(v.name) } }
    }
}

/** iOS ReadAloudBlockedView: names and words that are never read or shown, and AI moderation (Gemini Nano here). */
@Composable
internal fun DontReadPage() {
    Section(
        "Don't read",
        "Bots (names ending in bot, StreamElements, BotRix, Kicklet...) and !commands are skipped automatically. Messages with " +
            "a slur, \"kys\" or a blocked word aren't read, even disguised as n1gg3r or n i g g e r; a name containing one is " +
            "read as \"someone\". The same messages and names never show in on-stream chat, alert or event widgets. Add words " +
            "in any language, Persian included."
    ) {
        TextRow("Names, e.g. nightbot, spammer123", SpeechSettings.ignored, SpeechSettings::pickIgnored)
        TextRow("Blocked words, comma separated", ChatSettings.blocked, ChatSettings::pickBlocked)
    }
    val note = when (ChatModerator.status) {
        "available" -> ""
        "downloading" -> " The on-device model is downloading; this turns on when it's ready."
        else -> " Not available on this device."
    }
    Section(
        null,
        "Uses Gemini Nano on this device to hide hateful or harassing English messages from stream and speech. Held up to " +
            "1.5 s for review.$note"
    ) {
        var on by remember { mutableStateOf(Prefs.bool("aiModeration", true)) }
        SwitchRow("AI moderation (English)", on, ChatModerator.available) {
            on = it
            Prefs.put("aiModeration", it)
        }
    }
}
