package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.bot.TwitchBot
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.Green
import com.saeedkolivand.metastream.core.ui.NavRow
import com.saeedkolivand.metastream.core.ui.Red
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SystemBlue
import com.saeedkolivand.metastream.goal.DonationHub
import com.saeedkolivand.metastream.goal.Site
import com.saeedkolivand.metastream.platforms.Accounts
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.Restream
import com.saeedkolivand.metastream.platforms.Spotify
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.platforms.YouTube

private val KickGreen = Color(0xFF1F8C1F)
private val TwitchPurple = Color(0xFF9146FF)

/** iOS AccountsSettingsView: every login in one place -- streaming platforms, chat bots, services and donation sites. */
@Composable
internal fun AccountsPage(openAppBot: () -> Unit, openTelegram: () -> Unit, openSources: () -> Unit) {
    Section("Streaming", "Title, category and stream key live in Stream Manager. " + Accounts.status) {
        Platform(Kick, "K", KickGreen)
        Platform(Twitch, "T", TwitchPurple)
        Platform(YouTube, "Y", Red)
        Platform(Restream, "R", SystemBlue)
    }
    Section("Chat bots") {
        AccountRow(KickGreen, "K", "Kick app bot", "Uses your Kick login")
        if (TwitchBot.name.isEmpty()) {
            AccountRow(TwitchPurple, "T", "Twitch bot account", "Not connected", "Connect", TwitchBot::connect)
        } else {
            AccountRow(TwitchPurple, "T", "Twitch bot account", TwitchBot.name, "Disconnect", TwitchBot::disconnect, true)
        }
        NavRow("App bot settings", onClick = openAppBot)
    }
    Section("Services") {
        val on = Spotify.connected
        val spotify: () -> Unit = if (on) Spotify::disconnect else ({ Spotify.connect() })
        AccountRow(
            Green,
            null,
            "Spotify",
            if (on) "Connected" else "Not connected",
            if (on) "Disconnect" else "Connect",
            spotify,
            on,
            R.drawable.ic_music_note
        )
        val channel = Prefs.string("telegramChannel")
        val detail = if (!Prefs.bool("telegramOn")) "Live post off" else channel.ifEmpty { "No channel yet" }
        AccountRow(Color(0xFF64D2FF), null, "Telegram", detail, icon = R.drawable.ic_send, onRow = openTelegram)
    }
    Section("Donation sites", "Keys are set on the Donation sources screen.") {
        Site.entries.forEach { site ->
            AccountRow(Red, site.title.take(1), site.title, DonationHub.status[site] ?: "Not set up", onRow = openSources)
        }
    }
}

@Composable
private fun Platform(a: com.saeedkolivand.metastream.platforms.Account, letter: String, tint: Color) = when {
    !a.hasApp -> AccountRow(tint, letter, a.label, "No client ID in this build")
    a.connected -> AccountRow(tint, letter, a.label, a.user.ifEmpty { "Connected" }, "Disconnect", a::disconnect, true)
    else -> AccountRow(tint, letter, a.label, "Not connected", "Connect", a::connect)
}

/** One account line: tile, name, status, and an optional Connect / Disconnect button (iOS AccountRow). */
@Composable
private fun AccountRow(
    tint: Color,
    letter: String?,
    title: String,
    detail: String,
    action: String? = null,
    run: () -> Unit = {},
    destructive: Boolean = false,
    icon: Int? = null,
    onRow: (() -> Unit)? = null
) {
    val m = if (onRow != null) Modifier.clickable(onClick = onRow) else Modifier
    Row(m.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(30.dp).clip(RoundedCornerShape(7.dp)).background(tint), Alignment.Center) {
            if (icon != null) {
                Icon(painterResource(icon), null, Modifier.size(18.dp), tint = Color.White)
            } else {
                Text(letter.orEmpty(), color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 17.sp)
            Text(detail, color = Secondary, fontSize = 13.sp, maxLines = 2)
        }
        if (action != null) TextButton(run) { Text(action, color = if (destructive) Red else SystemBlue) }
        if (onRow != null) Text("\u203A", color = Color.White.copy(alpha = 0.35f), fontSize = 22.sp)
    }
}
