package com.saeedkolivand.metastream.ui

import android.text.format.DateUtils
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.platforms.Accounts
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.platforms.TwitchScopes
import com.saeedkolivand.metastream.platforms.announce
import com.saeedkolivand.metastream.platforms.createClip
import com.saeedkolivand.metastream.platforms.createMarker
import com.saeedkolivand.metastream.platforms.lockdownChat
import com.saeedkolivand.metastream.platforms.raid
import com.saeedkolivand.metastream.platforms.snoozeAd
import com.saeedkolivand.metastream.platforms.startCommercial
import kotlinx.coroutines.launch

/** Hands-free Twitch actions: one decisive tap each, each greyed out until its write scope was granted (iOS twitchActionsSection). */
@Composable
internal fun TwitchActions() {
    val scope = rememberCoroutineScope()
    var announce by remember { mutableStateOf("") }
    var raid by remember { mutableStateOf("") }
    fun has(feature: String) = Twitch.hasScopes(TwitchScopes.action.getValue(feature))
    fun go(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
            } catch (e: com.saeedkolivand.metastream.platforms.PlatformException) {
                Accounts.say(e.message.orEmpty())
            }
        }
    }
    SectionTitle("Quick actions")
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(12.dp)) {
        ActionButton("Clip", has("clips"), Modifier.weight(1f)) { go { Accounts.say("Clip created: ${Twitch.createClip()}") } }
        ActionButton("Marker", Twitch.hasScopes(setOf("channel:manage:broadcast")), Modifier.weight(1f)) {
            go {
                Twitch.createMarker()
                Accounts.say("Marker set")
            }
        }
    }
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text("Next ad")
        val next = Twitch.adNextAt
        Text(
            next?.let {
                DateUtils.getRelativeTimeSpanString(it.toEpochMilli(), System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()
            }
                ?: "unknown",
            color = Color.White.copy(alpha = 0.7f)
        )
    }
    ActionButton("Snooze ad (${Twitch.adSnoozeCount} left)", has("ads") && Twitch.adSnoozeCount > 0, Modifier.fillMaxWidth()) {
        go { Twitch.snoozeAd() }
    }
    ActionButton("Start 90s commercial", has("commercial"), Modifier.fillMaxWidth()) { go { Twitch.startCommercial() } }
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(12.dp), Alignment.CenterVertically) {
        Text("Chat lockdown", Modifier.weight(1f))
        ActionButton("Lock", has("chat lockdown")) { go { Twitch.lockdownChat(true) } }
        ActionButton("Unlock", has("chat lockdown")) { go { Twitch.lockdownChat(false) } }
    }
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp), Alignment.CenterVertically) {
        OutlinedTextField(announce, { announce = it }, Modifier.weight(1f), label = { Text("Announcement") }, singleLine = true)
        ActionButton("Send", has("announcements") && announce.isNotBlank()) {
            val t = announce
            announce = ""
            go { Twitch.announce(t) }
        }
    }
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp), Alignment.CenterVertically) {
        OutlinedTextField(raid, { raid = it }, Modifier.weight(1f), label = { Text("Raid channel") }, singleLine = true)
        ActionButton("Raid", has("raids") && raid.isNotBlank()) {
            val t = raid
            raid = ""
            go { Twitch.raid(t) }
        }
    }
    val missing = Twitch.missingScopeFeatures
    if (missing.isNotEmpty()) {
        Note("Disconnect and reconnect Twitch below to enable ${missing.joinToString(", ")}.", Orange)
    }
}
