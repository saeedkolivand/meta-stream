package com.saeedkolivand.metastream.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts.OpenDocument
import androidx.activity.result.contract.ActivityResultContracts.OpenDocumentTree
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

/** Settings content: import an OBS scene collection, find its files, pick the scene. */
@Composable
internal fun OverlaySettings() {
    val pickJson = rememberLauncherForActivityResult(OpenDocument()) { it?.let(OverlayStore::import) }
    val pickTree = rememberLauncherForActivityResult(OpenDocumentTree()) { it?.let(OverlayStore::locate) }
    OutlinedButton({
        pickJson.launch(arrayOf("application/json", "text/plain", "application/octet-stream"))
    }) { Text("Import OBS scene collection") }
    if (OverlayStore.message.isNotEmpty()) Text(OverlayStore.message, color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
    if (OverlayStore.missing().isNotEmpty()) OutlinedButton({ pickTree.launch(null) }) { Text("Locate files…") }
    val pack = OverlayStore.pack ?: return
    if (Engine.source == Source.Glasses) Text("Overlays are off for glasses", color = Orange, fontSize = 12.sp)
    Column {
        for (name in listOf("") + pack.scenes.map { it.name }) {
            Row(Modifier.fillMaxWidth().clickable { OverlayStore.select(name) }, verticalAlignment = Alignment.CenterVertically) {
                RadioButton(OverlayStore.scene == name, { OverlayStore.select(name) })
                Text(name.ifEmpty { "None" })
            }
        }
    }
}

/** HUD pill: the active scene; tap for the list. Glasses can't be drawn on, so it says so there. */
@Composable
internal fun ScenePill() {
    val pack = OverlayStore.pack ?: return
    var open by remember { mutableStateOf(false) }
    val glasses = Engine.source == Source.Glasses
    Box {
        Pill(
            R.drawable.ic_videocam,
            if (glasses) "overlays off for glasses" else OverlayStore.scene.ifEmpty { "no overlay" },
            if (glasses || OverlayStore.scene.isEmpty()) Color.Gray else Green
        ) { open = true }
        DropdownMenu(open, { open = false }) {
            for (name in listOf("") + pack.scenes.map { it.name }) {
                DropdownMenuItem(
                    { Text(name.ifEmpty { "None" }) },
                    {
                        OverlayStore.select(name)
                        open = false
                    }
                )
            }
        }
    }
}
