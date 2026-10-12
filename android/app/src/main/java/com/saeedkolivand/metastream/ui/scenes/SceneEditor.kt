package com.saeedkolivand.metastream.ui.scenes

import android.Manifest
import android.content.pm.PackageManager
import android.content.res.Configuration
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.activity.result.contract.ActivityResultContracts.RequestPermission
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.core.AppSettings
import com.saeedkolivand.metastream.core.toVideoParams
import com.saeedkolivand.metastream.overlay.Layer
import com.saeedkolivand.metastream.overlay.LayerType
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.overlay.Scenes
import com.saeedkolivand.metastream.overlay.WidgetVariables
import com.saeedkolivand.metastream.ui.Choice
import com.saeedkolivand.metastream.ui.Footnote
import com.saeedkolivand.metastream.ui.Hairline
import com.saeedkolivand.metastream.ui.Red
import com.saeedkolivand.metastream.ui.Section
import com.saeedkolivand.metastream.ui.SwitchRow
import com.saeedkolivand.metastream.ui.SystemBlue
import com.saeedkolivand.metastream.ui.rememberHaptic
import kotlin.math.max
import kotlin.math.min

internal val CameraChoices = listOf(
    "" to "Keep current",
    "back" to "Back camera",
    "front" to "Front camera",
    "external" to "External camera",
    "glasses" to "Glasses"
)

/**
 * Build one scene: arrange widgets on a live canvas, pick the camera it switches to, put it on stream. The canvas stays above
 * the form so every inspector change shows up at once. Layers are read straight from the store; edits write back once per
 * control change or finished gesture, because each write rebuilds the scene on stream.
 */
@Composable
internal fun SceneEditor(name: String, onClose: () -> Unit) {
    var current by rememberSaveable { mutableStateOf(name) }
    val scene = OverlayStore.scenes.firstOrNull { it.name == current }
    if (scene == null) {
        LaunchedEffect(Unit) { onClose() }
        return
    }
    val layers = scene.layers
    val haptic = rememberHaptic()
    var selected by rememberSaveable { mutableStateOf<Int?>(null) }
    var portraitPick by rememberSaveable { mutableStateOf<Boolean?>(null) }
    var askWeb by rememberSaveable { mutableStateOf(false) }
    var webUrl by rememberSaveable { mutableStateOf("") }
    var webNote by rememberSaveable { mutableStateOf("") }
    var draft by remember(current) { mutableStateOf(current) }

    fun save(next: List<Layer>) = OverlayStore.setLayers(current, next)

    fun append(l: Layer) {
        save(layers + l)
        selected = layers.size
        haptic(false)
    }

    fun remove(i: Int) {
        if (i !in layers.indices) return
        save(layers.filterIndexed { j, _ -> j != i })
        selected = null
        haptic(false)
    }

    fun move(i: Int, by: Int) {
        val j = i + by
        if (i !in layers.indices || j !in layers.indices) return
        save(layers.toMutableList().also { it[i] = layers[j] }.also { it[j] = layers[i] })
        selected = j
    }

    fun rename() {
        val t = draft.trim()
        if (t.isNotEmpty() && t != current && OverlayStore.renameScene(current, t)) current = t else draft = current
    }

    fun close() {
        rename()
        onClose()
    }

    val pickImage = rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
        uri?.let(OverlayStore::saveImage)?.let { append(pickedImage(it)) }
    }
    val askLocation = rememberLauncherForActivityResult(RequestPermission()) {}
    val ctx = LocalContext.current
    val needsLocation = layers.any { it.type == LayerType.Text && WidgetVariables.needsLocation(it.data["text"].orEmpty()) }
    LaunchedEffect(needsLocation) {
        val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (needsLocation && !granted) askLocation.launch(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    // The output the stream will use, so the canvas matches what viewers see; the toggle previews the other orientation.
    val devicePortrait = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    val params = AppSettings.ingest.toVideoParams(devicePortrait)
    val portrait = portraitPick ?: params.portrait
    val lo = min(params.width, params.height)
    val hi = max(params.width, params.height)
    val outW = if (portrait) lo else hi
    val outH = if (portrait) hi else lo

    Dialog(::close, DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = Color(0xFF1C1C1E), contentColor = Color.White) {
            Column(Modifier.safeDrawingPadding().padding(horizontal = 16.dp)) {
                Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                    TextButton(::close) { Text("Done") }
                    Text(current, fontWeight = FontWeight.Bold, maxLines = 1)
                    AddWidgetMenu { kind ->
                        when (kind) {
                            NewWidget.Image -> pickImage.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly))
                            NewWidget.Web -> {
                                webUrl = ""
                                webNote = ""
                                askWeb = true
                            }
                            else -> kind.make()?.let(::append)
                        }
                    }
                }
                Choice("Preview", listOf(false to "Landscape", true to "Portrait"), portrait) { portraitPick = it }
                Box(Modifier.fillMaxWidth().padding(vertical = 8.dp).heightIn(max = 300.dp), Alignment.Center) {
                    Box(Modifier.aspectRatio(outW.toFloat() / outH).clip(RoundedCornerShape(10.dp))) {
                        SceneCanvas(layers, outW, outH, selected, { selected = it }) { i, l ->
                            if (i in layers.indices) save(layers.toMutableList().also { it[i] = l })
                        }
                    }
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        draft,
                        { draft = it },
                        Modifier.fillMaxWidth().onFocusChanged { if (!it.isFocused) rename() },
                        label = { Text("Name") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { rename() })
                    )
                    SwitchRow("Show on stream", OverlayStore.scene == current) { Scenes.select(if (it) current else "") }
                    CameraPicker(scene.camera.orEmpty()) { OverlayStore.setCamera(current, it.ifEmpty { null }) }
                    Footnote("Switching to this scene also switches the camera, so one tap can go from the glasses to the back camera.")
                    Section("Layers") {
                        if (layers.isEmpty()) Footnote("Nothing here yet. Tap + to add chat, alerts, text, an image and more.")
                        for (i in layers.indices.reversed()) {
                            LayerRow(layers[i], i == selected, { selected = i }, {
                                save(layers.toMutableList().also { it[i] = layers[i].copy(visible = !layers[i].visible) })
                            }) { remove(i) }
                        }
                    }
                    selected?.takeIf { it in layers.indices }?.let { i ->
                        WidgetInspector(
                            layers[i],
                            i < layers.size - 1,
                            i > 0,
                            { l -> save(layers.toMutableList().also { it[i] = l }) },
                            { move(i, it) }
                        ) { remove(i) }
                    }
                }
            }
        }
    }
    if (askWeb) {
        AlertDialog(
            { askWeb = false },
            confirmButton = {
                TextButton({
                    val url = webUrl.trim()
                    if (validWebUrl(url)) {
                        askWeb = false
                        append(webLayer(url))
                    } else {
                        webNote = "That isn't an http or https link."
                    }
                }) { Text("Add") }
            },
            dismissButton = { TextButton({ askWeb = false }) { Text("Cancel") } },
            title = { Text("Web widget") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Paste a Streamlabs, StreamElements or BotRix widget link for alerts, goals or anything web-based.")
                    OutlinedTextField(
                        webUrl,
                        { webUrl = it },
                        label = { Text("https://") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
                    )
                    if (webNote.isNotEmpty()) Text(webNote, color = Red)
                }
            }
        )
    }
}

@Composable
private fun CameraPicker(camera: String, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    // A scene's current camera (such as "auto") stays listed so the button never goes blank.
    val options = if (CameraChoices.any { it.first == camera }) CameraChoices else CameraChoices + (camera to camera)
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text("Camera")
        OutlinedButton({ open = true }) { Text(options.first { it.first == camera }.second) }
        DropdownMenu(open, { open = false }) {
            for ((value, label) in options) {
                DropdownMenuItem({ Text(label) }, {
                    open = false
                    onPick(value)
                })
            }
        }
    }
}

@Composable
private fun LayerRow(l: Layer, selected: Boolean, onSelect: () -> Unit, onToggle: () -> Unit, onDelete: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
            .background(if (selected) SystemBlue.copy(alpha = 0.25f) else Hairline.copy(alpha = 0.06f))
            .clickable(onClick = onSelect).padding(start = 12.dp),
        Arrangement.spacedBy(12.dp),
        Alignment.CenterVertically
    ) {
        LayerIcon(l.type)
        Text(l.name, Modifier.weight(1f), color = Color.White.copy(alpha = if (l.visible) 1f else 0.5f), maxLines = 1)
        IconButton(onToggle) {
            val label = if (l.visible) "Hide ${l.name}" else "Show ${l.name}"
            Icon(painterResource(if (l.visible) R.drawable.ic_eye else R.drawable.ic_eye_off), label, Modifier.size(20.dp))
        }
        IconButton(onDelete, Modifier.semantics { contentDescription = "Delete ${l.name}" }) { Text("✕") }
    }
}
