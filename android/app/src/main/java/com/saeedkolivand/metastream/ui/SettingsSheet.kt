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
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.ui.scenes.ScenesPage
import com.saeedkolivand.metastream.ui.scenes.TransitionsPage

private val Teal = Color(0xFF40C8E0)
private val Cyan = Color(0xFF64D2FF)
private val Indigo = Color(0xFF5E5CE6)
private val Purple = Color(0xFFBF5AF2)
private val Pink = Color(0xFFFF375F)
private val Grey = Color(0xFF8E8E93)

/**
 * Settings pages in iOS SettingsCatalog order, with its titles, groups and tiles, so both apps read the same.
 * [parent] is where Back goes; [group] is the root section ("" = not on the root).
 */
private enum class Page(val title: String, val parent: Page?, val group: String = "", val icon: Int? = null, val tint: Color = Grey) {
    Root("Settings", null),
    Accounts("Accounts", Root, "Accounts", R.drawable.ic_person, SystemBlue),
    Ingest("Destination", Root, "Stream", R.drawable.ic_antenna, Red),
    Camera("Camera", Root, "Stream", R.drawable.ic_camera, Grey),
    Glasses("Meta glasses", Root, "Stream", R.drawable.ic_glasses, Indigo),
    Audio("Audio", Root, "Stream", R.drawable.ic_car_mic, Pink),
    Privacy("Privacy blur", Root, "Stream", R.drawable.ic_eye_off, Teal),
    Scenes("Scenes & widgets", Root, "On screen", R.drawable.ic_layers, Orange),
    Transitions("Transitions", Root, "On screen", R.drawable.ic_swap, Purple),
    Theme("Theme & story", Root, "On screen", R.drawable.ic_palette, Pink),
    ReadAloud("Chat & read aloud", Root, "Chat", R.drawable.ic_chat, Green),
    Commands("Commands", Root, "Chat", R.drawable.ic_feedback, Orange),
    AppBot("App bot", Root, "Chat", R.drawable.ic_cpu, Indigo),
    Bots("Known bots", Root, "Chat", R.drawable.ic_shield, Grey),
    Goal("Goal", Root, "Money", R.drawable.ic_target, Green),
    DonationSources("Donation sources", Root, "Money", R.drawable.ic_heart, Red),
    DonatePage("Donate page", Root, "Money", R.drawable.ic_globe, SystemBlue),
    Telegram("Telegram", Root, "Reach", R.drawable.ic_send, Cyan),
    Spotify("Spotify", Root, "Reach", R.drawable.ic_music_note, Green),
    Streams("Streams", Root, "Your streams", R.drawable.ic_history, Purple),
    Remote("Remote control", Root, "System", R.drawable.ic_remote, Grey),
    Diagnostics("Diagnostics & about", Root, "System", R.drawable.ic_info, Grey),
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
    Page.Accounts -> AccountsPage({ go(Page.AppBot) }, { go(Page.Telegram) }, { go(Page.DonationSources) })
    Page.Ingest -> IngestPage()
    Page.Camera -> CameraSettingsContent()
    Page.Glasses -> GlassesVideoPage()
    Page.Audio -> AudioPage()
    Page.Privacy -> PrivacySettings()
    Page.Scenes -> ScenesPage()
    Page.Transitions -> TransitionsPage()
    Page.Theme -> ThemePage()
    Page.ReadAloud -> ReadAloudSettings()
    Page.Commands -> CommandsPage()
    Page.AppBot -> AppBotPage()
    Page.Bots -> KnownBotsPage()
    Page.Goal -> GoalPage()
    Page.DonationSources -> DonationSourcesPage()
    Page.DonatePage -> DonatePagePage()
    Page.Telegram -> TelegramPage()
    Page.Spotify -> SpotifyPage()
    Page.Streams -> StreamsPage()
    Page.Remote -> RemotePage()
    Page.Diagnostics -> DiagnosticsPage { go(Page.Logs) }
    Page.Logs -> LogsPage()
}

/**
 * The root, grouped like iOS's catalog. Each page lists its sub-sections and the words search matches in them, so a hit
 * inside one shows its path (iOS 5e953c7): "Camera › Face cam".
 */
private val Catalog = listOf(
    Page.Accounts to
        "Streaming: kick twitch youtube restream login connect; Chat bots: bot; Services: spotify telegram; Donation sites: donofa reymit",
    Page.Ingest to "Ingest: rtmp srt srtla bonding url key; Encoder: bitrate codec resolution fps; Recording: record save local",
    Page.Camera to
        "Lens & zoom: lens zoom stabilization; Face cam: dual camera front pip; Looks: lut filter colour; Focus: focus exposure iso shutter white balance",
    Page.Glasses to "Meta glasses: meta ray-ban wearables register mock; Glasses video: resolution fps",
    Page.Audio to "Microphone: mic usb bluetooth gain; Soundboard: sounds sfx; Mix volume: music mix; Screen share: app audio",
    Page.Privacy to "Privacy: blur faces plates",
    Page.Scenes to "Scenes: widgets overlay; Templates: starting brb ending set",
    Page.Transitions to "Transition: stinger fade cut; Scene roles: brb starting ending countdown; Auto-rotate: rotate; Import: obs",
    Page.Theme to "Theme: colour color palette; Instagram story: instagram story card",
    Page.ReadAloud to "Chat: channel kick twitch; Read aloud: tts speech voice; Don't read: blocked words",
    Page.Commands to "Saved commands: moderation mod lock screen notification",
    Page.AppBot to "Viewer commands: commands; Timers: timers; Thank-yous: thanks; Scene notices: brb; kick.com session: kick web",
    Page.Bots to "Bots: nightbot bot names; Announcements: trigger words",
    Page.Goal to "Goal: goal target; Add amount: cash manual; Test donation: test; Rates: rates usd bits kicks",
    Page.DonationSources to "Donation sites: donofa reymit streamelements donito tip key",
    Page.DonatePage to "Donate page: donate page key address",
    Page.Telegram to "Telegram: bot channel; Post: live post recap",
    Page.Spotify to "Spotify: now playing song music",
    Page.Streams to "Streams: history session report; When your viewers show up: heatmap; Wrapped: wrapped year",
    Page.Remote to "Remote control: obs websocket stream deck touch portal streamer.bot; Password: password",
    Page.Diagnostics to "General: keep awake; Logs: logs debug; About: version"
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
    val hits = Catalog.mapNotNull { (page, words) -> searchHit(page.title, words, query)?.let { Triple(page.group, page, it) } }
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
}
