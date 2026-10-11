package com.saeedkolivand.metastream.chat

import org.json.JSONObject

/** What a [ChatEvent] is; everything but [Message] is an alert (iOS ChatEvent.Kind). */
enum class Kind { Message, Tip, Cheer, Follow, Subscribe, Raid }

/**
 * [color] is the sender's own name color as hex; [badges] are normalized roles in [ROLES] order.
 * [amountCents] is money (tips), [count] countable things (raid viewers, cheered bits); cents as Int, never floating point.
 */
data class ChatEvent(
    val platform: String,
    val user: String,
    val text: String,
    val time: Long = System.currentTimeMillis(),
    val color: String? = null,
    val badges: List<String> = emptyList(),
    val kind: Kind = Kind.Message,
    val amountCents: Int = 0,
    val count: Int = 0,
    // Unique per message, set by ChatFeed so the LazyColumn can key its rows.
    val id: Long = 0
)

private val ROLES = listOf("broadcaster", "staff", "moderator", "vip", "founder", "subscriber", "verified", "og")

// Twitch calls verified channels "partner"; unknown types (sub_gifter, premium, bits, ...) are dropped.
private val ROLE_ALIASES = mapOf("partner" to "verified", "admin" to "staff", "global_mod" to "staff")

internal fun normalizeRoles(raw: Sequence<String>): List<String> {
    val found = raw.map { ROLE_ALIASES[it] ?: it }.toSet()
    return ROLES.filter { it in found }
}

private const val KICK_MESSAGE = """App\Events\ChatMessageEvent"""

private fun kickEventName(frame: String): String? = runCatching { JSONObject(frame).optString("event") }.getOrNull()

internal fun isKickPing(frame: String) = kickEventName(frame) == "pusher:ping"

/** Pusher frame from a Kick chatroom -> message, or null for anything else (pings, subscriptions, malformed JSON). */
internal fun parseKickFrame(frame: String): ChatEvent? {
    if (kickEventName(frame) != KICK_MESSAGE) return null
    return runCatching {
        val d = JSONObject(JSONObject(frame).getString("data"))
        val sender = d.getJSONObject("sender")
        val identity = sender.optJSONObject("identity")
        val badges = identity?.optJSONArray("badges")
        val types = (0 until (badges?.length() ?: 0)).asSequence().map { badges!!.getJSONObject(it).optString("type") }
        ChatEvent(
            "kick",
            sender.getString("username"),
            d.getString("content"),
            color = identity?.optString("color")?.ifEmpty { null },
            badges = normalizeRoles(types)
        )
    }.getOrNull()
}

private val privmsg = Regex("""^@(\S+) :(\w+)!\S+ PRIVMSG #\S+ :(.*)$""")

internal fun isTwitchPing(line: String) = line.startsWith("PING")

/** One Twitch IRC line (with the tags capability) -> message; the display-name tag wins over the login. Null for non-PRIVMSG lines. */
internal fun parseTwitchLine(line: String): ChatEvent? {
    val m = privmsg.find(line)?.groupValues ?: return null
    val tags = m[1].split(';').associate { it.substringBefore('=') to it.substringAfter('=', "") }
    val roles = tags["badges"].orEmpty().split(',').map { it.substringBefore('/') }
    return ChatEvent(
        "twitch",
        tags["display-name"].orEmpty().ifEmpty { m[2] },
        m[3],
        color = tags["color"]?.ifEmpty { null },
        badges = normalizeRoles(roles.asSequence())
    )
}

private val kickEmote = Regex("""\[emote:\d+:([^\]]*)]""")

// ponytail: Kick emotes shown by name; iOS draws the images (Emotes.swift). Upgrade path: Coil inline images.
/** Chat text for display: Kick's `[emote:id:name]` tokens become `name`. Read-aloud strips them instead (sanitize). */
internal fun displayText(text: String) = kickEmote.replace(text, "$1")
