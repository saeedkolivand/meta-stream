package com.saeedkolivand.metastream.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.meta.wearable.dat.core.types.RegistrationState
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import com.saeedkolivand.metastream.ui.scenes.ScenesPage

/** Sub-pages of the settings sheet, like iOS NavigationLinks; [parent] is where Back goes. */
private enum class Page(val title: String, val parent: Page?) {
    Root("Settings", null),
    Ingest("Ingest & protocol", Root),
    Audio("Audio", Root),
    Glasses("Video (glasses)", Root),
    Camera("Camera", Root),
    ReadAloud("Read aloud", Root),
    AppBot("App bot", Root),
    Goal("Goal", Root),
    Telegram("Telegram", Root),
    Streams("Streams", Root),
    Spotify("Spotify", Root),
    Remote("Remote control", Root),
    DonationSources("Donation sources", Goal),
    Privacy("Privacy", Root),
    Scenes("Scenes & widgets", Root),
    Diagnostics("Diagnostics & about", Root),
    Logs("Logs", Diagnostics)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SettingsSheet(onDismiss: () -> Unit) {
    var page by rememberSaveable { mutableStateOf(Page.Root) }
    // In-sheet navigation: Back (system or the header button) steps up a page before it dismisses the sheet.
    BackHandler(page != Page.Root) { page = page.parent ?: Page.Root }
    // Swiping down doesn't close it (it closed by accident when pulling down at the top of a list); Done does.
    ModalBottomSheet(onDismiss, sheetGesturesEnabled = false, containerColor = Color(0xFF1C1C1E), contentColor = Color.White) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
            Arrangement.spacedBy(8.dp)
        ) {
            page.parent?.let { parent -> TextButton({ page = parent }) { Text("‹ ${parent.title}") } }
            androidx.compose.foundation.layout.Row(
                Modifier.fillMaxWidth(),
                Arrangement.SpaceBetween,
                androidx.compose.ui.Alignment.CenterVertically
            ) {
                Text(page.title, fontWeight = FontWeight.Bold)
                TextButton(onDismiss) { Text("Done", fontWeight = FontWeight.Bold) }
            }
            when (page) {
                Page.Root -> RootPage { page = it }
                Page.Ingest -> IngestPage()
                Page.Audio -> AudioPage()
                Page.Camera -> CameraSettingsContent()
                Page.ReadAloud -> ReadAloudSettings()
                Page.AppBot -> AppBotPage()
                Page.Goal -> GoalPage { page = Page.DonationSources }
                Page.DonationSources -> DonationSourcesPage()
                Page.Telegram -> TelegramPage()
                Page.Streams -> StreamsPage()
                Page.Spotify -> SpotifyPage()
                Page.Remote -> RemotePage()
                Page.Privacy -> PrivacySettings()
                Page.Scenes -> ScenesPage()
                Page.Glasses -> GlassesVideoPage()
                Page.Diagnostics -> DiagnosticsPage { page = Page.Logs }
                Page.Logs -> LogsPage()
            }
        }
    }
}

/**
 * The root, grouped like iOS's catalog. Each page lists its sub-sections and the words search matches in them, so a hit
 * inside one shows its path (iOS 5e953c7): "Camera › Face cam".
 */
private val Catalog = listOf(
    Triple(
        "Streaming",
        Page.Ingest,
        "Ingest: rtmp srt srtla bonding url key; Encoder: bitrate codec resolution fps; Recording: record save local"
    ),
    Triple(
        "Streaming",
        Page.Camera,
        "Lens & zoom: lens zoom stabilization; Face cam: dual camera front pip; Looks: lut filter colour; Focus: focus exposure iso shutter white balance"
    ),
    Triple("Streaming", Page.Audio, "Microphone: mic usb bluetooth gain; Soundboard: sounds sfx; Mix volume: music mix"),
    Triple("Streaming", Page.Glasses, "Meta glasses: meta ray-ban wearables; Glasses video: resolution fps"),
    Triple("Scenes", Page.Scenes, "Scenes: widgets overlay obs; Transitions: stinger fade; Scene roles: brb starting ending"),
    Triple("Scenes", Page.Privacy, "Privacy: blur faces plates"),
    Triple("Chat & bot", Page.ReadAloud, "Read aloud: tts speech voice; Blocked: blocked words"),
    Triple(
        "Chat & bot",
        Page.AppBot,
        "Viewer commands: commands; Timers: timers; Thank-yous: thanks; Saved commands: moderation mod; Scene notices: brb"
    ),
    Triple(
        "Money",
        Page.Goal,
        "Goal: goal; Accounts: donation donofa reymit streamelements donito tip; Donate page: donate page; Rates: rates usd bits kicks"
    ),
    Triple("Reach", Page.Telegram, "Telegram: bot channel; Post: live post recap; Instagram story: instagram story"),
    Triple("Reach", Page.Streams, "Streams: history session report; When your viewers show up: heatmap; Wrapped: wrapped year"),
    Triple("Reach", Page.Spotify, "Spotify: now playing song music"),
    Triple("Reach", Page.Remote, "Remote control: obs websocket stream deck touch portal streamer.bot; Password: password"),
    Triple("About", Page.Diagnostics, "General: keep awake; Logs: logs debug; About: version")
)

/** The row a search hit shows: the page alone when its title matches, else "Page › Section"; null when nothing matches. */
internal fun searchHit(title: String, words: String, query: String): String? {
    val q = query.trim()
    if (q.isEmpty() || title.contains(q, ignoreCase = true)) return title
    val sub = words.split(';').map { it.split(':', limit = 2) }.firstOrNull { it.joinToString(" ").contains(q, ignoreCase = true) }
    return sub?.let { "$title › ${it[0].trim()}" }
}

@Composable
private fun RootPage(go: (Page) -> Unit) {
    val activity = requireNotNull(LocalActivity.current)
    var query by rememberSaveable { mutableStateOf("") }
    // Ready to go live: what would stop GO LIVE, at a glance.
    val issues = listOfNotNull("No stream URL".takeIf { Engine.url.isBlank() }, "No stream key".takeIf { Engine.key.isBlank() })
    Note(
        if (issues.isEmpty()) "Ready to go live" else "Before going live: " + issues.joinToString(", "),
        if (issues.isEmpty()) Color(0xFF30D158) else Color(0xFFFF9F0A)
    )
    OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), label = { Text("Search settings") }, singleLine = true)
    val hits = Catalog.mapNotNull { (group, page, words) -> searchHit(page.title, words, query)?.let { Triple(group, page, it) } }
    if (query.isBlank()) NavRow("Stream Manager") { ManagerState.open = true }
    for ((group, rows) in hits.groupBy { it.first }) {
        Section(group) { rows.forEach { (_, page, label) -> NavRow(label) { go(page) } } }
    }
    if (hits.isEmpty()) Note("Nothing matches \"$query\"")
    if (query.isNotBlank()) return
    Section("Stream") {
        OutlinedTextField(Engine.url, Engine::updateUrl, Modifier.fillMaxWidth(), label = {
            Text("RTMP / SRT URL")
        }, singleLine = true, enabled = !Engine.live)
        OutlinedTextField(
            Engine.key,
            Engine::updateKey,
            Modifier.fillMaxWidth(),
            label = { Text("Stream key") },
            singleLine = true,
            enabled = !Engine.live,
            visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation()
        )
    }
    Section("Chat") {
        OutlinedTextField(ChatFeed.kickSlug, ChatFeed::setKick, Modifier.fillMaxWidth(), label = {
            Text("Kick channel")
        }, singleLine = true)
        OutlinedTextField(ChatFeed.twitchChannel, ChatFeed::setTwitch, Modifier.fillMaxWidth(), label = {
            Text("Twitch channel")
        }, singleLine = true)
        SwitchRow("Read chat aloud", Speaker.readAloud, onChange = Speaker::updateReadAloud)
    }
    if (Engine.source == Source.Glasses) {
        Section("Glasses") {
            val registered = Engine.glasses.registration == RegistrationState.REGISTERED
            OutlinedButton({ if (registered) Engine.glasses.unregister(activity) else Engine.glasses.register(activity) }) {
                Text(if (registered) "Unregister" else "Register with Meta AI")
            }
            SwitchRow("Mock glasses", Engine.glasses.mock, onChange = Engine.glasses::enableMock)
        }
    }
}
