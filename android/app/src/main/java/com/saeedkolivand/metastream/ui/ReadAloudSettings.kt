package com.saeedkolivand.metastream.ui

import android.speech.tts.Voice
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.speech.BoolPref
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.speech.SpeechSettings

private fun Voice.label() = locale.displayName + " · " + name

@Composable
private fun VoicePicker() {
    var open by remember { mutableStateOf(false) }
    val current = Speaker.voices.firstOrNull { it.name == SpeechSettings.voice }
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text("Voice")
        OutlinedButton({ open = true }) { Text(current?.label() ?: "System default") }
        DropdownMenu(open, { open = false }) {
            DropdownMenuItem({ Text("System default") }, {
                SpeechSettings.pickVoice("")
                open = false
            })
            for (v in Speaker.voices) {
                DropdownMenuItem({ Text(v.label()) }, {
                    SpeechSettings.pickVoice(v.name)
                    Speaker.applyVoice()
                    Speaker.preview("This is how chat will sound")
                    open = false
                })
            }
        }
    }
}

@Composable
private fun PrefSwitch(label: String, pref: BoolPref, after: () -> Unit = {}) = ToggleRow(label, pref.value) {
    pref.set(it)
    after()
}

/** Read-aloud settings as iOS ReadAloudSettingsView: voice, speed, per-event toggles, tip floor, per-platform chat. Self-contained so any sheet can host it. */
@Composable
internal fun ReadAloudSettings() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        VoicePicker()
        Note("Voices installed on this phone (system Settings > Text-to-speech output adds more).")
        PrefSwitch("Chat messages", SpeechSettings.messages)
        PrefSwitch("Tips and bits", SpeechSettings.tips)
        PrefSwitch("Follows", SpeechSettings.follows)
        PrefSwitch("Subscriptions", SpeechSettings.subs)
        PrefSwitch("Raids", SpeechSettings.raids)
        Text("Speed")
        Slider(SpeechSettings.rate, {
            SpeechSettings.pickRate(it)
            Speaker.applyVoice()
        }, valueRange = 0.35f..0.65f)
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Text("Read tips from $${SpeechSettings.minTipCents / 100}")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton({ SpeechSettings.pickMinTip((SpeechSettings.minTipCents - 100).coerceAtLeast(0)) }) { Text("−") }
                OutlinedButton({ SpeechSettings.pickMinTip((SpeechSettings.minTipCents + 100).coerceAtMost(5000)) }) { Text("+") }
            }
        }
        PrefSwitch("Kick chat", SpeechSettings.kickChat) { ChatFeed.restartKick() }
        PrefSwitch("Twitch chat", SpeechSettings.twitchChat) { ChatFeed.restartTwitch() }
        PrefSwitch("YouTube chat", SpeechSettings.youtubeChat) { ChatFeed.restartYouTube() }
        val missing = Twitch.missingScopeFeatures
        if (Twitch.connected && missing.isNotEmpty()) {
            Note("Reconnect Twitch in Stream Manager to enable ${missing.joinToString(", ")}.", Orange)
        }
        Note("The tts pill on the live screen silences chat and alerts; stream warnings such as a dropped connection always speak.")
    }
}
