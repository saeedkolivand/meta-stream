package com.saeedkolivand.metastream.overlay.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts.OpenDocument
import androidx.activity.result.contract.ActivityResultContracts.OpenDocumentTree
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.ui.ActionRow
import com.saeedkolivand.metastream.core.ui.Green
import com.saeedkolivand.metastream.core.ui.Pill
import com.saeedkolivand.metastream.core.ui.R as CoreR
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.overlay.Scenes
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

/** iOS SceneOptionsView import section: OBS scene collections merge into the in-app scenes; missing files are located afterwards. */
@Composable
fun ObsImportSection() {
    val pickJson = rememberLauncherForActivityResult(OpenDocument()) { it?.let(OverlayStore::import) }
    val pickTree = rememberLauncherForActivityResult(OpenDocumentTree()) { it?.let(OverlayStore::locate) }
    val skipped = OverlayStore.pack?.skippedText().orEmpty()
    Section(
        "Import from OBS (optional)",
        "In OBS: Scene Collection > Export, then pick that .json here. Imported scenes are added next to yours. Images, text, " +
            "colors, slideshows, local clips and web pages come across; cameras, game and screen captures and audio are PC-only " +
            "and skipped.\n\nLocate files takes the folder that holds the images and clips and copies the ones the scenes use " +
            "into the app.\n\nThe import holds your overlay page links, which can carry account tokens. It stays on this device, " +
            "out of backups, and the links are never written to the log." + if (skipped.isEmpty()) "" else "\n\n$skipped"
    ) {
        ActionRow("Import OBS scene collection") { pickJson.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) }
        if (OverlayStore.missing().isNotEmpty()) ActionRow("Locate files…") { pickTree.launch(null) }
        if (OverlayStore.message.isNotEmpty()) Text(OverlayStore.message, color = Secondary, fontSize = 13.sp)
    }
}

/** HUD pill: the active scene; tap for the list. Glasses can't be drawn on, so it says so there. */
@Composable
fun ScenePill() {
    if (OverlayStore.scenes.isEmpty()) return
    var open by remember { mutableStateOf(false) }
    val glasses = Engine.source == Source.Glasses
    Box {
        Pill(
            CoreR.drawable.ic_videocam,
            if (glasses) "overlays off for glasses" else OverlayStore.scene.ifEmpty { "No scene" },
            if (glasses || OverlayStore.scene.isEmpty()) Color.Gray else Green
        ) { open = true }
        DropdownMenu(open, { open = false }) {
            for (name in listOf("") + OverlayStore.scenes.map { it.name }) {
                DropdownMenuItem(
                    { Text(name.ifEmpty { "None" }) },
                    {
                        Scenes.select(name)
                        open = false
                    }
                )
            }
        }
    }
}
