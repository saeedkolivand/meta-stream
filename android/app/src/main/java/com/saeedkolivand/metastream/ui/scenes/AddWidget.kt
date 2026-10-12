package com.saeedkolivand.metastream.ui.scenes

import android.net.Uri
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.overlay.AlertStyle
import com.saeedkolivand.metastream.overlay.ChatStyle
import com.saeedkolivand.metastream.overlay.EventListStyle
import com.saeedkolivand.metastream.overlay.Layer
import com.saeedkolivand.metastream.overlay.LayerType
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.overlay.QrStyle
import com.saeedkolivand.metastream.overlay.TextStyle as TextWidgetStyle
import com.saeedkolivand.metastream.overlay.WidgetLayout
import com.saeedkolivand.metastream.overlay.widgetLayer

/** What the "+" menu can add. Image and Web need input first (a picked file, a URL), so the editor builds those itself. */
internal enum class NewWidget(val title: String) {
    Chat("Chat"),
    Alerts("Alerts"),
    Events("Event list"),
    Label("Text"),
    Image("Image or GIF"),
    Qr("QR code"),
    Web("Web widget");

    /** One place that knows each kind's defaults, so a new widget looks right the moment it lands. */
    fun make(): Layer? = when (this) {
        Chat -> widgetLayer(LayerType.Chat, "Chat", WidgetLayout.inset(6), ChatStyle().toData())
        Alerts -> widgetLayer(LayerType.Alerts, "Alerts", WidgetLayout.inset(1), AlertStyle().toData())
        Events -> widgetLayer(LayerType.Events, "Event list", WidgetLayout.inset(2), EventListStyle().toData())
        Label -> widgetLayer(LayerType.Text, "Text", WidgetLayout.inset(0), TextWidgetStyle(text = "{time}").toData())
        Qr -> widgetLayer(LayerType.Qr, "QR code", WidgetLayout.inset(8), QrStyle(text = "https://example.com").toData())
        Image, Web -> null
    }
}

/** Centred image, sized to span at most 35% of the short side so a 4000 px photo can't cover the frame. */
internal fun pickedImage(file: String): Layer {
    val l = widgetLayer(LayerType.Image, "Image", WidgetLayout.inset(4), mapOf("file" to file))
    val n = OverlayStore.naturalSize(l) ?: return l
    val longest = maxOf(n.first, n.second)
    if (longest <= 0f) return l
    return l.copy(layout = l.layout?.copy(scale = (0.35f * 1080f / longest).coerceIn(0.05f, 4f)))
}

internal fun webLayer(url: String): Layer = widgetLayer(
    LayerType.Browser,
    Uri.parse(url).host ?: "Web widget",
    WidgetLayout.inset(4),
    mapOf("url" to url, "width" to "800", "height" to "600")
)

/** http/https with a host, the only links a browser source may load. */
internal fun validWebUrl(s: String): Boolean =
    Uri.parse(s).let { it.scheme?.lowercase() in setOf("http", "https") && !it.host.isNullOrEmpty() }

/** Small type marker for layer rows; there's no icon pack, so most are glyphs. */
@Composable
internal fun LayerIcon(type: LayerType) {
    if (type == LayerType.Chat) {
        Icon(painterResource(R.drawable.ic_chat), null, Modifier.size(20.dp))
        return
    }
    val glyph = when (type) {
        LayerType.Alerts -> "!"
        LayerType.Events -> "≡"
        LayerType.Text -> "Aa"
        LayerType.Qr -> "▦"
        LayerType.Browser -> "⌘"
        LayerType.Color -> "■"
        else -> "▣"
    }
    Text(glyph, fontSize = 14.sp)
}

@Composable
internal fun AddWidgetMenu(onPick: (NewWidget) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton({ open = true }, Modifier.semantics { contentDescription = "Add widget" }) { Text("+", fontSize = 26.sp) }
        DropdownMenu(open, { open = false }) {
            for (kind in NewWidget.entries) {
                DropdownMenuItem({ Text(kind.title) }, {
                    open = false
                    onPick(kind)
                })
            }
        }
    }
}
