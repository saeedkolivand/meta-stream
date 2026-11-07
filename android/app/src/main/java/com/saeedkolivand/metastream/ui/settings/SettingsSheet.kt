package com.saeedkolivand.metastream.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.ProvideTextStyle
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.bot.ui.AppBotMessagesPage
import com.saeedkolivand.metastream.bot.ui.AppBotPage
import com.saeedkolivand.metastream.bot.ui.AppBotTimersPage
import com.saeedkolivand.metastream.bot.ui.CommandsPage
import com.saeedkolivand.metastream.bot.ui.KnownBotsPage
import com.saeedkolivand.metastream.core.ui.CardColor
import com.saeedkolivand.metastream.core.ui.Green
import com.saeedkolivand.metastream.core.ui.NavRow
import com.saeedkolivand.metastream.core.ui.Note
import com.saeedkolivand.metastream.core.ui.Orange
import com.saeedkolivand.metastream.core.ui.R as CoreR
import com.saeedkolivand.metastream.core.ui.Red
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SystemBlue
import com.saeedkolivand.metastream.goal.ui.DonatePagePage
import com.saeedkolivand.metastream.goal.ui.DonationSourcesPage
import com.saeedkolivand.metastream.goal.ui.GoalPage
import com.saeedkolivand.metastream.goal.ui.GoalRatesPage
import com.saeedkolivand.metastream.goal.ui.GoalRecentPage
import com.saeedkolivand.metastream.overlay.ui.scenes.ScenesPage
import com.saeedkolivand.metastream.overlay.ui.scenes.ScenesToolbar
import com.saeedkolivand.metastream.overlay.ui.scenes.StingerSettings
import com.saeedkolivand.metastream.overlay.ui.scenes.TransitionsPage
import com.saeedkolivand.metastream.platforms.ui.SpotifyPage
import com.saeedkolivand.metastream.privacy.ui.PrivacySettings
import com.saeedkolivand.metastream.reach.ui.PostTextsPage
import com.saeedkolivand.metastream.reach.ui.StreamsPage
import com.saeedkolivand.metastream.reach.ui.StreamsToolbar
import com.saeedkolivand.metastream.reach.ui.TelegramPage
import com.saeedkolivand.metastream.remote.ui.RemotePage
import com.saeedkolivand.metastream.speech.ui.DontReadPage
import com.saeedkolivand.metastream.speech.ui.ReadAloudSettings
import com.saeedkolivand.metastream.speech.ui.VoicePage
import com.saeedkolivand.metastream.streaming.ui.AudioPage
import com.saeedkolivand.metastream.streaming.ui.CameraProPage
import com.saeedkolivand.metastream.streaming.ui.CameraSettingsContent
import com.saeedkolivand.metastream.streaming.ui.SoundboardPage
import com.saeedkolivand.metastream.ui.CamCustomize
import com.saeedkolivand.metastream.ui.CamStrip

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
    Audio("Audio", Root, "Stream", CoreR.drawable.ic_car_mic, Pink),
    Privacy("Privacy blur", Root, "Stream", CoreR.drawable.ic_eye_off, Teal),
    Scenes("Scenes & widgets", Root, "On screen", R.drawable.ic_layers, Orange),
    Transitions("Transitions", Root, "On screen", R.drawable.ic_swap, Purple),
    Theme("Theme & story", Root, "On screen", R.drawable.ic_palette, Pink),
    ReadAloud("Chat & read aloud", Root, "Chat", CoreR.drawable.ic_chat, Green),
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
    Logs("Logs", Diagnostics),
    CamStrip("Customise controls", Camera),
    CamPro("Pro controls", Camera),
    Soundboard("Soundboard", Audio),
    Stinger("Stinger", Transitions),
    Voice("Voice", ReadAloud),
    DontRead("Don't read", ReadAloud),
    BotMessages("Messages", AppBot),
    BotTimers("Timers", AppBot),
    GoalRates("Rates", Goal),
    GoalRecent("Recent donations", Goal),
    PostTexts("Post texts", Telegram);

    val depth: Int get() = generateSequence(this) { it.parent }.count()
}

/** Full-screen settings like iOS: Back / Done bar, large title, pages slide in and out. Back steps up before it closes. */
@Composable
fun SettingsSheet(onDismiss: () -> Unit) {
    var page by rememberSaveable { mutableStateOf(Page.Root) }
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(page != Page.Root) { page = page.parent ?: Page.Root }
        Surface(Modifier.fillMaxSize(), color = Color.Black, contentColor = Color.White) {
            // iOS text metrics: SF's line height is ~1.3x the size (17/22, 13/18) with no extra tracking; Material's body style
            // would keep a fixed 24 sp line and 0.5 sp letter spacing whatever size a row asks for.
            ProvideTextStyle(TextStyle(lineHeight = 1.3.em, letterSpacing = 0.sp)) {
                Column(Modifier.safeDrawingPadding()) {
                    // iOS bar: back on the left, the sub-page's title inline in the middle, the page's actions and Done on the right.
                    Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 4.dp)) {
                        page.parent?.let { parent ->
                            TextButton({ page = parent }, Modifier.align(Alignment.CenterStart)) {
                                // iOS shortens the back title to "Back" when it would run into the page title.
                                val label = if (page != Page.Root && parent.title.length + page.title.length > 24) "Back" else parent.title
                                Text("‹ $label", fontSize = 17.sp, maxLines = 1)
                            }
                        }
                        if (page != Page.Root) {
                            Text(
                                page.title,
                                Modifier.align(Alignment.Center),
                                fontSize = 17.sp,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1
                            )
                        }
                        Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically) {
                            if (page == Page.Scenes) ScenesToolbar { page = Page.Transitions }
                            if (page == Page.Streams) StreamsToolbar()
                            TextButton(onDismiss) { Text("Done", fontWeight = FontWeight.Bold, fontSize = 17.sp) }
                        }
                    }
                    AnimatedContent(page, transitionSpec = {
                        val forward = targetState.depth > initialState.depth
                        (slideInHorizontally { if (forward) it else -it / 3 } + fadeIn()) togetherWith
                            (slideOutHorizontally { if (forward) -it / 3 else it } + fadeOut())
                    }, label = "settings page") { p ->
                        Column(
                            Modifier.fillMaxSize().verticalScroll(
                                rememberScrollState()
                            ).padding(start = 16.dp, end = 16.dp, bottom = 32.dp),
                            Arrangement.spacedBy(8.dp)
                        ) {
                            if (p ==
                                Page.Root
                            ) {
                                Text(p.title, fontSize = 34.sp, fontWeight = FontWeight.Bold)
                            }
                            PageContent(p) { page = it }
                        }
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
    Page.Camera -> CameraSettingsContent({ go(Page.CamStrip) }, { go(Page.CamPro) })
    Page.CamStrip -> CamCustomize()
    Page.CamPro -> CameraProPage()
    Page.Glasses -> GlassesVideoPage()
    Page.Audio -> AudioPage { go(Page.Soundboard) }
    Page.Soundboard -> SoundboardPage()
    Page.Privacy -> PrivacySettings()
    Page.Scenes -> ScenesPage()
    Page.Transitions -> TransitionsPage { go(Page.Stinger) }
    Page.Stinger -> StingerSettings()
    Page.Theme -> ThemePage()
    Page.ReadAloud -> ReadAloudSettings({ go(Page.Voice) }, { go(Page.DontRead) })
    Page.Voice -> VoicePage()
    Page.DontRead -> DontReadPage()
    Page.Commands -> CommandsPage()
    Page.AppBot -> AppBotPage({ go(Page.BotMessages) }, { go(Page.BotTimers) })
    Page.BotMessages -> AppBotMessagesPage()
    Page.BotTimers -> AppBotTimersPage()
    Page.Bots -> KnownBotsPage()
    Page.Goal -> GoalPage({ go(Page.GoalRates) }, { go(Page.GoalRecent) })
    Page.GoalRates -> GoalRatesPage()
    Page.GoalRecent -> GoalRecentPage()
    Page.DonationSources -> DonationSourcesPage()
    Page.DonatePage -> DonatePagePage()
    Page.Telegram -> TelegramPage { go(Page.PostTexts) }
    Page.PostTexts -> PostTextsPage()
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
    Page.Telegram to "Telegram: bot channel; Post: live post recap; Post texts: template wording text",
    Page.Spotify to "Spotify: now playing song music",
    Page.Streams to "Streams: history session report; When your viewers show up: heatmap; Wrapped: wrapped year",
    Page.Remote to "Remote control: obs websocket stream deck touch portal streamer.bot; Password: password",
    Page.Diagnostics to "General: keep awake; Logs: logs debug; About: version"
)

/** The row a search hit shows: the page alone when its title matches, else "Page › Section"; null when nothing matches. */
fun searchHit(title: String, words: String, query: String): String? {
    val q = query.trim()
    if (q.isEmpty() || title.contains(q, ignoreCase = true)) return title
    val sub = words.split(';').map { it.split(':', limit = 2) }.firstOrNull { it.joinToString(" ").contains(q, ignoreCase = true) }
    return sub?.let { "$title › ${it[0].trim()}" }
}

/** The grey value on a root row and the iOS page id issues point at (iOS SettingsCatalog value / id). */
private fun Page.value(): String = when (this) {
    Page.Accounts -> SettingsValues.accounts()
    Page.Ingest -> SettingsValues.ingest()
    Page.Camera -> SettingsValues.camera()
    Page.Glasses -> SettingsValues.glasses()
    Page.Audio -> SettingsValues.audio()
    Page.Privacy -> SettingsValues.privacy()
    Page.Scenes -> SettingsValues.scenes()
    Page.Theme -> SettingsValues.theme()
    Page.ReadAloud -> SettingsValues.chat()
    Page.Commands -> SettingsValues.commands()
    Page.AppBot -> SettingsValues.appBot()
    Page.Goal -> SettingsValues.goal()
    Page.DonationSources -> SettingsValues.sources()
    Page.Telegram -> SettingsValues.telegram()
    Page.Spotify -> SettingsValues.spotify()
    Page.Remote -> SettingsValues.remote()
    else -> ""
}

private val IssuePages = mapOf(
    "accounts" to Page.Accounts,
    "ingest" to Page.Ingest,
    "sources" to Page.DonationSources,
    "telegram" to Page.Telegram,
    "remote" to Page.Remote
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RootPage(go: (Page) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    TextField(
        query,
        { query = it },
        Modifier.fillMaxWidth(),
        placeholder = { Text("Search settings", color = Secondary) },
        leadingIcon = { Icon(painterResource(R.drawable.ic_search), null, Modifier.size(18.dp), tint = Secondary) },
        singleLine = true,
        shape = RoundedCornerShape(10.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = CardColor,
            unfocusedContainerColor = CardColor,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent
        )
    )
    if (query.isBlank()) {
        // Ready to go live: what is set up, and what would get in the way (iOS ReadinessCard).
        val issues = SettingsValues.issues()
        Section(null) {
            Column(Modifier.padding(vertical = 8.dp), Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(10.dp).background(if (issues.isEmpty()) Green else Orange, CircleShape))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        if (issues.isEmpty()) "Ready to go live" else "Check before going live",
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 17.sp
                    )
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    SettingsValues.chips().forEach {
                        Text(
                            it,
                            Modifier.background(Secondary.copy(alpha = 0.2f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp),
                            fontSize = 13.sp,
                            maxLines = 1
                        )
                    }
                }
                issues.forEach { (id, message) ->
                    Row(Modifier.fillMaxWidth().clickable { IssuePages[id]?.let(go) }, verticalAlignment = Alignment.CenterVertically) {
                        Text("⚠", color = Orange)
                        Spacer(Modifier.width(8.dp))
                        Text(message, Modifier.weight(1f))
                        Text("›", color = Color.White.copy(alpha = 0.3f), fontSize = 20.sp)
                    }
                }
            }
        }
        val counts = issues.groupingBy { IssuePages[it.first] }.eachCount()
        for ((group, pages) in Catalog.map { it.first }.groupBy { it.group }) {
            Section(group) {
                pages.forEach { page -> NavRow(page.title, page.icon, page.tint, page.value(), counts[page] ?: 0) { go(page) } }
            }
        }
        return
    }
    val hits = Catalog.mapNotNull { (page, words) -> searchHit(page.title, words, query)?.let { page to it } }
    if (hits.isEmpty()) {
        Note("No results for \"$query\"")
        return
    }
    Section("Settings") { hits.forEach { (page, label) -> NavRow(label, page.icon, page.tint) { go(page) } } }
}
