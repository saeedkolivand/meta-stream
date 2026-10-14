package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.Kind
import com.saeedkolivand.metastream.speech.eventSummary

private val Kick = Color(0xFF53FC18)
private val Twitch = Color(0xFF9146FF)
private val Gold = Color(0xFFFFC107)
private val Pink = Color(0xFFFF5FA2)
private val Blue = Color(0xFF3B9CFF)

// ponytail: text chips, not the real badge art. Twitch badge images need an authenticated Helix call
// (chat/badges/global + per-channel); upgrade path: fetch those once per channel and draw them with Coil.
private val CHIPS = mapOf(
    "broadcaster" to ("HOST" to Red),
    "staff" to ("STAFF" to Color(0xFF8E8E93)),
    "moderator" to ("MOD" to Green),
    "vip" to ("VIP" to Pink),
    "founder" to ("FNDR" to Gold),
    "subscriber" to ("SUB" to Twitch),
    "verified" to ("✓" to Blue),
    "og" to ("OG" to Orange)
)

/** Names are read on black: lighten dark colors until they pass a minimum luminance. */
internal fun readable(c: Color): Color {
    var out = c
    var t = 0f
    while (out.luminance() < 0.25f && t < 1f) {
        t += 0.1f
        out = lerp(c, Color.White, t)
    }
    return out
}

internal fun parseHex(hex: String?): Color? =
    hex?.removePrefix("#")?.takeIf { it.length == 6 }?.toLongOrNull(16)?.let { Color(0xFF000000 or it) }

@Composable
private fun Chip(role: String) {
    val (label, color) = CHIPS[role] ?: return
    Text(
        label,
        Modifier.clip(RoundedCornerShape(4.dp)).background(color.copy(alpha = 0.25f)).padding(horizontal = 5.dp, vertical = 1.dp),
        color = color,
        fontSize = 10.sp,
        fontWeight = FontWeight.ExtraBold
    )
}

private val YouTube = Color(0xFFFF0033)

/** Letter, circle colour and letter colour per origin. */
private fun origin(platform: String) = when (platform) {
    "kick" -> Triple("K", Kick, Color.Black)
    "youtube" -> Triple("Y", YouTube, Color.White)
    else -> Triple("T", Twitch, Color.White)
}

@Composable
private fun OriginBadge(platform: String) {
    val (letter, bg, fg) = origin(platform)
    Box(Modifier.size(20.dp).clip(CircleShape).background(bg), Alignment.Center) {
        Text(letter, color = fg, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
internal fun ChatRow(e: ChatEvent, size: Int, animate: Boolean = true) {
    // Alerts are already spoken, so they render as one compact secondary line with no name/badges.
    if (e.kind != Kind.Message) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), Arrangement.spacedBy(8.dp), Alignment.CenterVertically) {
            OriginBadge(e.platform)
            Text(eventSummary(e), color = Color.White.copy(alpha = 0.6f), fontSize = (size * 0.8f).sp)
        }
        return
    }
    val name = parseHex(e.color)?.let(::readable) ?: origin(e.platform).second
    // The owner is whoever's channel we're reading; their @name in a message is addressed to the streamer.
    val mention = listOf(ChatFeed.kickSlug, ChatFeed.twitchChannel).any { it.isNotEmpty() && e.text.contains("@$it", ignoreCase = true) }
    // Hairline divider, not alternating stripes: the feed is capped, so indices shift and stripes would flip per message.
    val bg = if (mention) Orange.copy(alpha = 0.22f) else Color.Transparent
    Column(Modifier.background(bg)) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                OriginBadge(e.platform)
                e.badges.forEach { Chip(it) }
                Text(e.user, color = name, fontSize = (size * 0.85f).sp, fontWeight = FontWeight.Bold)
            }
            MessageText(e.text, size, Modifier.padding(top = 2.dp), animate)
        }
        HorizontalDivider(color = Hairline)
    }
}
