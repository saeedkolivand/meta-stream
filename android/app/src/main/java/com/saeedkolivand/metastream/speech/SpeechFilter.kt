package com.saeedkolivand.metastream.speech

import com.saeedkolivand.metastream.chat.ChatEvent
import java.text.Normalizer

// Same rules as iOS Speaker.isNoise / Speaker.isBlocked: what read-aloud skips and what never goes on stream.

// ponytail: name heuristics, since no platform flags bots in chat; the ignore list covers the rest.
private val knownBots = setOf("streamelements", "streamlabs", "botrix", "kicklet", "soundalerts")

/** Bots (names ending in "bot" plus the big ones that don't), !commands, and names in [ignored] (comma or space separated). */
internal fun isNoise(user: String, text: String, ignored: String): Boolean {
    val u = user.lowercase()
    val names = ignored.lowercase().split(',', ' ', '\n', '\t').map { it.removePrefix("@") }
    return u.endsWith("bot") || u in knownBots || u in names || text.trimStart().startsWith("!")
}

// ponytail: the slurs and self-harm phrases most often behind hateful-conduct bans; the user's blocked words add any language.
private val bannedTerms = listOf(
    "nigger", "nigga", "faggot", "fag", "retard", "tranny", "kike", "chink", "spic",
    "wetback", "gook", "kys", "kill yourself", "heil hitler"
)
private val leet = mapOf(
    '0' to 'o', '1' to 'i', '3' to 'e', '4' to 'a', '5' to 's', '7' to 't', '@' to 'a', '$' to 's', '!' to 'i', '|' to 'i'
)
private val marks = Regex("\\p{Mn}+")
private val separators = Regex("[^\\p{L}013457@\$!|]+")

/** Lowercased letters only, accents dropped, leetspeak undone and repeats collapsed: "N1iiGG3R" -> "niger". */
internal fun squash(s: String): String {
    val out = StringBuilder()
    for (raw in Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(marks, "")) {
        val c = leet[raw] ?: raw
        if (c.isLetter() && out.lastOrNull() != c) out.append(c)
    }
    return out.toString()
}

private val squashedBanned = bannedTerms.map(::squash) // the widgets check every row many times a second

/**
 * True if [text] holds a banned term or one of [extra] (comma separated), through leetspeak and stretched letters; terms of
 * 5+ letters also through spacing ("n i g g e r"). Shorter ones match whole words only, so "spicy" passes.
 * ponytail: errs toward silence; a skipped harmless message costs nothing, a spoken slur can cost the channel.
 */
fun isBlocked(text: String, extra: String): Boolean {
    val terms = squashedBanned + extra.split(',').map(::squash).filter { it.isNotEmpty() }
    val words = text.split(separators).map(::squash)
    val joined = squash(text)
    return terms.any { t -> if (t.length >= 5) t in joined else words.any { it == t || it == t + "s" } }
}

/** A slur or blocked word (Read aloud settings) in the name or text: never read aloud and kept off the stream widgets. */
val ChatEvent.offensive: Boolean
    get() = isBlocked(user, SpeechSettings.blocked) || isBlocked(text, SpeechSettings.blocked)
