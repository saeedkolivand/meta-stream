package com.saeedkolivand.metastream.ui

import android.content.ClipData
import android.content.Intent
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.meta.wearable.dat.core.types.RegistrationState
import com.saeedkolivand.metastream.chat.ChatFlood
import com.saeedkolivand.metastream.core.AppSettings
import com.saeedkolivand.metastream.core.logging.LogBuffer
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.ActionRow
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.NavRow
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SwitchRow
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

/** iOS GlassesVideoSettingsView. Sizes are what the Meta DAT camera stream offers (VideoQuality LOW/MEDIUM/HIGH). */
@Composable
internal fun GlassesVideoPage() {
    var on by remember { mutableStateOf(Prefs.bool("glassesEnabled")) }
    Section(
        null,
        "Shows the glasses button, the Glasses source and the glasses status on the main screen. Off hides every glasses control."
    ) {
        SwitchRow("Use Meta glasses", on) {
            on = it
            Prefs.put("glassesEnabled", it)
            if (!it && Engine.source == Source.Glasses) Engine.pick(Source.Phone)
        }
    }
    if (!on) return
    val activity = requireNotNull(LocalActivity.current)
    // Android only: the DAT SDK pairs through the Meta AI app (iOS registers from the main screen's glasses button).
    Section("Meta AI app", "Mock glasses stand in for a real pair, for testing without them.") {
        val registered = Engine.glasses.registration == RegistrationState.REGISTERED
        ActionRow(if (registered) "Unregister" else "Register with Meta AI", destructive = registered) {
            if (registered) Engine.glasses.unregister(activity) else Engine.glasses.register(activity)
        }
        SwitchRow("Mock glasses", Engine.glasses.mock, onChange = Engine.glasses::enableMock)
    }
    Section(
        "Video",
        "Applied the next time the glasses session starts. 720×1280 at 30 fps is the ceiling — Meta's SDK offers third-party apps " +
            "nothing higher, so no setting here can raise it."
    ) {
        val opts = listOf("low" to "Low · 360×640", "medium" to "Medium · 504×896", "high" to "High · 720×1280")
        Choice("Resolution", opts, AppSettings.glassesResolution, !Engine.live) { AppSettings.updateGlasses(resolution = it) }
        Choice("Frame rate", listOf(15, 24, 30).map { it to "$it" }, AppSettings.glassesFps, !Engine.live) {
            AppSettings.updateGlasses(fps = it)
        }
    }
}

@Composable
private fun InfoRow(title: String, value: String) = Column(Modifier.fillMaxWidth()) {
    Text(title, color = Secondary, fontSize = 12.sp)
    Text(value, fontFamily = FontFamily.Monospace, fontSize = 13.sp)
}

/** iOS DiagnosticsSettingsView: keep-awake, logs and version. */
@Composable
internal fun DiagnosticsPage(openLogs: () -> Unit) {
    val context = LocalContext.current
    val info = remember { context.packageManager.getPackageInfo(context.packageName, 0) }
    Section("General") { SwitchRow("Keep screen awake", AppSettings.keepAwake, onChange = AppSettings::updateKeepAwake) }
    Section("Logs") { NavRow("View logs", onClick = openLogs) }
    Section("About") {
        InfoRow("Meta registration", Engine.glasses.registration.name.lowercase())
        InfoRow("Device", "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} · Android ${android.os.Build.VERSION.RELEASE}")
        InfoRow("Version", "${info.versionName} (${info.longVersionCode})")
    }
}

/** iOS LogView: the in-app ring of applog lines (stream key already redacted), with copy and share. */
@Composable
internal fun LogsPage() {
    val context = LocalContext.current
    val lines = remember(LogBuffer.version) { LogBuffer.lines() }
    val text = lines.joinToString("\n")
    Section(null) {
        ActionRow("Copy") {
            context.getSystemService(android.content.ClipboardManager::class.java)
                .setPrimaryClip(ClipData.newPlainText("MetaStream logs", text))
        }
        ActionRow("Share") {
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
            context.startActivity(Intent.createChooser(send, "Share logs").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        ActionRow(if (ChatFlood.running) "Stop flood" else "Chat flood test", destructive = ChatFlood.running) { ChatFlood.toggle() }
    }
    // Newest first; the sheet already scrolls, so the list is height-capped and scrolls itself.
    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 420.dp).padding(top = 8.dp)) {
        items(lines.asReversed()) { Text(it, fontFamily = FontFamily.Monospace, fontSize = 11.sp) }
    }
    if (lines.isEmpty()) Text("No log lines yet.")
}
