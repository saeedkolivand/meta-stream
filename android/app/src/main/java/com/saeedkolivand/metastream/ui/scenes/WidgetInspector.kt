package com.saeedkolivand.metastream.ui.scenes

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.overlay.AlertStyle
import com.saeedkolivand.metastream.overlay.ChatStyle
import com.saeedkolivand.metastream.overlay.DonationKind
import com.saeedkolivand.metastream.overlay.EventListStyle
import com.saeedkolivand.metastream.overlay.GoalStyle
import com.saeedkolivand.metastream.overlay.InlineIcons
import com.saeedkolivand.metastream.overlay.Layer
import com.saeedkolivand.metastream.overlay.LayerType
import com.saeedkolivand.metastream.overlay.NowPlayingStyle
import com.saeedkolivand.metastream.overlay.QrStyle
import com.saeedkolivand.metastream.overlay.TextStyle as TextWidgetStyle
import com.saeedkolivand.metastream.overlay.WidgetVariables
import com.saeedkolivand.metastream.ui.Choice
import com.saeedkolivand.metastream.ui.Footnote
import com.saeedkolivand.metastream.ui.Red
import com.saeedkolivand.metastream.ui.Section
import com.saeedkolivand.metastream.ui.SwitchRow

private fun defaultsOf(type: LayerType): Map<String, String> = when (type) {
    LayerType.Chat -> ChatStyle().toData()
    LayerType.Alerts -> AlertStyle().toData()
    LayerType.Events -> EventListStyle().toData()
    LayerType.Qr -> QrStyle().toData()
    LayerType.Goal -> GoalStyle().toData()
    LayerType.NowPlaying -> NowPlayingStyle().toData()
    LayerType.Text -> TextWidgetStyle().toData()
    LayerType.Browser -> mapOf("width" to "800", "height" to "600")
    else -> emptyMap()
}

/** Settings of the selected layer, the Android take on iOS WidgetInspectorView: same controls, same stored keys. */
@Composable
internal fun WidgetInspector(
    layer: Layer,
    canForward: Boolean,
    canBack: Boolean,
    onChange: (Layer) -> Unit,
    onMove: (Int) -> Unit,
    onDelete: () -> Unit
) {
    val d = DataKeys(layer, defaultsOf(layer.type)) { onChange(layer.copy(data = it)) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Section("Layer") {
            DebouncedField("Name", layer.name) { onChange(layer.copy(name = it)) }
            SwitchRow("Visible", layer.visible) { onChange(layer.copy(visible = it)) }
            SliderRow("Size", layer.layout?.scale ?: layer.sx, 0.05f..4f, "%.2f×") { onChange(resized(layer, it)) }
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
                TextButton({ onMove(1) }, enabled = canForward) { Text("Bring forward") }
                TextButton({ onMove(-1) }, enabled = canBack) { Text("Send back") }
            }
            TextButton(onDelete) { Text("Delete layer", color = Red) }
        }
        when (layer.type) {
            LayerType.Chat -> d.ChatSection()
            LayerType.Alerts -> d.AlertSection()
            LayerType.Events -> d.EventSection()
            LayerType.Text -> d.TextSection()
            LayerType.Qr -> d.QrSection()
            LayerType.Goal -> d.GoalSection()
            LayerType.NowPlaying -> d.NowPlayingSection()
            LayerType.Browser -> d.WebSection()
            else -> Unit
        }
    }
}

/** Widgets scale through their layout; OBS layers scale both axes by one ratio so the aspect holds. */
private fun resized(l: Layer, v: Float): Layer {
    l.layout?.let { return l.copy(layout = it.copy(scale = v)) }
    val r = if (l.sx > 0f) v / l.sx else 1f
    return l.copy(sx = l.sx * r, sy = l.sy * r)
}

@Composable
private fun DataKeys.ChatSection() {
    Section("Chat") {
        FontPicker()
        NumSlider("fontSize", "Font size", 14f..72f)
        NumSlider("maxMessages", "Messages", 3f..20f)
        Choice(
            "Fade out after",
            listOf(0 to "Never", 10 to "10 s", 20 to "20 s", 30 to "30 s", 60 to "60 s"),
            num("fadeSeconds").toInt()
        ) { putNum("fadeSeconds", it.toFloat()) }
        NumSlider("width", "Box width", 300f..1200f)
        NumSlider("height", "Box height", 200f..1200f)
    }
    Section("Look") {
        Flag("background", "Background")
        Flag("shadow", "Shadow")
        Flag("bold", "Bold")
        Flag("badges", "Badges")
        Flag("platform", "Platform dot")
        Flag("senderColors", "Viewer name colors")
        Swatches("textColor", "Text color")
        Swatches("backgroundColor", "Background color")
    }
    Section("Filters") {
        Flag("hideCommands", "Hide !commands")
        Flag("hideBots", "Hide bots")
        Flag("showEvents", "Show follows, subs and tips")
        Field("botNames", "Bot names", singleLine = false)
        Field("highlight", "Highlight words")
        Swatches("highlightColor", "Highlight color")
        Footnote("Bot names and highlight words are comma-separated. A message with a highlight word, or your channel name, gets a border.")
    }
}

@Composable
private fun DataKeys.KindToggles() {
    Flag("follow", "Follows")
    Flag("subscribe", "Subscriptions")
    Flag("raid", "Raids")
    Flag("tip", "Tips")
    Flag("cheer", "Cheers")
}

@Composable
private fun DataKeys.AlertSection() = Section("Alerts") {
    KindToggles()
    NumSlider("holdSeconds", "Show for", 3f..15f, " s")
    FontPicker()
    NumSlider("fontSize", "Font size", 20f..80f)
    Swatches("accentColor", "Accent color")
    Swatches("textColor", "Text color")
    Choice("Donation style", DonationKind.entries.map { it.id to it.title }, str("design")) { put("design", it) }
    if (str("design") != "island") {
        Choice("Speed", listOf("slow" to "Slow", "normal" to "Normal", "quick" to "Quick"), str("designSpeed")) { put("designSpeed", it) }
        DesignColor("designAccent", "Design colour")
        if (str("design") == "neon") DesignColor("designSecond", "Second tube")
    }
    Footnote("Tips, Bits and KICKs play the donation style over the whole picture, centred on this widget; Island is the banner.")
}

@Composable
private fun DataKeys.DesignColor(key: String, label: String) {
    if (str(key).toLongOrNull() == 0L) {
        TextButton({ putColor(key, 0xFFFFFF) }) { Text("$label: the design's own · change") }
    } else {
        Swatches(key, label)
        TextButton({ put(key, "0") }) { Text("Use the design's own") }
    }
}

@Composable
private fun DataKeys.EventSection() = Section("Event list") {
    KindToggles()
    NumSlider("maxEvents", "Entries", 3f..10f)
    FontPicker()
    NumSlider("fontSize", "Font size", 16f..48f)
    NumSlider("width", "Box width", 300f..900f)
    NumSlider("height", "Box height", 200f..900f)
    Flag("background", "Background")
    Swatches("backgroundColor", "Background color")
    Swatches("textColor", "Text color")
}

@Composable
private fun DataKeys.TextSection() {
    Section("Text") {
        Field("text", "Text", singleLine = false)
        TokenMenu { put("text", str("text") + it) }
        IconMenu { put("text", str("text") + it) }
        FontPicker()
        NumSlider("size", "Font size", 16f..200f)
        Flag("bold", "Bold")
        Flag("shadow", "Shadow")
        Flag("background", "Background")
        Flag("rotate", "Rotate lines")
        NumSlider("rotateSeconds", "Seconds per line", 3f..15f)
        Swatches("color", "Text color")
        Swatches("backgroundColor", "Background color")
        Footnote(
            "Values like {time} or {viewers} update on stream every second. Speed, distance, city and weather ask for " +
                "location access. Rotate lines shows one line at a time, for socials."
        )
    }
}

/** Appends a live value such as {viewers}; the token list belongs to WidgetVariables so the menu can't drift from what resolves. */
/** Inserts an inline icon token: icons on stream, never emoji. */
@Composable
private fun IconMenu(onInsert: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    OutlinedButton({ open = true }) { Text("Insert icon") }
    DropdownMenu(open, { open = false }) {
        for (name in InlineIcons.palette) {
            DropdownMenuItem({ Text(name) }, {
                open = false
                onInsert("{i:$name}")
            })
        }
    }
}

@Composable
private fun TokenMenu(onInsert: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    OutlinedButton({ open = true }) { Text("Insert live value") }
    DropdownMenu(open, { open = false }) {
        for ((a, b) in WidgetVariables.tokens) {
            // The contract pairs token and label; accept either order rather than break on a swap.
            val token = if (a.startsWith("{")) a else b
            val label = if (a.startsWith("{")) b else a
            DropdownMenuItem({ Text("$label  $token") }, {
                open = false
                onInsert(token)
            })
        }
    }
}

@Composable
private fun DataKeys.QrSection() = Section("QR code") {
    Field("text", "Text or link", keyboard = KeyboardType.Uri)
    Field("caption", "Caption")
    FontPicker()
    Swatches("foreground", "Code color")
    Swatches("background", "Background color")
}

@Composable
private fun DataKeys.GoalSection() = Section("Donation goal") {
    val designs = listOf("bar" to "Bar", "segments" to "Segments", "hairline" to "Hairline", "dots" to "Dots")
    Choice("Design", designs, str("design")) { put("design", it) }
    NumSlider("width", "Box width", 300f..1200f)
    NumSlider("height", "Box height", 80f..240f)
    FontPicker()
    NumSlider("fontSize", "Font size", 16f..48f)
    Swatches("barColor", "Bar color")
    Swatches("trackColor", "Track color")
    Swatches("textColor", "Text color")
    Flag("background", "Background")
    if (flag("background")) Swatches("backgroundColor", "Background color")
    Flag("showPercent", "Percent")
    Flag("showOther", "Other currencies")
    Footnote("Title, target and currency are in Settings › Goal.")
}

@Composable
private fun DataKeys.NowPlayingSection() = Section("Now playing") {
    val designs = listOf("slab" to "Slab", "text" to "Text", "twoLine" to "Two lines", "cover" to "Text with cover", "popup" to "Pop-up")
    Choice("Design", designs, str("design").takeIf { d -> designs.any { it.first == d } } ?: "slab") { put("design", it) }
    Swatches("accentColor", "Accent color")
    FontPicker()
    if (str("design") == "popup") NumSlider("popupSeconds", "Stays for (s)", 2f..30f)
    Footnote("Shows what your Spotify account plays (Settings › Spotify); hidden while nothing plays.")
}

@Composable
private fun DataKeys.WebSection() = Section("Web widget") {
    Field("url", "Link", keyboard = KeyboardType.Uri)
    NumSlider("width", "Page width", 200f..1920f)
    NumSlider("height", "Page height", 200f..1920f)
    Footnote("The link can carry account tokens. It stays on this device, and is never logged.")
}
