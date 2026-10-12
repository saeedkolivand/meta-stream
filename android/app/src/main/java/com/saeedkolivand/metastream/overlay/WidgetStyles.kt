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
    val fontSize: Float = 28f,
    val maxMessages: Int = 8,
    val fadeSeconds: Int = 0, // 0 = never
    val background: Boolean = true,
    val backgroundColor: Int = 0xD9101014.toInt(), // flat near-black, 85%
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
    val face: String = ""
) {
    val natural get() = 900f to 240f

    fun shows(k: Kind) = shown(k, follow, subscribe, raid, tip, cheer)

    fun toData() = mapOf(
        "follow" to "$follow", "subscribe" to "$subscribe", "raid" to "$raid", "tip" to "$tip", "cheer" to "$cheer",
        "holdSeconds" to "$holdSeconds", "fontSize" to "$fontSize", "accentColor" to accentColor.unsigned(),
        "textColor" to textColor.unsigned(), "face" to face
    )

    companion object {
        fun from(d: Map<String, String>): AlertStyle {
            val o = AlertStyle()
            return AlertStyle(
                d.flag("follow", o.follow), d.flag("subscribe", o.subscribe), d.flag("raid", o.raid), d.flag("tip", o.tip),
                d.flag("cheer", o.cheer), d.int("holdSeconds", o.holdSeconds), d.num("fontSize", o.fontSize),
                d.argb("accentColor", o.accentColor), d.argb("textColor", o.textColor), d.str("face", o.face)
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
    val size: Float = 64f, // font px at a 1080 px short side
    val bold: Boolean = true,
    val color: Int = 0xFFFFFFFF.toInt(),
    val face: String = "",
    val shadow: Boolean = true,
    val background: Boolean = false,
    val backgroundColor: Int = 0x8C000000.toInt()
) {
    fun toData() = mapOf(
        "text" to text,
        "size" to "$size",
        "bold" to "$bold",
        "color" to color.unsigned(),
        "face" to face,
        "shadow" to "$shadow",
        "background" to "$background",
        "backgroundColor" to backgroundColor.unsigned()
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
                d.argb("backgroundColor", o.backgroundColor)
            )
        }
    }
}
