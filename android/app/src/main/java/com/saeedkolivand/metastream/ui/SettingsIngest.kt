package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.core.storage.AppSettings
import com.saeedkolivand.metastream.core.storage.KBPS_STEP
import com.saeedkolivand.metastream.core.storage.MIN_KBPS
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.storage.snapKbps
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SliderRow
import com.saeedkolivand.metastream.core.ui.Stepper
import com.saeedkolivand.metastream.core.ui.TextRow
import com.saeedkolivand.metastream.streaming.BONDING_TRANSPORTS
import com.saeedkolivand.metastream.streaming.Engine

/** Bitrate ceilings a few destinations are known to reject above (iOS bitrateCeilings); others get the generic one. */
private val Ceilings = mapOf("kick" to 8000, "twitch" to 6000)
private const val GENERIC_CEILING = 9000

private val Hints = mapOf(
    "kick" to "H.264 only, up to 8000 kbps.",
    "twitch" to "Up to 6000 kbps, 8000 for Partners. HEVC is Affiliate/Partner only, so pick H.264.",
    "youtube" to "Takes HEVC over enhanced RTMP. Create the stream in YouTube Studio first.",
    "restream" to "Fans out to every destination set up in the Restream dashboard. Their RTMP ingest is H.264 only (HEVC needs SRT).",
    "instagram" to "Open Live Producer on instagram.com (desktop) and copy the stream URL and key here. H.264 only, up to 4000 kbps.",
    "tiktok" to "Get the server URL and key from TikTok LIVE Studio and paste both here. H.264 only.",
    "custom" to "Any RTMP, RTMPS or SRT server, such as your own relay. Paste an srt:// URL to publish over SRT, which survives packet " +
        "loss far better on cellular — put the stream key in its streamid query item, since SRT has no separate publish name."
)

/** iOS IngestSettingsView: platform, URL, key, codec, bitrate and SRT buffer; bonding roles for an srtla:// URL. */
@Composable
internal fun IngestPage() {
    val c = AppSettings.ingest
    val idle = !Engine.live // the encoder is configured at Go Live, so editing while live would do nothing
    var platform by remember { mutableStateOf(platformId()) }
    var showKey by remember { mutableStateOf(false) }
    val ceiling = Ceilings[platform] ?: GENERIC_CEILING
    Section(
        "Ingest",
        Hints[platform].orEmpty() +
            "\nH.264 is what Kick and Twitch take; HEVC is smaller at the same quality where the destination accepts it. " +
            "Applied when you go live; adaptive bitrate never goes above the bitrate set here."
    ) {
        Choice("Platform", Platforms.map { it.first to it.second }, platform, idle) { p ->
            platform = p
            Prefs.put("platform", p)
            val preset = Platforms.first { it.first == p }.third
            if (preset != null) {
                Engine.updateUrl(preset)
            } else if (p != "custom") {
                Engine.updateUrl("")
            }
            val cap = Ceilings[p] ?: GENERIC_CEILING
            if (c.bitrateKbps > cap) AppSettings.updateIngest(c.copy(bitrateKbps = cap))
        }
        TextRow("Ingest URL", Engine.url, Engine::updateUrl, idle, keyboard = KeyboardType.Uri, mono = true)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f)) { TextRow("Stream key", Engine.key, Engine::updateKey, idle, secure = !showKey) }
            Icon(
                painterResource(if (showKey) R.drawable.ic_eye_off else R.drawable.ic_eye),
                if (showKey) "Hide key" else "Show key",
                Modifier.padding(start = 8.dp).clickable { showKey = !showKey },
                tint = Secondary
            )
        }
        Choice("Video codec", listOf(false to "H.264", true to "HEVC"), c.h265, idle) { AppSettings.updateIngest(c.copy(h265 = it)) }
        SliderRow(
            "Bitrate",
            "${c.bitrateKbps} kbps",
            c.bitrateKbps.toFloat(),
            MIN_KBPS.toFloat()..ceiling.toFloat(),
            idle,
            (ceiling - MIN_KBPS) / KBPS_STEP - 1
        ) { AppSettings.updateIngest(c.copy(bitrateKbps = snapKbps(it.toInt()).coerceAtMost(ceiling))) }
        if (Engine.url.lowercase().startsWith("srt")) { // srt:// and srtla://
            Stepper("SRT buffer ${c.srtLatencyMs} ms", c.srtLatencyMs, 200..8000, 200, idle) {
                AppSettings.updateIngest(c.copy(srtLatencyMs = it))
            }
        }
    }
    if (Engine.url.lowercase().startsWith("srtla://")) {
        Section(
            "Bonding",
            "Bonding sends one stream over several connections to an SRTLA receiver (BELABOX Cloud, IRLHosting, your own srtla_rec). " +
                "Cellular as backup only carries video when Wi-Fi can't keep up."
        ) {
            for ((_, key, label, def) in BONDING_TRANSPORTS) {
                var role by remember { mutableStateOf(Prefs.string(key, def)) }
                Choice(label, listOf("main" to "Main", "backup" to "Backup", "off" to "Off"), role, idle) {
                    role = it
                    Prefs.put(key, it)
                }
            }
        }
    }
}
