package com.saeedkolivand.metastream.chat

// Same cleanup as iOS Speaker.sanitize (urls, kick/colon emotes, @ kept as the name, whitespace, 200 chars).
private val strip = listOf(Regex("""https?://\S+|\bwww\.\S+"""), Regex("""\[emote:\d+:[^\]]*\]"""), Regex(""":[A-Za-z0-9_]+:"""))
private val mention = Regex("""@(\w+)""")
private val spaces = Regex("""\s+""")

fun sanitizeSpeech(raw: String): String {
    var s = raw
    for (r in strip) s = r.replace(s, "")
    s = mention.replace(s, "$1")
    return s.trim().split(spaces).joinToString(" ").take(200)
}

/**
 * A name is whatever someone typed, and the bot posts it as a trusted account: no links, no leading "!" or "/"
 * (another bot would run it as a command), at most 25 characters.
 */
fun safeName(raw: String) = sanitizeSpeech(raw).take(25).dropWhile { it in "!/\\.@#" || it.isWhitespace() }.ifEmpty { "Someone" }
