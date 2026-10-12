package com.saeedkolivand.metastream.ui.scenes

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.overlay.Scene
import com.saeedkolivand.metastream.overlay.Scenes
import com.saeedkolivand.metastream.ui.Choice
import com.saeedkolivand.metastream.ui.Footnote
import com.saeedkolivand.metastream.ui.Green
import com.saeedkolivand.metastream.ui.ObsImportSection
import com.saeedkolivand.metastream.ui.Red
import com.saeedkolivand.metastream.ui.Section
import com.saeedkolivand.metastream.ui.SwitchRow

private val Intervals = listOf(15 to "15 s", 30 to "30 s", 60 to "1 min", 120 to "2 min", 300 to "5 min")

/** Settings page: the scene list (tap edits, long-press for more), auto-rotate, transition and the optional OBS import. */
@Composable
internal fun ScenesPage() {
    var editing by rememberSaveable { mutableStateOf<String?>(null) }
    var renaming by rememberSaveable { mutableStateOf<String?>(null) }
    var deleting by rememberSaveable { mutableStateOf<String?>(null) }
    Section("Scenes") {
        for (s in OverlayStore.scenes) SceneRow(s, { editing = s.name }, { renaming = s.name }, { deleting = s.name })
        if (OverlayStore.scenes.isEmpty()) Footnote("A scene is a set of widgets, plus the camera it switches to. Make one to get started.")
        Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp)) {
            OutlinedButton({ editing = OverlayStore.addScene() }) { Text("New scene") }
            if (OverlayStore.scene.isNotEmpty()) OutlinedButton({ Scenes.select("") }) { Text("None") }
        }
        Footnote("Tap a scene to edit it. Press and hold to show it on stream, duplicate, rename or delete.")
    }
    if (OverlayStore.scenes.size >= 2) RotationSection()
    Section("Transition") {
        Choice("Between scenes", listOf("cut" to "Cut", "fade" to "Fade"), OverlayStore.transition, onSelect = OverlayStore::setTransition)
    }
    Section("Import from OBS (optional)") { ObsImportSection() }
    editing?.let { SceneEditor(it) { editing = null } }
    renaming?.let { old -> RenameDialog(old) { renaming = null } }
    deleting?.let { name ->
        AlertDialog(
            { deleting = null },
            confirmButton = {
                TextButton({
                    OverlayStore.deleteScene(name)
                    Scenes.updateRotation()
                    deleting = null
                }) { Text("Delete", color = Red) }
            },
            dismissButton = { TextButton({ deleting = null }) { Text("Cancel") } },
            title = { Text("Delete \"$name\"?") },
            text = { Text("Its widgets go with it.") }
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SceneRow(s: Scene, onEdit: () -> Unit, onRename: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val live = OverlayStore.scene == s.name
    Box {
        Row(
            Modifier.fillMaxWidth().combinedClickable(onLongClick = { menu = true }, onClick = onEdit).padding(vertical = 12.dp),
            Arrangement.SpaceBetween,
            Alignment.CenterVertically
        ) {
            Column {
                Text(s.name, fontWeight = FontWeight.SemiBold)
                val sub = listOfNotNull(
                    CameraChoices.firstOrNull { it.first == s.camera && s.camera != null }?.second,
                    "${s.layers.size} widgets"
                ).joinToString(" · ")
                Text(sub, color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
            }
            if (live) Text("ON STREAM", color = Green, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
        DropdownMenu(menu, { menu = false }) {
            val items = listOf<Pair<String, () -> Unit>>(
                "Show on stream" to { Scenes.select(s.name) },
                "Duplicate" to { OverlayStore.duplicateScene(s.name) },
                "Rename" to onRename,
                "Delete" to onDelete
            )
            for ((label, action) in items) {
                DropdownMenuItem({ Text(label) }, {
                    menu = false
                    action()
                })
            }
        }
    }
}

@Composable
private fun RenameDialog(old: String, onDone: () -> Unit) {
    var text by remember { mutableStateOf(old) }
    var taken by remember { mutableStateOf(false) }
    AlertDialog(
        onDone,
        confirmButton = {
            TextButton({
                val t = text.trim()
                if (t == old || OverlayStore.renameScene(old, t)) onDone() else taken = true
            }) { Text("Rename") }
        },
        dismissButton = { TextButton(onDone) { Text("Cancel") } },
        title = { Text("Rename scene") },
        text = {
            Column {
                OutlinedTextField(text, {
                    text = it
                    taken = false
                }, singleLine = true)
                if (taken) Text("That name is empty or already used.", color = Red, fontSize = 12.sp)
            }
        }
    )
}

@Composable
private fun RotationSection() {
    Section("Auto-rotate") {
        SwitchRow("Rotate scenes", OverlayStore.rotateOn) {
            OverlayStore.setRotateOn(it)
            Scenes.updateRotation()
        }
        if (!OverlayStore.rotateOn) return@Section
        Choice("Every", Intervals, OverlayStore.rotateSeconds) {
            OverlayStore.setRotateSeconds(it)
            Scenes.updateRotation()
        }
        Text("Scenes in the rotation")
        for (s in OverlayStore.scenes) {
            val on = s.name in OverlayStore.rotateScenes
            Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), Arrangement.spacedBy(8.dp), Alignment.CenterVertically) {
                Checkbox(on, {
                    OverlayStore.setRotateScenes(if (on) OverlayStore.rotateScenes - s.name else OverlayStore.rotateScenes + s.name)
                    Scenes.updateRotation()
                })
                Text(s.name)
            }
        }
        Footnote("Needs at least two scenes ticked. Picking a scene by hand that isn't in the rotation turns it off.")
    }
}
