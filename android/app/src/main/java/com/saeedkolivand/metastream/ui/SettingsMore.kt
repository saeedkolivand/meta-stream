package com.saeedkolivand.metastream.ui

import android.content.ClipData
import android.content.Intent
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.meta.wearable.dat.core.types.RegistrationState
import com.saeedkolivand.metastream.chat.ChatFlood
import com.saeedkolivand.metastream.core.AppSettings
import com.saeedkolivand.metastream.core.LogBuffer
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

/** iOS GlassesVideoSettingsView. Sizes are what the Meta DAT camera stream offers (VideoQuality LOW/MEDIUM/HIGH). */
@Composable
internal fun GlassesVideoPage() {
    var on by remember { mutableStateOf(Prefs.bool("glassesEnabled")) }
    Section("Meta glasses") {
        SwitchRow("Use Meta glasses", on) {
            on = it
            Prefs.put("glassesEnabled", it)
            if (!it && Engine.source == Source.Glasses) Engine.pick(Source.Phone)
        }
        Footnote("Shows Glasses as a camera source. Off hides every glasses control.")
    }
    if (!on) return
    val activity = requireNotNull(LocalActivity.current)
    Section("Meta AI app") {
        val registered = Engine.glasses.registration == RegistrationState.REGISTERED
        OutlinedButton({ if (registered) Engine.glasses.unregister(activity) else Engine.glasses.register(activity) }) {
            Text(if (registered) "Unregister" else "Register with Meta AI")
        }
        SwitchRow("Mock glasses", Engine.glasses.mock, onChange = Engine.glasses::enableMock)
    }
    Section("Glasses video") {
        val opts = listOf("low" to "360x640", "medium" to "504x896", "high" to "720x1280")
        Choice("Resolution", opts, AppSettings.glassesResolution, !Engine.live) { AppSettings.updateGlasses(resolution = it) }
        Choice("Frame rate", listOf(15, 24, 30).map { it to "$it" }, AppSettings.glassesFps, !Engine.live) {
            AppSettings.updateGlasses(fps = it)
        }
        Footnote(
            "Applied the next time the glasses session starts. 720x1280 at 30 fps is the ceiling; " +
                "Meta's SDK offers third-party apps nothing higher."
        )
    }
}

/** iOS DiagnosticsSettingsView: keep-awake, logs and version. */
@Composable
internal fun DiagnosticsPage(openLogs: () -> Unit) {
    val context = LocalContext.current
    val info = remember { context.packageManager.getPackageInfo(context.packageName, 0) }
    Section("General") { SwitchRow("Keep screen awake", AppSettings.keepAwake, onChange = AppSettings::updateKeepAwake) }
    Section("Logs") { NavRow("View logs", onClick = openLogs) }
    Section("About") {
        Text("Version", color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
        Text("${info.versionName} (${info.longVersionCode})", fontFamily = FontFamily.Monospace, fontSize = 13.sp)
        Text("Meta registration", color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
        Text(Engine.glasses.registration.name.lowercase(), fontFamily = FontFamily.Monospace, fontSize = 13.sp)
    }
}

/** iOS LogView: the in-app ring of applog lines (stream key already redacted), with copy and share. */
@Composable
internal fun LogsPage() {
    val context = LocalContext.current
    val lines = remember(LogBuffer.version) { LogBuffer.lines() }
    val text = lines.joinToString("\n")
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp)) {
        OutlinedButton({
            context.getSystemService(android.content.ClipboardManager::class.java)
                .setPrimaryClip(ClipData.newPlainText("MetaStream logs", text))
        }) { Text("Copy") }
        OutlinedButton({
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
            context.startActivity(Intent.createChooser(send, "Share logs").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }) { Text("Share") }
        OutlinedButton(ChatFlood::toggle) { Text(if (ChatFlood.running) "Stop flood" else "Chat flood test") }
    }
    // Newest first; the sheet already scrolls, so the list is height-capped and scrolls itself.
    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 420.dp).padding(top = 8.dp)) {
        items(lines.asReversed()) { Text(it, fontFamily = FontFamily.Monospace, fontSize = 11.sp) }
    }
    if (lines.isEmpty()) Text("No log lines yet.")
}
