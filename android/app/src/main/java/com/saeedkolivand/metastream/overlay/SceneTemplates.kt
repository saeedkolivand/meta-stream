package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.core.Prefs

/** Named colour sets shared by the scene templates and the Instagram story card (iOS ColorTheme). One setting: colorTheme. */
enum class ColorTheme(val title: String, val faName: String, private val palette: LongArray) {
    Kick("Kick", "سبز کیک", longArrayOf(0xFF0B0B0C, 0xFF18181A, 0xFFF2F1EC, 0xFFA3A3A0, 0xFF53FC18, 0xFF0B0B0C)),
    Red("Live red", "قرمز لایو", longArrayOf(0xFF000000, 0xFF27272A, 0xFFFFFFFF, 0xFFA1A1AA, 0xFFE11D48, 0xFFFFFFFF)),
    Saffron("Saffron", "زعفرانی", longArrayOf(0xFF1C1410, 0xFF2E231C, 0xFFFFF8EE, 0xFFCDBBA7, 0xFFF59E0B, 0xFF1C1410)),
    Turquoise("Turquoise", "فیروزه‌ای", longArrayOf(0xFF071A1F, 0xFF0F2E36, 0xFFEFFFFE, 0xFF9CC7CC, 0xFF2DD4BF, 0xFF071A1F)),
    Purple("Twitch purple", "بنفش", longArrayOf(0xFF0E0B16, 0xFF1F1A2E, 0xFFFFFFFF, 0xFFB8AFCF, 0xFF9146FF, 0xFFFFFFFF)),
    Paper("Paper", "کاغذی", longArrayOf(0xFFF7F5F0, 0xFFE7E3DA, 0xFF141413, 0xFF57534E, 0xFFDC2626, 0xFFFFFFFF));

    val bg get() = palette[0].toInt()
    val surface get() = palette[1].toInt()
    val text get() = palette[2].toInt()
    val muted get() = palette[3].toInt()
    val accent get() = palette[4].toInt()
    val onAccent get() = palette[5].toInt()

    /** The Ticker scene's photo-stand-in backdrop: Kick keeps its slate grey, the rest use their surface. */
    val backdrop get() = if (this == Kick) 0xFF2B3138.toInt() else surface

    companion object {
        val current get() = entries.firstOrNull { it.name.equals(Prefs.string("colorTheme", ""), ignoreCase = true) } ?: Kick

        fun select(t: ColorTheme) = Prefs.put("colorTheme", t.name.lowercase()) // iOS stores the lowercase raw value
    }
}

/**
 * Ready-made Starting / BRB / Ending scenes (iOS SceneTemplates, Mono and Ticker), built from ordinary widget layers so
 * every piece stays editable. Positions are px of a 1920x1080 frame. Colours are baked in from the theme at creation.
 */
enum class SceneTemplate(val title: String) {
    Mono("Mono"),
    Ticker("Ticker");

    /** [channel] is the Kick name (empty = no channel line or QR code). */
    fun scenes(channel: String, theme: ColorTheme = ColorTheme.current): List<Scene> {
        val url = if (channel.isEmpty()) "" else "kick.com/${channel.lowercase()}"
        return if (this == Mono) mono(url, theme) else ticker(url, theme)
    }

    private fun mono(url: String, t: ColorTheme): List<Scene> {
        fun frame(label: String, headline: String, footer: String) = listOf(
            fill(t.bg, 4000f, 4000f, at(4, 0f, 0f)),
            text(label, 28f, t.accent, at(0, 96f, 96f)),
            text(headline, if ("{countdown}" in headline) 300f else 200f, t.text, at(3, 96f, -70f)),
            text(footer, 28f, t.muted, at(6, 96f, -96f))
        )
        val chatBox = chat(560f, 760f, t.surface, at(8, -96f, -96f))
        val place = if (url.isEmpty()) "{weather}" else "{weather}  ·  $url"
        val ending = frame("THAT'S A WRAP", "Thanks for\nwatching", "New follower {follower}  ·  New sub {sub}  ·  Live for {uptime}") +
            text("Next stream: day · time", 28f, t.muted, at(2, -96f, 96f)) +
            listOfNotNull(url.takeIf { it.isNotEmpty() }?.let { qr(it, at(8, -96f, -96f)) })
        return listOf(
            Scene(
                "Starting soon",
                frame("STARTING SOON", "{countdown}", place) + text("IRL from {city}", 64f, t.text, at(3, 96f, 200f)) + chatBox,
                role = "starting"
            ),
            Scene(
                "BRB",
                frame("STILL LIVE", "Be right\nback", "Live {uptime}  ·  {city}  ·  {weather}") +
                    text("Signal's weak here. Hang tight, I'll be back in a moment.", 36f, t.muted, at(3, 96f, 230f)) + chatBox,
                role = "brb"
            ),
            Scene("Ending", ending, role = "ending")
        )
    }

    private fun ticker(url: String, t: ColorTheme): List<Scene> {
        val bar = 180f
        fun frame(label: String, title: String, sub: String, right: String): List<Layer> {
            val tag = text(label, 40f, t.onAccent, WidgetLayout.inset(6))
            val block = (OverlayStore.naturalSize(tag)?.first ?: 400f) + 112f

            // Anchor 6/8 puts a widget's bottom on the frame's bottom; dy lifts its centre to fromBottom.
            fun mid(l: Layer, x: Float, fromBottom: Float, anchor: Int = 6): Layer {
                val h = OverlayStore.naturalSize(l)?.second ?: 0f
                return l.copy(layout = at(anchor, x, h / 2 - fromBottom))
            }
            val layers = listOf(
                fill(t.backdrop, 4000f, 4000f, at(4, 0f, 0f)),
                fill(t.bg, 4000f, bar, at(7, 0f, 0f)),
                fill(t.accent, block, bar, at(6, 0f, 0f)),
                mid(tag, 56f, bar / 2),
                mid(text(title, 52f, t.text, WidgetLayout.inset(6)), block + 56f, 115f),
                mid(text(sub, 26f, t.muted, WidgetLayout.inset(6)), block + 56f, 50f)
            )
            if (right.isEmpty()) return layers
            return layers + mid(text(right, if ("{countdown}" in right) 104f else 64f, t.text, WidgetLayout.inset(8)), -64f, bar / 2, 8)
        }
        val chatBox = chat(520f, 600f, t.bg, at(8, -64f, -(bar + 48f)))
        val channel = if (url.isEmpty()) "" else "  ·  $url"
        val ending = frame("THANKS FOR WATCHING", "Welcome {follower}  ·  Thanks {sub}", "Live for {uptime}$channel", "") +
            listOfNotNull(url.takeIf { it.isNotEmpty() }?.let { qr(it, at(8, -64f, -(bar + 48f))) })
        return listOf(
            Scene(
                "Starting soon",
                frame("STARTING SOON", "IRL from {city}", "{weather}$channel", "{countdown}") + chatBox,
                role = "starting"
            ),
            Scene(
                "BRB",
                frame("BE RIGHT BACK", "Signal's weak. Back in a moment.", "{city}  ·  {weather}", "{uptime}") + chatBox,
                role = "brb"
            ),
            Scene("Ending", ending, role = "ending")
        )
    }

    private fun at(anchor: Int, x: Float, y: Float) = WidgetLayout(anchor, x / 1920f, y / 1080f)

    private fun fill(argb: Int, w: Float, h: Float, l: WidgetLayout) =
        widgetLayer(LayerType.Color, "Color", l, mapOf("color" to "${argb.toLong() and 0xFFFFFFFFL}", "width" to "$w", "height" to "$h"))

    /** Flat text: no shadow, no backdrop (the templates are solid colour, nothing to lift the glyphs off). */
    private fun text(s: String, size: Float, color: Int, l: WidgetLayout) =
        widgetLayer(LayerType.Text, s.replace("\n", " "), l, TextStyle(text = s, size = size, color = color, shadow = false).toData())

    private fun chat(w: Float, h: Float, card: Int, l: WidgetLayout) = widgetLayer(
        LayerType.Chat,
        "Chat",
        l,
        ChatStyle(width = w, height = h, fontSize = 26f, background = true, backgroundColor = card, shadow = false).toData()
    )

    private fun qr(url: String, l: WidgetLayout) =
        widgetLayer(LayerType.Qr, "QR code", l, QrStyle(text = "https://$url", caption = url).toData())
}
