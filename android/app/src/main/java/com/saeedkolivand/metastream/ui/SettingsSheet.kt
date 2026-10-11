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

/** Sub-pages of the settings sheet, like iOS NavigationLinks; [parent] is where Back goes. */
private enum class Page(val title: String, val parent: Page?) {
    Root("Settings", null),
    Ingest("Ingest & protocol", Root),
    Audio("Audio", Root),
    Glasses("Video (glasses)", Root),
    Camera("Camera", Root),
    ReadAloud("Read aloud", Root),
    Diagnostics("Diagnostics & about", Root),
    Logs("Logs", Diagnostics)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SettingsSheet(onDismiss: () -> Unit) {
    var page by rememberSaveable { mutableStateOf(Page.Root) }
    // In-sheet navigation: Back (system or the header button) steps up a page before it dismisses the sheet.
    BackHandler(page != Page.Root) { page = page.parent ?: Page.Root }
    ModalBottomSheet(onDismiss, containerColor = Color(0xFF1C1C1E), contentColor = Color.White) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
            Arrangement.spacedBy(8.dp)
        ) {
            page.parent?.let { parent -> TextButton({ page = parent }) { Text("‹ ${parent.title}") } }
            Text(page.title, fontWeight = FontWeight.Bold)
            when (page) {
                Page.Root -> RootPage { page = it }
                Page.Ingest -> IngestPage()
                Page.Audio -> AudioPage()
                Page.Camera -> CameraSettingsContent()
                Page.ReadAloud -> ReadAloudSettings()
                Page.Glasses -> GlassesVideoPage()
                Page.Diagnostics -> DiagnosticsPage { page = Page.Logs }
                Page.Logs -> LogsPage()
            }
        }
    }
}

@Composable
private fun RootPage(go: (Page) -> Unit) {
    val activity = requireNotNull(LocalActivity.current)
    NavRow("Stream Manager") { ManagerState.open = true }
    NavRow(Page.Ingest.title) { go(Page.Ingest) }
    NavRow(Page.Camera.title) { go(Page.Camera) }
    NavRow(Page.Audio.title) { go(Page.Audio) }
    NavRow(Page.ReadAloud.title) { go(Page.ReadAloud) }
    NavRow(Page.Glasses.title) { go(Page.Glasses) }
    NavRow(Page.Diagnostics.title) { go(Page.Diagnostics) }
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
    Section("Overlays") { OverlaySettings() }
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
