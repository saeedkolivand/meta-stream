package com.saeedkolivand.metastream.chat

import org.json.JSONObject

data class ChatEvent(val platform: String, val user: String, val text: String, val time: Long = System.currentTimeMillis())

private const val KICK_MESSAGE = """App\Events\ChatMessageEvent"""

private fun kickEventName(frame: String): String? = runCatching { JSONObject(frame).optString("event") }.getOrNull()

internal fun isKickPing(frame: String) = kickEventName(frame) == "pusher:ping"

/** Pusher frame from a Kick chatroom -> message, or null for anything else (pings, subscriptions, malformed JSON). */
internal fun parseKickFrame(frame: String): ChatEvent? {
    if (kickEventName(frame) != KICK_MESSAGE) return null
    return runCatching {
        val d = JSONObject(JSONObject(frame).getString("data"))
        ChatEvent("kick", d.getJSONObject("sender").getString("username"), d.getString("content"))
    }.getOrNull()
}

private val privmsg = Regex("""^@(\S+) :(\w+)!\S+ PRIVMSG #\S+ :(.*)$""")

internal fun isTwitchPing(line: String) = line.startsWith("PING")

/** One Twitch IRC line (with the tags capability) -> message; the display-name tag wins over the login. Null for non-PRIVMSG lines. */
internal fun parseTwitchLine(line: String): ChatEvent? {
    val m = privmsg.find(line)?.groupValues ?: return null
    val name = m[1].split(';').firstOrNull { it.startsWith("display-name=") }?.substringAfter('=').orEmpty().ifEmpty { m[2] }
    return ChatEvent("twitch", name, m[3])
}
