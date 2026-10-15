package com.saeedkolivand.metastream.speech

import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.Kind

/** Which event kinds are read aloud, and the tip floor. */
data class SpeechOptions(
    val messages: Boolean = true,
    val tips: Boolean = true,
    val follows: Boolean = true,
    val subs: Boolean = true,
    val raids: Boolean = true,
    val minTipCents: Int = 0,
    val ignored: String = "",
    val blocked: String = ""
)

/** Whole dollars read as a number ("5 dollars"); anything with cents stays "12.50 dollars"; unknown amounts are just "money". */
internal fun spokenAmount(cents: Int): String {
    if (cents <= 0) return "money"
    val dollars = cents / 100
    return if (cents % 100 ==
        0
    ) {
        "$dollars dollar${if (dollars == 1) "" else "s"}"
    } else {
        "%.2f dollars".format(java.util.Locale.US, cents / 100.0)
    }
}

/**
 * The sentence for [e] (iOS Speaker.sentence), or null when its kind is switched off / empty / noise. [sameSpeaker]: the
 * previous spoken message was theirs too, so the name isn't repeated.
 */
internal fun spokenText(e: ChatEvent, o: SpeechOptions, sameSpeaker: Boolean = false): String? {
    // Reading a slur aloud on stream can get the streamer banned, even when a viewer typed it.
    val user = if (isBlocked(e.user, o.blocked)) "someone" else e.user
    val n = if (isBlocked(e.text, o.blocked)) "" else sanitizeSpeech(e.text)
    return when (e.kind) {
        Kind.Message ->
            n.takeIf { o.messages && it.isNotEmpty() && !isNoise(e.user, e.text, o.ignored) }
                ?.let { if (sameSpeaker) it else "$user says $it" }
        Kind.Tip -> if (!o.tips || e.amountCents < o.minTipCents) null else note(n, "$user tipped ${spokenAmount(e.amountCents)}")
        Kind.Cheer -> if (o.tips) note(n, "$user cheered ${e.count} bits") else null // bits are money: same gate as tips
        Kind.Follow -> if (o.follows) "$user followed" else null
        Kind.Subscribe -> if (o.subs) subscribeText(user, e.count) else null
        Kind.Raid -> if (o.raids) "$user raided with ${e.count} viewers" else null
    }
}

private fun subscribeText(user: String, count: Int) = when {
    count <= 0 -> "$user subscribed"
    count == 1 -> "$user gifted a sub"
    else -> "$user gifted $count subs"
}

private fun note(n: String, lead: String) = if (n.isEmpty()) lead else "$lead: $n"

/** Compact one-line text for the chat list (iOS DisplayNames.eventSummary). */
fun eventSummary(e: ChatEvent): String = when (e.kind) {
    Kind.Message -> e.text
    Kind.Tip -> "${e.user} tipped $${"%.2f".format(java.util.Locale.US, e.amountCents / 100.0)}" +
        if (e.text.isEmpty()) "" else " — ${e.text}"
    Kind.Cheer -> "${e.user} cheered ${e.count} bits" + if (e.text.isEmpty()) "" else " — ${e.text}"
    Kind.Follow -> "${e.user} followed"
    Kind.Subscribe -> subscribeText(e.user, e.count)
    Kind.Raid -> "${e.user} raided with ${e.count} viewers"
}
