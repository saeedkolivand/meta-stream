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
    val minTipCents: Int = 0
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

/** The sentence for [e] (iOS Speaker.sentence), or null when its kind is switched off / empty. */
internal fun spokenText(e: ChatEvent, o: SpeechOptions): String? = when (e.kind) {
    Kind.Message -> sanitizeSpeech(e.text).takeIf { o.messages && it.isNotEmpty() }?.let { "${e.user} says $it" }
    Kind.Tip ->
        if (!o.tips || e.amountCents < o.minTipCents) {
            null
        } else {
            note(e, "${e.user} tipped ${spokenAmount(e.amountCents)}")
        }
    Kind.Cheer -> if (o.tips) note(e, "${e.user} cheered ${e.count} bits") else null // bits are money: same gate as tips
    Kind.Follow -> if (o.follows) "${e.user} followed" else null
    Kind.Subscribe -> if (o.subs) "${e.user} subscribed" else null
    Kind.Raid -> if (o.raids) "${e.user} raided with ${e.count} viewers" else null
}

private fun note(e: ChatEvent, lead: String): String {
    val n = sanitizeSpeech(e.text)
    return if (n.isEmpty()) lead else "$lead: $n"
}

/** Compact one-line text for the chat list (iOS DisplayNames.eventSummary). */
fun eventSummary(e: ChatEvent): String = when (e.kind) {
    Kind.Message -> e.text
    Kind.Tip -> "${e.user} tipped $${"%.2f".format(java.util.Locale.US, e.amountCents / 100.0)}" +
        if (e.text.isEmpty()) "" else " — ${e.text}"
    Kind.Cheer -> "${e.user} cheered ${e.count} bits" + if (e.text.isEmpty()) "" else " — ${e.text}"
    Kind.Follow -> "${e.user} followed"
    Kind.Subscribe -> "${e.user} subscribed"
    Kind.Raid -> "${e.user} raided with ${e.count} viewers"
}
