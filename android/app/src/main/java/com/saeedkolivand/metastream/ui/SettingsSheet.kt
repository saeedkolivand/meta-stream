package com.saeedkolivand.metastream.ui

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.meta.wearable.dat.core.types.RegistrationState
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Text(
        title.uppercase(),
        Modifier.padding(top = 12.dp),
        color = Color.White.copy(alpha = 0.6f),
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold
    )
    content()
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text(label)
        Switch(checked, onChange)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SettingsSheet(onDismiss: () -> Unit) {
    val activity = requireNotNull(LocalActivity.current)
    ModalBottomSheet(onDismiss, containerColor = Color(0xFF1C1C1E), contentColor = Color.White) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
            Arrangement.spacedBy(8.dp)
        ) {
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
                    visualTransformation = PasswordVisualTransformation()
                )
            }
            Section("Chat") {
                OutlinedTextField(ChatFeed.kickSlug, ChatFeed::setKick, Modifier.fillMaxWidth(), label = {
                    Text("Kick channel")
                }, singleLine = true)
                OutlinedTextField(ChatFeed.twitchChannel, ChatFeed::setTwitch, Modifier.fillMaxWidth(), label = {
                    Text("Twitch channel")
                }, singleLine = true)
                SwitchRow("Read chat aloud", Speaker.readAloud, Speaker::updateReadAloud)
            }
            Section("Overlays") { OverlaySettings() }
            if (Engine.source == Source.Glasses) {
                Section("Glasses") {
                    val registered = Engine.glasses.registration == RegistrationState.REGISTERED
                    OutlinedButton({ if (registered) Engine.glasses.unregister(activity) else Engine.glasses.register(activity) }) {
                        Text(if (registered) "Unregister" else "Register with Meta AI")
                    }
                    SwitchRow("Mock glasses", Engine.glasses.mock, Engine.glasses::enableMock)
                }
            }
        }
    }
}
