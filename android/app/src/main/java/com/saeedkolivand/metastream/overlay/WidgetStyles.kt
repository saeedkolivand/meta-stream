package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.chat.Kind

// Settings of every in-app widget, stored as strings in Layer.data so a layer stays one flat value: ARGB colours as the
// unsigned 32-bit decimal (what iOS writes, so packs are portable), bools "true"/"false". A missing or unparsable key
// falls back to the default, so old packs keep loading when a field is added.

private fun Map<String, String>.int(k: String, d: Int) = this[k]?.toIntOrNull() ?: d

private fun Map<String, String>.num(k: String, d: Float) = this[k]?.toFloatOrNull() ?: d

private fun Map<String, String>.flag(k: String, d: Boolean) = when (this[k]) {
    "true" -> true
    "false" -> false
    else -> d
}

private fun Map<String, String>.argb(k: String, d: Int) = this[k]?.toLongOrNull()?.toInt() ?: d

private fun Map<String, String>.str(k: String, d: String) = this[k] ?: d

private fun Int.unsigned() = (toLong() and 0xFFFFFFFFL).toString()

/** Which event kinds an alert or event list reacts to; chat messages never do. */
private fun shown(k: Kind, follow: Boolean, subscribe: Boolean, raid: Boolean, tip: Boolean, cheer: Boolean) = when (k) {
    Kind.Message -> false
    Kind.Follow -> follow
    Kind.Subscribe -> subscribe
    Kind.Raid -> raid
    Kind.Tip -> tip
    Kind.Cheer -> cheer
}

data class ChatStyle(
    val width: Float = 600f,
    val height: Float = 500f,
    val fontSize: Float = 22f,
    val maxMessages: Int = 8,
    // 0 = never
    val fadeSeconds: Int = 0,
    val background: Boolean = false,
    // flat near-black, 85%
    val backgroundColor: Int = 0xD9101014.toInt(),
    val textColor: Int = 0xFFFFFFFF.toInt(),
    val senderColors: Boolean = true,
    val shadow: Boolean = true,
    val bold: Boolean = true,
    val badges: Boolean = true,
    val platform: Boolean = true,
    val hideCommands: Boolean = true,
    val hideBots: Boolean = true,
    val botNames: String = "nightbot,streamelements,streamlabs,moobot,fossabot,botrix,botrixoficial,kicklet,sery_bot,wizebot",
    val highlight: String = "",
    val highlightColor: Int = 0xFFFFC83D.toInt(),
    val showEvents: Boolean = true,
    val face: String = ""
) {
    val natural get() = width to height

    fun toData() = mapOf(
        "width" to "$width", "height" to "$height", "fontSize" to "$fontSize", "maxMessages" to "$maxMessages",
        "fadeSeconds" to "$fadeSeconds", "background" to "$background", "backgroundColor" to backgroundColor.unsigned(),
        "textColor" to textColor.unsigned(), "senderColors" to "$senderColors", "shadow" to "$shadow", "bold" to "$bold",
        "badges" to "$badges", "platform" to "$platform", "hideCommands" to "$hideCommands", "hideBots" to "$hideBots",
        "botNames" to botNames, "highlight" to highlight, "highlightColor" to highlightColor.unsigned(),
        "showEvents" to "$showEvents", "face" to face
    )

    companion object {
        fun from(d: Map<String, String>): ChatStyle {
            val o = ChatStyle()
            return ChatStyle(
                d.num("width", o.width), d.num("height", o.height), d.num("fontSize", o.fontSize),
                d.int("maxMessages", o.maxMessages), d.int("fadeSeconds", o.fadeSeconds),
                d.flag("background", o.background), d.argb("backgroundColor", o.backgroundColor),
                d.argb("textColor", o.textColor), d.flag("senderColors", o.senderColors), d.flag("shadow", o.shadow),
                d.flag("bold", o.bold), d.flag("badges", o.badges), d.flag("platform", o.platform),
                d.flag("hideCommands", o.hideCommands), d.flag("hideBots", o.hideBots), d.str("botNames", o.botNames),
                d.str("highlight", o.highlight), d.argb("highlightColor", o.highlightColor),
                d.flag("showEvents", o.showEvents), d.str("face", o.face)
            )
        }
    }
}

data class AlertStyle(
    val follow: Boolean = true,
    val subscribe: Boolean = true,
    val raid: Boolean = true,
    val tip: Boolean = true,
    val cheer: Boolean = true,
    val holdSeconds: Int = 5,
    val fontSize: Float = 40f,
    val accentColor: Int = 0xFF9146FF.toInt(),
    val textColor: Int = 0xFFFFFFFF.toInt(),
    val face: String = "",
    // DonationKind id; donations (tips, Bits, KICKs) only
    val design: String = "island",
    // 0 = the design's own colour
    val designAccent: Int = 0,
    // neon's second tube
    val designSecond: Int = 0,
    // slow | normal | quick
    val designSpeed: String = "normal"
) {
    val natural get() = 900f to 240f

    val speed get() = if (designSpeed == "slow") {
        0.75f
    } else if (designSpeed == "quick") {
        1.33f
    } else {
        1f
    }

    fun shows(k: Kind) = shown(k, follow, subscribe, raid, tip, cheer)

    fun toData() = mapOf(
        "follow" to "$follow", "subscribe" to "$subscribe", "raid" to "$raid", "tip" to "$tip", "cheer" to "$cheer",
        "holdSeconds" to "$holdSeconds", "fontSize" to "$fontSize", "accentColor" to accentColor.unsigned(),
        "textColor" to textColor.unsigned(), "face" to face, "design" to design, "designAccent" to designAccent.unsigned(),
        "designSecond" to designSecond.unsigned(), "designSpeed" to designSpeed
    )

    companion object {
        fun from(d: Map<String, String>): AlertStyle {
            val o = AlertStyle()
            return AlertStyle(
                d.flag("follow", o.follow), d.flag("subscribe", o.subscribe), d.flag("raid", o.raid), d.flag("tip", o.tip),
                d.flag("cheer", o.cheer), d.int("holdSeconds", o.holdSeconds), d.num("fontSize", o.fontSize),
                d.argb("accentColor", o.accentColor), d.argb("textColor", o.textColor), d.str("face", o.face), d.str("design", o.design),
                d.argb("designAccent", o.designAccent), d.argb("designSecond", o.designSecond), d.str("designSpeed", o.designSpeed)
            )
        }
    }
}

data class EventListStyle(
    val width: Float = 520f,
    val height: Float = 420f,
    val maxEvents: Int = 5,
    val fontSize: Float = 26f,
    val follow: Boolean = true,
    val subscribe: Boolean = true,
    val raid: Boolean = true,
    val tip: Boolean = true,
    val cheer: Boolean = true,
    val background: Boolean = true,
    val backgroundColor: Int = 0x73000000,
    val textColor: Int = 0xFFFFFFFF.toInt(),
    val face: String = ""
) {
    val natural get() = width to height

    fun shows(k: Kind) = shown(k, follow, subscribe, raid, tip, cheer)

    fun toData() = mapOf(
        "width" to "$width", "height" to "$height", "maxEvents" to "$maxEvents", "fontSize" to "$fontSize",
        "follow" to "$follow", "subscribe" to "$subscribe", "raid" to "$raid", "tip" to "$tip", "cheer" to "$cheer",
        "background" to "$background", "backgroundColor" to backgroundColor.unsigned(),
        "textColor" to textColor.unsigned(), "face" to face
    )

    companion object {
        fun from(d: Map<String, String>): EventListStyle {
            val o = EventListStyle()
            return EventListStyle(
                d.num("width", o.width), d.num("height", o.height), d.int("maxEvents", o.maxEvents),
                d.num("fontSize", o.fontSize), d.flag("follow", o.follow), d.flag("subscribe", o.subscribe),
                d.flag("raid", o.raid), d.flag("tip", o.tip), d.flag("cheer", o.cheer), d.flag("background", o.background),
                d.argb("backgroundColor", o.backgroundColor), d.argb("textColor", o.textColor), d.str("face", o.face)
            )
        }
    }
}

/** The Goal widget (iOS GoalWidgetStyle, same keys). The bar follows the box sliders; the other designs are a fixed size. */
data class GoalStyle(
    val width: Float = 720f,
    val height: Float = 120f,
    val fontSize: Float = 28f,
    val barColor: Int = 0xFF53FC18.toInt(),
    val trackColor: Int = 0xFF26262B.toInt(),
    val textColor: Int = 0xFFFFFFFF.toInt(),
    val backgroundColor: Int = 0xD9101014.toInt(),
    val background: Boolean = true,
    val showPercent: Boolean = true,
    val showOther: Boolean = false,
    val face: String = "",
    val design: String = "bar"
) {
    val natural get() = when (design) {
        "liquid" -> 630f to 114f // board size x 1.5
        "road" -> 750f to 111f
        "segments" -> 720f to 60f
        // Variable-width designs: a generous box (~40-character title) the content hugs one side of.
        "hairline" -> 720f to 130f
        "island" -> 800f to 90f
        "miniring" -> 760f to 150f
        "dots" -> 880f to 96f
        "spark" -> 760f to 120f
        else -> width to height
    }

    fun toData() = mapOf(
        "width" to "$width", "height" to "$height", "fontSize" to "$fontSize", "barColor" to barColor.unsigned(),
        "trackColor" to trackColor.unsigned(), "textColor" to textColor.unsigned(), "backgroundColor" to backgroundColor.unsigned(),
        "background" to "$background", "showPercent" to "$showPercent", "showOther" to "$showOther", "face" to face, "design" to design
    )

    companion object {
        fun from(d: Map<String, String>): GoalStyle {
            val o = GoalStyle()
            return GoalStyle(
                d.num("width", o.width), d.num("height", o.height), d.num("fontSize", o.fontSize), d.argb("barColor", o.barColor),
                d.argb("trackColor", o.trackColor), d.argb("textColor", o.textColor), d.argb("backgroundColor", o.backgroundColor),
                d.flag("background", o.background), d.flag("showPercent", o.showPercent), d.flag("showOther", o.showOther),
                d.str("face", o.face), d.str("design", o.design)
            )
        }
    }
}

/** The Now playing widget (iOS NowPlayingWidgetStyle, same keys). Natural size = iOS artboard x 2. */
data class NowPlayingStyle(
    val design: String = "slab",
    val accentColor: Int = 0xFF1DB954.toInt(),
    val face: String = "",
    val popupSeconds: Int = 6
) {
    val natural get() = when (design) {
        "text" -> 920f to 58f
        "twoLine" -> 520f to 98f
        "cover" -> 920f to 60f
        "popup" -> 1040f to 58f
        "island" -> 880f to 152f
        "disc" -> 860f to 224f
        "ticker" -> 920f to 96f
        else -> 840f to 256f
    }

    fun toData() = mapOf("design" to design, "accentColor" to accentColor.unsigned(), "face" to face, "popupSeconds" to "$popupSeconds")

    companion object {
        fun from(d: Map<String, String>) = NowPlayingStyle(
            d.str("design", "slab"),
            d.argb("accentColor", 0xFF1DB954.toInt()),
            d.str("face", ""),
            d.num("popupSeconds", 6f).toInt().coerceIn(2, 30)
        )
    }
}

data class QrStyle(
    val text: String = "",
    val caption: String = "",
    val foreground: Int = 0xFF000000.toInt(),
    val background: Int = 0xFFFFFFFF.toInt(),
    val face: String = ""
) {
    val natural get() = 400f to (if (caption.isEmpty()) 400f else 470f)

    fun toData() = mapOf(
        "text" to text,
        "caption" to caption,
        "foreground" to foreground.unsigned(),
        "background" to background.unsigned(),
        "face" to face
    )

    companion object {
        fun from(d: Map<String, String>): QrStyle {
            val o = QrStyle()
            return QrStyle(
                d.str("text", o.text),
                d.str("caption", o.caption),
                d.argb("foreground", o.foreground),
                d.argb("background", o.background),
                d.str("face", o.face)
            )
        }
    }
}

/** In-app text. OBS text layers use the same keys (text/size/bold/color/face), so the two share a decoder. */
data class TextStyle(
    val text: String = "",
    // font px at a 1080 px short side
    val size: Float = 64f,
    val bold: Boolean = true,
    val color: Int = 0xFFFFFFFF.toInt(),
    val face: String = "",
    val shadow: Boolean = true,
    val background: Boolean = false,
    // 20% near-black
    val backgroundColor: Int = 0x33101014.toInt(),
    // show one line of the text at a time
    val rotate: Boolean = false,
    val rotateSeconds: Int = 5
) {
    fun toData() = mapOf(
        "text" to text,
        "size" to "$size",
        "bold" to "$bold",
        "color" to color.unsigned(),
        "face" to face,
        "shadow" to "$shadow",
        "background" to "$background",
        "backgroundColor" to backgroundColor.unsigned(),
        "rotate" to "$rotate",
        "rotateSeconds" to "$rotateSeconds"
    )

    companion object {
        fun from(d: Map<String, String>): TextStyle {
            val o = TextStyle()
            return TextStyle(
                d.str("text", o.text),
                d.num("size", o.size),
                d.flag("bold", o.bold),
                d.argb("color", o.color),
                d.str("face", o.face),
                d.flag("shadow", o.shadow),
                d.flag("background", o.background),
                d.argb("backgroundColor", o.backgroundColor),
                d.flag("rotate", o.rotate),
                d.num("rotateSeconds", o.rotateSeconds.toFloat()).toInt() // the inspector slider stores "5.0"
            )
        }
    }
}
