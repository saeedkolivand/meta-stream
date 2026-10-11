package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.platforms.Account
import com.saeedkolivand.metastream.platforms.Accounts
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.Restream
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.platforms.YouTube
import com.saeedkolivand.metastream.streaming.Engine
import kotlinx.coroutines.launch

/** Whether the Stream Manager is showing; global so the HUD pill and Settings can open it without plumbing a callback. */
object ManagerState {
    var open by mutableStateOf(false)
}

@Composable
private fun ConnectSection(a: Account) {
    if (a === Twitch && Twitch.userCode.isNotEmpty()) {
        Note("Enter this code on Twitch:")
        Text(Twitch.userCode, fontWeight = FontWeight.Bold, style = androidx.compose.material3.MaterialTheme.typography.headlineMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Note(Twitch.verifyUrl)
            TextButton(Twitch::cancelLogin) { Text("Cancel") }
        }
    } else {
        Button(a::connect, Modifier.fillMaxWidth()) { Text("Connect ${a.label}") }
    }
    if (a === YouTube) Note("Create the live stream in YouTube Studio first; the app then finds it.")
}

@Composable
private fun HeaderSection(a: Account) {
    val scope = rememberCoroutineScope()
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp), Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(if (a.live) Red else Color.Gray))
        Text(a.user, fontWeight = FontWeight.Bold)
        Text(
            when {
                a === Restream -> "${Restream.destinations.count { it.active }}/${Restream.destinations.size} destinations"
                a.live -> "${a.viewers} viewers"
                else -> "offline"
            },
            Modifier.weight(1f),
            color = Color.White.copy(alpha = 0.7f)
        )
        TextButton({ scope.launch { a.refresh() } }) { Text("Refresh") }
    }
}

@Composable
private fun DestinationsSection() {
    val scope = rememberCoroutineScope()
    SectionTitle("Destinations")
    for (d in Restream.destinations) {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(d.name)
                Note(d.url)
            }
            androidx.compose.material3.Switch(d.active, { on -> scope.launch { Restream.setActive(d, on) } })
        }
    }
    Note("Turning one off stops Restream sending there on your next stream. Add new destinations in the Restream dashboard.")
}

/** Masked key plus "use for streaming": copies the ingest URL and key into the stream settings (iOS keySection). */
@Composable
private fun KeySection(a: Account) {
    SectionTitle("Stream key")
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text(if (a.streamKey.isEmpty()) "Not available" else "•••• " + a.streamKey.takeLast(4), color = Color.White.copy(alpha = 0.7f))
        OutlinedButton({
            Engine.updateUrl(a.ingest)
            Engine.updateKey(a.streamKey)
            Prefs.put("chatOrigin", a.origin)
            if (a === Kick && ChatFeed.kickSlug.isEmpty() && Kick.slug.isNotEmpty()) ChatFeed.setKick(Kick.slug)
            Accounts.say("Stream key and chat set for ${a.label}")
        }, enabled = a.streamKey.isNotEmpty() && !Engine.live) { Text("Use for streaming") }
    }
}

private val TABS = listOf<Account>(Kick, Twitch, Restream, YouTube)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun StreamManager() {
    if (!ManagerState.open) return
    var tab by remember { mutableStateOf(Prefs.string("managerTab", "kick")) }
    val a = TABS.firstOrNull { it.prefix == tab } ?: Kick
    ModalBottomSheet(
        { ManagerState.open = false },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Color(0xFF1C1C1E),
        contentColor = Color.White
    ) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
            Arrangement.spacedBy(8.dp)
        ) {
            Text("Stream Manager", fontWeight = FontWeight.Bold)
            PrimaryTabRow(TABS.indexOf(a), containerColor = Color.Transparent, contentColor = Color.White) {
                TABS.forEach {
                    Tab(it === a, {
                        tab = it.prefix
                        Prefs.put("managerTab", tab)
                    }, text = { Text(it.label) })
                }
            }
            when {
                !a.hasApp -> Note(
                    "This build has no ${a.label} client ID. Add ${a.missingSecrets} (local.properties or the repo secrets) and rebuild."
                )
                !a.connected -> ConnectSection(a)
                else -> {
                    HeaderSection(a)
                    if (a === Twitch) TwitchActions()
                    SectionTitle("Stream info")
                    InfoSection(a)
                    if (a === Restream) DestinationsSection()
                    KeySection(a)
                    SectionTitle("Account")
                    OutlinedButton(a::disconnect, Modifier.fillMaxWidth()) { Text("Disconnect ${a.label}", color = Red) }
                }
            }
            if (Accounts.status.isNotEmpty()) Note(Accounts.status)
        }
    }
}
