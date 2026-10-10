package com.saeedkolivand.metastream.speech

// Same cleanup as iOS Speaker.sanitize (urls, kick/colon emotes, @ kept as the name, whitespace, 200 chars).
private val strip = listOf(Regex("""https?://\S+|\bwww\.\S+"""), Regex("""\[emote:\d+:[^\]]*\]"""), Regex(""":[A-Za-z0-9_]+:"""))
private val mention = Regex("""@(\w+)""")
private val spaces = Regex("""\s+""")

internal fun sanitizeSpeech(raw: String): String {
    var s = raw
    for (r in strip) s = r.replace(s, "")
    s = mention.replace(s, "$1")
    return s.trim().split(spaces).joinToString(" ").take(200)
}
