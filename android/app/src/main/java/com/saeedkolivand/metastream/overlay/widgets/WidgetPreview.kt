package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.Kind

private const val SETTLED_MS = 3000L
private const val SAMPLE_QR = "https://example.com"

private fun sample(
    i: Long,
    now: Long,
    platform: String,
    user: String,
    text: String = "",
    kind: Kind = Kind.Message,
    f: (ChatEvent) -> ChatEvent = {
        it
    }
) = f(ChatEvent(platform, user, text, now - SETTLED_MS, kind = kind, id = i))

/** Six chat samples, timestamped 3 s ago so they are past the entry motion; computed per read so "fade" never ages them out. */
internal val sampleChat: List<ChatEvent>
    get() {
        val now = System.currentTimeMillis()
        return listOf(
            sample(1, now, "twitch", "ninja_fox", "that clutch was insane") { it.copy(badges = listOf("subscriber"), color = "#FF7F50") },
            sample(2, now, "kick", "سارا", "سلام! استریم خیلی خوبه 🔥") { it.copy(badges = listOf("vip"), color = "#4FC3F7") },
            sample(3, now, "youtube", "ModMike", "welcome in, be nice in chat") { it.copy(badges = listOf("moderator")) },
            sample(4, now, "twitch", "BigDaddyBear", kind = Kind.Subscribe),
            sample(5, now, "kick", "Reza", "gg خیلی خوب بود") { it.copy(badges = listOf("subscriber"), color = "#B39DDB") },
            sample(6, now, "youtube", "Lena", "keep it up!", Kind.Tip) { it.copy(amountCents = 500) }
        )
    }

private val sampleEvents: List<ChatEvent>
    get() {
        val now = System.currentTimeMillis()
        return listOf(
            sample(1, now, "twitch", "ninja_fox", kind = Kind.Follow),
            sample(2, now, "kick", "سارا", kind = Kind.Subscribe),
            sample(3, now, "youtube", "Lena", "keep it up!", Kind.Tip) { it.copy(amountCents = 500) },
            sample(4, now, "twitch", "BigDaddyBear", kind = Kind.Raid) { it.copy(count = 42) },
            sample(5, now, "twitch", "Reza", kind = Kind.Cheer) { it.copy(count = 100) }
        )
    }

/**
 * What the editor shows for a widget layer: the live renderer fed with sample data. [scale] is output px per natural px.
 * Chat ignores the fade setting (samples would otherwise age out) and the highlight needs no channel.
 */
internal fun previewBitmap(l: Layer, scale: Float): Bitmap? = when (l.type) {
    LayerType.Chat -> renderChat(sampleChat, ChatStyle.from(l.data).copy(fadeSeconds = 0), System.currentTimeMillis(), scale, "")
    LayerType.Alerts -> renderAlert(sampleEvents[0], AlertStyle.from(l.data), scale)
    LayerType.Events -> renderEventList(sampleEvents, EventListStyle.from(l.data), scale)
    LayerType.Qr -> QrStyle.from(l.data).let { renderQr(it.copy(text = it.text.ifEmpty { SAMPLE_QR }), scale) }
    LayerType.Text -> TextStyle.from(l.data).let { inAppTextBitmap(it.copy(text = WidgetVariables.resolve(it.text)), scale) }
    else -> null
}
