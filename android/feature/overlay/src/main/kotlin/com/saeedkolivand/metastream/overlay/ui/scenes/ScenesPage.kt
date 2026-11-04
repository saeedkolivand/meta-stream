package com.saeedkolivand.metastream.overlay.ui.scenes

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.CardColor
import com.saeedkolivand.metastream.core.ui.Orange
import com.saeedkolivand.metastream.core.ui.Red
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.SystemBlue
import com.saeedkolivand.metastream.overlay.LayerType
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.overlay.Scene
import com.saeedkolivand.metastream.overlay.SceneTemplate
import com.saeedkolivand.metastream.overlay.Scenes
import com.saeedkolivand.metastream.overlay.widgets.nowplaying.copy
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

/** The scene being arranged; the toolbar's New scene sets it too. */
private var editing by mutableStateOf<String?>(null)

/**
 * Settings › Scenes & widgets (iOS OverlaySettingsView): a grid of scene cards. Tap one to arrange its widgets, hold for
 * show / duplicate / rename / delete. Transitions and new scenes live in the bar ([ScenesToolbar]).
 */
@Composable
fun ScenesPage() {
    var renaming by rememberSaveable { mutableStateOf<String?>(null) }
    var deleting by rememberSaveable { mutableStateOf<String?>(null) }
    if (Engine.source == Source.Glasses) {
        Text("Overlays are off for glasses HEVC passthrough. Use the phone camera.", color = Orange, fontSize = 13.sp)
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(12.dp)).background(CardColor)
            .clickable { Scenes.select("") }.padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("None (no overlay)", Modifier.weight(1f), fontSize = 17.sp)
        if (OverlayStore.scene.isEmpty()) Text("✓", color = SystemBlue, fontSize = 17.sp)
    }
    // ponytail: two fixed columns (iOS adaptive 150 pt min is two on a phone); a LazyGrid can't nest in the page scroll.
    OverlayStore.scenes.chunked(2).forEach { pair ->
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), Arrangement.spacedBy(14.dp)) {
            pair.forEach { s -> SceneCard(s, Modifier.weight(1f), { renaming = s.name }, { deleting = s.name }) }
            if (pair.size == 1) Spacer(Modifier.weight(1f))
        }
    }
    if (OverlayStore.scenes.isEmpty()) {
        Text("No scenes yet. Tap + to make one, or add the Starting, BRB & Ending set.", color = Secondary, fontSize = 13.sp)
    }
    Text(
        "Tap a scene to arrange its widgets. Hold one to show it on stream, duplicate, rename or delete it. " +
            "The Starting, BRB & Ending set takes those roles over from your other scenes.",
        Modifier.padding(top = 8.dp),
        color = Secondary,
        fontSize = 13.sp
    )
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

/** iOS toolbar: options (Transitions & scene options) and + (New scene, the Starting/BRB/Ending set). */
@Composable
fun ScenesToolbar(openOptions: () -> Unit) = Row(verticalAlignment = Alignment.CenterVertically) {
    var open by remember { mutableStateOf(false) }
    Text("☰", Modifier.clickable(onClick = openOptions).padding(8.dp), color = SystemBlue, fontSize = 20.sp)
    Box {
        Text("+", Modifier.clickable { open = true }.padding(horizontal = 8.dp), color = SystemBlue, fontSize = 28.sp)
        DropdownMenu(open, { open = false }) {
            DropdownMenuItem({ Text("New scene") }, {
                open = false
                editing = OverlayStore.addScene()
            })
            for (t in SceneTemplate.entries) {
                DropdownMenuItem({ Text("Add ${t.title}") }, {
                    open = false
                    OverlayStore.addTemplate(t, Prefs.string("chatChannel", "").trim().ifEmpty { Kick.user })
                })
            }
        }
    }
}

private val Roles = mapOf("starting" to "Starting", "brb" to "BRB", "ending" to "Ending")

/** iOS SceneCard: thumbnail with the ON STREAM badge, name and role, then widget count and camera. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SceneCard(s: Scene, modifier: Modifier, onRename: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val live = OverlayStore.scene == s.name
    Box(modifier) {
        Column(Modifier.combinedClickable(onLongClick = { menu = true }) { editing = s.name }) {
            Box {
                val edge = if (live) Red else Color.White.copy(alpha = 0.1f)
                Thumbnail(s, Modifier.border(if (live) 2.dp else 1.dp, edge, RoundedCornerShape(10.dp)))
                if (live) {
                    Text(
                        "ON STREAM",
                        Modifier.padding(6.dp).clip(RoundedCornerShape(50)).background(Red).padding(horizontal = 6.dp, vertical = 2.dp),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(s.name, Modifier.weight(1f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                Roles[s.role]?.let {
                    Text(
                        it,
                        Modifier.clip(
                            RoundedCornerShape(50)
                        ).background(SystemBlue.copy(alpha = 0.18f)).padding(horizontal = 6.dp, vertical = 2.dp),
                        color = SystemBlue,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
            val widgets = if (s.layers.size == 1) "1 widget" else "${s.layers.size} widgets"
            val cam = CameraChoices.firstOrNull { it.first == s.camera && s.camera != null }?.second
            Text(listOfNotNull(widgets, cam).joinToString(" · "), color = Secondary, fontSize = 12.sp, maxLines = 1)
        }
        DropdownMenu(menu, { menu = false }) {
            val items = listOf<Pair<String, () -> Unit>>(
                "Show on stream" to { Scenes.select(s.name) },
                "Duplicate" to { OverlayStore.duplicateScene(s.name) },
                "Rename" to onRename,
                "Delete" to onDelete
            )
            for ((label, action) in items) {
                DropdownMenuItem({ Text(label, color = if (label == "Delete") Red else Color.Unspecified) }, {
                    menu = false
                    action()
                })
            }
        }
    }
}

private fun LayerType.tint() = when (this) {
    LayerType.Chat -> Color(0xFF0A84FF)
    LayerType.Alerts -> Color(0xFFFF9F0A)
    LayerType.Goal -> Color(0xFF30D158)
    LayerType.Text -> Color(0xFFBF5AF2)
    LayerType.NowPlaying -> Color(0xFF32D74B)
    LayerType.Qr -> Color(0xFF8E8E93)
    else -> Color(0xFF64D2FF)
}

/**
 * ponytail (as iOS SceneThumbnail): boxes at each visible layer's real position and size, tinted by kind with the kind's
 * marker, not the live widgets: a grid of ten scenes would otherwise run ten chat/QR/goal renderers.
 */
@Composable
private fun Thumbnail(s: Scene, modifier: Modifier) = BoxWithConstraints(
    modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp))
        .background(Brush.verticalGradient(listOf(Color(0xFF2E2E2E), Color(0xFF121212))))
) {
    val k = maxWidth / 1920f
    for (l in s.layers) {
        if (!l.visible) continue
        val b = layerBox(l, 1920, 1080) ?: continue
        val w = (k * b.w).coerceAtLeast(4.dp)
        val h = (k * b.h).coerceAtLeast(4.dp)
        Box(
            Modifier.offset(k * b.x, k * b.y).size(w, h).clip(RoundedCornerShape(3.dp)).background(l.type.tint().copy(alpha = 0.55f)),
            Alignment.Center
        ) { if (minOf(w, h) > 14.dp) LayerIcon(l.type) }
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
                val note = if (taken) "That name is empty or already used." else "Names must be unique."
                Text(note, color = if (taken) Red else Secondary, fontSize = 12.sp)
            }
        }
    )
}
