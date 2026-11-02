package com.saeedkolivand.metastream.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.meta.wearable.dat.core.types.RegistrationState
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import com.saeedkolivand.metastream.ui.scenes.ScenesPage

private val Cyan = Color(0xFF40C8E0)
private val Indigo = Color(0xFF5E5CE6)
private val Purple = Color(0xFFBF5AF2)
private val Pink = Color(0xFFFF375F)
private val Grey = Color(0xFF8E8E93)

/** Sub-pages of settings, like iOS NavigationLinks; [parent] is where Back goes; icon/tint are the iOS catalog's tile. */
private enum class Page(val title: String, val parent: Page?, val icon: Int? = null, val tint: Color = Grey) {
    Root("Settings", null),
    Ingest("Ingest & protocol", Root, R.drawable.ic_antenna, Red),
    Audio("Audio", Root, R.drawable.ic_car_mic, Pink),
    Glasses("Video (glasses)", Root, R.drawable.ic_glasses, Indigo),
    Camera("Camera", Root, R.drawable.ic_camera, Grey),
    ReadAloud("Read aloud", Root, R.drawable.ic_speaker, Green),
    AppBot("App bot", Root, R.drawable.ic_cpu, Indigo),
    Goal("Goal", Root, R.drawable.ic_target, Green),
    Telegram("Telegram", Root, R.drawable.ic_send, Cyan),
    Streams("Streams", Root, R.drawable.ic_history, Purple),
    Spotify("Spotify", Root, R.drawable.ic_music_note, Green),
    Remote("Remote control", Root, R.drawable.ic_remote, Grey),
    DonationSources("Donation sources", Goal),
    Privacy("Privacy", Root, R.drawable.ic_eye_off, Cyan),
    Scenes("Scenes & widgets", Root, R.drawable.ic_layers, Orange),
    Diagnostics("Diagnostics & about", Root, R.drawable.ic_info, Grey),
    Logs("Logs", Diagnostics);

    val depth: Int get() = generateSequence(this) { it.parent }.count()
}

/** Full-screen settings like iOS: Back / Done bar, large title, pages slide in and out. Back steps up before it closes. */
@Composable
internal fun SettingsSheet(onDismiss: () -> Unit) {
    var page by rememberSaveable { mutableStateOf(Page.Root) }
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(page != Page.Root) { page = page.parent ?: Page.Root }
        Surface(Modifier.fillMaxSize(), color = Color.Black, contentColor = Color.White) {
            Column(Modifier.safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                    val parent = page.parent
                    if (parent != null) TextButton({ page = parent }) { Text("‹ ${parent.title}", fontSize = 17.sp) } else Spacer(Modifier)
                    TextButton(onDismiss) { Text("Done", fontWeight = FontWeight.Bold, fontSize = 17.sp) }
                }
                AnimatedContent(page, transitionSpec = {
                    val forward = targetState.depth > initialState.depth
                    (slideInHorizontally { if (forward) it else -it / 3 } + fadeIn()) togetherWith
                        (slideOutHorizontally { if (forward) -it / 3 else it } + fadeOut())
                }, label = "settings page") { p ->
                    Column(
                        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, bottom = 32.dp),
                        Arrangement.spacedBy(8.dp)
                    ) {
                        Text(p.title, Modifier.padding(start = 4.dp, bottom = 4.dp), fontSize = 34.sp, fontWeight = FontWeight.Bold)
                        PageContent(p) { page = it }
                    }
                }
            }
        }
    }
}

@Composable
private fun PageContent(p: Page, go: (Page) -> Unit) = when (p) {
    Page.Root -> RootPage(go)
    Page.Ingest -> IngestPage()
    Page.Audio -> AudioPage()
    Page.Camera -> CameraSettingsContent()
    Page.ReadAloud -> ReadAloudSettings()
    Page.AppBot -> AppBotPage()
    Page.Goal -> GoalPage { go(Page.DonationSources) }
    Page.DonationSources -> DonationSourcesPage()
    Page.Telegram -> TelegramPage()
    Page.Streams -> StreamsPage()
    Page.Spotify -> SpotifyPage()
    Page.Remote -> RemotePage()
    Page.Privacy -> PrivacySettings()
    Page.Scenes -> ScenesPage()
    Page.Glasses -> GlassesVideoPage()
    Page.Diagnostics -> DiagnosticsPage { go(Page.Logs) }
    Page.Logs -> LogsPage()
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
    // Ready to go live: what would stop GO LIVE, at a glance (iOS ReadinessCard).
    val issues = listOfNotNull("No stream URL".takeIf { Engine.url.isBlank() }, "No stream key".takeIf { Engine.key.isBlank() })
    Section(null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).background(if (issues.isEmpty()) Green else Orange, CircleShape))
            Spacer(Modifier.width(8.dp))
            Text(if (issues.isEmpty()) "Ready to go live" else "Check before going live", fontWeight = FontWeight.SemiBold)
        }
        issues.forEach { Text(it, color = Orange, fontSize = 15.sp) }
    }
    TextField(
        query,
        { query = it },
        Modifier.fillMaxWidth(),
        placeholder = { Text("Search") },
        singleLine = true,
        shape = RoundedCornerShape(10.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = CardColor,
            unfocusedContainerColor = CardColor,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent
        )
    )
    val hits = Catalog.mapNotNull { (group, page, words) -> searchHit(page.title, words, query)?.let { Triple(group, page, it) } }
    if (query.isBlank()) Section(null) { NavRow("Stream Manager", R.drawable.ic_manage, SystemBlue) { ManagerState.open = true } }
    for ((group, rows) in hits.groupBy { it.first }) {
        Section(group) {
            Column {
                rows.forEachIndexed { i, (_, page, label) ->
                    if (i > 0) HorizontalDivider(Modifier.padding(start = 42.dp), color = Hairline)
                    NavRow(label, page.icon, page.tint) { go(page) }
                }
            }
        }
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
