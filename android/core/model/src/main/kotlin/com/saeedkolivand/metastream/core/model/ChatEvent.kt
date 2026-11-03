package com.saeedkolivand.metastream.core.model

/** What a [ChatEvent] is; everything but [Message] is an alert (iOS ChatEvent.Kind). */
enum class Kind { Message, Tip, Cheer, Follow, Subscribe, Raid }

/**
 * [color] is the sender's own name color as hex; [badges] are normalized roles in role order (broadcaster first).
 * [amountCents] is money (tips), [count] countable things (raid viewers, cheered bits); cents as Int, never floating point.
 * [Kind.Subscribe] with count > 0 is a GIFT of [count] subs by [user]; count 0 is a normal (re)sub.
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
    // Platform message id and sender id (Kick/Twitch chat messages): what the moderation slash commands act on.
    val msgId: String = "",
    val userId: String = "",
    // A tip's exact amount in its own currency (donation sites); Twitch sub tier 1-3.
    val money: Money? = null,
    val tier: Int = 0,
    // Set by ChatModerator when the on-device model judged the message unsafe: kept in the in-app chat, nowhere else.
    val flagged: Boolean = false,
    // Unique per message, set by ChatFeed so the LazyColumn can key its rows.
    val id: Long = 0
)
