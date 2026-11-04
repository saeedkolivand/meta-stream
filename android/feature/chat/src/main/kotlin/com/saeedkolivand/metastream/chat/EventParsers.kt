package com.saeedkolivand.metastream.chat

import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import org.json.JSONObject

/** One decoded Twitch EventSub WebSocket frame. */
sealed interface EventSubFrame {
    data class Welcome(val sessionId: String) : EventSubFrame

    data class Reconnect(val url: String) : EventSubFrame

    data class Notification(val event: ChatEvent) : EventSubFrame

    data class Mod(val action: Moderation) : EventSubFrame

    data object Ignored : EventSubFrame
}

/** Raw EventSub frame -> [EventSubFrame]; keepalives, unknown subscription types and malformed JSON are [EventSubFrame.Ignored]. */
fun parseEventSubFrame(text: String): EventSubFrame = runCatching {
    val obj = JSONObject(text)
    val meta = obj.getJSONObject("metadata")
    val payload = obj.getJSONObject("payload")
    when (meta.getString("message_type")) {
        "session_welcome" -> EventSubFrame.Welcome(payload.getJSONObject("session").getString("id"))
        "session_reconnect" -> EventSubFrame.Reconnect(payload.getJSONObject("session").getString("reconnect_url"))
        "notification" -> {
            val e = payload.getJSONObject("event")
            when (val type = meta.getString("subscription_type")) {
                "channel.chat.clear" -> EventSubFrame.Mod(Moderation.Clear)
                "channel.chat.message_delete" -> EventSubFrame.Mod(Moderation.Remove(msgId = e.getString("message_id")))
                // a ban or timeout clears that user's messages
                "channel.chat.clear_user_messages" ->
                    EventSubFrame.Mod(Moderation.Remove(userId = e.optString("target_user_id"), login = e.optString("target_user_login")))
                else -> parseEventSubEvent(type, e)?.let { EventSubFrame.Notification(it) } ?: EventSubFrame.Ignored
            }
        }
        else -> EventSubFrame.Ignored
    }
}.getOrDefault(EventSubFrame.Ignored)

private fun hexOrNull(raw: String): String? = raw.takeIf {
    it.length == 7 && it[0] == '#' && it.drop(1).toIntOrNull(16) != null
}?.uppercase()

/** One EventSub `event` object for [type] -> chat message or alert (iOS TwitchEventSubProvider.parseEvent). */
fun parseEventSubEvent(type: String, event: JSONObject): ChatEvent? = when (type) {
    "channel.chat.message" -> {
        val user = event.optString("chatter_user_name")
        val text = event.optJSONObject("message")?.optString("text")
        if (user.isEmpty() || text == null) {
            null
        } else {
            val badges = event.optJSONArray("badges")
            val ids = (0 until (badges?.length() ?: 0)).asSequence().map { badges!!.getJSONObject(it).optString("set_id") }
            ChatEvent(
                "twitch",
                user,
                text,
                color = hexOrNull(event.optString("color")),
                badges = normalizeRoles(ids),
                msgId = event.optString("message_id"),
                userId = event.optString("chatter_user_id")
            )
        }
    }
    "channel.follow" -> alert(event, "user_name", Kind.Follow)
    // Recipients of a gift arrive here too (is_gift); channel.subscription.gift already counts them.
    "channel.subscribe" -> if (event.optBoolean(
            "is_gift"
        )
    ) {
        null
    } else {
        alert(event, "user_name", Kind.Subscribe)?.copy(tier = twitchTier(event))
    }
    "channel.subscription.gift" -> ChatEvent(
        "twitch",
        if (event.optBoolean("is_anonymous")) "Anonymous" else event.optString("user_name").ifEmpty { "Anonymous" },
        "",
        kind = Kind.Subscribe,
        count = maxOf(event.optInt("total"), 1),
        tier = twitchTier(event)
    )
    "channel.subscription.message" -> alert(event, "user_name", Kind.Subscribe)
        ?.copy(text = event.optJSONObject("message")?.optString("text").orEmpty(), tier = twitchTier(event))
    "channel.raid" -> alert(event, "from_broadcaster_user_name", Kind.Raid, count = event.optInt("viewers"))
    "channel.cheer" -> ChatEvent(
        "twitch",
        event.optString("user_name").ifEmpty { "an anonymous cheerer" }, // anonymous cheers omit the name
        event.optString("message"),
        kind = Kind.Cheer,
        count = event.optInt("bits")
    )
    else -> null
}

private fun alert(event: JSONObject, nameKey: String, kind: Kind, count: Int = 0): ChatEvent? =
    event.optString(nameKey).takeIf { it.isNotEmpty() }?.let { ChatEvent("twitch", it, "", kind = kind, count = count) }

/** One `liveChat/messages` item -> message or Super Chat/Sticker tip; membership and other types are null. */
fun parseYouTubeItem(item: JSONObject): ChatEvent? {
    val snippet = item.optJSONObject("snippet") ?: return null
    val author = item.optJSONObject("authorDetails") ?: return null
    val user = author.optString("displayName").ifEmpty { return null }
    return when (val type = snippet.optString("type")) {
        "textMessageEvent" -> {
            val text = snippet.optJSONObject("textMessageDetails")?.optString("messageText") ?: return null
            ChatEvent("youtube", user, text, badges = normalizeRoles(youtubeRoles(author)))
        }
        "superChatEvent", "superStickerEvent" -> {
            val d = snippet.optJSONObject(if (type == "superChatEvent") "superChatDetails" else "superStickerDetails") ?: JSONObject()
            val micros = d.optString("amountMicros").toLongOrNull() ?: d.optLong("amountMicros")
            ChatEvent("youtube", user, d.optString("userComment"), kind = Kind.Tip, amountCents = (micros / 10_000).toInt())
        }
        "newSponsorEvent" -> ChatEvent("youtube", user, "", kind = Kind.Subscribe)
        "memberMilestoneChatEvent" -> ChatEvent(
            "youtube",
            user,
            snippet.optJSONObject("memberMilestoneChatDetails")?.optString("userComment").orEmpty(),
            kind = Kind.Subscribe
        )
        "membershipGiftingEvent" -> {
            val n = snippet.optJSONObject("membershipGiftingDetails")?.opt("giftMembershipsCount")
            ChatEvent("youtube", user, "", kind = Kind.Subscribe, count = (n as? Number)?.toInt() ?: n?.toString()?.toIntOrNull() ?: 1)
        }
        else -> null
    }
}

private fun youtubeRoles(author: JSONObject) = sequence {
    if (author.optBoolean("isChatOwner")) yield("broadcaster")
    if (author.optBoolean("isChatModerator")) yield("moderator")
    if (author.optBoolean("isChatSponsor")) yield("subscriber")
    if (author.optBoolean("isVerified")) yield("verified")
}

/** Twitch's "1000" / "2000" / "3000" as 1-3. */
private fun twitchTier(event: JSONObject) = (event.optString("tier").toIntOrNull() ?: 1000) / 1000
